{ config, pkgs, lib, ... }:

let
  jsonFormat = pkgs.formats.json { };

  # Written as a mutable file (not a Nix-store symlink) so Claude Code can
  # modify it at runtime — e.g. the /effort slash command rewrites this file.
  # Same content that programs.claude-code.settings would generate, but
  # deployed via home.activation (install -m 644) instead of home.file.
  # See: home-manager#8654 (same issue that forced settings to be omitted for
  # gemini-cli). Changes made at runtime are overwritten on the next `hms`.
  claudeCodeSettings = pkgs.writeText "claude-code-settings.json" (builtins.toJSON {
    "$schema"           = "https://json.schemastore.org/claude-code-settings.json";
    includeCoAuthoredBy = false;
    effortLevel         = "medium";
    permissions = {
      allow = [ "WebFetch" "WebSearch" ];
    };
    hooks = {
      Stop             = [{ hooks = [{ type = "command"; command = "bash ~/.claude/hooks/notify-waiting.sh stop";      }]; }];
      Notification     = [{ hooks = [{ type = "command"; command = "bash ~/.claude/hooks/notify-waiting.sh";           }]; }];
      UserPromptSubmit = [{ hooks = [{ type = "command"; command = "bash ~/.claude/hooks/notify-reset-dedupe.sh";      }]; }];
    };
  });
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
      # Default identity (1 = VictorVow); use `git su [1|2]` to switch per-repo
      # Identity 2 (USER2): 22418751+USER2@users.noreply.github.com, key GPGKEY2
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
        in
          "!f() { case \"$1\" in"
          + " 1) ${set1};;"
          + " 2) ${set2};;"
          + " \"\") echo \"current: $(git config user.name) <$(git config user.email)>\";;"
          + " *) echo 'usage: git su [1|2]';;"
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

  # Auto-select USER2 identity for repos under ~/Documents/ESSENTIALS/installs/
  # The trailing slash makes gitdir: match any repo inside the directory tree.
  # See docs/git-identity-management.md for the full picture of identity management.
  programs.git.includes = [
    {
      condition = "gitdir:~/Documents/ESSENTIALS/installs/";
      path      = "~/.config/git/identity-USER2";
    }
  ];

  # Identity snippet loaded by the includeIf above
  xdg.configFile."git/identity-USER2".text = ''
    [user]
        name       = USER2
        email      = 22418751+USER2@users.noreply.github.com
        signingkey = GPGKEY2
  '';

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

      # Inactive windows: dim text, no background
      set -g window-status-format        " #I:#W#{?window_flags,#{window_flags}, } "
      set -g window-status-style         fg="#666688",bg=default

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

  # Tell ripgrep (and tools that use it, like Claude Code and Gemini CLI) to skip
  # the rclone FUSE mount — traversing it causes high CPU on the rclone mount process.
  home.file.".ignore".text = ''
    Mounts/
  '';

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

  programs.vscode = {
    enable = true;
    # Nix store binaries can't have root-owned 4755 perms, so the SUID sandbox
    # helper is always misconfigured. Wrap the binary to pass --no-sandbox.
    package = pkgs.symlinkJoin {
      name = "vscode";
      inherit (pkgs.vscode) pname version meta;
      paths = [ pkgs.vscode ];
      buildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/code --add-flags "--no-sandbox"
      '';
    };
    # mutableExtensionsDir allows marketplace / manual installs to coexist alongside
    # Nix-managed extensions. Without this, HM would wipe any unlisted extension.
    mutableExtensionsDir = true;

    profiles.default = {
      # Share MCP servers from programs.mcp.servers with VS Code clients
      # (Continue, Claude Code extension, etc.). Written to VSCode's userMcp config.
      enableMcpIntegration = true;

      # Extensions available in pkgs.vscode-extensions (nixpkgs subset).
      # Extensions NOT in nixpkgs are managed by VS Code's built-in sync / marketplace.
      extensions = with pkgs.vscode-extensions; [
        bbenoist.nix
        dbaeumer.vscode-eslint
        eamodio.gitlens
        esbenp.prettier-vscode
        ms-python.python
        ms-python.vscode-pylance
        ms-python.debugpy
        ms-vscode.cpptools
        oderwat.indent-rainbow
        redhat.vscode-yaml
        rust-lang.rust-analyzer
        tamasfe.even-better-toml
        usernamehw.errorlens
      ];

    # Full extension inventory (for documentation / future declarative migration).
    # Extensions marked (*) are managed above via nixpkgs; the rest via VS Code sync.
    # To move more to Nix: use pkgs.vscode-utils.extensionsFromVscodeMarketplace with sha256.
    #
    # (*) bbenoist.nix
    # (*) dbaeumer.vscode-eslint
    # (*) eamodio.gitlens
    # (*) esbenp.prettier-vscode
    # (*) ms-python.python
    # (*) ms-python.vscode-pylance
    # (*) ms-python.debugpy
    # (*) ms-vscode.cpptools
    # (*) oderwat.indent-rainbow
    # (*) redhat.vscode-yaml
    # (*) rust-lang.rust-analyzer
    # (*) tamasfe.even-better-toml
    # (*) usernamehw.errorlens
    #     amazonwebservices.amazon-q-vscode
    #     anthropic.claude-code
    #     asvetliakov.vscode-neovim
    #     ccimage.jsonviewer
    #     christian-kohler.npm-intellisense
    #     continue.continue
    #     davidanson.vscode-markdownlint
    #     docker.docker
    #     donjayamanne.githistory
    #     editorconfig.editorconfig
    #     firefox-devtools.vscode-firefox-debug
    #     formulahendry.code-runner
    #     fuzionix.devtool-plus
    #     gbasood.byond-dm-language-support
    #     github.copilot-chat
    #     github.vscode-github-actions
    #     leizongmin.node-module-intellisense
    #     ms-azuretools.vscode-containers
    #     ms-dotnettools.csdevkit
    #     ms-dotnettools.csharp
    #     ms-dotnettools.vscode-dotnet-runtime
    #     ms-python.vscode-python-envs
    #     ms-toolsai.jupyter
    #     ms-toolsai.jupyter-keymap
    #     ms-toolsai.jupyter-renderers
    #     ms-toolsai.vscode-jupyter-cell-tags
    #     ms-toolsai.vscode-jupyter-slideshow
    #     ms-vscode-remote.remote-containers
    #     ms-vscode.cmake-tools
    #     ms-vscode.cpp-devtools
    #     ms-vscode.cpptools-extension-pack
    #     ms-vscode.cpptools-themes
    #     ms-vsliveshare.vsliveshare
    #     nickdemayo.vscode-json-editor
    #     ofhumanbondage.react-proptypes-intellisense
    #     onlyutkarsh.git-config-user-profiles
    #     platymuus.dm-langclient
    #     redhat.java
    #     ritwickdey.liveserver
    #     saoudrizwan.claude-dev
    #     sourcegraph.javascript-typescript
    #     tauri-apps.tauri-vscode
    #     twxs.cmake
    #     vscjava.vscode-gradle
    #     vscjava.vscode-java-debug
    #     vscjava.vscode-java-dependency
    #     vscjava.vscode-java-test
    #     vscjava.vscode-maven
    #     zainchen.json

      userSettings = {
      # ── Telemetry ──────────────────────────────────────────────────────────────
      "telemetry.telemetryLevel"      = "off";
      "redhat.telemetry.enabled"      = false;


      # ── Editor ─────────────────────────────────────────────────────────────────
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

      # Pin the integrated terminal shell to bashInteractive. The nixpkgs VSCode
      # wrapper resolves `bash` to the minimal (non-interactive) bash in its own
      # closure, which is built without programmable completion or prompt-string
      # decoding — so starship's \[...\] wrappers render literally and compgen is
      # missing. bashInteractive is what Yakuake/programs.bash use.
      "terminal.integrated.defaultProfile.linux" = "bash";
      "terminal.integrated.profiles.linux" = {
        bash = {
          path = "${pkgs.bashInteractive}/bin/bash";
        };
      };

      # ── Theme ──────────────────────────────────────────────────────────────────
      "workbench.colorTheme" = "Dark+";

      # ── Claude Code ────────────────────────────────────────────────────────────
      "claudeCode.preferredLocation" = "panel";

      # ── Copilot ────────────────────────────────────────────────────────────────
"github.copilot.nextEditSuggestions.enabled" = true;

      # ── Continue ───────────────────────────────────────────────────────────────
# yaml.schemas intentionally omitted: version-specific Continue paths become
      # stale on every extension update; Continue manages its own schema registration.

      # ── vscode-neovim ──────────────────────────────────────────────────────────
      # Point to the Nix-managed nvim binary (was: /home/linuxbrew/.linuxbrew/bin/nvim)
      "extensions.experimental.affinity"          = { "asvetliakov.vscode-neovim" = 1; };
      "vscode-neovim.neovimExecutablePaths.linux"  = "${pkgs.neovim}/bin/nvim";
      "vscode-neovim.neovimExecutablePaths.darwin" = "";
      "vscode-neovim.neovimExecutablePaths.win32"  = "";

      # ── Git Config User Profiles ────────────────────────────────────────────────
      # (extension: onlyutkarsh.git-config-user-profiles)
      "gitConfigUser.profiles" = [
        {
          label      = "Psuedononymous [VictorVow]";
          email      = "12621257+VictorVow@users.noreply.github.com";
          userName   = "VictorVow";
          selected   = true;
          id         = "f4feda82-9f84-40ed-ae25-45893e812650";
          signingKey = "GPGKEY1";
        }
        {
          label      = "Personal [USER2]";
          email      = "22418751+USER2@users.noreply.github.com";
          userName   = "USER2";
          selected   = false;
          id         = "80ec2d0d-bf53-4508-a832-380861ee3118";
          signingKey = "GPGKEY2";
        }
      ];
      "gitConfigUser.workspaceProfileSelections" = {
        "/home/boss/Documents/ESSENTIALS/installs" = "80ec2d0d-bf53-4508-a832-380861ee3118";
      };

      # ── Misc extension settings ─────────────────────────────────────────────────
      "dreammaker.autoUpdate"   = true;
      "dreammaker.tickOnCreate" = true;
      "docker.extension.enableComposeLanguageServer" = false;
      "java.autobuild.enabled"                       = false;
      "java.imports.gradle.wrapper.checksums" = [
        { sha256 = "f7566c1b7cd087d8395eb003f7c13d30ba2935f2071f08c6f275e79f63149d58"; allowed = true; }
      ];
      };
    };
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

  # ── App Launcher ──────────────────────────────────────────────────────────────

  programs.rofi = {
    enable  = true;
    package = pkgs.rofi;
    font    = "Noto Sans 11";
    theme   = "Arc-Dark";
    extraConfig = {
      show-icons = true;
      icon-theme = "breeze";
    };
  };

  # ── MCP Servers — shared registry ─────────────────────────────────────────────
  # Outputs ~/.config/mcp/mcp.json, consumed by:
  #   - programs.claude-code (via enableMcpIntegration = true → ~/.claude/.mcp.json)
  #   - programs.codex       (via enableMcpIntegration = true → ~/.codex/.mcp.json)
  #   - programs.vscode.profiles.default (via enableMcpIntegration = true → VSCode userMcp)
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
    enable               = true;
    package              = pkgs.claude-code;  # required when enableMcpIntegration = true
    enableMcpIntegration = true;              # merges programs.mcp.servers → ~/.claude/.mcp.json

    # ── Agents — creates ~/.claude/agents/<key>.md ────────────────────────────────

    agents = {

      "nix-helper" = ''
        ---
        name: nix-helper
        description: Assist with Home Manager and Nix flake configuration changes.
          Use when editing nix/modules/*.nix, flake.nix, or debugging eval errors.
        ---
        You are a Nix/Home Manager expert. When making changes:
        - Remember that the main Nix config is located at ~/Documents/ESSENTIALS/installs
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

    # ── Skills — creates ~/.claude/skills/<key>/SKILL.md ─────────────────────────
    # Can be run directly within a Claude window (similar to `/effort` in order to take an action)

    skills = {

      "nix-switch" = ''
        ---
        description: Run home-manager switch and show any new news items.
        ---
        1. If the user tells you to run `hms` then instead run `home-manager switch --flake ~/Documents/ESSENTIALS/installs/nix#boss` since you don't have access to `hms` from your Bash shell.
        2. If you see "warning: Git tree <filepath> has uncommitted changes" then just ignore that warning.
        3. If it failed, show the full error and suggest a fix.
        4. Don't run `home-manager news` unless it's part of the update.sh script. 
      '';

      "git-commit" = ''
        ---
        description: Make a git commit of the changes from this Claude session.
        ---
        - `git add` only the files touched by this session.
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
        - Do not `git push` unless it's necessary because a pull request, workflow action or 
          something else in our intended next steps needs the commit pushed first.
      '';

      "dbox-status" = ''
        ---
        description: Show status of distrobox containers and their key packages.
        ---
        1. Run `dbl` to list containers and their running state.
        2. For each container, state its purpose and key packages:
           - dev: build tools (gcc, clang, cmake, ninja, gdb, valgrind), Python, Node
           - media: ffmpeg, OBS, kdenlive, HandBrake, mpv, yt-dlp
        3. Suggest next steps based on current context.
      '';

      "yt-summary" = ''
        ---
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
           cat /tmp/yt-summary*.vtt | grep -v '^WEBVTT' | grep -v '^Kind:' | grep -v '^Language:' | grep -v '^$' | grep -v '^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]' | grep -v '^[0-9]*$' | grep -v '^\s*$' | sed 's/<[^>]*>//g' | awk '!seen[$0]++'
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

    };

  };

  # ── Codex ──────────────────────────────────────────────────────────────────────

  programs.codex = {
    enable               = true;
    package              = pkgs.codex;
    enableMcpIntegration = true;  # merges programs.mcp.servers → ~/.codex/.mcp.json
  };

  # ── Gemini CLI ─────────────────────────────────────────────────────────────────
  # enableMcpIntegration merges programs.mcp.servers → settings.mcpServers, which
  # causes HM to write ~/.gemini/settings.json as a read-only Nix store symlink.
  # OAuth tokens live in ~/.gemini/oauth_creds.json (unmanaged), so the symlink
  # no longer blocks login (home-manager#8654). The auth selection is preserved
  # here so gemini-cli doesn't re-prompt on launch.

  programs.gemini-cli = {
    enable  = true;
    package = pkgs.gemini-cli;
    enableMcpIntegration = true;
    settings.security.auth.selectedType = "oauth-personal";
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
    # all desired settings are explicitly set in matchBlocks below.
    enableDefaultConfig = false;
    matchBlocks."*" = {
      serverAliveInterval = 60;
      serverAliveCountMax = 10;
    };
  };

  # Replace the Nix-store symlink with a real file so Flatpak sandboxes
  # (e.g. Vorta) can follow ~/.ssh/config without needing /nix/store access.
  home.activation.sshConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dest="$HOME/.ssh/config"
    if [ -L "$dest" ]; then
      src=$(readlink -f "$dest")
      $DRY_RUN_CMD rm "$dest"
      $DRY_RUN_CMD install -m 600 "$src" "$dest"
    fi
  '';

}
