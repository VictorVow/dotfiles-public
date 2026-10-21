#!/usr/bin/env python3
"""PreToolUse guard: block casual Bash reads of files already denied to Read.

Claude Code's Read deny rules already cover Read/Grep/Glob and the file
commands it recognises inside Bash (cat/head/tail/sed) plus redirection
targets — but NOT other tools (xxd/od/dd/strings/base64/python3 -c/…), and
OpenCode's `bash` shell permission doesn't consult the `read` deny list at
all. This hook is the extra layer. It inspects argv only; it cannot catch
`bash -c "$(cat …)"`, process substitution, `find -exec`, or an agent that
writes a script then runs it. Deliberate exfiltration is still possible —
the goal is to stop routine/agents' first-instinct reads.

Exit codes (Claude Code PreToolUse contract):
  0 = allow (or "not a Bash call" — no-op)
  2 = block; stderr is shown to the agent
Non-zero other than 2 also blocks but surfaces as an error, so every deny
path exits exactly 2.

Deployed by ai-agents.nix to ~/.claude/hooks/. The path/command lists are
rendered from `secretGuard*` lists in that file — edit them there, not here.
"""

import fnmatch
import json
import os
import re
import shlex
import sys

# ── Policy (rendered by Nix; keep in sync with ai-agents.nix) ─────────────

# Absolute/home-anchored paths & basename globs that must not be read.
# "~"/$VARS in *args* are expanded before matching; patterns that start with
# "~/" or "$HOME/" are treated as anchored absolute paths, anything else as
# a basename-or-path-tail glob.
SECRET_PATH_PATTERNS = @SECRET_PATH_PATTERNS@

# Allow-exceptions inside denied patterns (matches opencodePermissions'
# "*.env.example*" carve-outs).
SECRET_PATH_ALLOW = ["*.env.example", "*.env.*.example", "*.env.example.*"]

# Commands whose non-flag args are file paths read to stdout.
READER_CMDS = @SECRET_GUARD_READERS@

# Commands that execute code — a protected path anywhere in argv blocks.
INTERP_CMDS = @SECRET_GUARD_INTERPRETERS@

# Env-var/wrapper prefixes to skip past to find the real argv[0].
WRAPPERS = {"sudo", "doas", "env", "command", "builtin", "exec", "noglob",
            "nice", "ionice", "time", "timeout", "xargs", "stdbuf"}

# Decode/extract flags — these tools are only blocked when the invocation
# actually reads a protected path to produce plaintext or a copy. For archivers
# that means BOTH extract AND create/update modes, since `tar cf out.tar
# ~/.ssh` reads the protected dir as surely as extraction does.
DECODE_FLAGS = {
    "base64": {"-d", "--decode"},
    "base32": {"-d", "--decode"},
    "openssl": {"-d", "-dec"},
    "gpg": {"-d", "--decrypt"},
    "gpg2": {"-d", "--decrypt"},
    "age": {"-d", "--decrypt"},
    # tar: extract OR create/update/append (subcommand is bundled positional).
    # Handled by first-char check in _check rather than this set.
    "tar": {"x", "c", "r", "u"},
    "uudecode": set(),   # always decodes
    "unzip": set(),      # always extracts; path arg is the archive
    "zip": set(),        # always creates; path args are the sources
    "7z": {"x", "e", "a"},
}

# Commands that move data — protected path as SOURCE blocks; destination is
# fine (writing a copy *to* .ssh is a different policy question).
MOVE_CMDS = {"cp", "mv", "rsync", "scp", "install", "ln"}

_SPLIT_RE = re.compile(r"\|\||&&|[|;\n]|`[^`]*`|\$\(")


def _deny(msg: str) -> None:
    sys.stderr.write(f"bash-secret-guard: {msg}\n")
    sys.exit(2)


def _norm(path: str, cwd: str) -> str:
    """Expand ~, $VARS, make absolute, collapse .. — without touching the fs."""
    p = os.path.expandvars(os.path.expanduser(path))
    if not p.startswith("/"):
        p = os.path.join(cwd, p)
    return os.path.normpath(p)


def _norm_pattern(pat: str) -> str:
    """Resolve ~/ and $VARS inside the pattern so anchored patterns match."""
    return os.path.expandvars(os.path.expanduser(pat))


