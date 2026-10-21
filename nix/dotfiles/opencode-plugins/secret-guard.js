// Secret-guard plugin for OpenCode — v1 (`opencode`/`opencode1`) and v2
// (`opencode2`) share this file; the `tool.execute.before` hook signature is
// identical in both. Deployed to both config dirs by ai-agents.nix.
//
// Purpose: the `bash`/`shell` permission doesn't consult the `read` deny
// list, so `cat ~/.ssh/id_ed25519` passes even though `read` on it is denied.
// This plugin inspects argv for shell calls and path args for file tools.
// Limits (same as the Claude Code PreToolUse hook it mirrors): can't catch
// `bash -c "$(cat …)"`, process substitution, `find -exec`, or agent-written
// scripts — casual first-instinct reads only.
//
// The path/command lists are rendered from `secretGuard*` lists in
// ai-agents.nix — edit there, not here.

const SECRET_PATH_PATTERNS = @SECRET_PATH_PATTERNS@;
const SECRET_PATH_ALLOW = ["*.env.example", "*.env.*.example", "*.env.example.*"];
const READER_CMDS = new Set(@SECRET_GUARD_READERS@);
const INTERP_CMDS = new Set(@SECRET_GUARD_INTERPRETERS@);

const WRAPPERS = new Set(["sudo", "doas", "env", "command", "builtin", "exec",
  "noglob", "nice", "ionice", "time", "timeout", "xargs", "stdbuf"]);

const DECODE_FLAGS = {
  base64: new Set(["-d", "--decode"]),
  base32: new Set(["-d", "--decode"]),
  openssl: new Set(["-d", "-dec"]),
  gpg: new Set(["-d", "--decrypt"]),
  gpg2: new Set(["-d", "--decrypt"]),
  age: new Set(["-d", "--decrypt"]),
  // tar/7z subcommand is bundled positional, matched by first char / word.
  // Extract AND create modes both read protected sources — `tar cf out.tar
  // ~/.ssh` reads the dir as surely as extraction does.
  tar: new Set(["x", "c", "r", "u"]),
  uudecode: new Set(),
  unzip: new Set(),
  zip: new Set(),
  "7z": new Set(["x", "e", "a"]),
};
const ALWAYS_DECODE = new Set(["uudecode", "unzip", "zip"]);

const MOVE_CMDS = new Set(["cp", "mv", "rsync", "scp", "install", "ln"]);

const FILE_TOOLS = new Set(["read", "edit", "write", "grep", "glob", "ls"]);
// Tools whose `path`/`include` args scope CONTENT reads — a parent dir of a
// protected pattern must be denied. `ls` only lists names, so its `path`
// is exempt (listing /home/boss shouldn't be blocked by ~/.ssh existing).
const CONTENT_SCOPE_TOOLS = new Set(["grep", "glob"]);

const HOME = process.env.HOME || "";
const XDG_RUNTIME = process.env.XDG_RUNTIME_DIR || `/run/user/${process.getuid?.() ?? 1000}`;

function norm(p) {
  if (typeof p !== "string") return p;
  let s = p;
  if (s === "~" || s.startsWith("~/")) s = HOME + s.slice(1);
  s = s.replace(/\$\{?HOME\}?/g, HOME)
       .replace(/\$\{?XDG_RUNTIME_DIR\}?/g, XDG_RUNTIME)
       .replace(/\$\(id -u\)/g, String(process.getuid?.() ?? 1000));
  if (!s.startsWith("/")) s = `${process.cwd()}/${s}`;
  const out = [];
  for (const part of s.split("/")) {
    if (part === "" || part === ".") continue;
    if (part === "..") out.pop(); else out.push(part);
  }
  return "/" + out.join("/");
}

function normPattern(pat) {
  let s = pat;
  if (s === "~" || s.startsWith("~/")) s = HOME + s.slice(1);
  return s.replace(/\$\{?HOME\}?/g, HOME)
          .replace(/\$\{?XDG_RUNTIME_DIR\}?/g, XDG_RUNTIME);
}

// Minimal fnmatch: * and ? work anywhere; `**` collapses to `*` — fine for
// the deny list's purposes (its `**` segments always mean "any depth").
function globMatch(name, pat) {
  const re = "^" + pat
    .replace(/[.+^${}()|[\]\\]/g, "\\$&")
    .replace(/\*/g, ".*")
    .replace(/\?/g, ".") + "$";
  return new RegExp(re).test(name);
}

function isProtected(rawPath) {
  const n = norm(rawPath);
  const base = n.split("/").pop() || "";
  for (const allow of SECRET_PATH_ALLOW) {
    if (globMatch(base, allow) || globMatch(n, normPattern(allow))) return false;
  }
  return SECRET_PATH_PATTERNS.some(p => {
    const np = normPattern(p);
    // "~/.ssh/**" matches "~/.ssh/id_x" but not "~/.ssh" itself — the
    // dir-as-arg case (tar cf out.tar ~/.ssh) still reads the dir.
    if (np.endsWith("/**") && n === np.slice(0, -3).replace(/\/+$/, "")) return true;
    return globMatch(n, np) || globMatch(base, np);
  });
}

