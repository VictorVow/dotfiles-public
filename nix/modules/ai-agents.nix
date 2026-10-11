{ pkgs, lib, llm-agents, ... }:

let
  jsonFormat = pkgs.formats.json { };

  # llm-agents.nix's own packages output, built against its pinned nixpkgs —
  # matches numtide's binary cache (cache.numtide.com). See home.nix for why
  # this is used instead of the llm-agents overlay.
  llmAgents = llm-agents.packages.${pkgs.system};

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
      Stop             = [{ hooks = [{ type = "command"; command = "bash ~/.claude/hooks/notify-waiting.sh stop";      }]; }];
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
  # Outputs ~/.config/mcp/mcp.json, consumed by:
  #   - programs.claude-code (via enableMcpIntegration = true → ~/.claude/.mcp.json)
  #   - programs.codex       (via enableMcpIntegration = true → ~/.codex/.mcp.json)
  #   - VSCode (no longer auto-wired since programs.vscode was removed; configure
  #     a marketplace MCP extension to read ~/.config/mcp/mcp.json if needed)
  #
  # Secret env vars (LOGSEQ_API_TOKEN, GITHUB_TOKEN) are intentionally NOT placed in
  # env blocks here — the env block overrides inherited shell values, so an empty string
  # would shadow the real token set in home.sessionVariables. MCP server processes
  # inherit the full session environment automatically.

  programs.mcp = {
    enable = true;
    servers = {

      # LogSeq knowledge base — requires LogSeq running with HTTP API enabled (port 12315).
      # One-time setup: LogSeq → Settings → Features → HTTP APIs → enable → generate token
      # → store it as logseq_api_token via `sops nix/secrets/shell.yaml` → hms + restart shell.
      logseq = {
        command = "uv";
        args    = [ "run" "--with" "mcp-logseq" "mcp-logseq" ];
        env     = { LOGSEQ_API_URL = "http://localhost:12315"; };
      };

      # Local file system — exposes ~/Documents for navigation and file operations.
      filesystem = {
        command = "npx";
        args    = [ "-y" "@modelcontextprotocol/server-filesystem"
                    "/home/boss/Documents" ];
      };

      # GitHub API — PR/issue operations, release queries, cross-repo search.
      # Needs GITHUB_TOKEN (repo + read:org scopes); sops-encrypted in nix/secrets/shell.yaml.
      github = {
        command = "npx";
        args    = [ "-y" "@modelcontextprotocol/server-github" ];
      };

      # Context7 — resolves up-to-date library docs at query time (Rust/Python/TS/Java/etc.)
      # HTTP transport; no credentials required.
      context7 = {
        url = "https://mcp.context7.com/mcp";
      };

      # Sequential thinking — structured step-by-step reasoning for architecture/analysis tasks.
      sequential-thinking = {
        command = "npx";
        args    = [ "-y" "@modelcontextprotocol/server-sequential-thinking" ];
      };

      # NixOS/nixpkgs — real package names, options, and Home Manager config lookups.
      # No NixOS required; queries upstream APIs. Works on any system.
      nixos = {
        command = "uvx";
        args    = [ "mcp-nixos" ];
      };

      # YouTube transcripts — extract captions from any YouTube video.
      # No credentials required.
      youtube-transcript = {
        command = "npx";
        args    = [ "-y" "@fabriqa.ai/youtube-transcript-mcp@latest" ];
      };

    };
  };

  # ── Claude Code ────────────────────────────────────────────────────────────────
  # Home Manager claude-code.nix source: https://github.com/nix-community/home-manager/blob/master/modules/programs/claude-code.nix

  programs.claude-code = {
    enable  = true;
    package = llmAgents.claude-code;
    # enableMcpIntegration — not available until HM 26.05

    # ── Global context — creates ~/.claude/CLAUDE.md (loaded in every project) ────
    context = ''
      When creating MD files do not use hard wrapping, reflow the text. If you're editing an MD file and notice hard wrapping then ask the user if they want it removed also.
    '';

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
    # enableMcpIntegration — not available until HM 26.05
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

  # ── OpenCode ───────────────────────────────────────────────────────────────────
  # opencode binary is in packages.nix (llmAgents.opencode). Config here
  # covers the two JSON files opencode reads from ~/.config/opencode/:
  #   - opencode.json: server/runtime prefs (provider, model)
  #   - tui.json:      TUI prefs (keybinds)
  # Read-only nix symlinks are fine — opencode stores provider auth in a separate
  # auth.json, never writes opencode.json/tui.json at runtime. The npm-managed
  # package.json / bun.lock / node_modules in the same dir are left alone (those
  # are opencode's plugin loader state).
  xdg.configFile."opencode/opencode.json".source = jsonFormat.generate "opencode-config" {
    "$schema"   = "https://opencode.ai/config.json";
    provider    = {};
    model       = "anthropic/claude-sonnet-4-5";
    small_model = "anthropic/claude-haiku-4-5";
  };

  xdg.configFile."opencode/tui.json".source = jsonFormat.generate "opencode-tui" {
    "$schema" = "https://opencode.ai/tui.json";
    # Rebind the command picker from the default ctrl+p to ctrl+o.
    keybinds.command_list = "ctrl+o";
  };

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
