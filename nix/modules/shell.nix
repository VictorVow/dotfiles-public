{ config, pkgs, lib, ... }:

# Shell environment configuration.
# Manages PATH, environment variables, aliases, and Bash integration.
# Also installs AI CLI tools that are not yet packaged in nixpkgs via npm.
{
  # ── Bash Integration ──────────────────────────────────────────────────────────

  programs.bash = {
    enable = true;
    # Home Manager appends these to ~/.bashrc automatically.
    # Note: starship, nix-index, and other program integrations are injected
    # automatically by their respective programs.* modules in programs.nix.

    initExtra = ''
      # ── HM session vars: re-source when nix store path changes ──────────────
      # home.sessionVariables are blocked by __HM_SESS_VARS_SOURCED (a "source
      # once" guard). New vars added after login never appear until full logout,
      # because child shells inherit the flag and skip re-sourcing.
      # Fix: track the active store path in __HM_SESS_VARS_PATH; re-source
      # (and reset the guard) whenever hms produces a new store derivation.
      _hm_sess_current=$(readlink ~/.nix-profile/etc/profile.d/hm-session-vars.sh 2>/dev/null)
      if [[ "$_hm_sess_current" != "$__HM_SESS_VARS_PATH" ]]; then
        unset __HM_SESS_VARS_SOURCED
        source ~/.nix-profile/etc/profile.d/hm-session-vars.sh
        export __HM_SESS_VARS_PATH="$_hm_sess_current"
      fi
      unset _hm_sess_current

      # ── Homebrew (Linux) ────────────────────────────────────────────────────
      # Homebrew is kept for packages not available in nixpkgs.
      # The nix-managed PATH takes priority; Homebrew fills in the gaps.
      if [ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
      fi

      # ── Rust / Cargo ────────────────────────────────────────────────────────
      # rustup (installed via nixpkgs) installs toolchains to ~/.cargo.
      # The cargo bin dir needs to be on PATH for installed binaries.
      export PATH="$HOME/.cargo/bin:$PATH"

      # ── npm global packages (user-local) ────────────────────────────────────
      # AI CLI tools not yet in nixpkgs are installed via npm to ~/.npm-global.
      # See the activation script below for the install logic.
      export NPM_CONFIG_PREFIX="$HOME/.npm-global"
      export PATH="$HOME/.npm-global/bin:$PATH"

      # ── Pipx ────────────────────────────────────────────────────────────────
      # pipx installs remain on the system from ansible; expose their bin dir.
      export PATH="$HOME/.local/bin:$PATH"

      # ── Android SDK ─────────────────────────────────────────────────────────
      # ANDROID_HOME is set via home.sessionVariables below.
      export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/tools:$ANDROID_HOME/emulator:$PATH"
      export PATH="$HOME/.pub-cache/bin:$PATH"   # Flutter pub-cache

      # ── Flatpak exports ─────────────────────────────────────────────────────
      # Needed for VSCode NeoVim extension and other Flatpak-installed binaries.
      export PATH="$PATH:/var/lib/flatpak/exports/bin"

      # ── Native Firefox ──────────────────────────────────────────────────────
      # Firefox installed as a native binary tarball (not Flatpak or snap).
      if [ -d "/home/boss/Documents/ESSENTIALS/Programs/firefox" ]; then
        export PATH="/home/boss/Documents/ESSENTIALS/Programs/firefox:$PATH"
      fi

      # ── Wayland / XDG ───────────────────────────────────────────────────────
      # Required for portals, screen sharing, and Wayland tooling.
      export XDG_RUNTIME_DIR="/run/user/$(id -u)"

      # ── Console Ninja ───────────────────────────────────────────────────────
      # IDE runtime-value inspector; installed via the IDE extension, not Nix.
      export PATH="$HOME/.console-ninja/.bin:$PATH"

      # ── grab-site (ArchiveTeam web archiving tool) ───────────────────────────
      # Installed in a dedicated venv; exposed here for CLI use.
      export PATH="$PATH:$HOME/gs-venv/bin"

      # ── fnm (Fast Node Manager) ─────────────────────────────────────────────
      # --use-on-cd: auto-switch Node version when entering a directory with .node-version/.nvmrc
      # --resolve-engines=false: don't try to resolve engines.node from package.json — fnm can't
      #   compare against the system node version and will error if no fnm-managed version matches
      eval "$(fnm env --use-on-cd --resolve-engines=false --shell bash)"

      # ── dnvm (.NET version manager) ─────────────────────────────────────────
      # Manages .NET SDK versions independently of the system Nix dotnet-sdk.
      if [ -f "$HOME/.local/share/dnvm/env" ]; then
        . "$HOME/.local/share/dnvm/env"
      fi

      # ── Distrobox: tint prompt when inside a container ───────────────────────
      # Makes it visually obvious which Distrobox container you're working in.
      if [ -n "$DISTROBOX_ENTER_PATH" ]; then
        export PS1='\[\e[1;36m\]\u@\h:\w \[\e[0m\]'
      fi

      # ── fastfetch ────────────────────────────────────────────────────────────
      # Show system info on:
      #   - new Yakuake sessions (parent process is yakuake)
      #   - new Distrobox container shells
      #   - return to local shell after an SSH session exits
      if [[ "$(ps -p $PPID -o comm= 2>/dev/null)" == "yakuake" ]] || \
         [[ -n "$DISTROBOX_ENTER_PATH" ]]; then
        fastfetch
      fi

      # Wrap ssh: run fastfetch when returning from a remote session
      ssh() {
        command ssh "$@"
        fastfetch
      }

      # Colours for ls
      eval "$(dircolors -b)"
    '';

    # ── Shell Aliases ──────────────────────────────────────────────────────────
    shellAliases = {
      # Home Manager shortcuts.
      # NOTE: Aliases are only loaded in interactive shells — non-interactive tools
      # (e.g. Claude's Bash tool, scripts, cron jobs) cannot resolve them.
      # Use the full `home-manager switch --flake ...` command in those contexts.
      hms   = "home-manager switch --flake ~/Documents/ESSENTIALS/installs/nix#boss";
      hmn   = "home-manager news --flake ~/Documents/ESSENTIALS/installs/nix#boss";

      # Nix shortcuts
      nsp   = "nix search nixpkgs";       # Search nixpkgs: nsp <package>
      nsh   = "nix shell nixpkgs#";       # Temp shell with package: nsh <package>

      # Distrobox shortcuts
      dbe   = "distrobox enter";
      dbl   = "distrobox list";

      # System update shortcut — runs all package managers in one pass
      update-all = "~/Documents/ESSENTIALS/installs/update.sh";

      # Colours for ls - may be redundantc
      ls = "ls --color=auto";

      # Launch a tmux agent workspace (auto-numbered session, no conflicts):
      #          67%        33%
      # ┌────────────────────┬──────────┐
      # │    top-L           │  top-R   │   67%
      # │                    │          │
      # ├───────────────┬────┴──────────┤
      # │    bot-L      │    bot-R      │   33%
      # └───────────────┴───────────────┘
      #       50%             50%
      tmux-agent = "tmux new-session \\; split-window -v -p 33 \\; select-pane -t 0 \\; split-window -h -p 33 \\; select-pane -t 2 \\; split-window -h \\; select-pane -t 0 \\; send-keys -t 1 'cd ~/Documents/ESSENTIALS/installs' Enter";
    };
  };

  # ── Session Variables ─────────────────────────────────────────────────────────
  # These are set for the full desktop session (not just terminal), so GUI apps
  # launched from the KDE application launcher also see them.

  home.sessionVariables = {
    # Default terminal editor — nano is simpler for quick edits; nvim is still available
    EDITOR = "nano";
    VISUAL = "nano";

    # npm global prefix — keeps npm global installs user-local (no sudo)
    NPM_CONFIG_PREFIX = "$HOME/.npm-global";

    # Go workspace root
    GOPATH = "$HOME/go";

    # Podman rootless networking — required for Distrobox rootless containers
    PODMAN_USERNS = "keep-id";

    # Force GTK apps to use the KDE file chooser (thumbnails, bookmarks, etc.)
    # https://wiki.archlinux.org/title/Uniform_look_for_Qt_and_GTK_applications
    GDK_DEBUG = "portals";

    # Firefox Wayland native support (was previously in ~/.pam_environment)
    MOZ_ENABLE_WAYLAND = "1";

    # Android SDK root — SDK tool paths are added to PATH in initExtra above
    ANDROID_HOME = "$HOME/Documents/Dev/Android/Sdk";

    # MCP server secrets — inherited by MCP server subprocesses at runtime.
    # DO NOT put these in programs.mcp.servers env blocks; the env block overrides
    # shell-inherited values and an empty string would shadow the real value.
    LOGSEQ_API_TOKEN = "7z5opygq2";   # ← paste your LogSeq HTTP API token (Settings → HTTP APIs)
    GITHUB_TOKEN     = "REDACTED_TOKEN";   # ← paste a GitHub PAT with repo + read:org scopes (github.com → Settings → Developer settings → PATs)
  };

  # ── Activation: Ensure Flathub user remote is configured ─────────────────────
  # Runs on every `hms`. The --if-not-exists flag makes it idempotent.
  # This ensures ansible's 3rd-party scripts (e.g. flathub-gpu-screen-recorder.sh)
  # and flatpak.sh can install user-scope Flatpaks without manual setup.

  home.activation.flathubRemote = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    if command -v flatpak &>/dev/null; then
      $DRY_RUN_CMD flatpak remote-add --if-not-exists --user flathub \
        https://dl.flathub.org/repo/flathub.flatpakrepo 2>/dev/null || true
    fi
  '';

  # ── Activation: Install AI CLI tools via npm ──────────────────────────────────
  # These tools are not yet packaged in nixpkgs. They are installed once into
  # ~/.npm-global. Re-running `home-manager switch` will check and install
  # any that are missing, but won't upgrade existing installs automatically.
  # To upgrade: npm update -g --prefix ~/.npm-global

  home.activation.npmGlobalPackages = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # HM activation runs in an isolated environment without standard system tools.
    # Prepend nodejs (for node/npm) and system paths (for tar, sh, etc. used by
    # npm postinstall scripts like @vscode/ripgrep's binary download).
    export PATH="${pkgs.nodejs}/bin:/usr/bin:/bin:$PATH"
    NPM="${pkgs.nodejs}/bin/npm"
    if ! [ -x "$NPM" ]; then
      echo "WARNING: npm not found at ${pkgs.nodejs}/bin/npm, skipping AI CLI tool installation"
    else
      export NPM_CONFIG_PREFIX="$HOME/.npm-global"
      mkdir -p "$HOME/.npm-global"

      # Helper: install an npm package globally if it's not already installed
      _npm_global_install() {
        local pkg="$1"
        local bin="$2"  # binary name to check for (defaults to package name)
        bin="''${bin:-$pkg}"
        if ! command -v "$bin" &>/dev/null && \
           [ ! -f "$HOME/.npm-global/bin/$bin" ]; then
          echo "Installing npm global package: $pkg"
          $DRY_RUN_CMD "$NPM" install --global --prefix "$HOME/.npm-global" "$pkg"
        fi
      }

      # AI / LLM CLI tools not yet in nixpkgs:
      _npm_global_install "cline" "cline"                    # Cline LLM CLI
      _npm_global_install "@continuedev/cli" "continue"      # Continue Dev LLM CLI
      _npm_global_install "opencode-ai" "opencode"           # OpenCode agentic AI
      _npm_global_install "@githubnext/github-copilot-cli" "github-copilot-cli"  # Copilot CLI

      unset -f _npm_global_install
    fi
  '';
}