function splitSegments(cmd) {
  return cmd.split(/\|\||&&|[|;\n]|`[^`]*`|\$\(/).map(s => s.trim()).filter(Boolean);
}

function tokenize(seg) {
  const out = [];
  const re = /"([^"]*)"|'([^']*)'|(\S+)/g;
  let m;
  while ((m = re.exec(seg))) out.push(m[1] ?? m[2] ?? m[3]);
  return out;
}

function realCmd(argv) {
  let i = 0;
  while (i < argv.length) {
    const a = argv[i];
    if (/^[A-Za-z_][A-Za-z0-9_]*=/.test(a)) { i++; continue; }
    if (WRAPPERS.has(a)) {
      i++;
      while (i < argv.length && argv[i].startsWith("-")) i++;
      continue;
    }
    break;
  }
  return argv.slice(i);
}

function checkShell(cmd) {
  for (const seg of splitSegments(cmd)) {
    const argv = realCmd(tokenize(seg));
    if (!argv.length) continue;
    const base = argv[0].split("/").pop();
    const args = argv.slice(1);
    const positional = args.filter(a => !a.startsWith("-"));

    if (READER_CMDS.has(base)) {
      for (const a of positional) {
        if (isProtected(a)) throw new Error(`secret-guard: ${base} on protected path ${a}`);
      }
    } else if (MOVE_CMDS.has(base)) {
      for (const a of positional.slice(0, -1)) {
        if (isProtected(a)) throw new Error(`secret-guard: ${base} source ${a} is protected`);
      }
    } else if (base in DECODE_FLAGS) {
      let decodes = ALWAYS_DECODE.has(base)
        || args.some(a => DECODE_FLAGS[base].has(a));
      // tar's subcommand is a bundled-positional ("xzf", "tf", …) not a
      // flag — match by first char. 7z uses separate words ("x", "e").
      if (base === "tar" && positional.length && /^[xcru]/.test(positional[0]))
        decodes = true;
      if (base === "7z" && positional.length && DECODE_FLAGS["7z"].has(positional[0]))
        decodes = true;
      if (decodes) {
        for (const a of positional) {
          if (isProtected(a)) throw new Error(`secret-guard: ${base} decode/extract on protected path ${a}`);
        }
      }
    } else if (INTERP_CMDS.has(base)) {
      for (const a of args) {
        if (isProtected(a)) throw new Error(`secret-guard: ${base} references protected path ${a}`);
        // `python3 -c 'open("/home/boss/.ssh/id")…'` — path embedded in a
        // longer arg; only anchored `**` patterns are safe to substring-match.
        for (const pat of SECRET_PATH_PATTERNS) {
          const np = normPattern(pat);
          if (np.startsWith("/") && np.includes("**")) {
            const head = np.split("**", 1)[0].replace(/\/+$/, "");
            if (head && a.includes(head))
              throw new Error(`secret-guard: ${base} embeds protected path ${head} in arg`);
          }
        }
      }
    }
  }
}

// A directory arg on a content-reading tool (grep/glob's `path`/`include`)
// is denied when the scope IS a protected dir or sits inside one — e.g.
// `/home/boss/.ssh` and `/home/boss/.ssh/subdir` both match `~/.ssh/**`.
// Scoping *above* the protected dir (`path:/home/boss`) is allowed: grep
// there may print protected *content* but that's already true of the
// cwd-default recursive search anyway — the deny just stops explicit
// targeting.
function isProtectedScope(rawPath) {
  const n = norm(rawPath).replace(/\/+$/, "");
  return SECRET_PATH_PATTERNS.some(p => {
    const np = normPattern(p);
    if (!np.includes("**")) return false;
    const head = np.split("**", 1)[0].replace(/\/+$/, "");
    return head && (n === head || n.startsWith(head + "/"));
  });
}

function checkFileArgs(tool, args) {
  for (const k of ["filePath", "path", "pattern", "include", "source", "destination"]) {
    const v = args?.[k];
    const check = (item) => {
      if (isProtected(item)) throw new Error(`secret-guard: protected path in arg ${k}: ${item}`);
      // `path`/`include` on content-reading tools scope a directory — also
      // reject when they name a parent of a `**`-protected dir. `pattern`/
      // `filePath` name the file itself; `ls` only lists names.
      if (CONTENT_SCOPE_TOOLS.has(tool) && (k === "path" || k === "include") && isProtectedScope(item))
        throw new Error(`secret-guard: arg ${k} scopes into protected dir: ${item}`);
    };
    if (typeof v === "string") check(v);
    if (Array.isArray(v)) for (const i of v) if (typeof i === "string") check(i);
  }
}

export const SecretGuard = async () => ({
  "tool.execute.before": async (input, output) => {
    const tool = input?.tool;
    const args = output?.args ?? {};
    if (tool === "bash" || tool === "shell") {
      const cmd = args.command ?? args.cmd ?? "";
      if (typeof cmd === "string") checkShell(cmd);
    } else if (FILE_TOOLS.has(tool)) {
      checkFileArgs(tool, args);
    }
  },
});
