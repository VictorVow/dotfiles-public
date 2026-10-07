{ config, pkgs, lib, ... }:

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

# Text editors and IDEs: Neovim, micro, VS Code, VSCodium, MarkText.
{
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
      " XDG migration: keep .viminfo out of $HOME (xdg-ninja)
      set viminfofile=$XDG_STATE_HOME/vim/viminfo
    '';
  };

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
        # any child process. Without scrubbing, the AppMan marktext's Electron binary
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
      # Launch the AppMan-installed marktext with a clean env so it works when spawned from
      # a VSCode/VSCodium extension host (which sets ELECTRON_RUN_AS_NODE=1).
      exec setsid env -u ELECTRON_RUN_AS_NODE -u NODE_OPTIONS DESKTOPINTEGRATION=1 \
        "${config.home.homeDirectory}/.local/bin/marktext" --no-sandbox "$@"
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
}
