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
  # the profile is relaunched in remote-debug mode (scripts/firefox-debugging/
  # ff-remote-debug.sh on). Procedure lives in the firefox-live-debug skill.
  # Public package: chrome-context/prefs tools are only in @mozilla/firefox-devtools-mcp-moz.
  firefoxDevtoolsMcp = {
    command = "npx";
    args    = [ "-y" "@mozilla/firefox-devtools-mcp@latest"
                "--connect-existing" "--tool-preset" "developer" ];
  };

  # llm-agents.nix's own packages output, built against its pinned nixpkgs —
  # matches numtide's binary cache (cache.numtide.com). See home.nix for why
  # this is used instead of the llm-agents overlay.
  llmAgents = llm-agents.packages.${pkgs.stdenv.hostPlatform.system};

  # Global agent instructions, shared by Claude Code (~/.claude/CLAUDE.md) and
  # OpenCode (~/.config/opencode/AGENTS.md).
  globalContext = ''
    When creating MD files do not use hard wrapping, reflow the text. If you're editing an MD file and notice hard wrapping then ask the user if they want it removed also.
  '';

  # Written as a mutable file (not a Nix-store symlink) so Claude Code can
  # modify it at runtime — e.g. the /effort slash command rewrites this file.
  # Same content that programs.claude-code.settings would generate, but
  # deployed via home.activation (install -m 644) instead of home.file.
  # See: home-manager#8654 — Nix-store symlink blocks runtime writes.
  # Changes made at runtime are overwritten on the next `hms`.
  claudeCodeSettings = pkgs.writeText "claude-code-settings.json" (builtins.toJSON {
    "$schema"           = "https://json.schemastore.org/claude-code-settings.json";
    includeCoAuthoredBy = false;
    effortLevel         = "medium";
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
    };
    # Devin CLI also reads these but rejects the whole block (no `Notification` event).
    # Intentional — Devin/Zed notify natively; see docs/system/claude-code.md § Hooks.
    hooks = {
      Notification     = [{ hooks = [{ type = "command"; command = "bash ~/.claude/hooks/notify-waiting.sh";           }]; }];
      UserPromptSubmit = [{ hooks = [{ type = "command"; command = "bash ~/.claude/hooks/notify-reset-dedupe.sh";      }]; }];
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
    };
    enabledPlugins = {
      "logseq-cli@spellbook"            = true;
      "logseq-db-plugin-api@spellbook"  = true;
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
  # would shadow the real token set in home.sessionVariables. MCP server processes
  # inherit the full session environment automatically.

  programs.mcp = {
    enable = true;
    servers = {

      # NixOS/nixpkgs — see nixosMcp in the let block (also given to Claude Code).
      nixos = nixosMcp;

      # Firefox DevTools — see firefoxDevtoolsMcp in the let block (also given to Claude Code).
      firefox-devtools = firefoxDevtoolsMcp;

    };
  };

  # ── Claude Code ────────────────────────────────────────────────────────────────
  # Home Manager claude-code.nix source: https://github.com/nix-community/home-manager/blob/master/modules/programs/claude-code.nix

  programs.claude-code = {
    enable  = true;
    package = llmAgents.claude-code;
    # Whole-registry enableMcpIntegration is available but deliberately off; opt in per server.
    mcpServers = {
      nixos            = nixosMcp;
      firefox-devtools = firefoxDevtoolsMcp;
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
  home.activation.claudeCodeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dest="$HOME/.claude/settings.json"
    # Replace any existing Nix-store symlink with a writable copy
    if [ -L "$dest" ]; then
      $DRY_RUN_CMD rm "$dest"
    fi
    $DRY_RUN_CMD install -m 644 ${claudeCodeSettings} "$dest"
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
      | ${pkgs.jq}/bin/jq '. + { attribution: false }' > "$tmp" \
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
    model     = "anthropic/claude-sonnet-4-5";
    # v1's small_model; v2 uses it only for session titles.
    agents.title.model = "anthropic/claude-haiku-4-5";
  };

  xdg.configFile."opencode/cli.json".source = jsonFormat.generate "opencode-cli" {
    "$schema" = "https://opencode.ai/v2/cli.json";
    # Rebind the command palette from the default ctrl+p to ctrl+o.
    keybinds."command.palette.show" = "ctrl+o";
  };

  xdg.configFile."opencode/AGENTS.md".text = globalContext;

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
}
