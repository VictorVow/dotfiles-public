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

  # Start Handy (dictation, see gui-apps.nix) hidden in the tray on login, so
  # the Meta+F toggle has a running instance to talk to. Handy's own
  # "launch on startup" setting rewrites its autostart entry, so leave that off.
  home.file.".config/autostart/handy.desktop".text = ''
    [Desktop Entry]
    Name=Handy
    Exec=${config.home.profileDirectory}/bin/handy --start-hidden
    Icon=handy
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

  # Route the freedesktop Secret Service (org.freedesktop.secrets) to KWallet's
  # ksecretd rather than gnome-keyring.
  #
  # Kubuntu ships both providers. gnome-keyring won the D-Bus name race at login
  # (via pam_gnome_keyring + its systemd user unit), so libsecret clients stored
  # secrets there while KDE/Electron apps using `--password-store=kwallet6` (e.g.
  # Signal) stored theirs in KWallet. When the daemons churned, Signal's
  # `safeStorage`-wrapped SQLCipher key stopped resolving and its database failed
  # to open on every launch ("hmac check failed for pgno=1").
  #
  # Fix: gnome-keyring is purged in ansible.yml, and this user-level D-Bus
  # activation file (which takes precedence over any /usr/share service file)
  # makes ksecretd — the KWallet-backed Secret Service — the sole provider.
  # See docs/system/secret-service-consolidation.md.
  home.file.".local/share/dbus-1/services/org.freedesktop.secrets.service".text = ''
    [D-BUS Service]
    Name=org.freedesktop.secrets
    Exec=/usr/bin/ksecretd
  '';

  # HTML thumbnails in Dolphin (and KDE file dialogs).
  #
  # KDE ships no HTML thumbnailer (the old KDE4 KHTML-based one is gone), but
  # KIO (KF6) also runs freedesktop `.thumbnailer` entries found in
  # $XDG_DATA_DIRS/thumbnailers/. The renderer itself (headless Chromium,
  # SingleFile handling, caching, KIO workarounds) is scripts/html-thumbnailer.sh;
  # here it's wrapped with PATH pinned to Nix store tools and registered.
  #
  # KIO uses the .thumbnailer file's base name as the plugin ID, so the ID is
  # "html-thumbnailer"; htmlThumbnailerEnable below adds it to Dolphin's
  # enabled preview plugins (Settings → Interface → Previews).
  xdg.dataFile."thumbnailers/html-thumbnailer.thumbnailer".text = let
    htmlThumbnailer = "${pkgs.writeShellScriptBin "html-thumbnailer" ''
      export PATH=${lib.makeBinPath (with pkgs; [ coreutils findutils gnugrep util-linux unzip ungoogled-chromium ffmpeg ])}
      ${builtins.readFile ../../scripts/html-thumbnailer.sh}
    ''}/bin/html-thumbnailer";
  in ''
    [Thumbnailer Entry]
    TryExec=${htmlThumbnailer}
    Exec=${htmlThumbnailer} %s %u %o
    MimeType=text/html;application/xhtml+xml;
  '';

  # Append the HTML thumbnailer to Dolphin's enabled preview plugins without
  # clobbering any other plugins toggled in the Dolphin UI.
  home.activation.htmlThumbnailerEnable = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    plugins=$(/usr/bin/kreadconfig6 --file dolphinrc --group PreviewSettings --key Plugins)
    if [ -n "$plugins" ] && [[ ",$plugins," != *",html-thumbnailer,"* ]]; then
      run /usr/bin/kwriteconfig6 --file dolphinrc --group PreviewSettings --key Plugins "$plugins,html-thumbnailer"
    fi
  '';

  # KWin window rule: Firefox's Picture-in-Picture window gets "Keep Above
  # Windows" automatically. kwinrulesrc is managed by KDE (the rules KCM
  # writes to it), so the rule is merged idempotently via kwriteconfig6
  # rather than owned as a whole file. Same shape as the existing FreeTube
  # PiP rule already in kwinrulesrc.
  home.activation.firefoxPipKeepAbove = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    rc="$HOME/.config/kwinrulesrc"
    if ! { [ -f "$rc" ] && /usr/bin/grep -qxF 'title=Picture-in-Picture' "$rc"; }; then
      uuid=$(/usr/bin/cat /proc/sys/kernel/random/uuid)
      run /usr/bin/kwriteconfig6 --file kwinrulesrc --group "$uuid" --key Description "Firefox Picture-in-Picture keep above"
      run /usr/bin/kwriteconfig6 --file kwinrulesrc --group "$uuid" --key above true
      run /usr/bin/kwriteconfig6 --file kwinrulesrc --group "$uuid" --key aboverule 2
      run /usr/bin/kwriteconfig6 --file kwinrulesrc --group "$uuid" --key title "Picture-in-Picture"
      run /usr/bin/kwriteconfig6 --file kwinrulesrc --group "$uuid" --key titlematch 2
      run /usr/bin/kwriteconfig6 --file kwinrulesrc --group "$uuid" --key wmclass firefox
      run /usr/bin/kwriteconfig6 --file kwinrulesrc --group "$uuid" --key wmclassmatch 1
      rules=$(/usr/bin/kreadconfig6 --file kwinrulesrc --group General --key rules)
      if [ -n "$rules" ]; then rules="$rules,$uuid"; else rules="$uuid"; fi
      run /usr/bin/kwriteconfig6 --file kwinrulesrc --group General --key rules "$rules"
      run /usr/bin/kwriteconfig6 --file kwinrulesrc --group General --key count "$(/usr/bin/awk -F, '{print NF}' <<<"$rules")"
      # Apply now instead of waiting for a re-login; ignore failure when no
      # session bus is around (e.g. activation over SSH).
      run /usr/bin/busctl --user call org.kde.KWin /KWin org.kde.KWin reconfigure || true
    fi
  '';

  # Vorta raw exclusions (Exclude dialog → Raw tab) for the cloud profiles,
  # owned by dotfiles/backups/vorta-excludes.txt. Vorta re-reads the profile
  # from settings.db on each use, so writing while it runs is fine; only an
  # Exclude dialog left open would save its stale copy back over this.
  # GUI edits are overwritten, so a drift diff is printed and the old value
  # kept in settings.db's directory before replacing it. The diff also goes to
  # the Notifications hub (source `vorta-excludes`, routes in
  # Self-Hosted/Notifications/notifications.yml) so it isn't lost in hms output.
  home.activation.vortaExcludes = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    db="$HOME/.var/app/com.borgbase.Vorta/data/Vorta/settings.db"
    src=${../dotfiles/backups/vorta-excludes.txt}
    if [ -f "$db" ]; then
      for profile in BorgBase.com rsync.net; do
        cur=$(${pkgs.sqlite}/bin/sqlite3 "$db" "select exclude_patterns from backupprofilemodel where name = '$profile'")
        if [ "$cur" != "$(<"$src")" ]; then
          echo "Vorta: replacing $profile raw exclusions (- DB, + repo):"
          changes=$(${pkgs.diffutils}/bin/diff <(echo "$cur") "$src" || true)
          echo "$changes"
          run ${pkgs.curl}/bin/curl -sSf -m 20 -o /dev/null \
            -H "Title: Vorta $profile exclusions replaced" \
            --data-binary "$changes
(- DB, + repo; old value in exclude_patterns.$profile.bak)" \
            https://notifications.device.example.com/vorta-excludes \
            || echo "notifications hub post failed" >&2
          run ${pkgs.coreutils}/bin/cp /dev/stdin "$(dirname "$db")/exclude_patterns.$profile.bak" <<<"$cur"
          run ${pkgs.sqlite}/bin/sqlite3 "$db" "update backupprofilemodel set exclude_patterns = rtrim(readfile('$src'), char(10)) where name = '$profile'"
        fi
      done
    fi
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
