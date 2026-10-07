{ pkgs, ... }:

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
