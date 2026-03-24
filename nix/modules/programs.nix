{ config, pkgs, lib, ... }:

# Home Manager program configurations.
# Using programs.* modules instead of bare packages gives Home Manager the
# ability to manage config files, shell integrations, and user services.
{
  # ── Version Control ──────────────────────────────────────────────────────────

  programs.git = {
    enable = true;
    # Minimal defaults — override in ~/.config/git/config for machine-specific
    # settings (user.name, user.email, signing key, etc.)
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = false;
      # Use libsecret (KDE Wallet) for credential storage.
      # Requires gitAndTools.gitCredentialLibsecret in packages.nix.
      credential.helper = "libsecret";
    };
  };

  # Git LFS — large file storage integration
  programs.git.lfs.enable = true;

  # ── Terminal Multiplexers ─────────────────────────────────────────────────────

  programs.tmux = {
    enable = true;
    # Start windows and panes at index 1 (more ergonomic than 0)
    baseIndex = 1;
    # Enable mouse support for scrolling and pane selection
    mouse = true;
    # Use a longer scrollback history (default is 2000)
    historyLimit = 10000;
    # 256-colour terminal for better colour rendering in editors
    terminal = "screen-256color";
    extraConfig = ''
      # Reload config with Prefix + r
      bind r source-file ~/.config/tmux/tmux.conf \; display "Config reloaded"

      # More intuitive pane splitting: | for vertical, - for horizontal
      bind | split-window -h -c "#{pane_current_path}"
      bind - split-window -v -c "#{pane_current_path}"

      # Vim-style pane navigation
      bind h select-pane -L
      bind j select-pane -D
      bind k select-pane -U
      bind l select-pane -R
    '';
  };

  # ── Shell Prompt ──────────────────────────────────────────────────────────────

  programs.starship = {
    enable = true;
    # Replaces `brew install starship` and manual shell init in .bashrc.
    # Home Manager automatically adds the `eval "$(starship init bash)"` snippet.
    settings = {
      # Add a blank line before each prompt for readability
      add_newline = true;
      # Show command duration for commands taking longer than 2 seconds
      cmd_duration = {
        min_time = 2000;
        format = "took [$duration]($style) ";
      };
    };
  };

  # ── Text Editors ──────────────────────────────────────────────────────────────

  programs.neovim = {
    enable = true;
    # Replaces `brew install neovim`.
    # Set as the default editor for the system.
    defaultEditor = true;
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
      # Show CPU usage as a percentage of total (not per-core)
      cpu_count_from_zero = false;
      # Show tree view by default
      tree_view = true;
    };
  };

  # ── File Sync ─────────────────────────────────────────────────────────────────

  # Run Syncthing as a user-level systemd service (no root required).
  # Web UI available at http://127.0.0.1:8384
  services.syncthing = {
    enable = true;
    # tray.enable = true;  # Uncomment to enable system tray icon (requires tray app)
  };

  # ── Nix Utilities ─────────────────────────────────────────────────────────────

  # nix-index provides `nix-locate` to find which package provides a given file,
  # and `command-not-found` integration so the shell suggests packages when a
  # command isn't found.
  programs.nix-index = {
    enable = true;
    enableBashIntegration = true;
  };
}
