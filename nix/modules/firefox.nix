{ pkgs, lib, pkgs-unstable, ... }:

let
  # ── Shared Firefox profile building blocks ──────────────────────────────

  # Containers shared by every managed profile
  ffContainers = {
    Personal = { id = 1; color = "blue";   icon = "fingerprint"; };
    Work     = { id = 2; color = "orange"; icon = "briefcase";   };
    Banking  = { id = 3; color = "green";  icon = "dollar";      };
    Shopping = { id = 4; color = "pink";   icon = "cart";        };
  };

  # Sites that block our normal egress (Mullvad) and go through tinyproxy on
  # ts-exit instead (Self-Hosted/Egress-proxy). Matches the domain and all its
  # subdomains. "; DIRECT" falls back to a direct connection off the tailnet.
  # Alternative: the FoxyProxy extension (same proxy, pattern per domain) if
  # you want a toolbar toggle to switch this on/off globally or per site.
  egressProxyDomains = [ "imgur.com" "imgur.io" ];
  egressProxyPac = pkgs.writeText "egress-proxy.pac" ''
    function FindProxyForURL(url, host) {
      var domains = ${builtins.toJSON egressProxyDomains};
      for (var i = 0; i < domains.length; i++) {
        if (host === domains[i] || dnsDomainIs(host, "." + domains[i]))
          return "PROXY 100.x.x.x:8888; DIRECT";
      }
      return "DIRECT";
    }
  '';

  # Native-messaging host for the FF Tab Closer add-on (firefox-live-debug/tab-closer/):
  # lets scripts/ff-close-tabs.py list/close live tabs by URL, unloaded ones included.
  # The add-on itself is installed by hand (AMO-signed XPI), like every other extension.
  tabCloserHost = pkgs.runCommand "ff-tab-closer-host" { } ''
    install -Dm755 ${../dotfiles/agent-skills/firefox-live-debug/tab-closer/host.py} $out/bin/ff-tab-closer-host
    substituteInPlace $out/bin/ff-tab-closer-host \
      --replace-fail '#!/usr/bin/env python3' '#!${pkgs.python3}/bin/python3'
    mkdir -p $out/lib/mozilla/native-messaging-hosts
    cat > $out/lib/mozilla/native-messaging-hosts/tab_closer.json <<EOF
    {"name": "tab_closer", "description": "FF Tab Closer agent bridge",
     "path": "$out/bin/ff-tab-closer-host", "type": "stdio",
     "allowed_extensions": ["ff-tab-closer@example.com"]}
    EOF
  '';

  # Settings shared by every managed profile (VERTEX + all 3 others)
  ffBase = {
    "browser.startup.page"                                       = 3;            # restore previous session
    "browser.startup.homepage"                                   = "about:home"; # default Firefox home page
    # ── Appearance ────────────────────────────────────────────────────────
    "browser.theme.toolbar-theme"                                = 0;      # dark toolbar (0 = dark, 1 = light, 2 = system)
    "extensions.activeThemeID"                         = "firefox-compact-dark@mozilla.org";  # compact dark theme
    "browser.theme.content-theme"                      = 0;  # dark content area for built-in pages (new tab, settings, etc.) (0 = dark, 1 = light, 2 = system)
    "layout.css.prefers-color-scheme.content-override" = 0;  # tell websites to use dark mode via CSS prefers-color-scheme media query (0 = dark, 1 = light, 2 = system)
    # ── Privacy / Security ───────────────────────────────────────────────
    "privacy.clearOnShutdown_v2.formdata"                        = true;   # clear form data on shutdown
    "privacy.userContext.enabled"                                = true;   # enable Multi-Account Containers
    "privacy.userContext.ui.enabled"                             = true;   # show container UI in menus
    # ── Remote debugging (ff-remote-debug.sh / firefox-devtools MCP) ───────
    "remote.prefs.recommended"                                   = false;  # don't apply automation prefs (no low-memory tab unloading, extension scopes, no crash resume…) when attaching to a live profile
    # ── Telemetry / Studies ───────────────────────────────────────────────
    "toolkit.telemetry.reportingpolicy.firstRun"                 = false;  # suppress the "help improve Firefox" telemetry opt-in dialog on first launch
    "browser.newtabpage.activity-stream.showSponsoredTopSites"   = false;  # no sponsored top sites
    "browser.newtabpage.activity-stream.system.showWeatherOptIn" = false;  # no weather widget prompt
    "datareporting.healthreport.uploadEnabled"                   = false;  # no health report uploads
    "datareporting.usage.uploadEnabled"                          = false;  # no usage data uploads
    # ── New Tab Page
    "browser.newtabpage.activity-stream.feeds.topsites"                   = false;  # no top sites
    "browser.newtabpage.activity-stream.feeds.section.topstories"         = false;  # no Pocket stories
    "browser.newtabpage.activity-stream.showSponsored"                    = false;  # no sponsored content
    "browser.newtabpage.activity-stream.showSponsoredCheckboxes"          = false;  # hide sponsored opt-in checkboxes
    "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.addons"   = false;  # disable CFR (Contextual Feature Recommender) popup notifications suggesting addons
    "browser.newtabpage.activity-stream.asrouter.userprefs.cfr.features" = false;  # disable CFR popup notifications promoting Firefox features ("did you know...")
    # ── URL bar ──────────────────────────────────────────────────────
    "browser.urlbar.suggest.engines"                               = false;  # hide search engine names/icons when typing in the URL bar
    "browser.urlbar.suggest.quicksuggest.sponsored"                = false;  # no sponsored suggestions in URL bar
    "browser.urlbar.showSearchSuggestionsFirst" = false;                   # show history before search suggestions
    # ── UI / Toolbar
    "browser.search.openintab"              = true;     # search results open in new tab
    "browser.search.widget.inNavBar"        = true;     # show search bar in toolbar
    "browser.toolbars.bookmarks.visibility" = "never";  # hide bookmarks bar
    # ── Media / Hardware Acceleration ─────────────────────────────────────
    "media.eme.enabled"                           = true;   # DRM / Widevine playback
    "media.ffmpeg.vaapi.enabled"                  = true;   # VA-API hardware video decode
    "media.ffvpx.enabled"                         = false;  # disable Firefox's bundled FFmpeg fork; forces use of system FFmpeg/VA-API for better hw acceleration
    "media.hardware-video-decoding.force-enabled" = true;   # force hardware video decode
    "media.webspeech.synth.enabled"               = false;  # disable the Web Speech API speechSynthesis interface; prevents websites from using text-to-speech
    "gfx.webrender.all"                           = true;   # force WebRender compositor
    # ── Reader Mode ───────────────────────────────────────────────────────
    "reader.color_scheme"  = "dark";  # dark reader theme
    "reader.font_size"     = 10;      # reader font size
    "reader.content_width" = 9;       # reader content width
    # ── AI Chat Sidebar ───────────────────────────────────────────────────
    "browser.ml.chat.provider"         = "https://claude.ai/new";  # Claude as AI sidebar provider
    "browser.ml.chat.shortcuts"        = false;  # prevent AI sidebar keyboard shortcuts from conflicting with existing keybindings
    "browser.ml.chat.page.footerBadge" = false;  # hide the small AI icon that appears in page footers suggesting the AI sidebar
    # ── DevTools ──────────────────────────────────────────────────────────
    "devtools.theme"        = "dark";   # dark devtools UI
    "devtools.toolbox.host" = "right";  # dock devtools to right side
    # ── Misc
    "findbar.highlightAll"             = true;        # highlight all find matches
    "intl.accept_languages"            = "en-US, en"; # set Accept-Language HTTP header sent to web servers for content negotiation
    "extensions.formautofill.creditCards.enabled" = false;  # no credit card autofill
    "extensions.pocket.enabled"              = false;  # disable Pocket integration
    "browser.tabs.groups.smart.userEnabled"               = false;  # disable Firefox's AI-powered automatic tab grouping that clusters tabs by topic
    "toolkit.legacyUserProfileCustomizations.stylesheets" = true;   # load userChrome.css/userContent.css from profile dir
  };

  # Hardened defaults for non-primary profiles (amnesic + persistent)
  # Extends ffBase with: telemetry lockdown, clean new tab, clean URL bar,
  # toolbar/search/reader/locale preferences
  ffHardened = {
    # ── Privacy / Security ────────────────────────────────────────────────
    # "custom" stops Firefox from enforcing a preset — "standard" and "strict" silently
    # override individual prefs (privacy.trackingprotection.enabled, network.cookie.cookieBehavior,
    # cryptomining/fingerprinting blocking, etc.) to match their preset values on every startup.
    # "custom" disables that override so the individual prefs below (and in profiles) are respected as-is.
    # "custom" does NOT build on "standard" — it simply stops all preset enforcement. Individual prefs
    # fall back to Firefox's factory defaults unless explicitly set. Since neither ffHardened nor the
    # profiles set network.cookie.cookieBehavior, it defaults to 5 (Total Cookie Protection / dFPI —
    # same as "strict", not "standard" which uses 4). Similarly, privacy.trackingprotection.enabled
    # defaults to false (tracking protection off outside private browsing, same as "standard").
    #   standard: trackingprotection only in private windows, blocks third-party tracking cookies
    #             (cookieBehavior=4), cryptominers, and fingerprinters.
    #   strict:   trackingprotection in ALL windows, blocks ALL third-party cookies (cookieBehavior=5),
    #             cryptominers, fingerprinters, and adds strict list annotation + email tracking protection.
    #             More likely to break sites (e.g. embedded logins, payment flows relying on third-party cookies).
    #   custom:
    "browser.contentblocking.category"       = "strict";
    # ── Privacy / Security
    "privacy.fingerprintingProtection" = true;    # Basic, high compatibility fingerprinting protection
    "privacy.resistFingerprinting.block_mozAddonManager" = true;   # prevent websites from detecting installed addons via the mozAddonManager API (fingerprinting vector)
    # ── Telemetry / Studies ───────────────────────────────────────────────
    "app.shield.optoutstudies.enabled"       = false;  # opt out of Mozilla Shield studies (A/B testing that silently installs experimental features)
    "browser.tabs.crashReporting.sendReport" = false;  # no crash reports
    "datareporting.policy.dataSubmissionEnabled" = false;  # master switch for all Mozilla data collection; overrides individual data reporting prefs
    "browser.discovery.enabled"                  = false;  # hide the "Recommended Extensions" section in about:addons
    # ── Network Privacy - No DNS/link/speculative prefetching
    "network.dns.disablePrefetch"             = true;   # prevent preemptive DNS resolution of links on a page, which leaks browsing patterns to DNS servers
    "network.prefetch-next"                   = false;  # prevent background downloading of linked pages, which leaks browsing intent and wastes bandwidth
    "network.http.speculative-parallel-limit" = 0;      # prevent Firefox from opening TCP connections to servers it predicts you'll visit (e.g. autocomplete hover)
    "network.trr.mode"                                   = 5;      # fully disable DNS-over-HTTPS (mode 5); system already uses a trusted resolver / local DNS filtering
    # ── Local Network Access (Firefox 151+) ───────────────────────────────
    # FF151 rolled LNA out to all users: it gates HTTPS pages from XHR/fetch to
    # "local network" address spaces, and 100.x.x.x/10 (the tailnet CGNAT range)
    # counts as local. Self-hosted apps on *.device.example.com (Calibre
    # reader, Forgejo, Syncthing, …) then have most of their request bursts dropped
    # by an open FF concurrency bug (bugzilla 2033408). Exempt the whole tailnet
    # base domain so LNA stays on everywhere else. Format: comma-separated, `*.`
    # prefix matches the base + all subdomains, hostname only (no scheme/port).
    "network.lna.skip-domains"                = "*.device.example.com";
    # ── Live suggestions
    "browser.urlbar.quicksuggest.scenario"    = "history";  # disable Mozilla's cloud-based Firefox Suggest service; only suggest from local history
    "browser.urlbar.suggest.searches"           = false;  # prevent URL bar from querying the default search engine for live suggestions as you type
    "browser.search.suggest.enabled"           = false;  # global switch disabling search engine live suggestions in all contexts (URL bar, search bar, new tab)
    # ── Media ─────────────────────────────────────────────────────────────
    "media.autoplay.default" = 5;  # block all autoplay (audio and video)
    "media.videocontrols.picture-in-picture.playback-speed.enabled" = true;   # Enable playback speed control in PiP
  };

  # Search engines shared by minimal profiles (extracted from VERTEX)
  ffSearch = import ./firefox-search.nix;

