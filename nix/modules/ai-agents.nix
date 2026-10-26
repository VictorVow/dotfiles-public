{ pkgs, lib, llm-agents, ... }:

let
  jsonFormat = pkgs.formats.json { };

  # MCP servers given to Claude Code are defined here (not read back from
  # config.programs.mcp.servers) because that copy carries option defaults
  # (url = null, enabled = null, …) into Claude Code's .mcp.json.

  # https://github.com/utensils/mcp-nixos
  # NixOS/nixpkgs — real package names, NixOS / Home Manager / nix-darwin options,
  # FlakeHub, Noogle. Two tools (~1k tokens). Queries upstream APIs; no credentials.
  nixosMcp = {
    command = "uvx";
    args    = [ "mcp-nixos" ];
  };

  # https://github.com/mozilla/firefox-devtools-mcp
  # Firefox DevTools MCP (Mozilla) — attaches to the live, already-running Firefox over
  # Marionette + WebDriver BiDi: tabs, DOM snapshot, console, network, JS eval,
  # logpoints, Gecko profiler. Connects lazily on first tool call, so it's inert until
  # the profile is relaunched in remote-debug mode (ff-remote-debug.sh on,
  # bundled in the firefox-live-debug skill's scripts/). Procedure lives there.
  # Public package: chrome-context/prefs tools are only in @mozilla/firefox-devtools-mcp-moz.
  firefoxDevtoolsMcp = {
    command = "npx";
    args    = [ "-y" "@mozilla/firefox-devtools-mcp@latest"
                "--connect-existing" "--tool-preset" "developer" ];
  };

  # https://github.com/ChromeDevTools/chrome-devtools-mcp
  # Chrome DevTools MCP (Google) — attaches to a running Chromium-family browser
  # over CDP at http://127.0.0.1:9223: tabs, DOM snapshot, console, network,
  # JS eval, performance traces, screencast. The browser must be relaunched with
  # --remote-debugging-port first (chromium-remote-debug.sh on, bundled in the
  # chromium-live-debug skill's scripts/; -u/-P for additional per-port
  # instances); unlike the Firefox MCP the server
  # starts fine with nothing listening yet and connects on first tool call.
  # One server = one --browserUrl, so a second debuggable browser needs another
  # registration here. Procedure lives in the chromium-live-debug skill.
  # --workspace lets its file-writing tools (screenshots, snapshots, trace
  # dumps) write outside the OS temp dir.
  chromiumDevtoolsMcp = {
    command = "npx";
    args    = [ "-y" "chrome-devtools-mcp@latest"
                "--browserUrl" "http://127.0.0.1:9223"
                "--usageStatistics" "false" "--performanceCrux" "false"
                "--workspace" "/tmp" "--workspace" "/home/boss/Projects" ];
  };

  # Throwaway-browser variant: no --browserUrl, so the MCP launches its own
  # Chromium on first tool call. --isolated gives it a temp user-data-dir that
  # is deleted when the browser closes; --executablePath pins it to the Nix
  # ungoogled-chromium instead of the default Google "stable" channel lookup.
  # Clean profile (no cookies/logins) — for automation and testing, not for
  # driving the user's real session. Drop --headless for a visible window.
  chromiumDevtoolsMcpIsolated = {
    command = "npx";
    args    = [ "-y" "chrome-devtools-mcp@latest"
                "--isolated" "--headless"
                "--executablePath" "${pkgs.ungoogled-chromium}/bin/chromium"
                "--usageStatistics" "false" "--performanceCrux" "false"
                "--workspace" "/tmp" "--workspace" "/home/boss/Projects" ];
  };

  # https://github.com/morluto/rea
  # REA — reverse engineering across binaries, JS/Electron apps, .NET, firmware,
  # captures, etc. `rea --mcp` serves the stdio MCP; the reverse-engineer-anything
  # skill (agent-skills.nix) drives it. Deep native analysis needs a provider
  # (Hopper/Ghidra/IDA — not installed); static JS/.NET inspection works without one.
  #
  # ── Adapting upstream install instructions ────────────────────────────────────
  # AI projects like this ship a one-shot installer (`npx <pkg> setup`,
  # `npx skills add …`) that writes agent config imperatively. Don't run them —
  # they fight this module's declarative files. Instead, translate what the
  # installer WOULD do into Nix:
  #   1. Find what the installer writes (run it with --dry-run/--json if it has
  #      one, or read its docs/source): usually an MCP server entry, a skill
  #      folder, and maybe a slash command.
  #   2. MCP server → add a <name>Mcp attrset here ({ command = "npx";
  #      args = [ "-y" "<pkg>@latest" <server-flag> ]; }) and reference it from
  #      programs.mcp.servers, programs.claude-code.mcpServers, and both
  #      opencode.json blocks below — one entry, four consumers. Prefer
  #      `npx -y <pkg>@latest <mcp-flag>` over installing the CLI globally:
  #      the package is fetched lazily on agent start and always current; add
  #      to npm-globals.txt instead only if the startup latency matters.
  #   3. Skill folder → flake = false input pinned to a SHA + channel comment
  #      in flake.nix, linked in agent-skills.nix (never copy the SKILL.md in
  #      by hand — it would go stale silently). Add the input to pin_specs and
  #      REVIEW_INPUTS in update.sh so it advances with the other sources.
  #   4. Anything else the installer manages (agents, permissions, hooks) → the
  #      matching programs.* option or a home.file/activation block here.
  #   5. Skip the installer's "restart your agent" step — hms + a new session
  #      covers it. If the project also has a CLI worth keeping, npm-globals.txt
  #      is the non-Nix escape hatch for tools missing from nixpkgs/llm-agents.
  reaMcp = {
    command = "npx";
    args    = [ "-y" "rea-agents@latest" "--mcp" ];
  };

  # llm-agents.nix's own packages output, built against its pinned nixpkgs —
  # matches numtide's binary cache (cache.numtide.com). See home.nix for why
  # this is used instead of the llm-agents overlay.
  llmAgents = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  # magpie-community OpenCode provider plugins, pinned npm tarballs (see the
  # opencode1 section below). Bump = new version + hash.
  magpiePkg = name: version: hash: pkgs.fetchzip {
    url = "https://registry.npmjs.org/@magpie-community/opencode-${name}-auth/-/opencode-${name}-auth-${version}.tgz";
    inherit hash;
  };
  cursorAuth = magpiePkg "cursor" "0.2.19" "sha256-+JKtCYQ5D0de3+7b6x1tmDEI174F9eFA4oRV9Ce4ynQ=";
  # Both OpenCodes' devin plugin is my fork's branch until its fixes land
  # upstream: the OpenCode 2 port (issue magpie-community/plugins#266; the
  # npm tarball has no v2 default export) and metadata.cli saved as the
  # string "true" (devin-v1-cli-string, on top of the port) — OpenCode 1
  # drops an auth.json entry with a non-string metadata value, and its
  # requests then 404 at the plugin's placeholder baseURL.
  #
  # Unpin once BOTH of these are merged into magpie-community/plugins main:
  #   - https://github.com/magpie-community/plugins/pull/396 (v1 metadata.cli fix)
  #   - https://github.com/magpie-community/plugins/pull/397 (OpenCode 2 support)
  # and a devin release after 0.1.23 that contains both is on npm (publish.yml
  # only publishes when packages/devin/package.json's version is bumped on main;
  # check `npm view @magpie-community/opencode-devin-auth versions`). Then
  # replace devinAuthSrc + devinAuth below with the npm tarball:
  #   devinAuth = magpiePkg "devin" "<that version>" "<hash>";
  # (hash: `nix store prefetch-file --unpack <tarball url>`, or build once with
  # lib.fakeHash), and make the same change in ai-agents-server.nix.
  # If only one PR merges, keep the fork pin: the other fix is still fork-only.
  devinAuthSrc = pkgs.fetchFromGitHub {
    owner  = "VictorVow";
    repo   = "magpie-plugins";
    rev    = "31a3f918e889fb381ac915d99553dbaf55be5696"; # devin-v1-cli-string
    hash   = "sha256-FIEyZJkxsAW2TYofojRGOi9HLpHkwneViTBffeSYMxk=";
  };
  devinAuth = "${devinAuthSrc}/packages/devin";

  # Permission set shared by every OpenCode (`opencode`/`opencode1` = v1,
  # `opencode2` = v2). Written once as v2-style ordered rules (last match wins,
  # appended after each version's built-in defaults) and rendered into both
  # schemas below. Pins down where v1 and v2 defaults differ: outside-project
  # paths (incl. /tmp) are allowed without a prompt (v2 default; v1 asks), and
  # .env files are denied (v1 default; v2 only asks).
  # https://opencode.ai/v2/docs/permissions/ · https://opencode.ai/docs/permissions/
  # Mirrored in `permissions.deny` for Claude Code below (minus the
  # external_directory entry, which is opencode-only). v2 evaluates this
  # ordered list last-match-wins, so the `*.env.example*` allows must come
  # after the `*.env*` denies. In v1's flattened {pattern: effect} map,
  # ordering is alphabetical and `*.env.*` < `*.env.example`, so the
  # example allows still come out on top.
  opencodePermissions = [
    { action = "external_directory"; resource = "*";              effect = "allow"; }
    { action = "read";               resource = "*.env";          effect = "deny";  }
    { action = "read";               resource = "*.env.*";        effect = "deny";  }
    { action = "read";               resource = "*.env.example";  effect = "allow"; }
    { action = "read";               resource = "*.env.*.example"; effect = "allow"; }
    { action = "read";               resource = "*.env.example.*"; effect = "allow"; }
    # Key material and cert/key bundles at any depth. SSH's own directory is
    # covered below; these catch keys kept elsewhere (certs/, secrets/, tmp).
    { action = "read";               resource = "*.pem";          effect = "deny";  }
    { action = "read";               resource = "*.key";          effect = "deny";  }
    { action = "read";               resource = "*.p12";          effect = "deny";  }
    { action = "read";               resource = "*.pfx";          effect = "deny";  }
    { action = "read";               resource = "id_*";           effect = "deny";  }
    # Decrypting secrets is the leak path, not reading ciphertext — the sops
    # yaml files stay readable so agents can edit recipients/keys structure.
    { action = "shell";              resource = "sops -d *";              effect = "deny"; }
    { action = "shell";              resource = "sops --decrypt *";       effect = "deny"; }
    { action = "shell";              resource = "sops decrypt *";         effect = "deny"; }
    { action = "shell";              resource = "sops exec-env *";        effect = "deny"; }
    { action = "shell";              resource = "sops exec-file *";       effect = "deny"; }
    { action = "shell";              resource = "sops output *";          effect = "deny"; }
    # Master identity for the repo's sops secrets (shell.nix `sops()` uses this).
    { action = "shell";              resource = "secret-tool lookup *";   effect = "deny"; }
    { action = "read";               resource = "~/.config/shell-secrets/**"; effect = "deny"; }
    # sops-nix's defaultSymlinkPath — symlink farm into /run/user/*/secrets.d
    # (tmpfs). Denied here because Bash-read tools can follow it; the tmpfs
    # targets themselves are covered by //run/user/*/secrets.d/** below.
    { action = "read";               resource = "~/.config/sops-nix/secrets/**"; effect = "deny"; }
    { action = "read";               resource = "~/.config/sops/**";          effect = "deny"; }
    # sops age identity materialised to tmpfs at login (sops-age-key.nix).
    { action = "read";               resource = "//run/user/*/sops-age/**";     effect = "deny"; }
    { action = "read";               resource = "//run/user/*/secrets.d/**";    effect = "deny"; }
    { action = "read";               resource = "~/.local/share/keyrings/**"; effect = "deny"; }
    { action = "read";               resource = "~/.ssh/**";                  effect = "deny"; }
    { action = "read";               resource = "~/.gnupg/**";                effect = "deny"; }
  ];
  # ── Secret-guard policy (shared by the Claude PreToolUse hook and the
  #    OpenCode plugin) ─────────────────────────────────────────────────────
  # `read`/`shell` deny rules can't express "command X on path Y", so these
  # lists are rendered into bash-secret-guard.py (Claude Code / Devin
  # PreToolUse) and secret-guard.js (OpenCode v1+v2 `tool.execute.before`).
  # Limits: argv inspection only — `bash -c "$(cat …)"`, process substitution,
  # `find -exec`, and agent-written scripts still get through. The goal is to
  # stop routine first-instinct reads, not a motivated agent.
  secretGuardPaths = [
    "*.env" "*.env.*"           # *.env.example* re-allowed inside the scripts
    "*.pem" "*.key" "*.p12" "*.pfx" "id_*"
    "~/.config/shell-secrets/**"
    "~/.config/sops/**"
    "/run/user/*/sops-age/**"
    "~/.local/share/keyrings/**"
    "~/.ssh/**"
    "~/.gnupg/**"
  ];
  secretGuardReaders = [
    "cat" "head" "tail" "less" "more" "xxd" "od" "hexdump" "strings" "dd"
    "tee" "file" "stat" "grep" "rg" "awk" "sed" "cut" "column" "nl" "wc"
    "readelf" "objdump" "nm" "sqlite3" "jq" "yq" "hexyl" "bat" "pv"
    # compress/decompress — `gzip -dc`/`bzip2 -dc`/`xz -dc`/`zstd -dc` write
    # the file's content to stdout; blocking in-place too is conservative
    # but harmless (an agent shouldn't be gzipping secrets at all).
    "gzip" "gunzip" "bzip2" "bunzip2" "xz" "unxz" "zstd" "unzstd" "lz4" "compress" "uncompress" "zcat" "bzcat" "xzcat" "zstdcat"
    "gpg-connect-agent" "ssh-keyscan" "ssh-keygen"
  ];
  # Interpreters/runners — a protected path anywhere in argv blocks. Decoders
  # (base64/gpg/age/tar/openssl/…) are deliberately NOT here; they live in the
  # scripts' DECODE_FLAGS map so `openssl version`, `gpg -k`, `tar tzf` still
  # work — only actual decode/extract against a protected path is blocked.
  secretGuardInterpreters = [
    "python" "python3" "perl" "ruby" "node" "deno" "bun"
    "bash" "sh" "zsh" "dash" "ksh"
    "sops" "sops-nix" "age-keygen"
    "ssh" "ssh-add" "gpg-agent" "ssh-agent"
    "secret-tool" "kwalletcli" "kwallet-query" "kwalletd6" "kwalletd5"
  ];
  # Render the lists as JSON into the scripts (@SECRET_PATH_PATTERNS@ etc.).
  secretGuardSubst = {
    SECRET_PATH_PATTERNS = builtins.toJSON secretGuardPaths;
    SECRET_GUARD_READERS = builtins.toJSON secretGuardReaders;
    SECRET_GUARD_INTERPRETERS = builtins.toJSON secretGuardInterpreters;
  };

  # v1 shape: { <action> = { <pattern> = <effect>; }; }, with v2's renamed
  # actions mapped back. Nix attrsets serialise with sorted keys, so within an
  # action the patterns come out alphabetically, not in list order — fine while
  # the catch-all "*" sorts first (it does: '*' < letters, '/', '.', '~').
  opencodeV1Action = a: { shell = "bash"; subagent = "task"; }.${a} or a;
  opencodePermissionV1 = lib.foldl' (acc: r: lib.recursiveUpdate acc {
    ${opencodeV1Action r.action}.${r.resource} = r.effect;
  }) { } opencodePermissions;

  # Global agent instructions, shared by Claude Code (~/.claude/CLAUDE.md) and
  # OpenCode (~/.config/opencode/AGENTS.md).
  globalContext = ''
    When creating MD files do not use hard wrapping, reflow the text. If you're editing an MD file and notice hard wrapping then ask the user if they want it removed also.

    To find something in the user's own data (documents, Logseq notes, Calibre highlights, Firefox tabs, past agent sessions), use the `search-personal-data` skill; its map of stores and commands is ~/Projects/installs/docs/system/data-stores.md.
  '';

  # Written as a mutable file (not a Nix-store symlink) so Claude Code can
  # modify it at runtime — e.g. the /effort slash command rewrites this file.
  # Same content that programs.claude-code.settings would generate, but
  # deployed via home.activation (install -m 644) instead of home.file.
  # See: home-manager#8654 — Nix-store symlink blocks runtime writes.
  # Changes made at runtime are overwritten on the next `hms`, except Orca's
  # managed hooks (see home.activation.claudeCodeSettings).
  claudeCodeSettings = pkgs.writeText "claude-code-settings.json" (builtins.toJSON {
    "$schema"           = "https://json.schemastore.org/claude-code-settings.json";
    includeCoAuthoredBy = false;
    effortLevel         = "medium";
    # Never auto-delete transcripts (default 30d) — full history stays
    # searchable via cass; secrets are handled by scripts/security/ instead.
    # NB: 0 is invalid (docs: "the minimum is 1; setting 0 fails with a
    # validation error") and every interactive start shows a Settings Error.
    # 36500 days ≈ 100 years: the largest value Claude Code accepts.
    cleanupPeriodDays   = 36500;
    # Render in the fullscreen (alt-screen) renderer by default every session. https://code.claude.com/docs/en/fullscreen
    # Makes copying easier as it eliminates line breaks and doesn't require SHIFT + CTRL + C
    # Equivalent to running `/tui fullscreen` once; toggle live with `/tui default`.
    tui                 = "fullscreen";
    # Force OSC 8 hyperlink emission. Claude Code's hyperlink-support detection
    # returns false under TERM=screen-* (i.e. inside tmux), so it strips the OSC 8
    # repo link from the statusline before rendering. FORCE_HYPERLINK=1 overrides
    # that detection so the 🔗 segment renders as a clickable link. (tmux forwards
    # the sequence to Konsole/Yakuake via terminal-features ,*:hyperlinks.)
    #
    # CLAUDE_CODE_ENABLE_TODO_TOOLS=1 opts in to TaskCreate/TaskUpdate/TaskList/TaskGet,
    # which Opus 5.5 doesn't get by default. Also reaches claude-agent-acp (Zed), which
    # runs the real Claude Code and renders the task list as an ACP plan update.
    env = {
      FORCE_HYPERLINK = "1";
      CLAUDE_CODE_ENABLE_TODO_TOOLS = "1";
    };
    # Centrally-managed permission allowlist. These apply to EVERY repo (user-level
    # settings merge under per-project settings), so common safe approvals no longer
    # need a per-repo .claude/settings.local.json. Curated from recurring approvals.
    # Deliberately excluded for safety: "Bash(git -C:*)" (would allow push from any
    # dir) and "Bash(gh api:*)" (can POST/DELETE on GitHub) — add per-repo if needed.
    permissions = {
      allow = [
        # ── Web ──
        "WebFetch"
        "WebSearch"

        # ── Read-only shell inspection ──
        "Bash(grep:*)"
        "Bash(rg:*)"
        "Bash(find:*)"
        "Bash(ls:*)"
        "Bash(cat:*)"
        "Bash(head:*)"
        "Bash(tail:*)"
        "Bash(wc:*)"
        "Bash(echo:*)"
        "Bash(env)"
        "Bash(du:*)"
        "Bash(df:*)"
        "Bash(ps:*)"
        "Bash(sort:*)"
        "Bash(uniq:*)"
        "Bash(which:*)"
        "Bash(file:*)"
        "Bash(stat:*)"
        "Bash(tree:*)"
        "Bash(xargs ls:*)"
        "Bash(xargs cat:*)"
        "Read(//tmp/**)"

        # ── Git: read-only ──
        "Bash(git status:*)"
        "Bash(git log:*)"
        "Bash(git diff:*)"
        "Bash(git show:*)"
        "Bash(git blame:*)"
        "Bash(git ls-tree:*)"
        "Bash(git ls-files:*)"
        "Bash(git branch:*)"
        "Bash(git remote:*)"
        "Bash(git config:*)"

        # ── Git: workflow mutations (push/reset still prompt) ──
        "Bash(git add:*)"
        "Bash(git commit:*)"
        "Bash(git stash:*)"
        "Bash(git checkout:*)"
        "Bash(git switch:*)"
        "Bash(git restore:*)"
        "Bash(git fetch:*)"
        "Bash(git submodule:*)"

        # ── GitHub CLI (read) ──
        "Bash(gh pr view:*)"
        "Bash(gh pr diff:*)"
        "Bash(gh pr list:*)"
        "Bash(gh issue view:*)"
        "Bash(gh issue list:*)"
        "Bash(gh run view:*)"
        "Bash(gh run list:*)"
        "Bash(gh search:*)"

        # ── Nix / Home Manager ──
        "Bash(nix --version)"
        "Bash(nix eval:*)"
        "Bash(nix search:*)"
        "Bash(nix flake:*)"
        "Bash(nix develop:*)"
        "Bash(nix run:*)"
        "Bash(nix build:*)"
        "Bash(nix profile:*)"
        "Bash(home-manager option:*)"
        "Bash(home-manager switch:*)"

        # ── Build & dev tooling ──
        "Bash(npm install:*)"
        "Bash(npm ci:*)"
        "Bash(npm run:*)"
        "Bash(npm view:*)"
        "Bash(npm test:*)"
        "Bash(npx tsc:*)"
        "Bash(pnpm install:*)"
        "Bash(pnpm run:*)"
        "Bash(pnpm build:*)"
        "Bash(pnpm test:*)"
        "Bash(python3:*)"
        "Bash(./gradlew:*)"
        "Bash(keytool:*)"
        "Bash(java -version)"
        "Bash(adb devices:*)"
        "Bash(adb shell:*)"
        "Bash(adb install:*)"
        "Bash(adb logcat:*)"

        # ── Network & system ──
        "Bash(curl:*)"
        "Bash(ping:*)"
        "Bash(systemctl:*)"
        "Bash(journalctl:*)"
        "Bash(dpkg -l)"
        "Bash(apt list:*)"
        "Bash(flatpak list:*)"
        "Bash(flatpak remotes:*)"
        "Bash(flatpak info:*)"
        "Bash(docker compose:*)"
        "Bash(docker ps:*)"
        "Bash(podman ps:*)"
        "Bash(podman info:*)"
        "Bash(wl-copy)"
        "Bash(code:*)"
        "Bash(fc-list)"
      ];
      # Deny rules: kept in sync with the opencode `permissions` list above.
      # A Read deny also covers built-ins that read files (Grep/Glob), the
      # file commands Claude Code recognizes in Bash (cat, head, tail, sed),
      # and Bash redirection targets. `!` negations inside the deny list
      # carve exceptions out of cwd-relative rules only (they can't reach
      # `~/`- or `//`-anchored rules). Docs: code.claude.com/docs/en/
      # permissions#read-and-edit
      deny = [
        # .env at any depth under the cwd (deny rules match single-segment
        # names at any depth), except the example/template files.
        "Read(.env)"
        "Read(.env.*)"
        "Read(!.env.example)"
        "Read(!.env.*.example)"
        "Read(!.env.example.*)"
        # Key material at any depth under the cwd — keys kept outside ~/.ssh
        # (certs/, secrets/, /tmp dumps). Ciphertext like *.crt isn't denied:
        # public certs hold no secret.
        "Read(*.pem)"
        "Read(*.key)"
        "Read(*.p12)"
        "Read(*.pfx)"
        "Read(id_*)"
        # Decrypting secrets is the leak path. The sops yaml ciphertext stays
        # readable; edit (`sops file.yaml`) still works and prompts normally.
        "Bash(sops -d *)"
        "Bash(sops --decrypt *)"
        "Bash(sops decrypt *)"
        "Bash(sops exec-env *)"
        "Bash(sops exec-file *)"
        "Bash(sops output *)"
        # Master identity for the repo's sops secrets (shell.nix `sops()`).
        "Bash(secret-tool lookup *)"
        # sops-decrypted materialized secrets (ai-secrets.nix, shell.nix)
        "Read(~/.config/shell-secrets/**)"
        # sops-nix defaultSymlinkPath — symlinks into tmpfs below
        "Read(~/.config/sops-nix/secrets/**)"
        # age master key — unlocks every sops secret
        "Read(~/.config/sops/**)"
        # sops age identity on tmpfs (sops-age-key.nix materialises it at login)
        "Read(//run/user/*/sops-age/**)"
        # sops-nix tmpfs secret dir (the targets ~/.config/sops-nix/secrets points at)
        "Read(//run/user/*/secrets.d/**)"
        # Login keyring (contains the same identity, plus app secrets)
        "Read(~/.local/share/keyrings/**)"
        "Read(~/.ssh/**)"
        "Read(~/.gnupg/**)"
      ];
    };
    # Devin CLI also reads these but rejects the whole block (no `Notification` event).
    # Intentional — Devin/Zed notify natively; see docs/system/claude-code.md § Hooks.
    hooks = {
      Notification     = [{ hooks = [{ type = "command"; command = "bash ~/.claude/hooks/notify-waiting.sh";           }]; }];
      UserPromptSubmit = [{ hooks = [{ type = "command"; command = "bash ~/.claude/hooks/notify-reset-dedupe.sh";      }]; }];
      # Read denies don't cover Bash payloads Claude doesn't parse (xxd, python3
      # -c, base64 -d, dd, …); the hook inspects argv for protected paths.
      PreToolUse       = [{ matcher = "Bash"; hooks = [{ type = "command"; command = "python3 ~/.claude/hooks/bash-secret-guard.py"; }]; }];
    };
    statusLine = {
      type    = "command";
      command = "python3 ~/.claude/statusline/statusline.py";
    };
    # ── Plugins (declarative equivalent of /plugin marketplace add + /plugin install) ──
    # Why NOT programs.claude-code.{marketplaces,plugins}:
    #   1. Feature gap: those options were added in home-manager PR #8934
    #      (https://github.com/nix-community/home-manager/pull/8934, closing issue
    #      #8227). `marketplaces` registers a market but only ever emits
    #      source="directory" (a Nix store path); `plugins` side-loads a plugin
    #      *directory* via a --plugin-dir wrapper arg. NEITHER is the equivalent of
    #      `/plugin install <name>@<market>` — there is deliberately no `enabledPlugins`
    #      option. The PR author's stated intent is to hand-write `enabledPlugins` into
    #      the free-form `settings` instead, which is exactly what we do below.
    #   2. This settings.json is the writable copy deployed via home.activation that
    #      overwrites everything (see header comment above), so the module's own
    #      settings.json output would be clobbered anyway.
    # `source = "github"` makes Claude Code clone kerim/spellbook at runtime into
    # ~/.claude/plugins/marketplaces/ — no sha256 pin needed (matches how the existing
    # runtime-added markets in known_marketplaces.json look). The market KEY
    # ("spellbook") must match the @suffix used in enabledPlugins.
    extraKnownMarketplaces = {
      spellbook = {
        source = {
          source = "github";
          repo   = "kerim/spellbook";
        };
      };
      # CLI-Anything's .claude-plugin/marketplace.json at repo root makes the repo
      # itself a marketplace — declarative `/plugin marketplace add HKUDS/CLI-Anything`.
      cli-anything = {
        source = {
          source = "github";
          repo   = "HKUDS/CLI-Anything";
        };
      };
      # Ponytail (github:DietrichGebert/ponytail) — "lazy senior dev" ruleset:
      # skills + hooks + /ponytail* commands. Declarative `/plugin marketplace
      # add DietrichGebert/ponytail`. Mirrored on lord (ai-agents-server.nix).
      ponytail = {
        source = {
          source = "github";
          repo   = "DietrichGebert/ponytail";
        };
      };
    };
    enabledPlugins = {
      # Superseded by the upstream skill from the local logseq checkout (agent-skills.nix).
      "logseq-cli@spellbook"            = false;
      "logseq-db-plugin-api@spellbook"  = true;
      # /cli-anything (+ :refine/:test/:validate/:list) — the 7-phase CLI generator.
      # OpenCode gets the same commands via agent-skills.nix; `cli-hub` is in uv-tools.txt.
      "cli-anything@cli-anything"       = true;
      # Always-on ruleset + mode switching (/ponytail lite|full|ultra|off) +
      # /ponytail-review, -audit, -debt, -gain, -help. Its hooks run `node`
      # (nodejs_24 on both hosts). The v5.3+ "band" is Claude-Code-only and
      # coexists with statusline.py — it writes to ~/.config/ponytail/, not
      # the statusLine setting.
      "ponytail@ponytail"               = true;
    };
  });

