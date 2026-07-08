{ config, pkgs, lib, pkgs-unstable, ... }:

let
  jsonFormat = pkgs.formats.json { };

  # VSCodium with --no-sandbox wrap. Extensions are installed by the user via the
  # marketplace into ~/.vscode-oss/extensions/ (writable). vscode-with-extensions
  # is intentionally NOT used because it pins --extensions-dir to a read-only Nix
  # store path, which breaks marketplace installs (EACCES on mkdir). If declarative
  # extensions are needed later, switch back but also redirect the writable dir.
  vscodiumPkg = pkgs.symlinkJoin {
    name = "vscodium";
    inherit (pkgs.vscodium) pname version meta;
    paths = [ pkgs.vscodium ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/codium --add-flags "--no-sandbox"
    '';
  };

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
    env = {
      FORCE_HYPERLINK = "1";
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

  # MarkText UI readability fix, injected via preferences.json "customCss".
  # MarkText's bundled CSS renders the TOC sidebar at var(--sideBarColor)
  # (~60% opacity) and file-tab titles at var(--editorColor50) @ 12px — both
  # too dim/thin/small to read comfortably. customCss is appended as the last
  # <style> in <head>, so these rules win over the bundled UI styles. Using
  # var(--editorColor) keeps the text colour correct in both light and dark
  # themes. Applied by the marktextCustomCss activation script below (jq-merged
  # into the mutable preferences.json so MarkText's other runtime-written
  # settings are preserved).
  marktextCss = pkgs.writeText "marktext-custom.css" ''
    /* ── MarkText UI readability: brighter, bolder TOC + tab titles ── */

    /* Table of Contents items */
    .side-bar-toc .el-tree,
    .side-bar-toc .el-tree-node__label,
    .side-bar-toc > li {
      color: var(--editorColor) !important;
      font-size: 15px !important;
      font-weight: 600 !important;
    }
    /* TOC heading */
    .side-bar-toc .title {
      color: var(--editorColor) !important;
      font-weight: 700 !important;
    }

    /* File tab titles */
    .tabs-container > li {
      color: var(--editorColor) !important;
      font-size: 14px !important;
      font-weight: 600 !important;
    }
    .tabs-container > li.active { font-weight: 700 !important; }
  '';

in

# Home Manager program configurations.
# Using programs.* modules instead of bare packages gives Home Manager the
# ability to manage config files, shell integrations, and user services.
{
  # ── Version Control ──────────────────────────────────────────────────────────

  programs.git = {
    enable = true;

    # GPG signing key — gpgsign is disabled by default; enable per-repo if needed
    signing = {
      key           = "GPGKEY1";
      format        = "openpgp";
      signByDefault = false;
    };

    settings = {
      # Default identity (1 = VictorVow); use `git su [1|2|3]` to switch per-repo
      # Identity 2 (USER2):      22418751+USER2@users.noreply.github.com,      key GPGKEY2
      # Identity 3 (USER3): 11584262+USER3@users.noreply.github.com, key GPGKEY3
      user.name  = "VictorVow";
      user.email = "12621257+VictorVow@users.noreply.github.com";

      init.defaultBranch   = "main";
      pull.rebase          = false;
      push.autoSetupRemote = true;

      gpg.program            = "/usr/bin/gpg";
      tag.forceSignAnnotated = false;

      # Credential storage: libsecret (KDE Wallet) with a 12-hour cache
      credential = {
        helper          = "libsecret";
        credentialStore = "cache";
        cacheOptions    = "--timeout 43200";
      };
      # Per-host credential helpers
      "credential \"https://github.com\"".helper      = "libsecret";
      "credential \"https://gist.github.com\"".helper = "libsecret";
      "credential \"https://dev.azure.com\"".useHttpPath = true;

      # git checkout-fb (shell application) - checkout an arbitrary branch and then remove that remote
      alias.ll = "log --oneline";
      core.editor = "micro";
      # Commit-identity-only fallback for non-Bash contexts (VS Code, GUIs,
      # scripts, subshells). Bash overrides `git su` with a function in
      # shell.nix that also realigns push auth (GITHUB_TOKEN + gh active
      # account). See docs/system/git-identity-management.md.
      alias.su =
        let
          set1 = "git config user.name 'VictorVow'"
            + " && git config user.email '12621257+VictorVow@users.noreply.github.com'"
            + " && git config user.signingkey 'GPGKEY1'"
            + " && echo 'switched -> VictorVow (identity 1)'";
          set2 = "git config user.name 'USER2'"
            + " && git config user.email '22418751+USER2@users.noreply.github.com'"
            + " && git config user.signingkey 'GPGKEY2'"
            + " && echo 'switched -> USER2 (identity 2)'";
          set3 = "git config user.name 'USER3'"
            + " && git config user.email '11584262+USER3@users.noreply.github.com'"
            + " && git config user.signingkey 'GPGKEY3'"
            + " && echo 'switched -> USER3 (identity 3)'";
        in
          "!f() { case \"$1\" in"
          + " 1) ${set1};;"
          + " 2) ${set2};;"
          + " 3) ${set3};;"
          + " \"\") echo \"current: $(git config user.name) <$(git config user.email)>\";;"
          + " *) echo 'usage: git su [1|2|3]';;"
          + " esac }; f";
    };
  };

  # Git LFS — large file storage integration
  programs.git.lfs.enable = true;

  # Global gitignore — local tooling artifacts that should never be committed
  programs.git.ignores = [
    ".direnv/"
    "**/.claude/settings.local.json"
  ];


  # ── Terminal Multiplexers ─────────────────────────────────────────────────────

  programs.tmux = {
    enable = true;
    # Enable mouse support for scrolling and pane selection
    mouse = true;
    # Use a longer scrollback history (default is 2000)
    historyLimit = 10000;
    # 256-colour terminal for better colour rendering in editors
    terminal = "screen-256color";
    extraConfig = ''
      # Forward OSC 8 hyperlinks through tmux to the outer terminal (Konsole/Yakuake).
      # Without this, tmux strips the escape sequence and only the link text is shown.
      set -as terminal-features ",*:hyperlinks"

      # Pane splitting — h for horizontal (side-by-side), v for vertical (stacked)
      bind h split-window -h -c "#{pane_current_path}"
      bind v split-window -v -c "#{pane_current_path}"
      # Percentage variants: C- opens a narrow 33% pane, M- opens a wide 66% pane
      bind C-h split-window -h -p 33 -c "#{pane_current_path}"
      bind M-h split-window -h -p 66 -c "#{pane_current_path}"
      bind C-v split-window -v -p 33 -c "#{pane_current_path}"
      bind M-v split-window -v -p 33 -c "#{pane_current_path}"
      unbind '"'
      unbind %

      # Show pane titles at the top of each pane border
      set -g pane-border-status top
      set -g pane-border-style fg="#00c1ff",bg=default

      # ── Status bar ──────────────────────────────────────────────────────────
      set -g status-style         bg="#1a1a2e",fg="#cdd6f4"
      set -g status-left          " [#S] "
      set -g status-left-style    fg="#00c1ff",bold
      set -g status-right         "#{?client_prefix,⌨️  PREFIX,}"
      set -g status-right-style   fg="#ffcc00",bold

      # Inactive windows: muted but legible text, no background
      set -g window-status-format        " #I:#W#{?window_flags,#{window_flags}, } "
      set -g window-status-style         fg="#bac2de",bg=default

      # Active window: cyan background, dark text, bold
      set -g window-status-current-format " #I:#W#{?window_flags,#{window_flags}, } "
      set -g window-status-current-style  fg="#1a1a2e",bg="#00c1ff",bold

      # Window with activity: amber highlight
      set -g window-status-activity-style fg="#ffcc00",bg=default

      # Cycle windows without prefix — Ctrl+Tab / Ctrl+Shift+Tab
      bind -n C-Tab  next-window
      bind -n C-BTab previous-window

      # New window without prefix — Ctrl+N
      bind -n C-n new-window -c "#{pane_current_path}"

      # Close window with prefix — prefix+X
      # Note: C-w conflicts with Readline delete word. C-q conflicts with Micro quit
      # (prefix) C-x = kill pane, so it mirrors this pattern
      bind X confirm-before -p "kill window? (y/n)" kill-window

      # Resize current pane width interactively — prefix+r, then type e.g. 50%
      bind r command-prompt -p "width (e.g. 50%):" "resize-pane -x %%"

      # Ctrl+D closes panes/windows via shell EOF (bash default behaviour, not a tmux binding)
    '';
  };

  # ── Shell Prompt ──────────────────────────────────────────────────────────────

  programs.starship = {
    enable = true;
    # Shell integration (eval "$(starship init bash)") is injected automatically.
    # The theme config is managed as a verbatim TOML file via home.file below
    # to preserve the gruvbox_dark powerline theme exactly (Unicode symbols, etc.).
    #
    # Note: still need to `hms` before `source ~/.bashrc` to reload config changes
    # This is because whilst the symlink from nix/dotfiles/starship.toml to ~/.config/starship.toml
    # the symlink still points to the old store path with the old content since these files are immutable
  };

  # Gruvbox dark powerline theme — verbatim copy of ~/.config/starship.toml.
  # Edit nix/dotfiles/starship.toml to change the prompt appearance.
  home.file.".config/starship.toml".source = ../dotfiles/starship.toml;

  # ── Shell Input (readline / .inputrc) ────────────────────────────────────────

  programs.readline = {
    enable = true;
    variables = {
      completion-ignore-case     = true;   # case-insensitive tab completion
      show-all-if-ambiguous      = true;   # show list on first Tab, not second
      colored-stats              = true;   # color completions by file type (LS_COLORS)
      colored-completion-prefix  = true;   # color the typed prefix in the list
      expand-tilde               = false;  # keep ~ as ~ instead of expanding to /home/boss
      skip-completed-text        = true;   # no duplicate chars when completing mid-word
      mark-symlinked-directories = true;   # append / to symlinks → directories
      completion-map-case        = true;   # treat - and _ as equivalent
      enable-bracketed-paste     = true;   # prevent accidental execution of pasted text
      echo-control-characters    = false;  # don't print ^C on Ctrl+C
      bell-style                 = "none"; # no audible or visible bell
      page-completions           = false;  # show list inline, not via pager
      keyseq-timeout             = 50;     # ms to wait for escape sequences (default 500)
    };
    bindings = {
      # Up/Down: search history by already-typed prefix (e.g. "git" + Up → git commands)
      "\\e[A"    = "history-search-backward";
      "\\e[B"    = "history-search-forward";
      "\\eOA"    = "history-search-backward";  # alternate escape sequence (kitty etc.)
      "\\eOB"    = "history-search-forward";
      # Delete key → forward-delete character
      "\\e[3~"   = "delete-char";
      # Ctrl+Right / Ctrl+Left → move word by word
      "\\e[1;5C" = "forward-word";
      "\\e[1;5D" = "backward-word";
    };
  };

  # Tell ripgrep (and tools that use it, like Claude Code) to skip the rclone
  # FUSE mount — traversing it causes high CPU on the rclone mount process.
  home.file.".ignore".text = ''
    Mounts/
  '';

  # Global prettier defaults. Prettier walks up from the file being formatted, so
  # anything under ~/ without a closer .prettierrc inherits this. MDX and Markdown
  # files get a very large printWidth and proseWrap=preserve so prose lines aren't
  # reflowed on save (and JSX inside MDX stays on one line).
  home.file.".prettierrc.json".text = builtins.toJSON {
    overrides = [
      {
        files = [ "*.md" "*.mdx" ];
        options = {
          printWidth = 9999;
          proseWrap  = "preserve";
        };
      }
    ];
  };

  # ── Supply-chain hardening: global npm / yarn / pnpm config ────────────────────
  # Mirrors pnpm v11's secure-by-default trio (install cooldown, no unreviewed
  # dependency build scripts, no exotic transitive sources) across all three
  # package managers, at user scope so every project inherits it. Per-invocation
  # flags / per-project config can still override where a real need exists.

  # npm (~/.npmrc, userconfig). Requires npm >= 11.10 for `min-release-age`
  # (guaranteed by nodejs_24 in packages.nix). npm has NO equivalent to pnpm's
  # blockExoticSubdeps / yarn's hardened mode — that third control is documented
  # here as an accepted gap rather than silently dropped. Independent of the
  # NPM_CONFIG_PREFIX env set in shell.nix (env vs rc are separate mechanisms).
  # The npm activation installs in shell.nix intentionally opt out (see there).
  home.file.".npmrc".text = ''
    min-release-age=1
    ignore-scripts=true
    # GAP: npm cannot block exotic (git / tarball / non-registry) transitive
    # deps. pnpm (block-exotic-subdeps) and yarn (enableHardenedMode) do; npm
    # has no equivalent setting as of npm 11.x. Audit lockfiles manually.
  '';

  # Yarn Berry v4 (~/.yarnrc.yml, global). npmMinimalAgeGate is the release-age
  # gate (default "3d"; pinned to 24h here). enableScripts:false is already the
  # Berry default; enableHardenedMode validates the lockfile against the
  # registry — the closest equivalent to blocking exotic subdeps. Pinned
  # explicitly so the behaviour can't regress on a Yarn default change.
  home.file.".yarnrc.yml".text = ''
    npmMinimalAgeGate: "1d"
    enableScripts: false
    enableHardenedMode: true
  '';

  # pnpm global config (~/.config/pnpm/rc, npmrc/ini style → kebab-case keys).
  # Version-aware: the age-pinned flake.lock currently ships pnpm ~10.28, where
  # `minimum-release-age` (added in 10.16) is honoured and the two pnpm-11 keys
  # below are simply ignored (pnpm warns on unknown keys, doesn't fail). Once
  # update-all advances the pin to a nixpkgs with pnpm 11, all three become
  # active — and are also pnpm-11 defaults, so this then just pins intent
  # against a future default change. pnpm's authoritative location for these is
  # per-project pnpm-workspace.yaml; `pnpm config list` shows what's in effect.
  home.file.".config/pnpm/rc".text = ''
    minimum-release-age=1440
    block-exotic-subdeps=true
    strict-dep-builds=true
  '';

  # ── OpenCode ───────────────────────────────────────────────────────────────────
  # opencode binary is in packages.nix (pkgs.llm-agents.opencode). Config here
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

  # ── Text Editors ──────────────────────────────────────────────────────────────

  programs.neovim = {
    enable = true;
    # Replaces `brew install neovim`.
    # defaultEditor is intentionally not set; EDITOR/VISUAL are set to nano in shell.nix.
    vimAlias  = true;   # Alias `vim` → `nvim`
    viAlias   = true;   # Alias `vi`  → `nvim`
    withRuby = false;     # Suppresses warnings
    withPython3 = false;  # Suppresses warnings
    extraConfig = ''
      " Enable line numbers
      set number
      " Enable syntax highlighting
      syntax on
      " Use system clipboard
      set clipboard=unnamedplus
      " Show existing tab with 2 spaces width
      set tabstop=2
      set shiftwidth=2
      set expandtab
    '';
  };

  # ── Process Viewer ────────────────────────────────────────────────────────────

  programs.htop = {
    enable = true;
    settings = {
      cpu_count_from_one   = true;   # Label CPUs starting from 1 (not 0)
      hide_kernel_threads  = true;
      highlight_megabytes  = true;
      highlight_threads    = true;
      enable_mouse         = true;
      # Header layout: two columns 50/50
      header_layout        = "two_50_50";
      column_meters_0      = "LeftCPUs Memory Swap";
      column_meter_modes_0 = "1 1 1";
      column_meters_1      = "RightCPUs Tasks LoadAverage Uptime";
      column_meter_modes_1 = "1 2 2 2";
      # Field/column order (htop field IDs matching ~/.config/htop/htoprc)
      fields               = "0 48 17 18 38 39 40 2 46 47 49 1";
    };
  };

  # ── System Monitor ────────────────────────────────────────────────────────────

  programs.btop = {
    enable = true;
    settings = {
      graph_symbol  = "braille";      # Braille character graphs
      update_ms     = 2000;           # Refresh rate in milliseconds
      proc_sorting  = "cpu direct";   # Sort processes by CPU (default: "cpu lazy")
      proc_per_core = true;           # Show CPU% per core instead of total (default: false)
      use_fstab     = true;           # Use /etc/fstab for disk display (default: false)
      net_auto      = false;          # Fixed scale for network graphs (default: true)
      net_download  = 100;            # Fixed download scale in Mbps
      net_upload    = 100;            # Fixed upload scale in Mbps
      # Custom preset layouts for cycling with 'p':
      presets       = "cpu:1:default,proc:0:default cpu:0:default,mem:0:default,net:0:default cpu:0:block,net:0:tty";
    };
  };

  # ── GitHub CLI ───────────────────────────────────────────────────────────────

  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "https";
      prompt       = "enabled";
      aliases = {
        co = "pr checkout";
      };
    };
  };

  # ── Text Editors ─────────────────────────────────────────────────────────────

  # programs.micro.enable = true also installs the micro package automatically;
  # it is therefore removed from packages.nix.
  programs.micro = {
    enable = true;
  };

  # Home Manager no longer exposes programs.micro.bindings, so keep the
  # keymap declarative by writing micro's native bindings.json directly.
  xdg.configFile."micro/bindings.json".source = jsonFormat.generate "micro-bindings" {
    "Alt-/" = "lua:comment.comment";
    "CtrlUnderscore" = "lua:comment.comment";
  };

  # ── IDE ───────────────────────────────────────────────────────────────────────

  # VSCode binary itself is no longer Nix-managed — it's installed via
  # custom-installers.yml from the Microsoft apt repo (packages.microsoft.com).
  # Reasons: nixpkgs repackages each release as a heavy build, and
  # ms-vscode.cpptools / ms-python.vscode-pylance are MS-licensed for *official*
  # VSCode only. All extensions are now installed via the in-app marketplace.
  #
  # We continue to manage settings.json and keybindings.json declaratively,
  # writing them to ~/.config/Code/User/ where official VSCode reads them.

  xdg.configFile."Code/User/keybindings.json".source = jsonFormat.generate "vscode-keybindings" [
    # Ctrl+; → Tasks: Run Task (open the task picker)
    { key = "ctrl+;"; command = "workbench.action.tasks.runTask"; }
    # Ctrl+K D → diff the active file against what's on disk. Useful because
    # settings.json is a read-only nix symlink: when VSCode/an extension auto-edits
    # a setting it can't save, the editor stays dirty and this shows exactly which
    # lines differ from the saved file. (No default keybinding for this command.)
    { key = "ctrl+k d"; command = "workbench.files.action.compareWithSaved"; when = "editorTextFocus"; }
  ];

  xdg.configFile."Code/User/settings.json".source = jsonFormat.generate "vscode-settings" {
    # ── Telemetry ──────────────────────────────────────────────────────────────
    "telemetry.telemetryLevel"      = "off";
    "redhat.telemetry.enabled"      = false;

    # ── Editor ─────────────────────────────────────────────────────────────────
    "editor.fontFamily"            = "JetBrains Mono"; # Chosen via https://www.codingfont.com/
    "editor.fontLigatures"         = true;
    "editor.inlineSuggest.enabled" = true;
    "editor.defaultFormatter"      = "esbenp.prettier-vscode";
    "editor.formatOnSave"          = true;

    # ── Git ────────────────────────────────────────────────────────────────────
    "git.autofetch"                     = true;
    "git.openRepositoryInParentFolders" = "never";

    # ── Explorer ───────────────────────────────────────────────────────────────
    "explorer.confirmDelete" = false;

    # ── Terminal ───────────────────────────────────────────────────────────────
    "terminal.integrated.allowChords"  = false;
    "terminal.integrated.fontFamily"   = "JetBrainsMono Nerd Font";

    # Pin the integrated terminal shell to bashInteractive — the apt VSCode
    # build resolves `bash` against the system PATH, but pinning to the same
    # interactive bash that Yakuake / programs.bash use keeps starship and
    # programmable completion behaving the same in both terminals.
    "terminal.integrated.defaultProfile.linux" = "bash";
    "terminal.integrated.profiles.linux" = {
      bash = {
        path = "${pkgs.bashInteractive}/bin/bash";
      };
    };

    # ── Theme ──────────────────────────────────────────────────────────────────
    # Theme *id* is "Dark Modern" in current VSCode (the theme-defaults extension
    # dropped the old "Default " prefix it used in older builds). Using the stale
    # "Default Dark Modern" id made VSCode normalize it to "Dark Modern" and try to
    # rewrite settings.json on every launch — which fails against the read-only nix
    # symlink, leaving a permanently dirty settings.json tab.
    "workbench.colorTheme" = "Dark Modern";
    "window.titleBarStyle" = "native"; # Bug with Electron when using custom title bar is causing 1-2px at top to pass through clicks the window below
    # Tint tabs with unsaved changes so a dirty editor (e.g. settings.json that
    # VSCode tried to auto-edit but can't save to the read-only nix symlink) is
    # obvious at a glance. Pair with Ctrl+K D to diff the buffer against disk.
    "workbench.editor.highlightModifiedTabs" = true;

    # ── Claude Code ────────────────────────────────────────────────────────────
    "claudeCode.preferredLocation" = "panel";

    # ── Continue ───────────────────────────────────────────────────────────────
    # yaml.schemas intentionally omitted: version-specific Continue paths become
    # stale on every extension update; Continue manages its own schema registration.

    # ── Misc extension settings ─────────────────────────────────────────────────
    # fabiospampinato.vscode-open-in-application: route .md through marktext-wrap.
    # Must be duplicated here (not just in VSCodium settings) — the extension is
    # installed in both editors but with no "md" mapping it falls back to
    # `xdg-open`, which under the extension host's ELECTRON_RUN_AS_NODE=1 launches
    # marktext's Electron in Node mode and dies silently. See the matching
    # VSCodium block and the marktext-wrap wrapper below for the full rationale.
    "openInApplication.applications" = {
      "md" = "${config.home.homeDirectory}/.local/bin/marktext-wrap";
    };
    "dreammaker.autoUpdate"   = true;
    "dreammaker.tickOnCreate" = true;
    "docker.extension.enableComposeLanguageServer" = false;
    # Disable Red Hat Java extension auto-build on save / on open — builds
    # are on-demand only (Command Palette → "Java: Rebuild Projects").
    "java.autobuild.enabled"                       = false;
    # Don't auto re-import the project when pom.xml / build.gradle change;
    # user must trigger re-import explicitly. (other values: "automatic",
    # "interactive")
    "java.configuration.updateBuildConfiguration" = "disabled";
    # Don't auto-import Gradle/Maven projects when the folder opens — wait
    # for an explicit "Java: Import Project" / "Gradle: Refresh" command.
    "java.import.gradle.enabled" = false;
    "java.import.maven.enabled" = false;
    # Stop the standalone Gradle for Java extension from auto-detecting and
    # syncing build.gradle files on workspace open.
    "gradle.autoDetect" = "off";
    "java.imports.gradle.wrapper.checksums" = [
      { sha256 = "f7566c1b7cd087d8395eb003f7c13d30ba2935f2071f08c6f275e79f63149d58"; allowed = true; }
    ];
  };

  # ── VSCodium ──────────────────────────────────────────────────────────────────
  # Managed via programs.vscodium (HM module added 2026-03-02). Settings live in
  # profiles.default.userSettings; the module writes them under ~/.config/VSCodium/User.
  # Default mutableExtensionsDir = true (no extra profiles) preserves the in-app
  # marketplace install flow into ~/.vscode-oss/extensions/.
  #
  # lowPrio: VSCodium and VS Code share locale file paths under lib/vscode/locales/.
  # Defer to VS Code on collisions so home.packages buildEnv resolves cleanly.
  programs.vscodium = {
    enable = true;
    package = lib.lowPrio vscodiumPkg;

    profiles.default = {
      userSettings = {
        "diffEditor.ignoreTrimWhitespace" = false;
        "window.titleBarStyle"            = "native"; # Bug with Electron when using custom title bar is causing 1-2px at top to pass through clicks the window below
        "editor.fontFamily"               = "JetBrains Mono"; # Chosen via https://www.codingfont.com/
        "editor.fontLigatures"            = true;
        "markdown.preview.fontSize"       = 18;
        # NOTE: this setting currently has no effect — VSCodium's patch to remove the onboarding
        # screen (PR #2804) left IOnboardingService unregistered, so workbench.contrib.startupPageRunner
        # fails to instantiate and the welcome page never auto-opens. Workaround: Ctrl+Shift+P →
        # "Help: Welcome" or "File: Open Recent…". Track fix at:
        #   https://github.com/VSCodium/vscodium/issues/2816 (bug report)
        #   https://github.com/VSCodium/vscodium/pull/2804  (regression source)
        "workbench.startupEditor"         = "welcomePage";  # show recent folders/files on new window
        # fabiospampinato.vscode-open-in-application: route .md through marktext-wrap.
        # The extension host runs with ELECTRON_RUN_AS_NODE=1, which it propagates to
        # any child process. Without scrubbing, marktext.appimage's Electron binary
        # is forced into Node mode, rejects --no-sandbox, and tries to exec the .md
        # as a JS file. The wrapper unsets the var and launches normally.
        "openInApplication.applications" = {
          "md" = "${config.home.homeDirectory}/.local/bin/marktext-wrap";
        };
        # Disable Red Hat Java extension auto-build on save / on open — builds
        # are on-demand only (Command Palette → "Java: Rebuild Projects").
        "java.autobuild.enabled" = false;
        # Don't auto re-import the project when pom.xml / build.gradle change;
        # user must trigger re-import explicitly. (other values: "automatic",
        # "interactive")
        "java.configuration.updateBuildConfiguration" = "disabled";
      };

      keybindings = [
        # Ctrl+; → Tasks: Run Task (open the task picker)
        { key = "ctrl+;"; command = "workbench.action.tasks.runTask"; }
      ];
    };
  };

  home.file.".local/bin/marktext-wrap" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Launch marktext.appimage with a clean env so it works when spawned from
      # a VSCode/VSCodium extension host (which sets ELECTRON_RUN_AS_NODE=1).
      exec setsid env -u ELECTRON_RUN_AS_NODE -u NODE_OPTIONS DESKTOPINTEGRATION=1 \
        "${config.home.homeDirectory}/AppImages/marktext.appimage" --no-sandbox "$@"
    '';
  };

  # Set MarkText's customCss (see marktextCss in the let block) without taking
  # over the whole preferences.json: MarkText writes theme, last-opened-folder,
  # window state, etc. back to that file at runtime, so it can't be a read-only
  # Nix symlink. Instead we jq-merge only the .customCss key, preserving every
  # other field. Nix is now the source of truth for customCss — edits made via
  # MarkText's Preferences UI are reverted on the next `hms`. If MarkText is
  # running during the switch, restart it to pick up the change.
  home.activation.marktextCustomCss = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dest="$HOME/.config/marktext/preferences.json"
    tmp=$(mktemp)
    if [ -f "$dest" ]; then
      ${pkgs.jq}/bin/jq --rawfile css ${marktextCss} '.customCss = $css' "$dest" > "$tmp"
    else
      $DRY_RUN_CMD mkdir -p "$(dirname "$dest")"
      ${pkgs.jq}/bin/jq -n --rawfile css ${marktextCss} '{customCss: $css}' > "$tmp"
    fi
    $DRY_RUN_CMD install -m 644 "$tmp" "$dest"
    rm -f "$tmp"
  '';

  # Point VSCodium at Microsoft's VS Code Marketplace instead of Open VSX.
  # VSCodium reads VSCODE_GALLERY_* env vars at launch (see resources/app/out/main.js).
  # environment.d covers systemd-user graphical launches (desktop entries, rofi);
  # home.sessionVariables covers terminal launches via login shell.
  # Caveat: violates MS marketplace ToS, and proprietary extensions (Pylance,
  # Remote-SSH, Live Share, cpptools debugger) license-check for official VS Code
  # and will refuse to run regardless of where they're sourced from.
  xdg.configFile."environment.d/50-vscodium-gallery.conf".text = ''
    VSCODE_GALLERY_SERVICE_URL=https://marketplace.visualstudio.com/_apis/public/gallery
    VSCODE_GALLERY_ITEM_URL=https://marketplace.visualstudio.com/items
    VSCODE_GALLERY_CONTROL_URL=https://az764295.vo.msecnd.net/extensions/marketplace.json
    VSCODE_GALLERY_EXTENSION_URL_TEMPLATE=https://{publisher}.gallery.vsassets.io/_apis/public/gallery/publisher/{publisher}/extension/{name}/{version}/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage
    VSCODE_GALLERY_RESOURCE_URL_TEMPLATE=https://{publisher}.gallery.vsassets.io/_apis/public/gallery/publisher/{publisher}/extension/{name}/{version}/assetbyname/{path}
  '';

  home.sessionVariables = {
    VSCODE_GALLERY_SERVICE_URL = "https://marketplace.visualstudio.com/_apis/public/gallery";
    VSCODE_GALLERY_ITEM_URL    = "https://marketplace.visualstudio.com/items";
    VSCODE_GALLERY_CONTROL_URL = "https://az764295.vo.msecnd.net/extensions/marketplace.json";
    VSCODE_GALLERY_EXTENSION_URL_TEMPLATE  = "https://{publisher}.gallery.vsassets.io/_apis/public/gallery/publisher/{publisher}/extension/{name}/{version}/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage";
    VSCODE_GALLERY_RESOURCE_URL_TEMPLATE   = "https://{publisher}.gallery.vsassets.io/_apis/public/gallery/publisher/{publisher}/extension/{name}/{version}/assetbyname/{path}";
  };

  # ── Nix Utilities ─────────────────────────────────────────────────────────────

  # nix-index provides `nix-locate` to find which package provides a given file,
  # and `command-not-found` integration so the shell suggests packages when a
  # command isn't found.
  programs.nix-index = {
    enable = true;
    enableBashIntegration = true;
  };

  # direnv auto-loads/unloads environments when entering/leaving directories with
  # an .envrc file. nix-direnv caches flake devShell results in the Nix store so
  # re-entering a project is instant instead of re-evaluating the flake each time.
  # Usage: echo "use flake" > .envrc && direnv allow
  programs.direnv = {
    enable = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
    config = {
      global.hide_env_diff = true;
    };
  };

  # Register Stremio as the handler for stremio:// links in ~/.config/mimeapps.list.
  #
  # Done via `xdg-mime` rather than the `xdg.mimeApps` HM option on purpose: that
  # option replaces the whole mimeapps.list with a read-only store symlink, which
  # would wipe the 150+ existing KDE-managed associations and stop KDE from ever
  # updating them. `xdg-mime default` instead sets just this one entry under
  # [Default Applications] in the mutable file, idempotently, on every `hms`.
  #
  # Why it's needed: GIO (used by Firefox/GTK) only honours a scheme handler that
  # is listed explicitly under [Default Applications]. It will NOT derive one from
  # a desktop file's MimeType= line the way KDE's xdg-mime query does — so without
  # this, clicking a stremio:// link in Firefox silently does nothing.
  home.activation.stremioSchemeHandler = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${pkgs.xdg-utils}/bin/xdg-mime default com.stremio.Stremio.desktop x-scheme-handler/stremio
  '';

  # Stremio's app-menu / KRunner entry, managed here so its Exec stays correct.
  #
  # A KDE Menu Editor-generated entry previously used
  #   --command=sh -c 'stremio -u "%u"'
  # which passes an EMPTY `-u` argument on a plain launch (when %u expands to
  # nothing). Stremio 5's `-u/--url` overrides its default startup URL, so an empty
  # value made the GTK4 webview navigate to "" and render a fully black window —
  # only on menu/KRunner launches (a bare `stremio` with no `-u` uses the default
  # URL and renders fine). This was originally misdiagnosed as an AMD GBM/llvmpipe
  # GPU fault; it is purely the empty-URL argument, and the GPU path is fine.
  #
  # This mirrors upstream's flatpak export: --file-forwarding passes a stremio://
  # link as a trailing arg only when one is present, otherwise Stremio falls back
  # to its default startup URL.
  xdg.desktopEntries."com.stremio.Stremio" = {
    name        = "Stremio (Flatpak)";
    comment     = "Freedom To Stream";
    exec        = "/usr/bin/flatpak run --branch=beta --arch=x86_64 --command=stremio --file-forwarding com.stremio.Stremio @@u %u @@";
    icon        = "com.stremio.Stremio";
    terminal    = false;
    type        = "Application";
    categories  = [ "Utility" "AudioVideo" "Video" "Player" ];
    mimeType    = [ "x-scheme-handler/stremio" ];
    settings = {
      Keywords  = "Stremio;Media;Play;";
      X-Flatpak = "com.stremio.Stremio";
    };
  };

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
      # → set LOGSEQ_API_TOKEN in home.sessionVariables above → hms + restart shell.
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
      # Needs GITHUB_TOKEN (classic PAT, repo + read:org scopes) in sessionVariables.
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
    package = pkgs.llm-agents.claude-code;
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

  # ── Claude Code skills (home.file for correct subdirectory structure) ────────
  # programs.claude-code.skills (current HM rev) generates flat .claude/skills/<name>.md
  # but Claude Code 2.x requires .claude/skills/<name>/SKILL.md — use home.file directly.

  home.file.".claude/skills/nix-switch/SKILL.md".text = ''
    ---
    name: nix-switch
    description: Run home-manager switch and show any new news items.
    ---
    1. If the user tells you to run `hms` then instead run `home-manager switch --flake ~/Projects/installs/nix#boss --no-write-lock-file` since you don't have access to `hms` from your Bash shell.
       - The `--no-write-lock-file` flag is important: only `update.sh` (run via `update-all`) is allowed to advance `flake.lock`. The repo intentionally pins nixpkgs / home-manager to a 2-week-old upstream commit so Hydra's binary cache has caught up — without that pin, ad-hoc switches risk recompiling large packages from source. If a switch fails because it wants to write the lock, surface that to the user (it means something edited `flake.nix` since the last `update-all`); don't drop the flag to "fix" it.
    2. If you see "warning: Git tree <filepath> has uncommitted changes" then just ignore that warning.
    3. If it failed, show the full error and suggest a fix.
    4. Don't run `home-manager news` unless it's part of the update.sh script.
  '';

  home.file.".claude/skills/git-commit/SKILL.md".text = ''
    ---
    name: git-commit
    description: Make a git commit of the changes from this Claude session.
    ---
    - `git add` only the files touched by this session. If there are no files touched by this
      session then give a summary of what files have been changed outside of this session and
      give a commit message suggestion.
    - If executed not in a git repo, then check the child directories for which contain git repos.
    - git commit messages should follow the Conventional Commit structure i.e.
    <type>[optional scope]: <description>

    [optional body]

    [optional footer]
      - Examples:
        - feat: allow provided config object to extend other configs
        - docs(lang): correct spelling of CHANGELOG
        - fix: minor typos in code

          see the issue for details on the typos fixed

          fixes issue #12
    - Aim to have a descriptive commit message body unless the change is trivial
      - Examples:
        - feat(api.ts): add OpenAI class with generateCommitMessage method

          This commit adds a new OpenAI class with a generateCommitMessage method that uses
          the OpenAI API to generate a commit message based on an array of messages. The
          method takes an array of ChatCompletionRequestMessage objects and returns a
          Promise that resolves to a ChatCompletionResponseMessage object. The OpenAI
          class is exported as a singleton instance named api.
        - fix(README): fixed two small typos
    - Do not `git push` unless the remote is a example.com URL. If not, then don't unless
      it's necessary because a pull request, workflow action or something else in our intended next steps needs the commit pushed first.

  '';

  home.file.".claude/skills/direnv-ignored/SKILL.md".text = ''
    ---
    name: direnv-ignored
    description: Setup nix-direnv in this repo without having to commit it.
    ---
    1. Create `.envrc` in the top-level of repo with the content `use flake "path:$PWD/.nix"`.
    2. Append to the repo `.git/info/exclude` this content: `.nix/`.
    3. Create `.nix/flake.nix` with the packages needed in this project environment.
    4. Execute `direnv allow` in order to activate nix-direnv and setup the project environment.
  '';

  home.file.".claude/skills/claude-md-ignored/SKILL.md".text = ''
    ---
    name: claude-md-ignored
    description: Add CLAUDE.md and AGENTS.md to this repo without committing them, redirecting CLAUDE.md to AGENTS.md.
    ---
    1. Append to the repo `.git/info/exclude` these two lines, one per line: `CLAUDE.md` then `AGENTS.md`.
    2. Create `AGENTS.md` in the top-level of the repo with placeholder text. Use this content:
       ```
       # Agent instructions

       <!-- Add project-specific agent guidance here. -->
       ```
    3. Create `CLAUDE.md` in the top-level of the repo with exactly this single line of content (no code fence): Read the `AGENTS.md` file now.
  '';

  home.file.".claude/skills/dbox-status/SKILL.md".text = ''
    ---
    name: dbox-status
    description: Show status of distrobox containers and their key packages.
    ---
    1. Run `dbl` to list containers and their running state.
    2. For each container, state its purpose and key packages:
       - dev: build tools (gcc, clang, cmake, ninja, gdb, valgrind), Python, Node
       - media: ffmpeg, OBS, kdenlive, HandBrake, mpv, yt-dlp
    3. Suggest next steps based on current context.
  '';

  home.file.".claude/skills/wl-copy/SKILL.md".text = ''
    ---
    name: wl-copy
    description: Copy text from Claude Code's messages to the clipboard directly in order to eliminate formatting issues.
    ---
    1. A user selecting text to copy and paste from Claude Code's messages has indenting and new line issues.
    2. Use `wl-copy` to copy your last message, it should look something like this:
      - wl-copy << 'EOF'
        Here's a bunch of text...
        EOF
        echo "Copied to clipboard"
    3. Make sure to eliminate any formatting issues before copying text.
  '';

    home.file.".claude/skills/md-open/SKILL.md".text = ''
    ---
    name: md-open
    description: Save text from Claude Code's messages to a temporary Markdown file and open it in order to more easily read the text.
    ---
    1. Claude Code's messages are rendered in a small tmux pane, which is good for multi-tasking productivity but makes reading long messages a challenge.
    2. Create a file in `/tmp/` with the extension `.md` containing the last message's contents.
    3. Open it with `~/.local/bin/marktext-wrap /tmp/filename.md` — this launches the user's Markdown reader (MarkText) detached via `setsid` with a scrubbed env, so it works from Claude Code's non-interactive shell. Do NOT use the `md` command: it is a `~/.bashrc` shell function and is not available in this shell.
  '';

  home.file.".claude/skills/yt-summary/SKILL.md".text = ''
    ---
    name: yt-summary
    description: Summarise a YouTube video using yt-dlp subtitles.
    allowed_tools:
      - Bash
      - Write
      - Read
      - Edit
    user_invocable: true
    ---
    The user will provide a YouTube URL and optionally an output file path.

    ## Steps

    1. **Get the video title:**
       ```
       yt-dlp --print title "<URL>"
       ```

    2. **Download subtitles** — prefer manual subs over auto-generated:
       ```
       yt-dlp --write-sub --sub-lang "en.*" --skip-download --sub-format vtt -o "/tmp/yt-summary" "<URL>" 2>&1
       ```
       Check if any `.vtt` files were written. If none were found (no manual subs), fall back to auto-generated:
       ```
       yt-dlp --write-auto-sub --sub-lang "en.*" --skip-download --sub-format vtt -o "/tmp/yt-summary" "<URL>" 2>&1
       ```

    3. **Extract clean text** from the VTT file (pick the `en-orig` variant if present, otherwise `en`):
       ```
       cat /tmp/yt-summary*.vtt | grep -v '^WEBVTT' | grep -v '^Kind:' | grep -v '^Language:' | grep -v '^$' | grep -v '^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]' | grep -v '^[0-9]*$' | grep -v '^\s*\$' | sed 's/<[^>]*>//g' | awk '!seen[$0]++'
       ```

    4. **Summarise** the transcript into a Markdown document with:
       - H1: the video title
       - **Source:** link to the video
       - **Summary** section: a short (2–4 sentence) overview
       - Subsections (H3) for each major topic discussed, with a paragraph each
       - A "Misc" or "Other Topics" subsection for brief tangents

    5. **Write** the summary to the path the user specified. If no path was given, ask where to save it.

    6. **Clean up** the temp files:
       ```
       rm -f /tmp/yt-summary*.vtt
       ```
  '';

  home.file.".claude/skills/usage/SKILL.md".text = ''
    ---
    name: usage
    description: Show Claude.ai subscription usage (current 5-hour session + weekly limits) by calling the OAuth usage endpoint that powers /usage.
    allowed_tools:
      - Bash
    user_invocable: true
    ---
    Run the bundled script and print its output verbatim — no extra commentary:

    ```
    python3 ~/.claude/skills/usage/usage.py
    ```

    The script reads the OAuth access token from `~/.claude/.credentials.json`,
    GETs `https://api.anthropic.com/api/oauth/usage`, and prints three lines:

        Current session: N% used (resets in Xh Ym)
        All models: N% used (resets <Weekday> H:MM AM/PM)
        Sonnet only: N% used (resets <Weekday> H:MM AM/PM)

    Endpoint is undocumented and may change without notice.
  '';

  home.file.".claude/skills/usage/usage.py" = {
    executable = true;
    text = ''
      #!/usr/bin/env python3
      import json, sys, urllib.request
      from datetime import datetime, timezone
      from pathlib import Path

      CRED = Path.home() / ".claude" / ".credentials.json"
      URL = "https://api.anthropic.com/api/oauth/usage"

      try:
          token = json.loads(CRED.read_text())["claudeAiOauth"]["accessToken"]
      except Exception as e:
          sys.exit(f"failed to read OAuth token from {CRED}: {e}")

      req = urllib.request.Request(URL, headers={"Authorization": f"Bearer {token}"})
      try:
          with urllib.request.urlopen(req, timeout=10) as r:
              data = json.load(r)
      except Exception as e:
          sys.exit(f"request failed: {e}")

      now = datetime.now(timezone.utc)

      def pct(b):
          return f"{round(b['utilization'])}% used" if b else "n/a"

      def rel(b):
          if not b or not b.get("resets_at"):
              return ""
          t = datetime.fromisoformat(b["resets_at"].replace("Z", "+00:00"))
          secs = max(0, int((t - now).total_seconds()))
          h, m = secs // 3600, (secs % 3600) // 60
          return f"resets in {h}h {m}m"

      def absfmt(b):
          if not b or not b.get("resets_at"):
              return ""
          t = datetime.fromisoformat(b["resets_at"].replace("Z", "+00:00")).astimezone()
          return f"resets {t.strftime('%a %-I:%M %p')}"

      fh = data.get("five_hour")
      sd = data.get("seven_day")
      so = data.get("seven_day_sonnet")

      print(f"Current session: {pct(fh)} ({rel(fh)})")
      print(f"All models: {pct(sd)} ({absfmt(sd)})")
      print(f"Sonnet only: {pct(so)} ({absfmt(so)})")
    '';
  };

  home.file.".claude/statusline/statusline.py" = {
    executable = true;
    text = ''
      #!/usr/bin/env python3
      # Claude Code statusline:
      #   <model> | 🌡️ <effort> | ⏳ <ctx>% | 💰 $X.XX | 📁 <dir> | 🌿 <branch> | 🔗 <repo> | ⏰ N% (Xh Ym) | 📅 N% (Day HAM/PM)
      # Reads session JSON from stdin (when invoked by Claude Code); when run from
      # a terminal directly, falls back to defaults. Usage data cached in
      # ~/.cache/claude-usage.json (15 min TTL). When the joined line exceeds the
      # terminal width, parts are wrapped across multiple lines.
      import json, os, re, shutil, subprocess, sys, time, urllib.request
      from datetime import datetime, timezone
      from pathlib import Path

      HOME = Path.home()
      CRED = HOME / ".claude" / ".credentials.json"
      CACHE = HOME / ".cache" / "claude-usage.json"
      TTL = 15 * 60
      URL = "https://api.anthropic.com/api/oauth/usage"

      payload = {}
      if not sys.stdin.isatty():
          try:
              payload = json.load(sys.stdin)
          except Exception:
              pass
      model = (payload.get("model") or {}).get("display_name") \
              or (payload.get("model") or {}).get("id") or "claude"
      cwd = (payload.get("workspace") or {}).get("current_dir") or os.getcwd()
      dir_name = os.path.basename(cwd.rstrip("/")) or "/"
      ctx_pct = int((payload.get("context_window") or {}).get("used_percentage") or 0)
      cost_info = payload.get("cost") or {}
      cost_usd = cost_info.get("total_cost_usd") or 0

      # Live session effort is nested under effort.level in the statusline
      # payload. /effort is session-only (never written to settings.json), so
      # prefer the payload; only fall back to the persisted settings.json default.
      effort = (payload.get("effort") or {}).get("level") \
          or payload.get("effortLevel") or payload.get("effort_level")
      if not effort:
          try:
              effort = json.loads((HOME / ".claude" / "settings.json").read_text()).get("effortLevel")
          except Exception:
              effort = None

      def _git(args):
          return subprocess.check_output(
              ["git", "-C", cwd] + args,
              text=True, stderr=subprocess.DEVNULL, timeout=2,
          ).strip()

      branch, staged, modified = "", 0, 0
      remote_url, repo_name = "", ""
      try:
          _git(["rev-parse", "--git-dir"])
          branch = _git(["branch", "--show-current"])
          s = _git(["diff", "--cached", "--numstat"])
          m = _git(["diff", "--numstat"])
          staged = len(s.split("\n")) if s else 0
          modified = len(m.split("\n")) if m else 0
          try:
              remote_url = _git(["remote", "get-url", "origin"])
              remote_url = re.sub(r"^git@github\.com:", "https://github.com/", remote_url)
              remote_url = re.sub(r"\.git$", "", remote_url)
              repo_name = os.path.basename(remote_url)
          except Exception:
              remote_url, repo_name = "", ""
      except Exception:
          pass

      GREEN, YELLOW, RESET = "\033[32m", "\033[33m", "\033[0m"
      git_extra = ""
      if staged:
          git_extra += f" {GREEN}+{staged}{RESET}"
      if modified:
          git_extra += f" {YELLOW}~{modified}{RESET}"

      def fetch():
          token = json.loads(CRED.read_text())["claudeAiOauth"]["accessToken"]
          req = urllib.request.Request(URL, headers={"Authorization": f"Bearer {token}"})
          with urllib.request.urlopen(req, timeout=5) as r:
              return json.load(r)

      data = None
      try:
          st = CACHE.stat()
          if time.time() - st.st_mtime < TTL:
              data = json.loads(CACHE.read_text())
      except FileNotFoundError:
          pass
      except Exception:
          data = None

      if data is None:
          try:
              data = fetch()
              CACHE.parent.mkdir(parents=True, exist_ok=True)
              CACHE.write_text(json.dumps(data))
          except Exception:
              data = {}

      now = datetime.now(timezone.utc)
      fh = data.get("five_hour") or {}
      sd = data.get("seven_day") or {}

      def reset_rel(b):
          t = b.get("resets_at")
          if not t:
              return "?"
          dt = datetime.fromisoformat(t.replace("Z", "+00:00"))
          secs = max(0, int((dt - now).total_seconds()))
          return f"{secs // 3600}h{(secs % 3600) // 60}m"

      def reset_day(b):
          t = b.get("resets_at")
          if not t:
              return "?"
          dt = datetime.fromisoformat(t.replace("Z", "+00:00")).astimezone()
          return dt.strftime("%a %-I%p") if dt.minute == 0 else dt.strftime("%a %-I:%M%p")

      parts = [model]
      if effort:
          parts.append(f"🌡️ {effort}")
      parts.append(f"⏳ {ctx_pct}%")
      parts.append(f"💰 ''${cost_usd:.2f}")
      parts.append(f"📁 {dir_name}")
      if branch:
          parts.append(f"🌿 {branch}{git_extra}")
      if remote_url:
          # Wrap the link text in SGR underline (\e[4m … \e[24m) so it gets the
          # same visible "this is a link" cue as Claude Code's own PR badge
          # (PrBadge sets <Text underline={true}>). Without it, the OSC 8 region
          # is still clickable via Ctrl+Click in Konsole/Yakuake but renders
          # indistinguishably from surrounding text — users have no idea it's
          # there. Claude Code's f_ ANSI parser carries the underline prop into
          # the rendered <Link><StyledText underline …>> so both the visual cue
          # and the OSC 8 hyperlink survive the Ink round-trip.
          link = f"\033]8;;{remote_url}\033\\\033[4m{repo_name}\033[24m\033]8;;\033\\"
          parts.append(f"🔗 {link}")
      if fh:
          parts.append(f"⏰ {round(fh.get('utilization', 0))}% ({reset_rel(fh)})")
      else:
          parts.append("⏰ ?")
      if sd:
          parts.append(f"📅 {round(sd.get('utilization', 0))}% ({reset_day(sd)})")
      else:
          parts.append("📅 ?")

      ANSI_RE = re.compile(r"\x1b\[[0-9;]*m|\x1b\]8;[^\x07\x1b]*(?:\x07|\x1b\\)")

      def vlen(s):
          # Visible width: strip ANSI/OSC-8 escapes, then count non-ASCII
          # (mostly emoji) as 2 cols to approximate East-Asian wide width.
          clean = ANSI_RE.sub("", s)
          return len(clean) + sum(1 for c in clean if ord(c) > 127)

      # Claude Code spawns the statusline with no tty and piped stdio, so the
      # only reliable width source is $COLUMNS, which Claude Code v2.1.153+
      # sets before exec (anthropics/claude-code#22115, #5430). On older
      # versions the wrap falls back to 120 and the host terminal clips lines.
      try:
          width = int(os.environ.get("COLUMNS") or 0) \
                  or shutil.get_terminal_size((120, 24)).columns
      except Exception:
          width = 120

      SEP = " | "
      lines, cur, cur_w = [], "", 0
      for p in parts:
          pw = vlen(p)
          if not cur:
              cur, cur_w = p, pw
              continue
          if cur_w + len(SEP) + pw <= width:
              cur += SEP + p
              cur_w += len(SEP) + pw
          else:
              lines.append(cur)
              cur, cur_w = p, pw
      if cur:
          lines.append(cur)
      print("\n".join(lines))
    '';
  };


  # ── Codex ──────────────────────────────────────────────────────────────────────

  programs.codex = {
    enable  = true;
    package = pkgs.llm-agents.codex;
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

  # ── SSH ──────────────────────────────────────────────────────────────────────

  programs.ssh = {
    enable = true;
    # Suppress deprecation warning — defaults will be removed in a future HM release;
    # all desired settings are explicitly set in settings below.
    enableDefaultConfig = false;
    settings."*" = {
      serverAliveInterval = 60;
      serverAliveCountMax = 10;
    };
  };

  # The activation script below converts the HM-managed ssh config symlink
  # into a real file so Flatpak sandboxes (e.g. Vorta) can read it without
  # /nix/store access. force = true lets HM overwrite the regular file on
  # the next switch without a "would be clobbered" / "in the way" warning.
  home.file.".ssh/config".force = true;

  # Replace the Nix-store symlink with a real file so Flatpak sandboxes
  # (e.g. Vorta) can follow ~/.ssh/config without needing /nix/store access.
  home.activation.sshConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    dest="$HOME/.ssh/config"
    if [ -L "$dest" ]; then
      src=$(readlink -f "$dest")
      $DRY_RUN_CMD rm "$dest"
      $DRY_RUN_CMD install -m 600 "$src" "$dest"
    fi
  '';

}
