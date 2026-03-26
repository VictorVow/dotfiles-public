{ config, pkgs, lib, ... }:

let
  jsonFormat = pkgs.formats.json { };
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
      # Default identity (1 = Victor239); use `git su [1|2]` to switch per-repo
      # Identity 2 (USER2): 22418751+USER2@users.noreply.github.com, key GPGKEY2
      user.name  = "Victor239";
      user.email = "12621257+Victor239@users.noreply.github.com";

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

      alias.ll = "log --oneline";
      alias.su =
        let
          set1 = "git config user.name 'Victor239'"
            + " && git config user.email '12621257+Victor239@users.noreply.github.com'"
            + " && git config user.signingkey 'GPGKEY1'"
            + " && echo 'switched -> Victor239 (identity 1)'";
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

      # Visual indicator in the status bar when the PREFIX key is active
      set -g status-right "#{?client_prefix,⌨️  PREFIX,}"
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

  # Tell ripgrep (and tools that use it, like Claude Code and Gemini CLI) to skip
  # the rclone FUSE mount — traversing it causes high CPU on the rclone mount process.
  home.file.".ignore".text = ''
    Mounts/
  '';

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
      "telemetry.enableCrashReporter" = false;
      "telemetry.enableTelemetry"     = false;
      "redhat.telemetry.enabled"      = false;
      "amazonQ.telemetry"             = false;

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
      "terminal.integrated.allowChords" = false;

      # ── Claude Code ────────────────────────────────────────────────────────────
      "claudeCode.preferredLocation" = "panel";

      # ── Copilot ────────────────────────────────────────────────────────────────
      "github.copilot.advanced"                    = {};
      "github.copilot.nextEditSuggestions.enabled" = true;

      # ── Continue ───────────────────────────────────────────────────────────────
      "continue.showInlineTip" = false;
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
          label      = "Psuedononymous [Victor239]";
          email      = "12621257+Victor239@users.noreply.github.com";
          userName   = "Victor239";
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
      "cmake.showOptionsMovedNotification"           = false;
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
  };
}
