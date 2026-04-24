{ config, pkgs, lib, ... }:

let
  jsonFormat = pkgs.formats.json { };

  # Written as a mutable file (not a Nix-store symlink) so Claude Code can
  # modify it at runtime — e.g. the /effort slash command rewrites this file.
  # Same content that programs.claude-code.settings would generate, but
  # deployed via home.activation (install -m 644) instead of home.file.
  # See: home-manager#8654 (same issue that forced settings to be omitted for
  # gemini-cli). Changes made at runtime are overwritten on the next `hms`.
  claudeCodeSettings = pkgs.writeText "claude-code-settings.json" (builtins.toJSON {
    "$schema"           = "https://json.schemastore.org/claude-code-settings.json";
    includeCoAuthoredBy = false;
    effortLevel         = "medium";
    permissions = {
      allow = [ "WebFetch" "WebSearch" ];
    };
    hooks = {
      Stop             = [{ hooks = [{ type = "command"; command = "bash ~/.claude/hooks/notify-waiting.sh stop";      }]; }];
      Notification     = [{ hooks = [{ type = "command"; command = "bash ~/.claude/hooks/notify-waiting.sh";           }]; }];
      UserPromptSubmit = [{ hooks = [{ type = "command"; command = "bash ~/.claude/hooks/notify-reset-dedupe.sh";      }]; }];
    };
  });

  # ── Shared Firefox profile building blocks ──────────────────────────────

  # Containers shared by every managed profile
  ffContainers = {
    Personal = { id = 1; color = "blue";   icon = "fingerprint"; };
    Work     = { id = 2; color = "orange"; icon = "briefcase";   };
    Banking  = { id = 3; color = "green";  icon = "dollar";      };
    Shopping = { id = 4; color = "pink";   icon = "cart";        };
  };

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
    "browser.urlbar.quicksuggest.scenario"                         = "history";  # disable Mozilla's cloud-based Firefox Suggest service; only suggest from local history
        "browser.urlbar.showSearchSuggestionsFirst" = false;  # show history before search suggestions
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
  };

  # Hardened defaults for non-primary profiles (amnesic + persistent)
  # Extends ffBase with: telemetry lockdown, clean new tab, clean URL bar,
  # toolbar/search/reader/locale preferences
  ffHardened = {
    # ── Privacy / Security ────────────────────────────────────────────────
    "browser.contentblocking.category"       = "custom";  # use custom tracking protection rather than "standard"/"strict" presets, allowing granular control
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
    "dom.security.https_only_mode"                       = true;   # enable HTTPS-Only Mode — blocks or warns on all plain HTTP connections

    # ── URL bar
    "browser.urlbar.suggest.searches"           = false;  # prevent URL bar from querying the default search engine for live suggestions as you type
    # ── Media ─────────────────────────────────────────────────────────────
    "media.autoplay.default" = 5;  # block all autoplay (audio and video)
    # ── UI ────────────────────────────────────────────────────────────────
    "browser.search.suggest.enabled" = false;  # global switch disabling search suggestions in all contexts (URL bar, search bar, new tab)
  };

in