def _matches(path: str) -> bool:
    n = path  # already normalised by caller
    base = os.path.basename(n)
    for allow in SECRET_PATH_ALLOW:
        if fnmatch.fnmatch(base, allow) or fnmatch.fnmatch(n, _norm_pattern(allow)):
            return False
    for pat in SECRET_PATH_PATTERNS:
        np = _norm_pattern(pat)
        # "~/.ssh/**" matches "~/.ssh/id_x" but not "~/.ssh" itself — the
        # dir-as-arg case (tar cf out.tar ~/.ssh, zip -r x.zip ~/.ssh, chmod
        # -R ~/.ssh) still reads/acts on the dir, so strip a trailing "/**"
        # for the dir match too.
        if np.endswith("/**") and n == np[:-3].rstrip("/"):
            return True
        if fnmatch.fnmatch(n, np) or fnmatch.fnmatch(base, np):
            return True
    return False


def _argv(seg: str) -> list:
    try:
        return shlex.split(seg, posix=True)
    except ValueError:
        return seg.split()


def _real_cmd(argv: list) -> list:
    """Skip env wrappers and VAR=val prefixes to reach the actual command."""
    i = 0
    while i < len(argv):
        a = argv[i]
        if "=" in a and not a.startswith("-") and a.split("=", 1)[0].isidentifier():
            i += 1
            continue
        if a in WRAPPERS:
            i += 1
            # xargs consumes its own flags before the inner command
            while i < len(argv) and argv[i].startswith("-"):
                i += 1
            continue
        break
    return argv[i:]


def _check(cmd_argv: list, cwd: str) -> None:
    if not cmd_argv:
        return
    cmd = os.path.basename(cmd_argv[0])
    args = cmd_argv[1:]

    if cmd in READER_CMDS:
        for a in args:
            if a.startswith("-"):
                continue
            if _matches(_norm(a, cwd)):
                _deny(f"{cmd} on protected path: {a}")

    elif cmd in MOVE_CMDS:
        pos = [a for a in args if not a.startswith("-")]
        for a in pos[:-1]:  # all but destination
            if _matches(_norm(a, cwd)):
                _deny(f"{cmd} source is a protected path: {a}")

    elif cmd in DECODE_FLAGS:
        positional = [a for a in args if not a.startswith("-")]
        flagvals = {a for a in args if a.startswith("-")}
        decodes = bool(flagvals & DECODE_FLAGS[cmd])
        # tar/7z's subcommand is bundled-positional ("xzf", "cf", "a", "l"):
        # match by first char for tar ("x|c|r|u" all read sources), word for 7z.
        if cmd == "tar" and positional and positional[0] and positional[0][0] in "xcru":
            decodes = True
        if cmd in {"uudecode", "unzip", "zip"}:
            decodes = True
        if cmd == "7z" and positional and positional[0] in {"x", "e", "a"}:
            decodes = True
        if decodes:
            for a in positional:
                if _matches(_norm(a, cwd)):
                    _deny(f"{cmd} decode/extract on protected path: {a}")

    elif cmd in INTERP_CMDS:
        for a in args:
            if _matches(_norm(a, cwd)):
                _deny(f"{cmd} references protected path: {a}")
            # Inline-code case: `python3 -c 'open("/home/boss/.ssh/id")…'`
            # embeds the path inside a longer arg. Scan for anchored patterns
            # only — basename globs like "*.key" would false-positive on
            # `print("x.key")`.
            for pat in SECRET_PATH_PATTERNS:
                np = _norm_pattern(pat)
                if np.startswith("/") and "**" in np:
                    # e.g. /home/boss/.ssh/** → match "/home/boss/.ssh/" substring
                    head = np.split("**", 1)[0].rstrip("/")
                    if head and head in a:
                        _deny(f"{cmd} embeds protected path {head} in arg")


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        sys.exit(0)
    if payload.get("tool_name") != "Bash":
        sys.exit(0)
    command = payload.get("tool_input", {}).get("command") or ""
    cwd = payload.get("cwd") or os.getcwd()
    for seg in _SPLIT_RE.split(command):
        seg = seg.strip()
        if seg:
            _check(_real_cmd(_argv(seg)), cwd)
    sys.exit(0)


if __name__ == "__main__":
    main()
