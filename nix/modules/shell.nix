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
          split-window -h \;
          select-pane -t 0 \;
          send-keys -t 1 'cd ~/Projects/installs' Enter
        )
        if [ -n "$TMUX" ]; then
          tmux "''${splits[@]}"
        else
          tmux new-session \; "''${splits[@]}"
        fi
      }

      # ── md/Markdown: open file(s) in MarkText Flatpak ──────────────────────────
      md() {
        ~/AppImages/marktext.appimage --no-sandbox "$@" & disown
      }

      # ── hms: home-manager switch ───────────────────────────────────────────
      # 1. Evaluates the flake and builds a stopping set of user-level packages
      #    by expanding through HM aggregator drvs (home-manager-path, etc.).
      # 2. Dry-runs against the binary cache to find what needs local compilation.
      # 3. If nothing: switches immediately with max-jobs 0 (substitutes only).
      # 4. If something: shows a table of (derivation → top-level cause) and
      #    asks for Y/n confirmation before proceeding with a full switch.
      #
      # Every nix invocation below passes --no-write-lock-file. Only update.sh
      # (run via `update-all`) is allowed to advance flake.lock — it age-pins
      # inputs to a ≥PIN_AGE_DAYS-old commit so Hydra's binary cache has caught
      # up. If `hms` were free to rewrite the lock it could pull fresh upstream
      # commits and trigger from-source compiles of new package versions. A
      # "refusing to write lock file" error from hms means flake.nix changed
      # since the last update-all; re-run update-all rather than dropping the
      # flag.
      hms() {
        local flake="$HOME/Projects/installs/nix"
        local config="boss"

        # Strip the nix store hash prefix and .drv suffix from a store path.
        _drv_name() { basename "$1" | sed 's/^[a-z0-9]\{32\}-//; s/\.drv$//'; }

        # Home Manager scaffolding that always misses the cache but builds in
        # milliseconds (symlinks/file copies, no compilation). Filtered from
        # the pre-flight prompt so only real package builds prompt the user.
        # Combines name-pattern matching with a dep-graph set populated below
        # (any drv that's a direct child of home-manager-files /
        # home-manager-generation / activation-script — i.e. a dotfile or
        # activation artifact — is trivial regardless of its leaf name).
        _hms_is_trivial() {
          local path="$1" name
          name=$(_drv_name "$path")
          case "$name" in
            home-manager-files|home-manager-generation|home-manager-path) return 0 ;;
            activation-script*|hm_*|unit-*) return 0 ;;
          esac
          [[ -v "_hms_trivial[$path]" ]]
        }

        # BFS upward through the .drv referrer graph. Returns the name of the
        # first ancestor found in _hms_stops (the user-level package set).
        _hms_find_cause() {
          local target="$1"
          [[ -v "_hms_stops[$target]" ]] && { _drv_name "$target"; return; }
          local -A seen=(["$target"]=1)
          local -a frontier=("$target")
          local depth node ref
          for ((depth = 0; depth < 25; depth++)); do
            local -a next=()
            for node in "''${frontier[@]}"; do
              while IFS= read -r ref; do
                [[ -z "$ref" || -v "seen[$ref]" ]] && continue
                seen["$ref"]=1
                if [[ -v "_hms_stops[$ref]" ]]; then _drv_name "$ref"; return; fi
                next+=("$ref")
              done < <(nix-store -q --referrers "$node" 2>/dev/null | grep '\.drv$' || true)
            done
            [[ ''${#next[@]} -eq 0 ]] && break
            frontier=("''${next[@]}")
          done
          printf '(unknown)'
        }

        # ── 1. evaluate flake ──────────────────────────────────────────────
        printf 'Evaluating flake...\r'
        local act_drv
        act_drv=$(nix eval --raw --no-write-lock-file \
          "$flake#homeConfigurations.$config.activationPackage.drvPath" \
          2>&1 | grep '^/nix/store') || {
          printf '\033[31mERROR: flake evaluation failed\033[0m\n' >&2
          return 1
        }

        # ── 2. build stopping set: expand HM aggregators one level ─────────
        # home-manager-path bundles home.packages; home-manager-files holds
        # dotfiles; activation-script orchestrates activation. Expanding through
        # them exposes the actual user packages as BFS stop nodes.
        local -A _hms_stops=()
        # Children of HM dotfile/activation aggregators — populated in the
        # walk below and consulted by _hms_is_trivial. home-manager-path is
        # excluded because its children are real user packages (firefox, etc.).
        local -A _hms_trivial=()
        _hms_stops["$act_drv"]=1
        local l1_dep l1_name child
        while IFS= read -r l1_dep; do
          l1_name=$(_drv_name "$l1_dep")
          if [[ "$l1_name" == home-manager-* || "$l1_name" == activation-script* ]]; then
            while IFS= read -r child; do
              [[ -z "$child" ]] && continue
              _hms_stops["$child"]=1
              if [[ "$l1_name" != home-manager-path ]]; then
                _hms_trivial["$child"]=1
              fi
            done < <(nix-store -q --references "$l1_dep" 2>/dev/null | grep '\.drv$')
          else
            _hms_stops["$l1_dep"]=1
          fi
        done < <(nix-store -q --references "$act_drv" 2>/dev/null | grep '\.drv$')

        # ── 3. dry-run to check binary cache ───────────────────────────────
        printf 'Checking binary cache...\r'
        local dry
        dry=$(nix build --dry-run --no-write-lock-file \
          "$flake#homeConfigurations.$config.activationPackage" 2>&1) || {
          printf '%s\n' "$dry" >&2
          return 1
        }

        local -a to_build_real=() to_build_trivial=()
        local drv_path
        while IFS= read -r drv_path; do
          if _hms_is_trivial "$drv_path"; then
            to_build_trivial+=("$drv_path")
          else
            to_build_real+=("$drv_path")
          fi
        done < <(
          printf '%s\n' "$dry" \
          | grep -E '^\s+/nix/store/[a-z0-9]+-.*\.drv$' \
          | sed 's/^[[:space:]]*//'
        )

        # ── 4a. nothing to build at all: cache-only switch ─────────────────
        if [[ ''${#to_build_real[@]} -eq 0 && ''${#to_build_trivial[@]} -eq 0 ]]; then
          printf '                        \r'
          home-manager switch --flake "$flake#$config" --no-write-lock-file --option max-jobs 0
          return
        fi

        # ── 4b. only HM scaffolding: full switch, no prompt ────────────────
        if [[ ''${#to_build_real[@]} -eq 0 ]]; then
          printf '                        \r'
          home-manager switch --flake "$flake#$config" --no-write-lock-file
          return
        fi

        # ── 5. show dependency table ────────────────────────────────────────
        printf '\n\033[33mNot in binary cache — will require local compilation:\033[0m\n\n'
        printf '  %-54s  %s\n' 'Derivation' 'Caused by'
        printf '  %s\n' "$(printf '─%.0s' {1..74})"
        local drv name cause
        for drv in "''${to_build_real[@]}"; do
          name=$(_drv_name "$drv")
          cause=$(_hms_find_cause "$drv")
          printf '  \033[36m%-54s\033[0m  \033[33m%s\033[0m\n' "$name" "$cause"
        done

        # ── 6. confirm before compiling ─────────────────────────────────────
        printf '\nProceed with local compilation? [y/N] '
        local reply
        read -r reply
        [[ "$reply" =~ ^[Yy]$ ]] || { printf 'Aborted.\n'; return 1; }

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

      # ── git identity switch (full-axis) ─────────────────────────────────────
      # Override `git su [N]` so it realigns push-auth state too — clearing
      # GITHUB_TOKEN in this shell and switching the gh keyring active account
      # — not just commit identity. All other `git ...` invocations fall
      # through to real git unchanged. The `programs.git.settings.alias.su`
      # entry in programs.nix remains as a commit-identity-only fallback for
      # non-Bash callers (VS Code, GUIs, scripts, subshells) where this
      # function isn't visible. See docs/system/git-identity-management.md.
      git() {
        if [ "$1" = "su" ]; then
          shift
          _git_su "$@"
        else
          command git "$@"
        fi
      }

      _git_su() {
        local id="$1" name email key current_gh
        case "$id" in
          1) name=VictorVow;   email=12621257+VictorVow@users.noreply.github.com;   key=GPGKEY1 ;;
          2) name=USER2;      email=22418751+USER2@users.noreply.github.com;      key=GPGKEY2 ;;
          3) name=USER3; email=11584262+USER3@users.noreply.github.com; key=GPGKEY3 ;;
          "")
            echo "commit identity: $(command git config user.name) <$(command git config user.email)>"
            if [ -n "$GITHUB_TOKEN" ]; then
              echo "push auth: GITHUB_TOKEN env var (gh sees: $(gh api user --jq .login 2>/dev/null || echo '?'))"
            else
              echo "push auth: gh keyring (active: $(gh api user --jq .login 2>/dev/null || echo 'none'))"
            fi
            return 0 ;;
          *) echo "usage: git su [1|2|3]" >&2; return 1 ;;
        esac

        command git config user.name       "$name"
        command git config user.email      "$email"
        command git config user.signingkey "$key"
        echo "commit identity -> $name (identity $id)"

        if [ -n "$GITHUB_TOKEN" ]; then
          unset GITHUB_TOKEN
          echo "  unset GITHUB_TOKEN in this shell (was dominating push auth)"
        fi

        current_gh=$(gh api user --jq .login 2>/dev/null)
        if [ "$current_gh" != "$name" ]; then
          if gh auth switch -u "$name" >/dev/null 2>&1; then
            echo "  gh active account -> $name"
          else
            echo "  WARN: could not switch gh to $name — run: gh auth login -u $name" >&2
          fi
        fi
      }

      # eza uses its own built-in colour support (dircolors not needed)
    '';

    # ── Shell Aliases ──────────────────────────────────────────────────────────
    shellAliases = {
      # Home Manager shortcuts.
      # NOTE: Aliases are only loaded in interactive shells — non-interactive tools
      # (e.g. Claude's Bash tool, scripts, cron jobs) cannot resolve them.
      # Use the full `home-manager switch --flake ...` command in those contexts.
      # hms is a function (defined in initExtra) not an alias — it runs a cache
      # preflight check before switching.
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
    ANDROID_HOME = "$HOME/Documents/Dev/Android/Sdk";

    # Disable GitHub CLI telemetry (enabled by default since gh ≥ 2.91.0)
    GH_TELEMETRY = "false";

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
