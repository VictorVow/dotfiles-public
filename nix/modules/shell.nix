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
      # ── nvm (Node Version Manager) ──────────────────────────────────────────
      # nvm is installed via nixpkgs but requires shell initialisation.
      # This sources the nvm script so `nvm use`, `nvm install`, etc. work.
      export NVM_DIR="$HOME/.nvm"
      [ -s "${pkgs.nvm}/share/nvm/nvm.sh" ] && \. "${pkgs.nvm}/share/nvm/nvm.sh"
      [ -s "${pkgs.nvm}/share/nvm/bash_completion" ] && \. "${pkgs.nvm}/share/nvm/bash_completion"

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
    '';

    # ── Shell Aliases ──────────────────────────────────────────────────────────
    shellAliases = {
      # Home Manager shortcuts
      hms   = "home-manager switch --flake ~/Documents/ESSENTIALS/installs/nix#boss";
      hmn   = "home-manager news --flake ~/Documents/ESSENTIALS/installs/nix#boss";

      # Nix shortcuts
      nsp   = "nix search nixpkgs";       # Search nixpkgs: nsp <package>
      nsh   = "nix shell nixpkgs#";       # Temp shell with package: nsh <package>

      # Distrobox shortcuts
      dbe   = "distrobox enter";
      dbl   = "distrobox list";

      # System update shortcut (runs home-manager + apt + brew)
      update-all = "hms && sudo apt update && sudo apt upgrade -y && brew update && brew upgrade";
    };
  };

  # ── Session Variables ─────────────────────────────────────────────────────────
  # These are set for the full desktop session (not just terminal), so GUI apps
  # launched from launchers also see them.

  home.sessionVariables = {
    # Default editor (also set via programs.neovim.defaultEditor, belt-and-suspenders)
    EDITOR = "nvim";
    VISUAL = "nvim";

    # npm global prefix — keeps npm global installs user-local (no sudo)
    NPM_CONFIG_PREFIX = "$HOME/.npm-global";
  };

  # ── Activation: Install AI CLI tools via npm ──────────────────────────────────
  # These tools are not yet packaged in nixpkgs. They are installed once into
  # ~/.npm-global. Re-running `home-manager switch` will check and install
  # any that are missing, but won't upgrade existing installs automatically.
  # To upgrade: npm update -g --prefix ~/.npm-global

  home.activation.npmGlobalPackages = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # Ensure npm is available (comes from nodejs package in packages.nix)
    if ! command -v npm &>/dev/null; then
      echo "WARNING: npm not found, skipping AI CLI tool installation"
    else
      export NPM_CONFIG_PREFIX="$HOME/.npm-global"
      mkdir -p "$HOME/.npm-global"

      # Helper: install an npm package globally if it's not already installed
      _npm_global_install() {
        local pkg="$1"
        local bin="$2"  # binary name to check for (defaults to package name)
        bin="${bin:-$pkg}"
        if ! command -v "$bin" &>/dev/null && \
           [ ! -f "$HOME/.npm-global/bin/$bin" ]; then
          echo "Installing npm global package: $pkg"
          $DRY_RUN_CMD npm install --global --prefix "$HOME/.npm-global" "$pkg"
        fi
      }

      # AI / LLM CLI tools not yet in nixpkgs:
      _npm_global_install "cline" "cline"                    # Cline LLM CLI
      _npm_global_install "@continuedev/cli" "continue"      # Continue Dev LLM CLI
      _npm_global_install "opencode-ai" "opencode"           # OpenCode agentic AI
      _npm_global_install "codex" "codex"                    # OpenAI Codex agentic AI
      _npm_global_install "@githubnext/github-copilot-cli" "github-copilot-cli"  # Copilot CLI
      _npm_global_install "gemini-cli" "gemini"              # Google Gemini CLI

      unset -f _npm_global_install
    fi
  '';
}
