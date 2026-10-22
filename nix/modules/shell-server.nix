{ config, hostProfile, ... }:

# Server variant of shell.nix — headless lord-ubuntu.
# Kept: bash integration, hms/nsh/nr/ver helpers, PATH/session vars that apply
# to a headless box. Dropped: Yakuake/fastfetch-on-GUI triggers, MarkText
# helpers, tmux-agent pane layout, Android SDK, Flatpak exports, namecheap
# proxy fn, brew completions, dnvm, npm-globals install (no GUI CLIs needed
# there), flathub remote activation, sops()/with-secret wrappers that key off
# the desktop's Secret Service keyring.
{
  programs.bash = {
    enable = true;

    initExtra = ''
      stty -ixon

      # Re-source HM session vars after each hms (same fix as desktop shell.nix).
      _hm_sess_current=$(readlink ~/.nix-profile/etc/profile.d/hm-session-vars.sh 2>/dev/null)
      if [[ "$_hm_sess_current" != "$__HM_SESS_VARS_PATH" ]]; then
        unset __HM_SESS_VARS_SOURCED
        source ~/.nix-profile/etc/profile.d/hm-session-vars.sh
        export __HM_SESS_VARS_PATH="$_hm_sess_current"
      fi
      unset _hm_sess_current

      # API tokens: whitelist only. No `with-secret github` here — `gh` on the
      # server uses its own keyring. freellmapi reads the sops-decrypted file
      # from ai-secrets.nix.
      with-secret() {
        [ $# -ge 2 ] || { echo "usage: with-secret freellmapi <command> [args...]" >&2; return 1; }
        local which="$1"; shift
        case "$which" in
          freellmapi) env FREELLMAPI_API_KEY="$(cat ${config.sops.secrets.freellmapi_api_key.path})" "$@" ;;
          *) echo "usage: with-secret freellmapi <command> [args...]" >&2; return 1 ;;
        esac
      }

      # Interactive sops on the server: the age key is a TPM-wrapped
      # credential (~/.config/sops/age/keys.txt.cred), not a plaintext file —
      # decrypted into sops-nix.service's private dir at runtime. For ad-hoc
      # `sops -d`, run on the desktop (its keyring is reachable) or pipe a
      # `systemd-creds decrypt` output via --age /dev/stdin (needs sudo).

      # Homebrew (Linux) — installed on the server via ansible/lord-ubuntu.yml
      # (Brewfile.lord, currently just cass). Same guarded shellenv pattern as
      # desktop shell.nix.
      if [ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
      fi

      # User-local PATH additions
      export PATH="$HOME/.cargo/bin:$PATH"
      export NPM_CONFIG_PREFIX="$HOME/.npm-global"
      export PATH="$HOME/.npm-global/bin:$PATH"
      export PATH="$HOME/.local/bin:$PATH"

      export XDG_RUNTIME_DIR="/run/user/$(id -u)"

      eval "$(fnm env --use-on-cd --resolve-engines=false --shell bash)"

      # hms — home-manager switch for this host. --no-write-lock-file keeps the
      # pin controlled by update-all on the desktop (see desktop shell.nix).
      hms() {
        local flake="${hostProfile.hms.flakePath}"
        local config="${hostProfile.hms.configName}"
        home-manager switch --flake "$flake#$config" --no-write-lock-file
      }

      nsh() {
        if [ $# -eq 0 ]; then
          echo "usage: nsh <pkg> [pkg...]" >&2
          return 2
        fi
        local -a installables=()
        local p
        for p in "$@"; do installables+=("nixpkgs#$p"); done
        NIXPKGS_ALLOW_UNFREE=1 nix shell --impure "''${installables[@]}"
      }

      nr() {
        if [ $# -eq 0 ]; then
          echo "usage: nr <pkg> [-- args...]" >&2
          return 2
        fi
        local pkg="$1"; shift
        NIXPKGS_ALLOW_UNFREE=1 nix run --impure "nixpkgs#$pkg" "$@"
      }

      ver() {
        if [ $# -ne 1 ]; then
          echo "usage: ver <command>" >&2
          return 2
        fi
        local p real pkg f
        p=$(command -v "$1") || { echo "$1: not found" >&2; return 1; }
        real=$(readlink -f "$p")
        case $real in
          /nix/store/*)
            real=''${real#/nix/store/*-}; echo "''${real%%/*}" ;;
          *)
            if pkg=$(dpkg -S "$real" 2>/dev/null); then
              dpkg-query -W "''${pkg%%:*}"
            else
              for f in --version -V version -v; do
                timeout 2 "$p" "$f" </dev/null 2>&1 | head -n1 | grep -m1 '[0-9]' && return
              done
              echo "$1: version unknown ($real)" >&2
              return 1
            fi ;;
        esac
      }

      # Show fastfetch when an interactive SSH session starts (this is a server —
      # every login shell is via SSH).
      if [[ -n "$SSH_CONNECTION" ]] && command -v fastfetch >/dev/null; then
        fastfetch
      fi
    '';

    shellAliases = {
      hmn = "home-manager news --flake ~/installs/nix#lord";
      nsp = "echo 'Ignore the legacyPackages.x86_64-linux. prefix' && echo '' && nix search nixpkgs";

      ls = "eza";
      ll = "eza -l";
      la = "eza -la";
      lt = "eza --tree";

      cwd = "pwd";
    };
  };

  home.sessionVariables = {
    EDITOR = "micro";
    VISUAL = "micro";

    NPM_CONFIG_PREFIX = "$HOME/.npm-global";
    GOPATH = "$HOME/go";

    FJ_FALLBACK_HOST = "https://git.device.example.com";
    GCP_VPS_EGRESS_PROXY = "http://100.x.x.x:8888";

    CARGO_HOME = "$HOME/.local/share/cargo";
    RUSTUP_HOME = "$HOME/.local/share/rustup";
    GNUPGHOME = "$HOME/.local/share/gnupg";
    DOTNET_CLI_HOME = "$HOME/.local/share/dotnet";
    ANSIBLE_HOME = "$HOME/.local/share/ansible";
    GRADLE_USER_HOME = "$HOME/.local/share/gradle";
    AWS_SHARED_CREDENTIALS_FILE = "$HOME/.config/aws/credentials";
    AWS_CONFIG_FILE = "$HOME/.config/aws/config";
    DOCKER_CONFIG = "$HOME/.config/docker";
    NPM_CONFIG_CACHE = "$HOME/.cache/npm";
    HISTFILE = "$HOME/.local/state/bash/history";
    NODE_REPL_HISTORY = "$HOME/.local/state/node_repl_history";
    PYTHON_HISTORY = "$HOME/.local/state/python_history";

    PODMAN_USERNS = "keep-id";
    GH_TELEMETRY = "false";
    COREPACK_ENABLE_DOWNLOAD_PROMPT = "0";
  };
}