in

{
  # ── Web Browser ──────────────────────────────────────────────────────────────
  #
  # Home Manager Firefox module — docs and source:
  #   Options reference: https://nix-community.github.io/home-manager/options.xhtml#opt-programs.firefox.enable
  #   Source code:       https://github.com/nix-community/home-manager/tree/master/modules/programs/firefox
  #   Release notes:     https://nix-community.github.io/home-manager/release-notes.xhtml
  #   Commit history:    https://github.com/nix-community/home-manager/commits/master/modules/programs/firefox
  #   Local docs:        docs/system/nix-firefox.md

  programs.firefox = {
    enable = true;
    # With `package = null` it would use the non-Nix tarball at ~/Documents/ESSENTIALS/Programs/firefox
    # WARNING: With package = null, Home Manager skips writing policies.json to the Firefox installation directory entirely — it doesn't
    # know where to put it. The policies in programs.firefox.policies are just ignored.
    # Fix: write policies.json directly to your tarball Firefox's distribution/ directory via home.file.
    package = pkgs-unstable.firefox;
    configPath = ".mozilla/firefox"; # new 2026 default: "${config.xdg.configHome}/mozilla/firefox";
    nativeMessagingHosts = [ pkgs.kdePackages.plasma-browser-integration tabCloserHost ];

    # Cookie exceptions — populated from xsy8besa.PRIME permissions.sqlite.
    # Sites listed in Allow keep their cookies even with sanitizeOnShutdown.
    #
    # These sites can track whatever I do on them and that it's me the same
    # user visiting each time despite VPN pseudononymisation. Additionally
    # local attacks (evil maid) can see my account info / steal cookies.
    policies.Cookies.Allow = [
      "http://localhost:8384"
      "http://localhost:8193"
      "http://100.x.x.x:6768"
      # Headscale
      "https://aiometadata.device.example.com"
      "https://calibre.device.example.com"
      "https://calibre-content.device.example.com"
      "https://firefox-desktop-tabs.device.example.com"
      "https://freellmapi.device.example.com"
      "https://git.device.example.com"
      "https://headscale.device.example.com"
      "https://lord-ubuntu.device.example.com"
      "https://rclone-lord-ubuntu.device.example.com"
      "https://reddit.device.example.com/"
      "https://syncyomi.device.example.com"
      "https://ttrss.device.example.com"
      "https://yamtrack.device.example.com/"
      "https://watchsync.device.example.com/"
      "https://wud-lord-ubuntu.device.example.com"
      # Tailscale
      "https://lord-ubuntu.tailee8f02.ts.net"
      # Own services
      "https://13-ttrss.example.com"  # "https://.example.com" didn't work
      "https://.ts.net"   # Tailscale
      "https://9433uf4rgkf7.shares.zrok.io/"    # Calibre # "https://.zrok.io" didn't work
      # OTHER
      "https://.claude.com"
      "https://.geforcenow.com"
      "https://accounts.google.com"
      # AWS
      "https://.amazon.com"
      "https://.aws.com"
      "https://.awspartner.com"
      "https://us-east-1.signin.aws"
      "https://cloudquest.skillbuilder.aws"
      "https://.signin.aws"
      "https://steampowered.com"    # "https://store.steampowered.com" alone didn't work
      "https://store.steampowered.com"    # "https://.steampowered.com" didn't work
      "https://account.bbc.com"
      "https://account.booking.com"
      "https://account.nuffieldhealth.com"
      "https://accounts.firefox.com"
      "https://accounts.spotify.com"
      "https://aiostreams.elfhosted.com"
      "https://anilist.co"
      "https://app.addy.io"
      "https://app.element.io"
      "https://app.trakt.tv"
      "https://apps.axahealth.co.uk"
      "https://auth.mozilla.auth0.com"
      "https://auth.openai.com"
      "https://auth.scribd.com" # uses email 2FA
      "https://auth.rumble.com"
      "https://backloggd.com"
      "https://bank.barclays.co.uk"
      "https://www.bbc.co.uk" # iPlayer sign-in - wasn't enough
      "https://bcol.barclaycard.co.uk"
      "https://bugs.kde.org"
      "https://bugzilla.mozilla.org"
      "https://chatgpt.com"
      "https://christisking.cc"
      "https://claude.ai"
      "https://cloud.digitalocean.com"
      "https://community.frame.work"
      "https://community.signalusers.org"
      "https://confer.to"
      "https://dental.bupa.co.uk"
      "https://discord.com"
      "https://discuss.grapheneos.org"
      "https://discuss.logseq.com"
      "https://discuss.privacyguides.net"
      "https://f95zone.to"
      "https://forum.mobilism.org"
      "https://forum.questionablequesting.com"
      "https://forums.socialmediagirls.com"
      "https://funnyjunk.com"
      "https://gameruprising.to"
      "https://gaming.amazon.com"
      "https://gg.deals"
      "https://github.com"
      "https://gitlab.com"
      "https://howlongtobeat.com"
      "https://www.kagesekai.ai/"
      "https://www.isekaizero.ai"
      "https://www.itv.com" # Football streams
      "https://access.leedsbuildingsociety.co.uk"
      "https://login.coinbase.com"
      "https://login.live.com"
      "https://login.mailbox.org"
      "https://login.nvgs.nvidia.com"
      "https://login.tailscale.com"
      "https://logseq.com"
      "https://mega.nz"
      "https://personal.metrobankonline.co.uk"
      "https://money4life.scottishwidows.co.uk"
      "https://musicbrainz.org"
      "https://my.asos.com"
      "https://mypolicy.unum.co.uk"
      "https://nano-gpt.com"
      "https://news.ycombinator.com"
      "https://open.spotify.com"
      "https://openrouter.ai"
      "https://real-debrid.com"
      # Redlib for Reddit
      "https://red.artemislena.eu"
      "https://reddit.adminforge.de"
      "https://reddit.nerdvpn.de"
      "https://redlib.4o1x5.dev"
      "https://redlib.catsarch.com"
      "https://redlib.cow.rip"
      "https://redlib.frontendfriendly.xyz"
      "https://redlib.kylrth.com"
      "https://redlib.nadeko.net"
      "https://redlib.orangenet.cc"
      "https://redlib.perennialte.ch"
      "https://redlib.privacyredirect.com"
      "https://redlib.privadency.com"
      "https://redlib.pussthecat.org"
      "https://redlib.r4fo.com"
      "https://redlib-2.privadency.com"
      "https://safereddit.com"

      "https://roadmap.sh"
      "https://secure.backblaze.com"
      "https://slack.com"
      "https://sso.crunchyroll.com"
      "https://steamcommunity.com"
      "https://steamdb.info"
      "https://store.epicgames.com"
      "https://streamable.com"
      "https://trakt.tv"
      "https://.stremio.com"
      "https://.telegram.org"
      "https://web.whatsapp.com"
      "https://www.amazon.co.uk"
      "https://www.axahealth.co.uk"
      "https://www.britishairways.com"
      "https://www.codecademy.com"
      "https://www.direct.aviva.co.uk"
      "https://www.epicgames.com"
      "https://www.goodreads.com"
      "https://www.instagram.com"
      "https://www.last.fm"
      "https://www.loaded.com"
      "https://www.mtggoldfish.com"
      "https://.nexusmods.com"
      "https://www.nexusmods.com"
      "https://www.patreon.com"
      "https://www.paypal.com"
      "https://www.reddit.com"
      "https://www.royalroad.com"
      "https://www.tiktok.com"
      "https://www.tripadvisor.co.uk"
      "https://www.twitch.tv"
      "https://www.youtube.com"
      "https://x.com"
      "https://z-lib.fm"
      "https://z-library.sk"
    ];

    # Per-site permission grants (about:preferences → Permissions exceptions).
    # Autoplay.Allow = the site's "Audio and Video" permission set to Allow,
    # overriding `media.autoplay.default = 5` (block all) for these origins.
    policies.Permissions.Autoplay.Allow = [
      "https://www.pornhub.com"
    ];

    # Copied from /home/boss/.mozilla/firefox/xsy8besa.PRIME
    # to /home/boss/.mozilla/firefox/VERTEX
    profiles.VERTEX = {
      id = 0;
      isDefault = true;

      settings = ffBase // ffHardened // {
        # ── Appearance ────────────────────────────────────────────────────────
        "browser.display.background_color"                  = "#000000";  # page bg for unstyled pages
        "browser.display.foreground_color"                  = "#f6f5f4";  # page text for unstyled pages

        # ── Privacy / Security ────────────────────────────────────────────────
        "privacy.sanitize.sanitizeOnShutdown"                 = true;   # enable "Delete cookies and site data when Firefox is closed" (exceptions via Cookies.Allow above)
        "privacy.clearOnShutdown_v2.browsingHistoryAndDownloads" = false;  # exempt browsing history from the sanitize-on-shutdown sweep so navigation history is preserved
        "privacy.history.custom"                             = true;   # enable "Use custom settings for history" in about:preferences#privacy for granular history control
        "privacy.resistFingerprinting.letterboxing"          = true;   # pad window to resist fingerprinting

        # ── Network ───────────────────────────────────────────────────────────
        "network.proxy.type"                                 = 2;      # use a PAC file (proxy auto-config)
        "network.proxy.autoconfig_url"                       = "file://${egressProxyPac}";  # route egressProxyDomains via the ts-exit egress proxy

        # ── UI / Toolbar ──────────────────────────────────────────────────────
        "browser.tabs.inTitlebar"                             = 0;      # tabs below title bar
        "browser.bookmarks.defaultLocation"                   = "toolbar_____";  # new bookmarks go to toolbar
        "browser.bookmarks.showMobileBookmarks"               = true;   # make bookmarks synced from Firefox for Android/iOS visible in the bookmarks menu
        "browser.toolbars.bookmarks.visibility"               = "always";  # always show bookmarks bar
        "browser.zoom.siteSpecific"                           = false;  # apply zoom level uniformly across all sites rather than remembering zoom per domain

      };

      search = ffSearch;


      userChrome = ''
        /* Hide the horizontal tab bar — Sidebery provides vertical tabs instead. */
        #TabsToolbar {
            visibility: collapse !important;
        }

        /* Native tabs auto-hide when not hovered - for Tab Note/Split View usage https://github.com/mbnuqw/sidebery/issues/2327#issuecomment-4340647031
        @media -moz-pref("sidebar.verticalTabs") and -moz-pref("sidebar.visibility","expand-on-hover"){
          #main-window > body > #browser{
            --sidebar-launcher-collapsed-width: 10px !important;
          }
          sidebar-main:not([expanded]){
            max-width: 10px !important;
          }
        }
        Disabled because it gets in the way when I move my mouse off-screen
        */
      '';

      containers = ffContainers;
      containersForce = true;

    # Extensions are managed by Firefox Sync, not declaratively. The NUR
    # firefox-addons attrset would provide some, but nixpkgs itself has very
    # few. Since 74 extensions are installed in PRIME, Sync is the practical
    # path. Below is a reference inventory of all installed extensions.
    #
    # addon@darkreader.org                    Dark Reader
    # uBlock0@raymondhill.net                 uBlock Origin
    # sponsorBlocker@ajay.app                SponsorBlock
    # {3c078156-979c-498b-8990-85f7987dd929} Sidebery (vertical tabs)
    # keepassxc-browser@keepassxc.org         KeePassXC Browser
    # zotero@chnm.gmu.edu                    Zotero Connector
    # enhancerforyoutube@maximerf.addons.mozilla.org  Enhancer for YouTube
    # redirector@einaregilsson.com            Redirector
    # page-assist@nazeem                      Page Assist (local AI)
    # plasma-browser-integration@kde.org      Plasma Browser Integration
    # WebToEpub@Baka-tsuki.org                Web to EPUB
    # faststream@andrews                      FastStream
    # feed-preview@code.guido-berhoerster.org Feed Preview
    # firefox-extension@steamdb.info          SteamDB
    # gdpr@cavi.au.dk                         GDPR consent manager
    # harper@writewithharper.com              Harper (grammar checker)
    # i@diygod.me                             RSSHub Radar
    # amptra@keepa.com                        Keepa (Amazon price tracker)
    # browser-extension@anonaddy              AnonAddy / SimpleLogin
    # chrome-mask@overengineer.dev            Chrome Mask (UA spoofing)
    # copy-opaque-image@qw.thucfb.com        Copy Opaque Image
    # fakedata@haterapps.com                  Fake Data
    # dont-accept-webp@jeffersonscher.com     Don't Accept WebP
    # webpconverter@hilberteikelboom.nl       WebP Converter
    # zoompage-we@DW-dev                      ZoomPage WE
    # refinedhackernews@mihir.ch              Refined Hacker News
    # save-as-pdf-ff@pdfcrowd.com             Save as PDF
    # youtube-rss-finder@gustiaux.com         YouTube RSS Finder
    # wappalyzer@crunchlabz.com               Wappalyzer (tech detector)
    # readit@lucidity                         Read It
    # @activatereaderview                      Activate Reader View
    # referer-mod@9a5ba22d-...                Referer Mod
    # jid0-dsq67mf5kjjhiiju2dfb6kk8dfw@jetpack  DownThemAll
    # your-dynamic-dashboard@ditom.com        Dynamic Dashboard (new tab)
    # 7esoorv3@alefvanoon.anonaddy.me         SimpleLogin
    # dharmikparmar2004@yahoo.com             (unknown)
    # + ~40 additional extensions identified by GUID only
    };

    # ── Other profiles ──

    profiles.minimal-amnesic = {
      id = 1;

      settings = ffBase // ffHardened // {
        # ── Privacy / Security (amnesic extras) ───────────────────────────────
        "privacy.sanitize.sanitizeOnShutdown"      = true;   # clear data on shutdown
        "privacy.sanitize.timeSpan"               = 0;      # clear everything (all time)
        "privacy.clearOnShutdown_v2.siteSettings" = true;   # reset per-site permissions (camera, mic, notifications, location, etc.) on shutdown
        "privacy.history.custom"                  = true;   # use custom history settings
        "signon.rememberSignons"                  = false;  # never save passwords
      };

      search = ffSearch;
      userChrome = ''
        /* Show search one-off engines as a grid of icons instead of a vertical list */
        #PopupSearchAutoComplete .search-panel-one-offs {
            display: flex !important;
            flex-wrap: wrap !important;
        }
        #PopupSearchAutoComplete .searchbar-engine-one-off-item {
            flex-basis: calc(25% - 4px) !important;
            margin: 2px !important;
        }
      '';
      containers = ffContainers;
      containersForce = true;

      extensions = {
        force = true;
        packages = with pkgs.nur.repos.rycee.firefox-addons; [
          ublock-origin
          consent-o-matic
          darkreader
        ];
      };
    };

    profiles.minimal-persistent = {
      id = 2;
      settings = ffBase // ffHardened;
      search = ffSearch;
      userChrome = ''
        /* Show search one-off engines as a grid of icons instead of a vertical list */
        #PopupSearchAutoComplete .search-panel-one-offs {
            display: flex !important;
            flex-wrap: wrap !important;
        }
        #PopupSearchAutoComplete .searchbar-engine-one-off-item {
            flex-basis: calc(25% - 4px) !important;
            margin: 2px !important;
        }
      '';
      containers = ffContainers;
      containersForce = true;

      extensions = {
        force = true;
        packages = with pkgs.nur.repos.rycee.firefox-addons; [
          ublock-origin
          consent-o-matic
          darkreader
          keepassxc-browser
          libredirect
          plasma-integration
        ];
      };
    };

    profiles.dev-edition-default = {
      id = 3;

      settings = ffBase // {
        # ── Privacy / Security ────────────────────────────────────────────────
        "permissions.isolateBy.userContext"          = true;   # each Multi-Account Container gets its own permission grants (e.g. camera in Personal ≠ camera in Banking)
        # "custom" prevents Firefox from overriding individual tracking/cookie/fingerprint prefs with a
        # preset's values on startup — the explicit prefs in this profile (and inherited from ffBase) are used as-is.
        "browser.contentblocking.category"          = "standard";
        "signon.rememberSignons"                    = false;  # never save passwords
        "signon.autofillForms"                      = false;  # no password autofill
        "extensions.formautofill.addresses.enabled" = false;  # no address autofill
        # ── Safe Browsing (off for dev/testing) ───────────────────────────────
        "browser.safebrowsing.blockedURIs.enabled" = false;  # no blocked URI checks
        "browser.safebrowsing.downloads.enabled"   = false;  # disable Google Safe Browsing checks on downloads; off for dev profile since it can block legitimate tools
        "browser.safebrowsing.malware.enabled"     = false;  # no malware protection
        "browser.safebrowsing.phishing.enabled"    = false;  # no phishing protection


        # ── New Tab Page ──────────────────────────────────────────────────────
        "browser.topsites.contile.enabled"           = false;  # disable Contile (Mozilla's ad-tile partnership) sponsored shortcut tiles on the new tab page
        "browser.urlbar.suggest.searches"            = false;  # prevent URL bar from querying the default search engine for live suggestions as you type

        # ── Developer ─────────────────────────────────────────────────────────
        "browser.dom.window.dump.enabled" = true;   # enable window.dump() for debugging
        "xpinstall.signatures.required"   = false;  # allow unsigned extensions
        "extensions.update.enabled"       = false;  # no automatic extension updates
        "browser.backup.enabled"          = false;  # disable Firefox's built-in profile backup feature that periodically saves profile snapshots
      };

      containers = ffContainers;
      containersForce = true;
    };
  };

  # The post-link activation script below converts the HM-managed profiles.ini
  # symlink into a writable copy (to append [Install*] sections). On the next
  # switch, HM sees the regular file and refuses to overwrite it. Setting
  # force = true makes HM replace it unconditionally.
  home.file.".mozilla/firefox/profiles.ini".force = true;

  # Replace the HM-managed profiles.ini symlink with a writable copy that
  # includes [Install*] sections. Firefox uses these to map installation IDs
  # to default profiles — without them, Firefox Developer Edition (and other
  # parallel installs) show "Profile Missing" on launch.
  home.activation.firefoxProfilesIni = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    dest="$HOME/.mozilla/firefox/profiles.ini"
    if [ -L "$dest" ]; then
      src=$(readlink -f "$dest")
      $DRY_RUN_CMD rm "$dest"
      $DRY_RUN_CMD install -m 644 "$src" "$dest"
      # HM's profiles.ini has no StoreID=, which hides profiles from the new
      # Manage Profiles UI. Restore each one from the profile's own prefs.js.
      for path in $(sed -n 's/^Path=//p' "$dest"); do
        id=$(sed -n 's/.*"toolkit.profiles.storeID", "\([^"]*\)".*/\1/p' "$HOME/.mozilla/firefox/$path/prefs.js" 2>/dev/null || true)
        if [ -n "$id" ]; then $DRY_RUN_CMD sed -i "/^Path=$path\$/a StoreID=$id" "$dest"; fi
      done
    fi
    # Append Install sections only if not already present
    if ! grep -q 'Install9255EBAFD2F5B3DD' "$dest" 2>/dev/null; then
      cat >> "$dest" << 'INSTALLS'

[Install9255EBAFD2F5B3DD]
Default=xsy8besa.PRIME
Locked=1

[InstallF7E9AADF645338CA]
Default=dev-edition-default
Locked=1

[Install4F96D1932A9F858E]
Default=vw6ecpgi.Default
Locked=1

[Install3703CE5FC1A60019]
Default=/home/boss/Vaults/gocryptfs1/Browsers/DEVELOP/profile
Locked=1

[Install5217A8ECA6170CFA]
Default=dxka9jsp.firefox-test-2023
Locked=1

[Install48512B97725692BF]
Default=jsyi7924.default-release-1
Locked=1

[Install52D6329630FDDB0C]
Default=/home/boss/Vaults/gocryptfs1/Browsers/MASTER/profile
Locked=1

[Install81EC076AA7E7C9D3]
Default=/home/boss/Vaults/gocryptfs1/Browsers/WORK2/profile
Locked=1
INSTALLS
    fi
  '';
}
