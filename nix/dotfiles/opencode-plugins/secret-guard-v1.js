// Secret-guard plugin for OpenCode v1 (`opencode`/`opencode1`).
//
// v1 plugin shape: any named export whose value is `async (ctx) => {hooks}`
// is invoked; the hooks object maps event names to handlers. v2 requires a
// different shape (`export default {id, setup}`), so this file only deploys
// to ~/.opencode1/config/opencode/plugins/ — not ~/.config/opencode/.
//
// Purpose: the `bash` shell permission doesn't consult the `read` deny list,
// so `cat ~/.ssh/id_ed25519` passes even though `read` on it is denied.
// Limits: argv inspection only — `bash -c "$(cat …)"`, process substitution,
// `find -exec`, and agent-written scripts all still get through.
//
// The path/command lists are rendered from `secretGuard*` lists in
// ai-agents.nix — edit there, not here. Keep logic in sync with
// secret-guard.js (v2) — the algorithms are identical, only the
// registration wrapper differs.

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
  tar: new Set(["x", "c", "r", "u"]),
  uudecode: new Set(),
  unzip: new Set(),
  zip: new Set(),
  "7z": new Set(["x", "e", "a"]),
};
const ALWAYS_DECODE = new Set(["uudecode", "unzip", "zip"]);
const MOVE_CMDS = new Set(["cp", "mv", "rsync", "scp", "install", "ln"]);

const FILE_TOOLS = new Set(["read", "edit", "write", "grep", "glob", "ls"]);
const CONTENT_SCOPE_TOOLS = new Set(["grep", "glob"]);
const CODE_TOOLS = new Set(["execute"]);

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
    if (np.endsWith("/**") && n === np.slice(0, -3).replace(/\/+$/, "")) return true;
    return globMatch(n, np) || globMatch(base, np);
  });
}

function isProtectedScope(rawPath) {
  const n = norm(rawPath).replace(/\/+$/, "");
  return SECRET_PATH_PATTERNS.some(p => {
    const np = normPattern(p);
    if (!np.includes("**")) return false;
    const head = np.split("**", 1)[0].replace(/\/+$/, "");
    return head && (n === head || n.startsWith(head + "/"));
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

function* iterStrings(code) {
  const re = /"((?:[^"\\]|\\.)*)"|'((?:[^'\\]|\\.)*)'|`((?:[^`\\]|\\.)*)`/g;
  let m;
  while ((m = re.exec(code))) yield m[1] ?? m[2] ?? m[3];
}

function checkCode(code) {
  for (const s of iterStrings(code)) {
    if (!/\s/.test(s)) continue;
    checkShell(s);
  }
  for (const s of iterStrings(code)) {
    if (isProtected(s)) throw new Error(`secret-guard: protected path in code: ${s}`);
    for (const pat of SECRET_PATH_PATTERNS) {
      const np = normPattern(pat);
      if (np.startsWith("/") && np.includes("**")) {
        const head = np.split("**", 1)[0].replace(/\/+$/, "");
        if (head && s.includes(head))
          throw new Error(`secret-guard: code references protected dir ${head}`);
      }
    }
  }
}

function checkFileArgs(tool, args) {
  for (const k of ["filePath", "path", "pattern", "include", "source", "destination"]) {
    const v = args?.[k];
    const check = (item) => {
      if (isProtected(item)) throw new Error(`secret-guard: protected path in arg ${k}: ${item}`);
      if (CONTENT_SCOPE_TOOLS.has(tool) && (k === "path" || k === "include") && isProtectedScope(item))
        throw new Error(`secret-guard: arg ${k} scopes into protected dir: ${item}`);
    };
    if (typeof v === "string") check(v);
    if (Array.isArray(v)) for (const i of v) if (typeof i === "string") check(i);
  }
}

// v1 plugin shape: a named export returning {event: fn, "tool.execute.before":
// fn, ...}. The hook receives (input, output) where input has {tool} and
// output.args carries the tool's arguments.
export const SecretGuard = async () => ({
  "tool.execute.before": async (input, output) => {
    const tool = input?.tool;
    const args = output?.args ?? {};
    if (tool === "bash" || tool === "shell") {
      const cmd = args.command ?? args.cmd ?? "";
      if (typeof cmd === "string") checkShell(cmd);
    } else if (CODE_TOOLS.has(tool)) {
      const code = args.code ?? "";
      if (typeof code === "string") checkCode(code);
    } else if (FILE_TOOLS.has(tool)) {
      checkFileArgs(tool, args);
    }
  },
});
