{ config, pkgs, lib, ... }:

{
  # Start Solaar (Logitech device manager) in the system tray on login.
  # Uses KDE autostart (.desktop) instead of a systemd service so that
  # hms doesn't restart it (and open a window) on every home-manager switch.
  home.file.".config/autostart/solaar.desktop".text = ''
    [Desktop Entry]
    Name=Solaar
    Exec=${pkgs.solaar}/bin/solaar --window=hide
    Type=Application
    X-KDE-autostart-after=panel
  '';

  # Start VeraCrypt background task in the system tray on login.
  # WAYLAND_DISPLAY is unset so wxWidgets falls back to the XEmbed tray
  # protocol via XWayland, where xembedsniproxy bridges it to KDE's SNI tray.
  home.file.".config/autostart/veracrypt.desktop".text = ''
    [Desktop Entry]
    Name=VeraCrypt
    Exec=env WAYLAND_DISPLAY= ${pkgs.veracrypt}/bin/veracrypt --background-task
    Type=Application
    X-KDE-autostart-after=panel
  '';

  # Start Tailscale system tray icon on login.
  # Tailscale is installed via apt (custom-installers.yml), not Nix,
  # so we use the absolute system path rather than a Nix store reference.
  home.file.".config/autostart/tailscale-systray.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Tailscale System Tray
    Comment=Tailscale system tray applet for managing Tailscale
    Exec=/usr/bin/tailscale systray
    TryExec=/usr/bin/tailscale
    Icon=tailscale
    Terminal=false
    NoDisplay=true
    StartupNotify=false
    Categories=Network;System;
    X-KDE-autostart-after=panel
  '';

  # xdg-open wrapper: translate Firefox's non-standard 2-arg calling
  # convention into `gio launch`.
  #
  # Firefox Developer Edition (and possibly other Firefox builds)
  # invokes external protocol handlers (e.g. logseq://) by calling:
  #
  #     xdg-open <desktop-file-path> <uri>
  #
  # Standard xdg-open (xdg-utils) only accepts a single URL/file
  # argument, so the URI is rejected as "unexpected argument" and the
  # click silently fails. That 2-arg form is actually the `gio launch`
  # calling convention — Firefox is mixing up two tools.
  #
  # This wrapper detects the 2-arg "<desktop> <uri>" shape and
  # translates it to `gio launch`. All other invocations are forwarded
  # unchanged to the real /usr/bin/xdg-open, so standard 1-arg calls
  # keep working for every other app.
  #
  # Installed as a nix-packaged binary (writeShellScriptBin) so it
  # lands in ~/.nix-profile/bin/xdg-open, which is at the front of
  # PATH for every process — including GUI apps launched from KDE's
  # launcher, where ~/.local/bin (from shell.nix's initExtra) is not
  # visible because initExtra only runs in interactive bash shells.
  #
  # Can be removed if upstream Firefox fixes its calling convention,
  # or if upstream xdg-utils grows support for the 2-arg form.
  home.packages = [
    (pkgs.writeShellScriptBin "xdg-open" ''
      if [ $# -eq 2 ] \
         && [[ "$1" == *.desktop ]] \
         && [ -f "$1" ] \
         && [[ "$2" == *://* ]]; then
        exec ${pkgs.glib}/bin/gio launch "$1" "$2"
      fi
      exec /usr/bin/xdg-open "$@"
    '')

    # FreeTube "External Player" → mpv wrapper.
    #
    # FreeTube (run as an AppImage) launches the configured external player via
    # a bare `spawn()` that inherits the AppImage's environment (it injects its
    # own LD_LIBRARY_PATH) and discards stdout/stderr, so any failure is
    # completely silent. Two things broke YouTube playback through it:
    #
    #   1. VLC can't descramble YouTube's `n` parameter → HTTP 403 → empty
    #      window. mpv avoids this by delegating extraction to yt-dlp.
    #   2. yt-dlp gets blocked by YouTube's "confirm you're not a bot" check on
    #      many videos unless it presents real cookies.
    #
    # This wrapper pins mpv + yt-dlp to their Nix store paths (so it never
    # depends on PATH or the AppImage's LD_LIBRARY_PATH) and feeds yt-dlp
    # cookies from the Firefox "VERTEX" profile to pass the bot check.
    #
    # Like xdg-open above, it lands in ~/.nix-profile/bin (on the GUI PATH).
    # Point FreeTube → Settings → External Player Settings:
    #   External Player          = mpv
    #   Custom Executable        = ~/.nix-profile/bin/ft-mpv  (or just: ft-mpv)
    #   Custom Arguments         = (empty)
    (pkgs.writeShellScriptBin "ft-mpv" ''
      unset LD_LIBRARY_PATH
      exec ${pkgs.mpv}/bin/mpv \
        --script-opts=ytdl_hook-ytdl_path=${pkgs.yt-dlp}/bin/yt-dlp \
        --ytdl-raw-options=cookies-from-browser=firefox:VERTEX \
        "$@"
    '')
  ];
}