in

# AI coding agents: Claude Code, Codex, OpenCode, and the shared MCP server registry.
{
  # ── MCP Servers — shared registry ─────────────────────────────────────────────
  # Outputs ~/.config/mcp/mcp.json. NOT wired into Claude Code / Codex wholesale
  # (enableMcpIntegration = false); Claude Code picks individual servers via
  # programs.claude-code.mcpServers below. HM bakes those into a plugin dir passed
  # with `--plugin-dir` by a wrapper around the claude binary (not ~/.claude.json).
  # VSCode is not wired either (no longer auto-wired since programs.vscode was removed; configure
  # a marketplace MCP extension to read ~/.config/mcp/mcp.json if needed)
  #
  # Secret env vars (API tokens) are intentionally NOT placed in
  # env blocks here — the env block overrides inherited shell values, so an empty string
  # would shadow a real inherited token. No tokens are exported to shells any
  # more ("API tokens: whitelist only" in shell.nix): wrap the agent binary
  # (like opencode in packages.nix) if an MCP server needs one.

  programs.mcp = {
    enable = true;
    servers = {

      # NixOS/nixpkgs — see nixosMcp in the let block (also given to Claude Code).
      nixos = nixosMcp;

      # Firefox DevTools — see firefoxDevtoolsMcp in the let block (also given to Claude Code).
      firefox-devtools = firefoxDevtoolsMcp;

      # Chrome DevTools — see chromiumDevtoolsMcp in the let block (also given to Claude Code).
      # -isolated launches its own throwaway browser (no --browserUrl, no script needed).
      chromium-devtools          = chromiumDevtoolsMcp;
      chromium-devtools-isolated = chromiumDevtoolsMcpIsolated;

      # REA — see reaMcp in the let block (also given to Claude Code).
      rea = reaMcp;

    };
  };

  # ── Claude Code ────────────────────────────────────────────────────────────────
  # Home Manager claude-code.nix source: https://github.com/nix-community/home-manager/blob/master/modules/programs/claude-code.nix

  programs.claude-code = {
    enable  = true;
    package = llmAgents.claude-code;
    # Whole-registry enableMcpIntegration is available but deliberately off; opt in per server.
    mcpServers = {
      nixos                      = nixosMcp;
      firefox-devtools           = firefoxDevtoolsMcp;
      chromium-devtools          = chromiumDevtoolsMcp;
      chromium-devtools-isolated = chromiumDevtoolsMcpIsolated;
      rea                        = reaMcp;
    };

    # ── Global context — creates ~/.claude/CLAUDE.md (loaded in every project) ────
    context = globalContext;

    # ── Agents — creates ~/.claude/agents/<key>.md ────────────────────────────────

    agents = {

      "nix-helper" = ''
        ---
        name: nix-helper
        description: Assist with Home Manager and Nix flake configuration changes.
          Use when editing nix/modules/*.nix, flake.nix, or debugging eval errors.
        ---
        You are a Nix/Home Manager expert. When making changes:
        - Remember that the main Nix config is located at ~/Projects/installs
        - Read existing module files before proposing edits
        - Prefer extending existing modules over creating new ones
        - Use lib helpers; avoid string-based workarounds
        - Always remind the user to run `hms` after any change
        - Know the module structure: programs.nix, packages.nix, shell.nix, distrobox.nix
      '';

      "container-helper" = ''
        ---
        name: container-helper
        description: Distrobox container assistant. Use when working with or troubleshooting
          the dev or media containers, exporting apps, or installing packages inside containers.
        ---
        This system uses two distrobox containers:
        - dev (ubuntu:24.04): build tools, C/C++, cmake, clang, Python, Node, npm, git
        - media (fedora:latest): ffmpeg, OBS, kdenlive, HandBrake, mpv, yt-dlp (RPMFusion codecs)

        Guidelines:
        - Prefer exporting desktop entries or binaries to the host over installing directly on the host
        - Use `dbe dev` or `dbe media` to enter containers
        - Media container exports GUI apps to the host desktop automatically
        - For GUI apps not in either container, suggest a new distrobox.nix entry
      '';

    };

  };

  home.file.".claude/statusline/statusline.py" = {
    source     = ../dotfiles/claude-statusline/statusline.py;
    executable = true;
  };

  # ── Codex ──────────────────────────────────────────────────────────────────────

  programs.codex = {
    enable  = true;
    package = llmAgents.codex;
    # enableMcpIntegration available but off (same opt-in policy as Claude Code)
  };

  # ── Claude Code settings (writable copy) ────────────────────────────────────
  # Replaces programs.claude-code.settings to avoid a read-only Nix-store
  # symlink. install -m 644 copies the file so Claude Code can overwrite it.
  # The Nix settings win wholesale, except Orca's managed hook entries (any
  # hook whose command references ~/.orca/agent-hooks/) are carried over from
  # the existing file. Without them Orca can't detect Claude in its terminals:
  # no agent status, and "Switch to chat view" shows "No conversation here".
  home.activation.claudeCodeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dest="$HOME/.claude/settings.json"
    # Replace any existing Nix-store symlink with a writable copy
    if [ -L "$dest" ]; then
      $DRY_RUN_CMD rm "$dest"
    fi
    tmp="$(mktemp)"
    if [ -s "$dest" ] && ${pkgs.jq}/bin/jq -s '
         (.[0].hooks // {}) as $old
         | .[1]
         | .hooks = reduce ($old | keys[]) as $ev (.hooks // {};
             ($old[$ev] | map(select(any(.hooks[]?; (.command // "") | contains(".orca/agent-hooks/"))))) as $orca
             | if ($orca | length) > 0 then .[$ev] = ((.[$ev] // []) + $orca) else . end)
       ' "$dest" ${claudeCodeSettings} > "$tmp" 2>/dev/null; then
      $DRY_RUN_CMD install -m 644 "$tmp" "$dest"
    else
      $DRY_RUN_CMD install -m 644 ${claudeCodeSettings} "$dest"
    fi
    rm -f "$tmp"
  '';

  # ── Devin CLI settings (merged keys) ───────────────────────────────────────────
  # ~/.config/devin/config.json is runtime-mutable (Devin writes permissions/org_id,
  # Orca writes hooks), so only the keys below are merged in with jq rather than
  # replacing the file. attribution = false drops the "Generated with Devin" +
  # Co-Authored-By trailer from commits/PRs (Devin's includeCoAuthoredBy).
  home.activation.devinSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dest="$HOME/.config/devin/config.json"
    $DRY_RUN_CMD mkdir -p "$(dirname "$dest")"
    tmp="$(mktemp)"
    { [ -s "$dest" ] && cat "$dest" || echo '{}'; } \
      | ${pkgs.jq}/bin/jq '. + { attribution: false,
          hooks: ((.hooks // {}) + {
            PreToolUse: ((.hooks.PreToolUse // []) + [{
              matcher: "Bash",
              hooks: [{ type: "command", command: "python3 ~/.claude/hooks/bash-secret-guard.py" }]
            }])
          }) }' > "$tmp" \
      && $DRY_RUN_CMD install -m 600 "$tmp" "$dest"
    rm -f "$tmp"
  '';

  # ── OpenCode ───────────────────────────────────────────────────────────────────
  # OpenCode 2 binary is in packages.nix (llmAgents.opencode2). Config here
  # covers the files it reads from ~/.config/opencode/:
  #   - opencode.json: background service prefs (providers, model, agents)
  #   - cli.json:      terminal client prefs (keybinds) — v2's replacement for tui.json
  #   - AGENTS.md:     global instructions (v2 no longer reads ~/.claude/CLAUDE.md)
  # Read-only nix symlinks are fine — opencode stores provider auth in a separate
  # auth.json, never writes these at runtime. The package.json / bun.lock /
  # node_modules / plugins/ in the same dir are left alone (plugin loader state;
  # plugins/orca-opencode-status-tui is installed by Orca).
  # v1 → v2 key mapping: https://opencode.ai/v2/docs/migrate-v1/
  xdg.configFile."opencode/opencode.json".source = jsonFormat.generate "opencode-config" {
    "$schema" = "https://opencode.ai/config.json";
    # Ponytail (github:DietrichGebert/ponytail) — lazy-senior-dev ruleset with
    # hooks + /ponytail* commands. Declarative `opencode plugin add
    # @dietrichgebert/ponytail`; v2 fetches the npm package at runtime into
    # ~/.config/opencode/node_modules (left unmanaged, like Orca's TUI plugin).
    # Mirrored on lord (ai-agents-server.nix). Not added to opencode1 — its
    # v1 `plugin` key fetches the same package but it's a fallback runtime.
    plugins   = [ "@dietrichgebert/ponytail" ];
    # Devin, as in opencode1's config below — served by the fork's v2 plugin
    # (plugins/devin-auth.js) until the port lands upstream (#266).
    model     = "devin/swe-2";
    # v1's small_model; v2 uses it only for session titles.
    agents.title.model = "devin/swe-1.7-lightning";
    permissions = opencodePermissions;
    # Self-hosted FreeLLMAPI (Self-Hosted/FreeLLMAPI, tailnet-only). Key comes
    # from FREELLMAPI_API_KEY (sops, see modules/ai-secrets.nix). `auto*` let
    # the router pick; any explicit model ID from its Models page also works.
    providers.freellmapi = {
      name     = "FreeLLMAPI";
      env      = [ "FREELLMAPI_API_KEY" ];
      package  = "@opencode/ai/providers/openai-compatible";
      settings.baseURL = "https://freellmapi.device.example.com/v1";
      models = {
        "auto"       = { name = "FreeLLMAPI auto"; };
        "auto:fast"  = { name = "FreeLLMAPI auto (fast)"; };
        "auto:smart" = { name = "FreeLLMAPI auto (smart)"; };
      };
    };
    # Web search via FreeLLMAPI's /mcp `web_search` tool (its pooled search
    # providers) instead of OpenCode's built-in websearch, whose provider list
    # is fixed (exa/tavily/…) and can't point at a custom endpoint. Needs the
    # MCP server enabled on FreeLLMAPI (Keys → Agent compatibility) and search
    # provider keys (Tavily/Exa/Firecrawl, sops ai.yaml → its declarative config).
    websearch = false;
    mcp.servers.freellmapi = {
      type    = "remote";
      url     = "https://freellmapi.device.example.com/mcp";
      oauth   = false;
      headers.Authorization = "Bearer {env:FREELLMAPI_API_KEY}";
    };
    # Same servers Claude Code gets (see the let block). v2's local format takes
    # the command and its args as one array. Like every MCP server in v2 they
    # run under Code Mode (codemode defaults to true): the agent calls them from
    # scripts via its `execute` tool as tools.<server>.<tool>(...).
    mcp.servers.nixos = {
      type    = "local";
      command = [ nixosMcp.command ] ++ nixosMcp.args;
    };
    mcp.servers.firefox-devtools = {
      type    = "local";
      command = [ firefoxDevtoolsMcp.command ] ++ firefoxDevtoolsMcp.args;
    };
    mcp.servers.chromium-devtools = {
      type    = "local";
      command = [ chromiumDevtoolsMcp.command ] ++ chromiumDevtoolsMcp.args;
    };
    mcp.servers.chromium-devtools-isolated = {
      type    = "local";
      command = [ chromiumDevtoolsMcpIsolated.command ] ++ chromiumDevtoolsMcpIsolated.args;
    };
    mcp.servers.rea = {
      type    = "local";
      command = [ reaMcp.command ] ++ reaMcp.args;
    };
  };

  # force: the running TUI rewrites cli.json when settings change in the UI
  # (replacing the nix symlink with a real file); don't let activation fail on it.
  xdg.configFile."opencode/cli.json".force = true;
  xdg.configFile."opencode/cli.json".source = jsonFormat.generate "opencode-cli" {
    "$schema" = "https://opencode.ai/v2/cli.json";
    keybinds = {
      leader = "ctrl+x"; # default, made explicit; <leader> below refers to this
      # Rebind the command palette from the default ctrl+p to ctrl+o.
      "command.palette.show" = "ctrl+o";
      # Transcript density: <leader> is ctrl+x. No per-block folding exists
      # (unlike Orca's UI) — these toggle/cycle whole classes of content.
      "session.verbosity.cycle"             = "<leader>v"; # full → summary → minimal
      "session.toggle.exploration_grouping" = "<leader>u"; # grouped vs flat tool calls
      "session.toggle.thinking"             = "<leader>i"; # show/hide reasoning
    };
    session = {
      thinking = "hide";   # reasoning blocks hidden unless toggled
      grouping = "auto";   # group related tool calls into summary rows (default, explicit)
      # TUI persists this back into cli.json when cycled via <leader>v.
      verbosity = "low";
    };
  };

  xdg.configFile."opencode/AGENTS.md".text = globalContext;

  # OpenCode 1 (`opencode1`, packages.nix) with the magpie-community provider
  # plugins for Devin and Cursor subscriptions — v1-style plugins that v2 rejects
  # ("Plugin must export a default definition…"). Sign in with `opencode1 auth login`.
  # https://github.com/magpie-community/plugins
  # They also can't be listed under `plugin` even in v1 (1.19): the packages export
  # a non-function `_internal` (test hooks) and v1 fails with "Plugin export is not
  # a function". So the pinned npm tarballs are unpacked into the store and local
  # plugin files re-export only the plugin function.
  # Same providers/MCP servers as the v2 config above, in v1's schema (`provider` +
  # npm package, `mcp.<name>` with command arrays). FREELLMAPI_API_KEY comes from
  # the opencode1 wrapper (packages.nix).
  home.file.".opencode1/config/opencode/opencode.json".source = jsonFormat.generate "opencode1-config" {
    "$schema" = "https://opencode.ai/config.json";
    # Devin, not anthropic/*: opencode1 has no Anthropic sign-in, so an anthropic default
    # falls back to the rate-limited free opencode/big-pickle (Orca chats then fail).
    model       = "devin/swe-2";
    small_model = "devin/swe-1.7-lightning";
    # REA's skill drives its MCP tools, which are disabled here (see mcp.rea below);
    # `deny` hides it from the agent's skill list (still found via ~/.claude/skills).
    permission  = lib.recursiveUpdate opencodePermissionV1 {
      skill."reverse-engineer-anything" = "deny";
    };
    provider.freellmapi = {
      name = "FreeLLMAPI";
      npm  = "@ai-sdk/openai-compatible";
      options = {
        baseURL = "https://freellmapi.device.example.com/v1";
        apiKey  = "{env:FREELLMAPI_API_KEY}";
      };
      models = {
        "auto"       = { name = "FreeLLMAPI auto"; };
        "auto:fast"  = { name = "FreeLLMAPI auto (fast)"; };
        "auto:smart" = { name = "FreeLLMAPI auto (smart)"; };
      };
    };
    mcp.freellmapi = {
      type    = "remote";
      url     = "https://freellmapi.device.example.com/mcp";
      oauth   = false;
      headers.Authorization = "Bearer {env:FREELLMAPI_API_KEY}";
    };
    mcp.nixos = {
      type    = "local";
      command = [ nixosMcp.command ] ++ nixosMcp.args;
    };
    mcp.firefox-devtools = {
      type    = "local";
      command = [ firefoxDevtoolsMcp.command ] ++ firefoxDevtoolsMcp.args;
    };
    mcp.chromium-devtools = {
      type    = "local";
      command = [ chromiumDevtoolsMcp.command ] ++ chromiumDevtoolsMcp.args;
    };
    mcp.chromium-devtools-isolated = {
      type    = "local";
      command = [ chromiumDevtoolsMcpIsolated.command ] ++ chromiumDevtoolsMcpIsolated.args;
    };
    # Disabled: v1 has no Code Mode, so every MCP tool schema goes inline in every
    # request. REA's ~200 tools put the baseline at ~231k tokens, past swe-2's
    # compaction threshold (262k context − 32k output reserve) — every step then
    # auto-compacted into an endless "Continue if you have next steps…" loop
    # (anomalyco/opencode#48827, closed as v1 won't-fix). Use REA from Claude Code
    # or opencode2 (Code Mode) instead.
    mcp.rea = {
      type    = "local";
      command = [ reaMcp.command ] ++ reaMcp.args;
      enabled = false;
    };
  };
  # opencode2 reads plugin files from ~/.config/opencode/plugins/; the fork
  # has the v2 default export the upstream tarball lacks (#266).
  xdg.configFile."opencode/plugins/devin-auth.js".text =
    ''export { default } from "${devinAuth}/index.mjs"'';
  home.file.".opencode1/config/opencode/plugins/devin-auth.js".text =
    ''export { DevinAuthPlugin } from "${devinAuth}/index.mjs"'';
  home.file.".opencode1/config/opencode/plugins/cursor-auth.js".text =
    ''export { CursorAuthPlugin } from "${cursorAuth}/index.mjs"'';
  home.file.".opencode1/config/opencode/AGENTS.md".text = globalContext;

  # ── Claude Code hook scripts ───────────────────────────────────────────────────
  # Managed here so they're version-controlled alongside the rest of the nix config.
  # Using home.file with executable = true (NOT programs.claude-code.hooks, which
  # writes non-executable read-only Nix-store symlinks that cannot be chmod'd).

  home.file.".claude/hooks/notify-waiting.sh" = {
    source     = ../dotfiles/claude-hooks/notify-waiting.sh;
    executable = true;
  };

  home.file.".claude/hooks/notify-reset-dedupe.sh" = {
    source     = ../dotfiles/claude-hooks/notify-reset-dedupe.sh;
    executable = true;
  };

  # PreToolUse hook: blocks casual Bash reads of Read-denied paths (see
  # secretGuard* above). python3 is already in the Claude allowlist.
  home.file.".claude/hooks/bash-secret-guard.py" = {
    source = pkgs.replaceVars ../dotfiles/claude-hooks/bash-secret-guard.py
      secretGuardSubst;
    executable = true;
  };

  # Same guard for OpenCode — v1 and v2 have different plugin APIs (v1:
  # `export const X = async () => {hooks}`, v2: `export default {id, setup}`),
  # so two files share the same policy lists rendered by secretGuardSubst.
  # Auto-loaded from the plugins dir; no config key needed.
  home.file.".config/opencode/plugins/secret-guard.js".source =
    pkgs.replaceVars ../dotfiles/opencode-plugins/secret-guard.js secretGuardSubst;
  home.file.".opencode1/config/opencode/plugins/secret-guard.js".source =
    pkgs.replaceVars ../dotfiles/opencode-plugins/secret-guard-v1.js secretGuardSubst;

  # ── Claude Code: direnv in the Bash tool ───────────────────────────────────────
  # The Bash tool runs non-interactive shells, so direnv's PROMPT_COMMAND hook
  # never fires. Claude Code sources $CLAUDE_ENV_FILE before every Bash command,
  # so exporting direnv's env there loads the .envrc for the current cwd (follows
  # `cd`; nix-direnv's cache keeps it cheap). Unallowed .envrc files stay blocked.
  home.file.".claude/direnv-env.sh".text = ''
    if command -v direnv >/dev/null 2>&1; then
      export DIRENV_LOG_FORMAT=""
      eval "$(direnv export bash 2>/dev/null)"
    fi
  '';

  home.sessionVariables.CLAUDE_ENV_FILE = "$HOME/.claude/direnv-env.sh";
}
