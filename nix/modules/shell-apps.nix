{ pkgs, lib, hostProfile, ... }:

# Home Manager program configurations.
# Using programs.* modules instead of bare packages gives Home Manager the
# ability to manage config files, shell integrations, and user services.
let
  # ── Git identities ─────────────────────────────────────────────────────────
  # 1 is the global default (and gh's active account). The others apply
  # automatically to any repo with a remote under their GitHub account (see
  # programs.git.includes); `git su N` pins one by hand. See
  # docs/system/git-identity-management.md.
  defaultIdentity = builtins.head identities;
  identities = [
    { id = 1; name = "VictorVow";   email = "12621257+VictorVow@users.noreply.github.com";   key = "GPGKEY1"; }
    { id = 2; name = "USER2";      email = "22418751+USER2@users.noreply.github.com";      key = "GPGKEY2"; }
    { id = 3; name = "USER3"; email = "11584262+USER3@users.noreply.github.com"; key = "GPGKEY3"; }
  ];
  altIdentities = builtins.tail identities;

  # Credential helper returning one account's gh keyring token, without
  # changing gh's active account. `$1`/`$(...)` are expanded by git at push time.
  credHelperFor = name:
    "!f() { test \"$1\" = get || return 0; echo username=${name}; echo \"password=$(gh auth token --user ${name})\"; }; f";