# Home Manager program configurations.
# Using programs.* modules instead of bare packages gives Home Manager the
# ability to manage config files, shell integrations, and user services.
{
  # ── Version Control ──────────────────────────────────────────────────────────

  programs.git = {
    enable = true;

    # GPG signing key — gpgsign is disabled by default; enable per-repo if needed
    signing = {
      key           = "GPGKEY1";
      format        = "openpgp";
      signByDefault = false;
    };

    settings = {
      # Default identity (1 = VictorVow); use `git su [1|2]` to switch per-repo
      # Identity 2 (USER2): 22418751+USER2@users.noreply.github.com, key GPGKEY2
      user.name  = "VictorVow";
      user.email = "12621257+VictorVow@users.noreply.github.com";

      init.defaultBranch   = "main";
      pull.rebase          = false;
      push.autoSetupRemote = true;

      gpg.program            = "/usr/bin/gpg";
      tag.forceSignAnnotated = false;

      # Credential storage: libsecret (KDE Wallet) with a 12-hour cache
      credential = {
        helper          = "libsecret";
        credentialStore = "cache";
        cacheOptions    = "--timeout 43200";
      };
      # Per-host credential helpers
      "credential \"https://github.com\"".helper      = "libsecret";
      "credential \"https://gist.github.com\"".helper = "libsecret";
      "credential \"https://dev.azure.com\"".useHttpPath = true;

      # git checkout-fb (shell application) - checkout an arbitrary branch and then remove that remote
      alias.ll = "log --oneline";
      core.editor = "micro";
      alias.su =
        let
          set1 = "git config user.name 'VictorVow'"
            + " && git config user.email '12621257+VictorVow@users.noreply.github.com'"
            + " && git config user.signingkey 'GPGKEY1'"
            + " && echo 'switched -> VictorVow (identity 1)'";
          set2 = "git config user.name 'USER2'"
            + " && git config user.email '22418751+USER2@users.noreply.github.com'"
            + " && git config user.signingkey 'GPGKEY2'"
            + " && echo 'switched -> USER2 (identity 2)'";
        in
          "!f() { case \"$1\" in"
          + " 1) ${set1};;"
          + " 2) ${set2};;"
          + " \"\") echo \"current: $(git config user.name) <$(git config user.email)>\";;"
          + " *) echo 'usage: git su [1|2]';;"
          + " esac }; f";
    };
  };

  # Git LFS — large file storage integration
  programs.git.lfs.enable = true;

  # Global gitignore — local tooling artifacts that should never be committed
  programs.git.ignores = [
    ".direnv/"
    "**/.claude/settings.local.json"
  ];

  # Auto-select USER2 identity for repos under ~/Documents/ESSENTIALS/installs/
  # The trailing slash makes gitdir: match any repo inside the directory tree.
  # See docs/git-identity-management.md for the full picture of identity management.
  programs.git.includes = [
    {
      condition = "gitdir:~/Documents/ESSENTIALS/installs/";
      path      = "~/.config/git/identity-USER2";
    }
  ];

  # Identity snippet loaded by the includeIf above
  xdg.configFile."git/identity-USER2".text = ''
    [user]
        name       = USER2
        email      = 22418751+USER2@users.noreply.github.com
        signingkey = GPGKEY2
  '';

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

    # Nix-wrapped Firefox uses its own native-messaging-host paths, so the
    # system-level /usr/lib/mozilla/native-messaging-hosts/ is not found.
    # KeePassXC (Flatpak) uses ~/.mozilla/native-messaging-hosts/ which the
    # wrapper does check, so it continues to work without being listed here.
    nativeMessagingHosts = [
      pkgs.kdePackages.plasma-browser-integration
    ];

    # Cookie exceptions — populated from xsy8besa.PRIME permissions.sqlite.
    # Sites listed in Allow keep their cookies even with sanitizeOnShutdown.
    #
    # These sites can track whatever I do on them and that it's me the same 
    # user visiting each time despite VPN pseudononymisation
    policies.Cookies.Allow = [
      "http://15-baikal.example.com"
      "http://localhost:8080"
      "http://localhost:8193"
      "https://.steampowered.com"
      "https://13-ttrss.example.com"
      "https://9433uf4rgkf7.shares.zrok.io"
      "https://account.booking.com"
      "https://account.nuffieldhealth.com"
      "https://accounts.firefox.com"
      "https://accounts.google.com"
      "https://aiostreams.elfhosted.com"
      "https://anilist.co"
      "https://app.addy.io"
      "https://app.element.io"
      "https://apps.axahealth.co.uk"
      "https://auth.mozilla.auth0.com"
      "https://auth.my.idmobile.co.uk"
      "https://auth.openai.com"
      "https://auth.rumble.com"
      "https://backloggd.com"
      "https://bank.barclays.co.uk"
      "https://bcol.barclaycard.co.uk"
      "https://bugs.kde.org"
      "https://bugzilla.mozilla.org"
      "https://chatgpt.com"
      "https://christisking.cc"
      "https://cla-assistant.io"
      "https://claude.ai"
      "https://cloud.digitalocean.com"
      "https://community.frame.work"
      "https://community.signalusers.org"
      "https://confer.to"
      "https://console.scaleway.com"
      "https://dental.bupa.co.uk"
      "https://discord.com"
      "https://discuss.grapheneos.org"
      "https://discuss.logseq.com"
      "https://discuss.privacyguides.net"
      "https://eu.shadow.tech"
      "https://exercism.org"
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
      "https://gitlab.torproject.org"
      "https://howlongtobeat.com"
      "https://itch.io"
      "https://jam.aws.com"
      "https://kjy1zvaces13.share.zrok.io"
      "https://l.opnxng.com"
      "https://libreddit.kavin.rocks"
      "https://libreddit.privacydev.net"
      "https://listenbrainz.org"
      "https://login.coinbase.com"
      "https://login.live.com"
      "https://login.mailbox.org"
      "https://login.nvgs.nvidia.com"
      "https://login.tailscale.com"
      "https://login.us-east-1.auth.skillbuilder.aws"
      "https://logseq.com"
      "https://mega.nz"
      "https://money4life.scottishwidows.co.uk"
      "https://musicbrainz.org"
      "https://my.asos.com"
      "https://mypolicy.unum.co.uk"
      "https://nano-gpt.com"
      "https://news.ycombinator.com"
      "https://open.spotify.com"
      "https://openrouter.ai"
      "https://partnercentral.awspartner.com"
      "https://pixeldrain.com"
      "https://platform.claude.com"
      "https://play.geforcenow.com"
      "https://profile.aws.amazon.com"
      "https://real-debrid.com"
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
      "https://roadmap.sh"
      "https://rule34.xxx"
      "https://secure.nexdock.com"
      "https://signup.cloud.oracle.com"
      "https://skillbuilder.aws"
      "https://slack.com"
      "https://sso.crunchyroll.com"
      "https://steamcommunity.com"
      "https://steamdb.info"
      "https://steampowered.com"
      "https://store.steampowered.com"
      "https://streamable.com"
      "https://tdac.immigration.go.th"
      "https://thegameawards.com"
      "https://tmo.tescotravelmoney.com"
      "https://trakt.tv"
      "https://us-east-1.signin.aws"
      "https://users.nexusmods.com"
      "https://web.stremio.com"
      "https://web.telegram.org"
      "https://web.whatsapp.com"
      "https://www.airalo.com"
      "https://www.amazon.co.uk"
      "https://www.axahealth.co.uk"
      "https://www.britishairways.com"
      "https://www.codecademy.com"
      "https://www.direct.aviva.co.uk"
      "https://www.epicgames.com"
      "https://www.fanfiction.net"
      "https://www.feelgoodcontacts.com"
      "https://www.goodreads.com"
      "https://www.google.com"
      "https://www.instagram.com"
      "https://www.last.fm"
      "https://www.loaded.com"
      "https://www.mtggoldfish.com"
      "https://www.nexusmods.com"
      "https://www.patreon.com"
      "https://www.paypal.com"
      "https://www.reddit.com"
      "https://www.royalroad.com"
      "https://www.thetrainline.com"
      "https://www.tiktok.com"
      "https://www.tripadvisor.co.uk"
      "https://www.twitch.tv"
      "https://www.youtube.com"
      "https://z-lib.fm"
      "https://z-library.sk"
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
        "privacy.resistFingerprinting.block_mozAddonManager" = true;   # prevent websites from detecting installed addons via the mozAddonManager API (fingerprinting vector)
        "browser.contentblocking.category"                   = "standard";  # balanced preset (blocks known trackers, cryptominers, fingerprinters); overrides ffHardened's "custom" for this profile

        # ── UI / Toolbar ──────────────────────────────────────────────────────
        "browser.tabs.inTitlebar"                             = 0;      # tabs below title bar
        "browser.search.suggest.enabled.private"              = true;   # allow search suggestions in private windows
        "browser.bookmarks.defaultLocation"                   = "toolbar_____";  # new bookmarks go to toolbar
        "browser.bookmarks.showMobileBookmarks"               = true;   # make bookmarks synced from Firefox for Android/iOS visible in the bookmarks menu
        "browser.toolbars.bookmarks.visibility"               = "always";  # always show bookmarks bar
        "browser.zoom.siteSpecific"                           = false;  # apply zoom level uniformly across all sites rather than remembering zoom per domain
        "toolkit.legacyUserProfileCustomizations.stylesheets" = true;   # load userChrome.css/userContent.css from the profile dir to customize Firefox UI (required for Sidebery tab bar hiding below)

      };

      # Hide the horizontal tab bar — Sidebery provides vertical tabs instead.
      userChrome = ''
        #TabsToolbar {
            visibility: collapse !important;
        }
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

    profiles.PRIME = {
      id = 1;
    };

    profiles.minimal-amnesic = {
      id = 2;

      settings = ffBase // ffHardened // {
        # ── Privacy / Security (amnesic extras) ───────────────────────────────
        "privacy.sanitize.sanitizeOnShutdown"      = true;   # clear data on shutdown
        "privacy.sanitize.timeSpan"               = 0;      # clear everything (all time)
        "privacy.clearOnShutdown_v2.siteSettings" = true;   # reset per-site permissions (camera, mic, notifications, location, etc.) on shutdown
        "privacy.history.custom"                  = true;   # use custom history settings
        "signon.rememberSignons"                  = false;  # never save passwords
      };

      containers = ffContainers;
      containersForce = true;
    };

    profiles.minimal-persistent = {
      id = 3;
      settings = ffBase // ffHardened;
      containers = ffContainers;
      containersForce = true;
    };

    profiles.dev-edition-default = {
      id = 4;

      settings = ffBase // {
        # ── Privacy / Security ────────────────────────────────────────────────
        "permissions.isolateBy.userContext"          = true;   # each Multi-Account Container gets its own permission grants (e.g. camera in Personal ≠ camera in Banking)
        "browser.contentblocking.category"          = "custom";  # use custom tracking protection rather than "standard"/"strict" presets, allowing granular control
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

      # ── Status bar ──────────────────────────────────────────────────────────
      set -g status-style         bg="#1a1a2e",fg="#cdd6f4"
      set -g status-left          " [#S] "
      set -g status-left-style    fg="#00c1ff",bold
      set -g status-right         "#{?client_prefix,⌨️  PREFIX,}"
      set -g status-right-style   fg="#ffcc00",bold

      # Inactive windows: dim text, no background
      set -g window-status-format        " #I:#W#{?window_flags,#{window_flags}, } "
      set -g window-status-style         fg="#666688",bg=default

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

  # Tell ripgrep (and tools that use it, like Claude Code and Gemini CLI) to skip
  # the rclone FUSE mount — traversing it causes high CPU on the rclone mount process.
  home.file.".ignore".text = ''
    Mounts/
  '';

  # ── Claude Code hook scripts ───────────────────────────────────────────────────
  # Managed here so they're version-controlled alongside the rest of the nix config.
  # Using home.file with executable = true (NOT programs.claude-code.hooks, which
  # writes non-executable read-only Nix-store symlinks that cannot be chmod'd).

  home.file.".claude/hooks/notify-waiting.sh" = {
    source     = ../dotfiles/claude-hooks/notify-waiting.sh;
    executable = true;
  };

  home.file.".claude/hooks/notify-reset-dedupe.sh" = {
    source     = ../dotfiles/claude-hooks/notify-reset-dedupe.sh;
    executable = true;
  };

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
    '';
  };

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

  # ── Text Editors ─────────────────────────────────────────────────────────────

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

  programs.vscode = {
    enable = true;
    # Nix store binaries can't have root-owned 4755 perms, so the SUID sandbox
    # helper is always misconfigured. Wrap the binary to pass --no-sandbox.
    package = pkgs.symlinkJoin {
      name = "vscode";
      inherit (pkgs.vscode) pname version meta;
      paths = [ pkgs.vscode ];
      buildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/code --add-flags "--no-sandbox"
      '';
    };
    # mutableExtensionsDir allows marketplace / manual installs to coexist alongside
    # Nix-managed extensions. Without this, HM would wipe any unlisted extension.
    mutableExtensionsDir = true;

    profiles.default = {
      # Share MCP servers from programs.mcp.servers with VS Code clients
      # (Continue, Claude Code extension, etc.). Written to VSCode's userMcp config.
      enableMcpIntegration = true;

      # Extensions available in pkgs.vscode-extensions (nixpkgs subset).
      # Extensions NOT in nixpkgs are managed by VS Code's built-in sync / marketplace.
      extensions = with pkgs.vscode-extensions; [
        bbenoist.nix
        dbaeumer.vscode-eslint
        eamodio.gitlens
        esbenp.prettier-vscode
        ms-python.python
        ms-python.vscode-pylance
        ms-python.debugpy
        ms-vscode.cpptools
        oderwat.indent-rainbow
        redhat.vscode-yaml
        rust-lang.rust-analyzer
        tamasfe.even-better-toml
        usernamehw.errorlens
      ];

    # Full extension inventory (for documentation / future declarative migration).
    # Extensions marked (*) are managed above via nixpkgs; the rest via VS Code sync.
    # To move more to Nix: use pkgs.vscode-utils.extensionsFromVscodeMarketplace with sha256.
    #
    # (*) bbenoist.nix
    # (*) dbaeumer.vscode-eslint
    # (*) eamodio.gitlens
    # (*) esbenp.prettier-vscode
    # (*) ms-python.python
    # (*) ms-python.vscode-pylance
    # (*) ms-python.debugpy
    # (*) ms-vscode.cpptools
    # (*) oderwat.indent-rainbow
    # (*) redhat.vscode-yaml
    # (*) rust-lang.rust-analyzer
    # (*) tamasfe.even-better-toml
    # (*) usernamehw.errorlens
    #     amazonwebservices.amazon-q-vscode
    #     anthropic.claude-code
    #     asvetliakov.vscode-neovim
    #     ccimage.jsonviewer
    #     christian-kohler.npm-intellisense
    #     continue.continue
    #     davidanson.vscode-markdownlint
    #     docker.docker
    #     donjayamanne.githistory
    #     editorconfig.editorconfig
    #     firefox-devtools.vscode-firefox-debug
    #     formulahendry.code-runner
    #     fuzionix.devtool-plus
    #     gbasood.byond-dm-language-support
    #     github.copilot-chat
    #     github.vscode-github-actions
    #     leizongmin.node-module-intellisense
    #     ms-azuretools.vscode-containers
    #     ms-dotnettools.csdevkit
    #     ms-dotnettools.csharp
    #     ms-dotnettools.vscode-dotnet-runtime
    #     ms-python.vscode-python-envs
    #     ms-toolsai.jupyter
    #     ms-toolsai.jupyter-keymap
    #     ms-toolsai.jupyter-renderers
    #     ms-toolsai.vscode-jupyter-cell-tags
    #     ms-toolsai.vscode-jupyter-slideshow
    #     ms-vscode-remote.remote-containers
    #     ms-vscode.cmake-tools
    #     ms-vscode.cpp-devtools
    #     ms-vscode.cpptools-extension-pack
    #     ms-vscode.cpptools-themes
    #     ms-vsliveshare.vsliveshare
    #     nickdemayo.vscode-json-editor
    #     ofhumanbondage.react-proptypes-intellisense
    #     onlyutkarsh.git-config-user-profiles
    #     platymuus.dm-langclient
    #     redhat.java
    #     ritwickdey.liveserver
    #     saoudrizwan.claude-dev
    #     sourcegraph.javascript-typescript
    #     tauri-apps.tauri-vscode
    #     twxs.cmake
    #     vscjava.vscode-gradle
    #     vscjava.vscode-java-debug
    #     vscjava.vscode-java-dependency
    #     vscjava.vscode-java-test
    #     vscjava.vscode-maven
    #     zainchen.json

      userSettings = {
      # ── Telemetry ──────────────────────────────────────────────────────────────
      "telemetry.telemetryLevel"      = "off";
      "redhat.telemetry.enabled"      = false;


      # ── Editor ─────────────────────────────────────────────────────────────────
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

      # Pin the integrated terminal shell to bashInteractive. The nixpkgs VSCode
      # wrapper resolves `bash` to the minimal (non-interactive) bash in its own
      # closure, which is built without programmable completion or prompt-string
      # decoding — so starship's \[...\] wrappers render literally and compgen is
      # missing. bashInteractive is what Yakuake/programs.bash use.
      "terminal.integrated.defaultProfile.linux" = "bash";
      "terminal.integrated.profiles.linux" = {
        bash = {
          path = "${pkgs.bashInteractive}/bin/bash";
        };
      };

      # ── Theme ──────────────────────────────────────────────────────────────────
      "workbench.colorTheme" = "Dark+";

      # ── Claude Code ────────────────────────────────────────────────────────────
      "claudeCode.preferredLocation" = "panel";

      # ── Copilot ────────────────────────────────────────────────────────────────
"github.copilot.nextEditSuggestions.enabled" = true;

      # ── Continue ───────────────────────────────────────────────────────────────
# yaml.schemas intentionally omitted: version-specific Continue paths become
      # stale on every extension update; Continue manages its own schema registration.

      # ── vscode-neovim ──────────────────────────────────────────────────────────
      # Point to the Nix-managed nvim binary (was: /home/linuxbrew/.linuxbrew/bin/nvim)
      "extensions.experimental.affinity"          = { "asvetliakov.vscode-neovim" = 1; };
      "vscode-neovim.neovimExecutablePaths.linux"  = "${pkgs.neovim}/bin/nvim";
      "vscode-neovim.neovimExecutablePaths.darwin" = "";
      "vscode-neovim.neovimExecutablePaths.win32"  = "";

      # ── Git Config User Profiles ────────────────────────────────────────────────
      # (extension: onlyutkarsh.git-config-user-profiles)
      "gitConfigUser.profiles" = [
        {
          label      = "Psuedononymous [VictorVow]";
          email      = "12621257+VictorVow@users.noreply.github.com";
          userName   = "VictorVow";
          selected   = true;
          id         = "f4feda82-9f84-40ed-ae25-45893e812650";
          signingKey = "GPGKEY1";
        }
        {
          label      = "Personal [USER2]";
          email      = "22418751+USER2@users.noreply.github.com";
          userName   = "USER2";
          selected   = false;
          id         = "80ec2d0d-bf53-4508-a832-380861ee3118";
          signingKey = "GPGKEY2";
        }
      ];
      "gitConfigUser.workspaceProfileSelections" = {
        "/home/boss/Documents/ESSENTIALS/installs" = "80ec2d0d-bf53-4508-a832-380861ee3118";
      };

      # ── Misc extension settings ─────────────────────────────────────────────────
      "dreammaker.autoUpdate"   = true;
      "dreammaker.tickOnCreate" = true;
      "docker.extension.enableComposeLanguageServer" = false;
      "java.autobuild.enabled"                       = false;
      "java.imports.gradle.wrapper.checksums" = [
        { sha256 = "f7566c1b7cd087d8395eb003f7c13d30ba2935f2071f08c6f275e79f63149d58"; allowed = true; }
      ];
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

  # ── MCP Servers — shared registry ─────────────────────────────────────────────
  # Outputs ~/.config/mcp/mcp.json, consumed by:
  #   - programs.claude-code (via enableMcpIntegration = true → ~/.claude/.mcp.json)
  #   - programs.codex       (via enableMcpIntegration = true → ~/.codex/.mcp.json)
  #   - programs.vscode.profiles.default (via enableMcpIntegration = true → VSCode userMcp)
  #
  # Secret env vars (LOGSEQ_API_TOKEN, GITHUB_TOKEN) are intentionally NOT placed in
  # env blocks here — the env block overrides inherited shell values, so an empty string
  # would shadow the real token set in home.sessionVariables. MCP server processes
  # inherit the full session environment automatically.

  programs.mcp = {
    enable = true;
    servers = {

      # LogSeq knowledge base — requires LogSeq running with HTTP API enabled (port 12315).
      # One-time setup: LogSeq → Settings → Features → HTTP APIs → enable → generate token
      # → set LOGSEQ_API_TOKEN in home.sessionVariables above → hms + restart shell.
      logseq = {
        command = "uv";
        args    = [ "run" "--with" "mcp-logseq" "mcp-logseq" ];
        env     = { LOGSEQ_API_URL = "http://localhost:12315"; };
      };

      # Local file system — exposes ~/Documents for navigation and file operations.
      filesystem = {
        command = "npx";
        args    = [ "-y" "@modelcontextprotocol/server-filesystem"
                    "/home/boss/Documents" ];
      };

      # GitHub API — PR/issue operations, release queries, cross-repo search.
      # Needs GITHUB_TOKEN (classic PAT, repo + read:org scopes) in sessionVariables.
      github = {
        command = "npx";
        args    = [ "-y" "@modelcontextprotocol/server-github" ];
      };

      # Context7 — resolves up-to-date library docs at query time (Rust/Python/TS/Java/etc.)
      # HTTP transport; no credentials required.
      context7 = {
        url = "https://mcp.context7.com/mcp";
      };

      # Sequential thinking — structured step-by-step reasoning for architecture/analysis tasks.
      sequential-thinking = {
        command = "npx";
        args    = [ "-y" "@modelcontextprotocol/server-sequential-thinking" ];
      };

      # NixOS/nixpkgs — real package names, options, and Home Manager config lookups.
      # No NixOS required; queries upstream APIs. Works on any system.
      nixos = {
        command = "uvx";
        args    = [ "mcp-nixos" ];
      };

      # YouTube transcripts — extract captions from any YouTube video.
      # No credentials required.
      youtube-transcript = {
        command = "npx";
        args    = [ "-y" "@fabriqa.ai/youtube-transcript-mcp@latest" ];
      };

    };
  };

  # ── Claude Code ────────────────────────────────────────────────────────────────
  # Home Manager claude-code.nix source: https://github.com/nix-community/home-manager/blob/master/modules/programs/claude-code.nix

  programs.claude-code = {
    enable               = true;
    package              = pkgs.claude-code;  # required when enableMcpIntegration = true
    enableMcpIntegration = true;              # merges programs.mcp.servers → ~/.claude/.mcp.json

    # ── Agents — creates ~/.claude/agents/<key>.md ────────────────────────────────

    agents = {

      "nix-helper" = ''
        ---
        name: nix-helper
        description: Assist with Home Manager and Nix flake configuration changes.
          Use when editing nix/modules/*.nix, flake.nix, or debugging eval errors.
        ---
        You are a Nix/Home Manager expert. When making changes:
        - Remember that the main Nix config is located at ~/Documents/ESSENTIALS/installs
        - Read existing module files before proposing edits
        - Prefer extending existing modules over creating new ones
        - Use lib helpers; avoid string-based workarounds
        - Always remind the user to run `hms` after any change
        - Know the module structure: programs.nix, packages.nix, shell.nix, distrobox.nix
      '';

      "container-helper" = ''
        ---
        name: container-helper
        description: Distrobox container assistant. Use when working with or troubleshooting
          the dev or media containers, exporting apps, or installing packages inside containers.
        ---
        This system uses two distrobox containers:
        - dev (ubuntu:24.04): build tools, C/C++, cmake, clang, Python, Node, npm, git
        - media (fedora:latest): ffmpeg, OBS, kdenlive, HandBrake, mpv, yt-dlp (RPMFusion codecs)

        Guidelines:
        - Prefer exporting desktop entries or binaries to the host over installing directly on the host
        - Use `dbe dev` or `dbe media` to enter containers
        - Media container exports GUI apps to the host desktop automatically
        - For GUI apps not in either container, suggest a new distrobox.nix entry
      '';

    };

    # ── Skills — creates ~/.claude/skills/<key>/SKILL.md ─────────────────────────
    # Can be run directly within a Claude window (similar to `/effort` in order to take an action)

    skills = {

      "nix-switch" = ''
        ---
        description: Run home-manager switch and show any new news items.
        ---
        1. If the user tells you to run `hms` then instead run `home-manager switch --flake ~/Documents/ESSENTIALS/installs/nix#boss` since you don't have access to `hms` from your Bash shell.
        2. If you see "warning: Git tree <filepath> has uncommitted changes" then just ignore that warning.
        3. If it failed, show the full error and suggest a fix.
        4. Don't run `home-manager news` unless it's part of the update.sh script. 
      '';

      "git-commit" = ''
        ---
        description: Make a git commit of the changes from this Claude session.
        ---
        - `git add` only the files touched by this session.
        - git commit messages should follow the Conventional Commit structure i.e.
        <type>[optional scope]: <description>

        [optional body]

        [optional footer]
          - Examples:
            - feat: allow provided config object to extend other configs
            - docs(lang): correct spelling of CHANGELOG
            - fix: minor typos in code

              see the issue for details on the typos fixed

              fixes issue #12
        - Aim to have a descriptive commit message body unless the change is trivial
          - Examples:
            - feat(api.ts): add OpenAI class with generateCommitMessage method

              This commit adds a new OpenAI class with a generateCommitMessage method that uses 
              the OpenAI API to generate a commit message based on an array of messages. The 
              method takes an array of ChatCompletionRequestMessage objects and returns a 
              Promise that resolves to a ChatCompletionResponseMessage object. The OpenAI 
              class is exported as a singleton instance named api.
            - fix(README): fixed two small typos
        - Do not `git push` unless it's necessary because a pull request, workflow action or 
          something else in our intended next steps needs the commit pushed first.
      '';

      "dbox-status" = ''
        ---
        description: Show status of distrobox containers and their key packages.
        ---
        1. Run `dbl` to list containers and their running state.
        2. For each container, state its purpose and key packages:
           - dev: build tools (gcc, clang, cmake, ninja, gdb, valgrind), Python, Node
           - media: ffmpeg, OBS, kdenlive, HandBrake, mpv, yt-dlp
        3. Suggest next steps based on current context.
      '';

      "yt-summary" = ''
        ---
        description: Summarise a YouTube video using yt-dlp subtitles.
        allowed_tools:
          - Bash
          - Write
          - Read
          - Edit
        user_invocable: true
        ---
        The user will provide a YouTube URL and optionally an output file path.

        ## Steps

        1. **Get the video title:**
           ```
           yt-dlp --print title "<URL>"
           ```

        2. **Download subtitles** — prefer manual subs over auto-generated:
           ```
           yt-dlp --write-sub --sub-lang "en.*" --skip-download --sub-format vtt -o "/tmp/yt-summary" "<URL>" 2>&1
           ```
           Check if any `.vtt` files were written. If none were found (no manual subs), fall back to auto-generated:
           ```
           yt-dlp --write-auto-sub --sub-lang "en.*" --skip-download --sub-format vtt -o "/tmp/yt-summary" "<URL>" 2>&1
           ```

        3. **Extract clean text** from the VTT file (pick the `en-orig` variant if present, otherwise `en`):
           ```
           cat /tmp/yt-summary*.vtt | grep -v '^WEBVTT' | grep -v '^Kind:' | grep -v '^Language:' | grep -v '^$' | grep -v '^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]' | grep -v '^[0-9]*$' | grep -v '^\s*$' | sed 's/<[^>]*>//g' | awk '!seen[$0]++'
           ```

        4. **Summarise** the transcript into a Markdown document with:
           - H1: the video title
           - **Source:** link to the video
           - **Summary** section: a short (2–4 sentence) overview
           - Subsections (H3) for each major topic discussed, with a paragraph each
           - A "Misc" or "Other Topics" subsection for brief tangents

        5. **Write** the summary to the path the user specified. If no path was given, ask where to save it.

        6. **Clean up** the temp files:
           ```
           rm -f /tmp/yt-summary*.vtt
           ```
      '';

    };

  };

  # ── Codex ──────────────────────────────────────────────────────────────────────

  programs.codex = {
    enable               = true;
    package              = pkgs.codex;
    enableMcpIntegration = true;  # merges programs.mcp.servers → ~/.codex/.mcp.json
  };

  # ── Gemini CLI ─────────────────────────────────────────────────────────────────
  # enableMcpIntegration merges programs.mcp.servers → settings.mcpServers, which
  # causes HM to write ~/.gemini/settings.json as a read-only Nix store symlink.
  # OAuth tokens live in ~/.gemini/oauth_creds.json (unmanaged), so the symlink
  # no longer blocks login (home-manager#8654). The auth selection is preserved
  # here so gemini-cli doesn't re-prompt on launch.

  programs.gemini-cli = {
    enable  = true;
    package = pkgs.gemini-cli;
    enableMcpIntegration = true;
    settings.security.auth.selectedType = "oauth-personal";
  };

  # ── Claude Code settings (writable copy) ────────────────────────────────────
  # Replaces programs.claude-code.settings to avoid a read-only Nix-store
  # symlink. install -m 644 copies the file so Claude Code can overwrite it.
  home.activation.claudeCodeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    dest="$HOME/.claude/settings.json"
    # Replace any existing Nix-store symlink with a writable copy
    if [ -L "$dest" ]; then
      $DRY_RUN_CMD rm "$dest"
    fi
    $DRY_RUN_CMD install -m 644 ${claudeCodeSettings} "$dest"
  '';

  # ── SSH ──────────────────────────────────────────────────────────────────────

  programs.ssh = {
    enable = true;
    # Suppress deprecation warning — defaults will be removed in a future HM release;
    # all desired settings are explicitly set in matchBlocks below.
    enableDefaultConfig = false;
    matchBlocks."*" = {
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
