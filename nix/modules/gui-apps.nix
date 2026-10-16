{ pkgs, pkgs-unstable, lib, ... }:

{
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

  # KDE binds Meta+R to this desktop entry via ~/.config/kglobalshortcutsrc
  # ([services][net.local.vault-launch.desktop] _launch=Meta+R). Without the
  # .desktop file present, KWin has no target to dispatch the shortcut to.
  xdg.desktopEntries."net.local.vault-launch" = {
    name        = "Vault Launch";
    comment     = "Rofi launcher for vault apps";
    exec        = "vault-launch";
    icon        = "system-run";
    terminal    = false;
    type        = "Application";
    categories  = [ "Utility" ];
  };

  # ── Dictation (Handy) ─────────────────────────────────────────────────────────

  # Handy: offline speech-to-text that types into the focused window.
  # See docs/research/speech-to-text-desktop.md for why it's set up this way:
  #   - wtype can't type on KWin (no virtual-keyboard protocol), so Handy's
  #     auto mode uses dotool (kernel uinput; needs the `input` group, which
  #     boss is in). dotool assumes a US layout unless told otherwise, so the
  #     wrapper sets it to match kxkbrc (gb) — otherwise @ and " come out swapped.
  #   - Handy's own global shortcut doesn't work on Wayland, so KDE owns the
  #     key: Meta+F runs `handy --toggle-transcription` (toggle mode, since KDE
  #     shortcuts only fire on press, not release).
  home.packages = [
    (pkgs.symlinkJoin {
      name = "handy";
      paths = [ pkgs-unstable.handy ];  # not in the pinned stable nixpkgs yet
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/handy --set DOTOOL_XKB_LAYOUT gb
      '';
    })
    pkgs.dotool
  ];

  # Target for the KDE global shortcut below.
  xdg.desktopEntries."net.local.handy-toggle" = {
    name        = "Handy: Toggle Transcription";
    comment     = "Start/stop Handy dictation";
    exec        = "handy --toggle-transcription";
    icon        = "audio-input-microphone";
    terminal    = false;
    type        = "Application";
    noDisplay   = true;
  };

  # Bind Meta+F to the entry above. On Plasma 6 kglobalaccel runs inside KWin
  # and only reads kglobalshortcutsrc at login, so register the binding live
  # over D-Bus (kglobalaccel then persists it to
  # [services][net.local.handy-toggle.desktop] itself). setShortcut's flags
  # must include SetPresent (2) — setForeignShortcut stores the keys but leaves
  # the action "not present", and kglobalaccel ignores presses for those.
  # NoAutoloading (4) makes it apply our keys instead of its stored ones.
  # If there's no session bus (e.g. switching from a TTY), write the file for
  # next login. 268435526 = Qt::META (0x10000000) | Qt::Key_F (0x46).
  home.activation.handyShortcut = lib.hm.dag.entryAfter [ "installPackages" "linkGeneration" ] ''
    id=(4 net.local.handy-toggle.desktop _launch "Handy: Toggle Transcription" "Handy: Toggle Transcription")
    if /usr/bin/busctl --user status org.kde.kglobalaccel >/dev/null 2>&1; then
      active=$(/usr/bin/qdbus6 org.kde.kglobalaccel /component/net_local_handy_toggle_desktop org.kde.kglobalaccel.Component.isActive 2>/dev/null || true)
      keys=$(/usr/bin/busctl --user call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel shortcut as "''${id[@]}" 2>/dev/null || true)
      if [ "$active" != "true" ] || [ "$keys" != "ai 1 268435526" ]; then
        run /usr/bin/kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
        run /usr/bin/busctl --user call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel doRegister as "''${id[@]}"
        run /usr/bin/busctl --user call org.kde.kglobalaccel /kglobalaccel org.kde.KGlobalAccel setShortcut asaiu "''${id[@]}" 1 268435526 6 >/dev/null
      fi
    else
      current=$(/usr/bin/kreadconfig6 --file kglobalshortcutsrc --group services --group net.local.handy-toggle.desktop --key _launch)
      if [ "$current" != "Meta+F" ]; then
        run /usr/bin/kwriteconfig6 --file kglobalshortcutsrc --group services --group net.local.handy-toggle.desktop --key _launch "Meta+F"
      fi
    fi
  '';

  # ── Screencasting ─────────────────────────────────────────────────────────────

  # Replaces key-mon (uninstalled — abandoned upstream, broken on Python 3.12+
  # and unbuildable against system PyGObject in a pipx venv). input-overlay
  # reads raw evdev input directly, so unlike key-mon (Xlib) or screenkey
  # (X11 XRecord) it works under Wayland/KWin and captures every app, not just
  # XWayland clients. Needs evdev read access: either run OBS as a member of
  # the `input` group, or add a udev rule granting access to /dev/input/event*.
  programs.obs-studio = {
    enable = true;
    plugins = with pkgs.obs-studio-plugins; [
      input-overlay
    ];
  };
}