in
{
  # ── Version Control ──────────────────────────────────────────────────────────

  programs.git = {
    enable = true;

    # GPG signing key — gpgsign is disabled by default; enable per-repo if needed
    signing = {
      inherit (defaultIdentity) key;
      format        = "openpgp";
      signByDefault = false;
    };

    settings = {
      # Default identity (see `identities` above; alt accounts via includes below)
      user = { inherit (defaultIdentity) name email; };

      init.defaultBranch   = "main";
      pull.rebase          = false;
      push.autoSetupRemote = true;

      gpg.program            = "/usr/bin/gpg";
      tag.forceSignAnnotated = false;

      # Credential storage. Desktop: libsecret (KDE Wallet) with a 12-hour cache.
      # Server (lord-ubuntu): headless, no Secret Service and no
      # git-credential-libsecret binary (Nix git doesn't ship it), so `git push`
      # died with "'credential-libsecret' is not a git command". Use the
      # built-in in-memory cache helper instead (re-enter the password every 12h).
      credential = if hostProfile.isServer then {
        helper = "cache --timeout 43200";
      } else {
        helper          = "libsecret";
        credentialStore = "cache";
        cacheOptions    = "--timeout 43200";
      };
    } // lib.optionalAttrs (!hostProfile.isServer) {
      # Per-host credential helpers
      "credential \"https://github.com\"".helper      = "libsecret";
      "credential \"https://gist.github.com\"".helper = "libsecret";
    } // {
      "credential \"https://dev.azure.com\"".useHttpPath = true;

      # git checkout-fb (shell application) - checkout an arbitrary branch and then remove that remote
      alias.ll = "log --oneline";
      core.editor = "micro";
      # `git su [N|auto]` — show or pin a repo's identity (git-su script below).
      # A git alias (not a bash function) so it works the same in VS Code,
      # GUIs and scripts. See docs/system/git-identity-management.md.
      alias.su = "!git-su";
    };

    # Alt identities apply automatically to any repo with a remote under that
    # GitHub account (https or ssh): commit identity + a credential helper that
    # pushes with that account's gh keyring token. Rendered after the global
    # helpers, so the empty entry resets them. Repo-local config (`git su N`)
    # still wins. Needs git ≥ 2.36 for hasconfig:remote.*.url.
    includes = lib.concatMap (i:
      map (url: {
        condition = "hasconfig:remote.*.url:${url}";
        contents = {
          user = { inherit (i) name email; signingKey = i.key; };
          "credential \"https://github.com\"".helper = [ "" (credHelperFor i.name) ];
        };
      }) [ "https://github.com/${i.name}/**" "git@github.com:${i.name}/**" ]
    ) altIdentities;
  };

  # git-su: `git su` shows the repo's effective identity and push account;
  # `git su N` pins identity N in the local .git/config (commit identity + push
  # helper), overriding the automatic includes; `git su auto` removes the pin.
  # gh's active account is kept on the default identity throughout, so pushing
  # as an alt account never changes push auth (or `gh` commands) elsewhere.
  home.packages = [
    (pkgs.writeShellApplication {
      name = "git-su";
      text = ''
        default=${defaultIdentity.name}
        helper_key=credential.https://github.com.helper
        arg=''${1-}

        show() {
          local helper
          local how=automatic
          [ "$(git config --show-scope user.name | cut -f1)" = local ] && how="pinned by git su"
          echo "commit identity: $(git config user.name) <$(git config user.email)>  ($how)"
          if [ -n "''${GITHUB_TOKEN-}" ]; then
            echo "push auth: GITHUB_TOKEN env var (overrides everything)"
          elif helper=$(git config --get-all "$helper_key" | tail -n1 | grep -o 'username=[^;]*'); then
            echo "push auth: ''${helper#username=}"
          else
            echo "push auth: gh active account ($(gh api user --jq .login 2>/dev/null || echo 'none'))"
          fi
        }

        case "$arg" in
          "") show; exit 0 ;;
          auto)
            for k in user.name user.email user.signingkey "$helper_key"; do
              git config --local --unset-all "$k" 2>/dev/null || true
            done
            echo "removed this repo's identity pin; now automatic:"
            show; exit 0 ;;
          ${lib.concatMapStrings (i: "${toString i.id}) name=${i.name}; email=${i.email}; key=${i.key} ;;\n  ") identities}*) echo "usage: git su [${lib.concatMapStringsSep "|" (i: toString i.id) identities}|auto]" >&2; exit 1 ;;
        esac

        git config --local user.name       "$name"
        git config --local user.email      "$email"
        git config --local user.signingkey "$key"
        git config --local --unset-all "$helper_key" 2>/dev/null || true
        git config --local --add "$helper_key" ""
        # shellcheck disable=SC2016  # $1 / $(...) are expanded by git at push time
        git config --local --add "$helper_key" \
          '!f() { test "$1" = get || return 0; echo username='"$name"'; echo "password=$(gh auth token --user '"$name"')"; }; f'
        echo "pinned this repo to $name (identity $arg); \`git su auto\` to undo"

        # Check the keyring token actually works (a stale one still prints).
        if ! { tok=$(gh auth token --user "$name" 2>/dev/null) \
               && [ "$(GH_TOKEN=$tok gh api user --jq .login 2>/dev/null)" = "$name" ]; }; then
          echo "  WARN: no working keyring token for $name — run: gh auth login -h github.com (log in as $name in the browser), then gh auth switch -u $default" >&2
        fi

        # Keep the default as gh's active account.
        if [ -z "''${GITHUB_TOKEN-}" ] && [ "$(gh api user --jq .login 2>/dev/null)" != "$default" ]; then
          gh auth switch -u "$default" >/dev/null 2>&1 \
            && echo "  gh active account -> $default"
        fi
      '';
    })
  ];

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
      # Active pane border: green normally, yellow while zoomed (prefix+z)
      set -g pane-active-border-style "#{?window_zoomed_flag,fg=#ffff00,fg=green},bg=default"

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

  # npm (userconfig; path decided by programs.npm below, home.preferXdgDirectories
  # → $XDG_CONFIG_HOME/npm/npmrc). Requires npm >= 11.10 for `min-release-age`
  # (guaranteed by nodejs_24 in packages.nix). npm has NO equivalent to pnpm's
  # blockExoticSubdeps / yarn's hardened mode — that third control is documented
  # here as an accepted gap rather than silently dropped. Independent of the
  # NPM_CONFIG_PREFIX env set in shell.nix (env vs rc are separate mechanisms).
  # The npm activation installs in shell.nix intentionally opt out (see there).
  #
  # GAP: npm cannot block exotic (git / tarball / non-registry) transitive deps.
  # pnpm (block-exotic-subdeps) and yarn (enableHardenedMode) do; npm has no
  # equivalent setting as of npm 11.x. Audit lockfiles manually.
  #
  # package = null: programs.npm defaults to pulling in plain `pkgs.nodejs`,
  # which would collide with the nodejs_24 derivation already declared in
  # packages.nix (both provide bin/npm). nodejs_24 already satisfies this
  # module's runtime needs, so don't add a second Node package.
  programs.npm = {
    enable = true;
    package = null;
    settings = {
      "min-release-age" = 1;
      ignore-scripts = true;
    };
  };

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
  #
  # On KDE 6, xdg-mime locates mimeapps.list via a bare `qtpaths`, which on Ubuntu
  # is a qtchooser shim with no Qt 6 entry ("could not find a Qt installation of ''")
  # — xdg-mime then silently skips the write. /usr/lib/qt6/bin has a real qtpaths.
  home.activation.stremioSchemeHandler = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    PATH="/usr/lib/qt6/bin:$PATH" run ${pkgs.xdg-utils}/bin/xdg-mime default com.stremio.Stremio.desktop x-scheme-handler/stremio
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
