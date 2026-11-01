{ config, pkgs, lib, hostProfile, ... }:

# Shell environment configuration.
# Manages PATH, environment variables, aliases, and Bash integration.
# Also installs AI CLI tools that are not yet packaged in nixpkgs via npm.
let
  # npm-globals.txt → [ { pkg; bin; } ]; strips comments/blank lines, bin
  # defaults to the package name.
  npmGlobals = lib.pipe (builtins.readFile ../../npm-globals.txt) [
    (lib.splitString "\n")
    (map (line: lib.trim (builtins.head (lib.splitString "#" line))))
    (lib.filter (line: line != ""))
    (map (line:
      let words = lib.filter (w: w != "") (lib.splitString " " line);
      in {
        pkg = builtins.head words;
        bin = if builtins.length words > 1 then builtins.elemAt words 1 else builtins.head words;
      }))
  ];
in
{
  # ── Bash Integration ──────────────────────────────────────────────────────────

  programs.bash = {
    enable = true;
    # Home Manager appends these to ~/.bashrc automatically.
    # Note: starship, nix-index, and other program integrations are injected
    # automatically by their respective programs.* modules in programs.nix.

    # i.e. ~/.bashrc equivalent
    initExtra = ''
      # ── TTY: disable XON/XOFF flow control ──────────────────────────────────
      # Frees C-s and C-q for tmux/readline (XON/XOFF is a 70s serial-terminal
      # feature with no practical use on modern terminals).
      stty -ixon

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

      # ── API tokens: whitelist only, never exported globally ─────────────────
      # No token is in the session or shell environment (an exported var reaches
      # every child process, and e.g. Flatpak's flatpak-spawn copies its whole
      # env onto its world-readable command line). Instead:
      #   - gh / git push use the gh keyring (VictorVow; `git su 2|3` sets a per-repo alt account)
      #   - opencode2 gets FREELLMAPI_API_KEY from a wrapper (packages.nix)
      #   - one-offs: `with-secret github|freellmapi <cmd>` sets the var for that
      #     command only. github pulls the PAT straight from gh's keyring (no
      #     plaintext file — there used to be a sops github_token here; removed
      #     because any same-uid process could cat it). freellmapi cats the sops
      #     output from ai-secrets.nix.
      with-secret() {
        [ $# -ge 2 ] || { echo "usage: with-secret {github|freellmapi} <command> [args...]" >&2; return 1; }
        local which="$1"; shift
        case "$which" in
          github)     env GITHUB_TOKEN="$(gh auth token)" "$@" ;;
          freellmapi) env FREELLMAPI_API_KEY="$(cat ${config.sops.secrets.freellmapi_api_key.path})" "$@" ;;
          *) echo "usage: with-secret {github|freellmapi} <command> [args...]" >&2; return 1 ;;
        esac
      }

      # sops's age identity lives in the Secret Service keyring (KWallet via
      # ksecretd), not ~/.config/sops/age/keys.txt — see sops-age-key.nix for
      # why and for the systemd path used by sops-nix.service. Interactive
      # sops gets it via SOPS_AGE_KEY here so `sops nix/secrets/*.yaml` and
      # Ansible `sops -d` lookups keep working.
      sops() {
        SOPS_AGE_KEY="$(secret-tool lookup service sops-age key identity)" command sops "$@"
      }

      # ── Homebrew (Linux) ────────────────────────────────────────────────────
      # Homebrew is kept for packages not available in nixpkgs.
      # The nix-managed PATH takes priority; Homebrew fills in the gaps.
      if [ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
        eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
      fi
      # Brew puts bash completions in etc/bash_completion.d, which bash-completion doesn't scan.
      # Source only the ones wanted: the dir has 120+ files (incl. brew's util-linux, which would
      # shadow the Nix ones) and sourcing it all adds ~350ms to startup.
      for _brew_comp in cass; do
        [ -r "/home/linuxbrew/.linuxbrew/etc/bash_completion.d/$_brew_comp" ] && \
          . "/home/linuxbrew/.linuxbrew/etc/bash_completion.d/$_brew_comp"
      done
      unset _brew_comp

      # ── Rust / Cargo ────────────────────────────────────────────────────────
      # rustup (installed via nixpkgs) installs toolchains to ~/.cargo.
      # The cargo bin dir needs to be on PATH for installed binaries.
      export PATH="$HOME/.cargo/bin:$PATH"

      # ── npm global packages (user-local) ────────────────────────────────────
      # AI CLI tools not yet in nixpkgs are installed via npm to ~/.npm-global.
      # See the activation script below for the install logic.
      export NPM_CONFIG_PREFIX="$HOME/.npm-global"
      export PATH="$HOME/.npm-global/bin:$PATH"

      # ── uv tools ────────────────────────────────────────────────────────────
      # `uv tool install` links executables into ~/.local/bin.
      export PATH="$HOME/.local/bin:$PATH"

      # ── Android SDK ─────────────────────────────────────────────────────────
      # ANDROID_HOME is set via home.sessionVariables below.
      export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/tools:$ANDROID_HOME/emulator:$PATH"
      export PATH="$HOME/.pub-cache/bin:$PATH"   # Flutter pub-cache

      # ── Flatpak exports ─────────────────────────────────────────────────────
      # Needed for VSCode NeoVim extension and other Flatpak-installed binaries.
      export PATH="$PATH:/var/lib/flatpak/exports/bin"

      # ── Wayland / XDG ───────────────────────────────────────────────────────
      # Required for portals, screen sharing, and Wayland tooling.
      export XDG_RUNTIME_DIR="/run/user/$(id -u)"

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

      # ── Yakuake new-tab: cd to last tmux pane directory ────────────────────
      # In tmux panes: persist $PWD to ~/.tmux_last_dir on every prompt.
      # In new non-tmux shells (new Yakuake tabs): cd to that saved path.
      if [[ -n "$TMUX" ]]; then
        _tmux_save_dir() { printf '%s' "$PWD" > "$HOME/.tmux_last_dir"; }
        PROMPT_COMMAND="_tmux_save_dir''${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
      elif [[ -f "$HOME/.tmux_last_dir" ]] && pstree -s $$ | grep -qi yakuake; then
        _tmux_dir=$(< "$HOME/.tmux_last_dir")
        [[ -d "$_tmux_dir" ]] && cd "$_tmux_dir"
        unset _tmux_dir
      fi

      # ── tmux-agent: 4-pane agent workspace ──────────────────────────────────
      # Works in any context: inside an existing tmux session (applies splits to
      # the current window) or outside tmux (creates a new session first).
      #          67%        33%
      # ┌────────────────────┬──────────┐
      # │    top-L           │  top-R   │   67%
      # │                    │          │
      # ├───────────────┬────┴──────────┤
      # │    bot-L      │    bot-R      │   33%
      # └───────────────┴───────────────┘
      #       50%             50%
      tmux-agent() {
        local -a splits=(
          split-window -v -p 33 \;
          select-pane -t 0 \;
          split-window -h -p 33 \;
          select-pane -t 2 \;
          split-window -h -p 33 \;
          select-pane -t 2 \;
          split-window -h \;
          select-pane -t 0 \;
          split-window -h -l 1 \;
          send-keys -t 2 'cd ~/Projects/installs' Enter \;
          send-keys -t 2 'clear' Enter \;
          select-pane -t 0 \;
        )
        if [ -n "$TMUX" ]; then
          tmux "''${splits[@]}"
        else
          tmux new-session \; "''${splits[@]}"
        fi
      }

      # ── md/mds: open file(s) in MarkText ───────────────────────────────────────
      # The AppMan-installed marktext fork's second-instance handler routes args
      # into the running process. With `openFilesInNewWindow: false` set in
      # ~/.config/marktext/preferences.json (the default), bare args land as
      # tabs in the existing window. Passing `-n` forces a fresh window
      # (shared process, shared settings — no temp profile). `--no-sandbox`
      # is required because the AppImage's chrome-sandbox needs SUID root
      # it can't get from $HOME.
      #
      #   md   — files open as tabs in the existing window (default flow).
      #   mds  — new window per invocation (even with no args → blank window).
      #
      # AppMan-installed AppImage at `~/.local/bin/marktext` vs ~/AppImages/marktext-fork.appimage
      #   There's a few features of my fork that I haven't been able to upstream yet
      #
      md() {
        ~/AppImages/marktext-fork.appimage --no-sandbox "$@" & disown
      }
      mds() {
        ~/AppImages/marktext-fork.appimage --no-sandbox -n "$@" & disown
      }

      # ── hms: home-manager switch ───────────────────────────────────────────
      # The switch passes --no-write-lock-file. Only update.sh (run via
      # `update-all`) is allowed to advance flake.lock — it age-pins inputs to
      # a ≥PIN_AGE_DAYS-old commit so Hydra's binary cache has caught up. If
      # `hms` were free to rewrite the lock it could pull fresh upstream
      # commits and trigger from-source compiles of new package versions. A
      # "refusing to write lock file" error from hms means flake.nix changed
      # since the last update-all; re-run update-all rather than dropping the
      # flag.
      #
      # Two cache-cooldown warnings so `hms` doesn't silently burn CPU on
      # source builds (both warn only — the switch proceeds regardless):
      #   1. Warn if flake.lock's nixpkgs pin is younger than PIN_AGE_DAYS —
      #      Hydra's cache may not have caught up yet (run update-all first).
      #   2. `nix build --dry-run` the activationPackage and list what would
      #      compile locally vs download.
      hms() {
        local flake="${hostProfile.hms.flakePath}"
        local config="${hostProfile.hms.configName}"
        local pin_age_days="''${PIN_AGE_DAYS:-14}"

        # 1. Lock-age check: nixpkgs' lastModified is the channel-release
        #    commit's date, close enough to Hydra publish time to matter.
        local lock="$flake/flake.lock"
        if [[ -f "$lock" ]]; then
          local pin_ts now_ts age_days
          pin_ts=$(jq -r '.nodes.nixpkgs.locked.lastModified // empty' "$lock" 2>/dev/null)
          if [[ -n "$pin_ts" ]]; then
            now_ts=$(date +%s)
            age_days=$(( (now_ts - pin_ts) / 86400 ))
            if (( age_days < pin_age_days )); then
              printf '\033[1;33m[WARN]\033[0m nixpkgs pin is %sd old (< %sd cooldown).\n' \
                     "$age_days" "$pin_age_days" >&2
              printf '       Hydra may not have built all of it yet — expect local\n' >&2
              printf '       compiles. Run `update-all` first, or continue anyway.\n' >&2
            fi
          fi
        fi

        # 2. Dry-run: what would build from source vs substitute from caches.
        local plan built=() line
        plan=$(nix build --dry-run --no-link \
                 "$flake#homeConfigurations.$config.activationPackage" 2>&1) || {
          printf '\033[0;31m[ERROR]\033[0m dry-run failed:\n%s\n' "$plan" >&2
          return 1
        }
        while IFS= read -r line; do
          case "$line" in
            *"/nix/store/"*.drv)
              line="''${line##*/nix/store/}"   # strip leading space + /nix/store/<hash>-
              line="''${line#*-}"
              built+=("''${line%.drv}") ;;
          esac
        done <<< "$plan"

        if (( ''${#built[@]} > 0 )); then
          printf '\033[1;33m[WARN]\033[0m %d derivation(s) would build locally (no cache):\n' \
                 "''${#built[@]}" >&2
          printf '  %s\n' "''${built[@]}" >&2
        fi

        home-manager switch --flake "$flake#$config" --no-write-lock-file
      }

      # ── Nix shortcuts: nsh / nr ────────────────────────────────────────────
      # Defined as functions (not aliases) because bash aliases always insert a
      # space between the alias value and the next word. An alias
      # `nsh="nix shell nixpkgs#"` followed by `nsh foo` expands to
      # `nix shell nixpkgs# foo` — Nix then reads `nixpkgs#` as a flake ref with
      # an empty attr path (→ packages.x86_64-linux.default) and errors out
      # before ever looking at `foo`.

      # Temp shell with package: nsh <package> | it'll now be available as if
      # it was installed (`which package`)
      #
      # NIXPKGS_ALLOW_UNFREE=1 + --impure: Home Manager's allowUnfree config
      # doesn't apply to ad-hoc `nix shell`/`nix run` invocations — they need
      # the env var, and `--impure` is required to let flake commands read it.
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

      # Run package without installing: nr <package> [-- args...]
      nr() {
        if [ $# -eq 0 ]; then
          echo "usage: nr <pkg> [-- args...]" >&2
          return 2
        fi
        local pkg="$1"; shift
        NIXPKGS_ALLOW_UNFREE=1 nix run --impure "nixpkgs#$pkg" "$@"
      }

      # Print a command's version, like `which` but for versions: ver <cmd>
      # Asks the package manager rather than the binary (--version flags vary):
      # Nix → store path name, apt → dpkg-query. Anything else (AppImages,
      # cargo/uv/npm installs) falls back to trying common version flags.
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

      # ── namecheap: route API calls via the ts-exit forward proxy ────────────
      # Namecheap's API only answers whitelisted egress IPs and Mullvad exits
      # rotate, so send all namecheap traffic through the forward proxy in
      # $GCP_VPS_EGRESS_PROXY (tinyproxy on ts-exit, static GCP IP — see
      # Self-Hosted/Egress-proxy). Whitelist that IP at
      # Namecheap → Profile → Tools → API Access and use it as the ClientIp in
      # `namecheap auth login`.
      # NODE_USE_ENV_PROXY=1 is required: Node 24's global fetch ignores
      # HTTPS_PROXY without it.
      namecheap() {
        NODE_USE_ENV_PROXY=1 HTTPS_PROXY="$GCP_VPS_EGRESS_PROXY" \
          command namecheap "$@"
      }

      # eza uses its own built-in colour support (dircolors not needed)
    '';

    # ── Shell Aliases ──────────────────────────────────────────────────────────
    shellAliases = {
      # Home Manager shortcuts.
      # NOTE: Aliases are only loaded in interactive shells — non-interactive tools
      # (e.g. Claude's Bash tool, scripts, cron jobs) cannot resolve them.
      # Use the full `home-manager switch --flake ...` command in those contexts.
      # hms is a function (defined in initExtra) not an alias.
      hmn   = "home-manager news --flake ~/Projects/installs/nix#boss";

      # Nix shortcuts
      #
      # nsp results show a 'legacyPackages.x86_64-linux.' prefix — this is normal. nixpkgs exposes
      # packages under the 'legacyPackages' attribute in flakes (vs 'packages' for individual derivations).
      # It does not mean the packages are outdated.
      #
      # Search nixpkgs: nsp <package>
      # Note: `nsh` and `nr` are bash functions defined in `initExtra` above,
      # not aliases — see the comment there for why.
      nsp   = "echo 'Ignore the legacyPackages.x86_64-linux. prefix' && echo '' && nix search nixpkgs";

      # Distrobox shortcuts
      dbe   = "distrobox enter";
      dbl   = "distrobox list";

      # System update shortcut — runs all package managers in one pass
      update-all = "~/Projects/installs/update.sh";

      # eza replaces uutils ls (Ubuntu 24.04 default) which has broken locale sorting
      ls  = "eza";
      ll  = "eza -l";
      la  = "eza -la";
      lt  = "eza --tree";

      # Assorted
      cwd = "pwd | wl-copy"; # Copy working directory to clipboard

      # XDG migration: settings.xml moved to $XDG_CONFIG_HOME/maven (see
      # ~/.config/maven/settings.xml's <localRepository> for the repo-cache side).
      mvn = "mvn -gs $XDG_CONFIG_HOME/maven/settings.xml";

      # XDG migration: wget doesn't support an env var for its HSTS cache file.
      wget = "wget --hsts-file=$XDG_DATA_HOME/wget-hsts";

      # XDG migration: yarn classic has no env var for its rc file location;
      # this alias may not stick — yarn can still write ~/.yarnrc directly.
      yarn = "yarn --use-yarnrc $XDG_CONFIG_HOME/yarn/config";

    };
  };

  # ── Session Variables ─────────────────────────────────────────────────────────
  # These are set for the full desktop session (not just terminal), so GUI apps
  # launched from the KDE application launcher also see them.

  home.sessionVariables = {
    # Default terminal editor — micro for quick edits; nvim is still available
    EDITOR = "micro";
    VISUAL = "micro";

    # npm global prefix — keeps npm global installs user-local (no sudo)
    NPM_CONFIG_PREFIX = "$HOME/.npm-global";

    # Go workspace root
    GOPATH = "$HOME/go";

    # forgejo-cli (`fj`): host to use when it can't infer one from the cwd's git remote
    FJ_FALLBACK_HOST = "https://git.device.example.com";

    # Forward proxy on ts-exit (tinyproxy, tailnet-only, static GCP egress IP).
    # See Self-Hosted/Egress-proxy. Used by the `namecheap` function in initExtra.
    GCP_VPS_EGRESS_PROXY = "http://100.x.x.x:8888";

    # XDG migration (via xdg-ninja) — redirect dev-tool state out of $HOME.
    WINEPREFIX = "$HOME/.local/share/wine";
    KDEHOME = "$HOME/.config/kde";
    CARGO_HOME = "$HOME/.local/share/cargo";
    RUSTUP_HOME = "$HOME/.local/share/rustup";
    GNUPGHOME = "$HOME/.local/share/gnupg";
    DOTNET_CLI_HOME = "$HOME/.local/share/dotnet";
    ANSIBLE_HOME = "$HOME/.local/share/ansible";
    GRADLE_USER_HOME = "$HOME/.local/share/gradle";
    AWS_SHARED_CREDENTIALS_FILE = "$HOME/.config/aws/credentials";
    AWS_CONFIG_FILE = "$HOME/.config/aws/config";
    IPFS_PATH = "$HOME/.local/share/ipfs";
    ANDROID_USER_HOME = "$HOME/.local/share/android";
    ANDROID_AVD_HOME = "$HOME/.local/share/android/avd";
    # CODEX_HOME is set by programs.codex itself (home.preferXdgDirectories, home.nix)
    NUGET_PACKAGES = "$HOME/.cache/NuGetPackages";
    DOCKER_CONFIG = "$HOME/.config/docker";
    NPM_CONFIG_CACHE = "$HOME/.cache/npm";
    GTK2_RC_FILES = "$HOME/.config/gtk-2.0/gtkrc";
    # INPUTRC is set by programs.readline itself (home.preferXdgDirectories, home.nix)
    HISTFILE = "$HOME/.local/state/bash/history";
    NODE_REPL_HISTORY = "$HOME/.local/state/node_repl_history";
    PYTHON_HISTORY = "$HOME/.local/state/python_history";
    GITLIBS = "$HOME/.local/state/clojure/gitlibs";
    # Base dir only — Ren'Py appends its own <Game>-<id> subfolder underneath.
    RENPY_PATH_TO_SAVES = "$HOME/.local/share/renpy";
    FVM_CACHE_PATH = "$HOME/.cache/fvm";

    # Podman rootless networking — required for Distrobox rootless containers
    PODMAN_USERNS = "keep-id";

    # Force GTK apps to use the KDE file chooser (thumbnails, bookmarks, etc.)
    # https://wiki.archlinux.org/title/Uniform_look_for_Qt_and_GTK_applications
    GDK_DEBUG = "portals";

    # Firefox Wayland native support (was previously in ~/.pam_environment)
    MOZ_ENABLE_WAYLAND = "1";

    # Default Java home — JDK 21 LTS (jdk17 still installed for Minecraft/legacy apps)
    JAVA_HOME = "${pkgs.jdk21}";

    # Android SDK root — SDK tool paths are added to PATH in initExtra above
    ANDROID_HOME = "$HOME/Projects/Dev/Android/Sdk";

    # Disable GitHub CLI telemetry (enabled by default since gh ≥ 2.91.0)
    GH_TELEMETRY = "false";

    # corepack provides yarn/pnpm (see packages.nix). Disable its interactive
    # "download package manager X?" prompt so non-interactive contexts (git
    # hooks, CI, scripts) fetch the pinned version silently instead of hanging.
    COREPACK_ENABLE_DOWNLOAD_PROMPT = "0";

    # API tokens are deliberately NOT here — see "API tokens: whitelist only"
    # in initExtra.
  };

  # ── Sops secrets for shell API tokens ────────────────────────────────────────
  # shell.yaml still holds matrix_bot_password (read by Apprise's deploy.yml in
  # Self-Hosted), but no key is materialised to disk from it here — github_token
  # was removed since `with-secret github` now uses `gh auth token` instead.
  # If a future key needs a stable on-disk path, copy the pattern from
  # modules/ai-secrets.nix. Edit the file with: sops nix/secrets/shell.yaml

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
    export PATH="${pkgs.nodejs_24}/bin:/usr/bin:/bin:$PATH"
    NPM="${pkgs.nodejs_24}/bin/npm"
    if ! [ -x "$NPM" ]; then
      echo "WARNING: npm not found at ${pkgs.nodejs_24}/bin/npm, skipping AI CLI tool installation"
    else
      export NPM_CONFIG_PREFIX="$HOME/.npm-global"
      mkdir -p "$HOME/.npm-global"

      # Helper: install an npm package globally if it's not already installed.
      # The global npmrc ($XDG_CONFIG_HOME/npm/npmrc, programs.npm in
      # shell-apps.nix) hardens every npm invocation with ignore-scripts=true
      # and min-release-age=1. These AI CLIs are curated and
      # trusted, and several need their postinstall scripts (e.g. native binary
      # downloads), so this install path explicitly opts out:
      #   --ignore-scripts=false   run postinstall (binaries would be missing otherwise)
      #   --foreground-scripts     surface postinstall output in the activation log
      #   --min-release-age=0      skip the cooldown so a fresh CLI release installs now
      _npm_global_install() {
        local pkg="$1"
        local bin="$2"  # binary name to check for (defaults to package name)
        bin="''${bin:-$pkg}"
        if ! command -v "$bin" &>/dev/null && \
           [ ! -f "$HOME/.npm-global/bin/$bin" ]; then
          echo "Installing npm global package: $pkg"
          $DRY_RUN_CMD "$NPM" install --global --prefix "$HOME/.npm-global" \
            --ignore-scripts=false --foreground-scripts --min-release-age=0 "$pkg"
        fi
      }

      # Package list lives in npm-globals.txt at the repo root.
      ${lib.concatMapStringsSep "\n  " ({ pkg, bin }:
        "_npm_global_install ${lib.escapeShellArg pkg} ${lib.escapeShellArg bin}") npmGlobals}

      unset -f _npm_global_install
    fi
  '';
}
