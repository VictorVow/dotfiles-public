{ config, pkgs, lib, pkgs-unstable, ... }:

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
    # ── Live suggestions
    "browser.urlbar.quicksuggest.scenario"    = "history";  # disable Mozilla's cloud-based Firefox Suggest service; only suggest from local history
    "browser.urlbar.suggest.searches"           = false;  # prevent URL bar from querying the default search engine for live suggestions as you type
    "browser.search.suggest.enabled"           = false;  # global switch disabling search engine live suggestions in all contexts (URL bar, search bar, new tab)
    # ── Media ─────────────────────────────────────────────────────────────
    "media.autoplay.default" = 5;  # block all autoplay (audio and video)
  };

  # Search engines shared by minimal profiles (extracted from VERTEX)
  ffIcons = ../assets/firefox-search-icons;

  ffSearch = {
    default = "Brave";
    force = true;
    order = [
      "Brave"
      "google"
      "ddg"
      "wikipedia"
      "Google (Verbatim, De-personalized)"
      "Yandex"
      "Thesaurus.com"
      "Firefox Add-ons"
      "Mycroft Project"
      "F-Droid"
      "Google Play"
      "NixOS packages"
      "NUR"
      "NUR (code)"
      "flathub.org"
      "GitHub"
      "AlternativeTo"
      "brew.sh"
      "Ubuntu Packages"
      "NPM"
      "Arch Packages"
      "pypi.org"
      "Reddit - Google"
      "reddit"
      "Hacker News Search"
      "Steam"
      "Lutris"
      "ProtonDB"
      "Scryfall"
      "IGDB game search"
      "vndb.org"
      "Goodreads"
      "youtube"
      "Rumble"
      "Twitch"
      "AniList Anime"
      "TMDB"
      "Trakt"
      "Wikitubia (en)"
      "Last.fm"
      "Last.fm - Tracks"
      "Amazon UK"
      "Temu.com"
      "Aliexpress"
      "Wikispooks (en)"
      "Conservapedia (en)"
      "Grokipedia"
    ];
    engines = {
      # ── Built-in engine overrides ────────────────────────────────────────
      ddg.metaData.alias = "@duck";
      bing.metaData.hidden = true;
      ebay.metaData.hidden = true;
      ecosia.metaData.hidden = true;
      qwant.metaData.hidden = true;
      amazondotcom-us.metaData.hidden = true;

      # ── Custom engines ─────────────────────────────────────────────────

      # ── Search ─────────────────────────────────────────────────
      "Brave" = {
        urls = [{ template = "https://search.brave.com/search?q={searchTerms}"; }];
        icon = "${ffIcons}/brave.ico";
        definedAliases = [ "@brave" ];
      };
      "Google (Verbatim, De-personalized)" = {
        urls = [{ template = "https://www.google.com/search?q={searchTerms}&tbs=li:1&pws=0"; }];
        icon = "${ffIcons}/google.ico";
      };
      "Yandex" = {
        urls = [{ template = "https://yandex.com/search/?text={searchTerms}&from=os&clid=1836587"; }];
        icon = "${ffIcons}/yandex.ico";
      };
      # ── Utilities ─────────────────────────────────────────────────
      "Thesaurus.com" = {
        urls = [{ template = "https://www.thesaurus.com/browse/{searchTerms}"; }];
        icon = "${ffIcons}/thesaurus.png";
        definedAliases = [ "@thesaurus" ];
      };
      # ── Software ─────────────────────────────────────────────────
      "Firefox Add-ons" = {
        urls = [{ template = "https://addons.mozilla.org/en-GB/firefox/search/?q={searchTerms}"; }];
        icon = "${ffIcons}/firefox-addons.ico";
        definedAliases = [ "@addons" ];
      };
      "Mycroft Project" = {
        urls = [{ template = "https://mycroftproject.com/search-engines.html?name={searchTerms}"; }];
        icon = "${ffIcons}/mycroft.ico";
        definedAliases = [ "@mycroft" ];
      };
      "F-Droid" = {
        urls = [{ template = "https://search.f-droid.org/?q={searchTerms}"; }];
        icon = "${ffIcons}/f-droid.ico";
        definedAliases = [ "@fdroid" ];
      };
      "Google Play" = {
        urls = [{ template = "https://play.google.com/store/search?q={searchTerms}&utm_source=opensearch"; }];
        icon = "${ffIcons}/google-play.ico";
        definedAliases = [ "@googleplay" ];
      };
      "NixOS packages" = {
        urls = [{ template = "https://search.nixos.org/packages?query={searchTerms}"; }];
        icon = "${ffIcons}/nixos-packages.png";
        definedAliases = [ "@nix" ];
      };
      "NUR" = {
        urls = [{ template = "https://nur.nix-community.org/?q={searchTerms}"; }];
        icon = "${ffIcons}/nur.png";
        definedAliases = [ "@nur" ];
      };
      "NUR (code)" = {
        urls = [{ template = "https://github.com/search?q=repo%3Anix-community%2Fnur-combined+{searchTerms}&type=code"; }];
        icon = "${ffIcons}/github.ico";
        definedAliases = [ "@nurcode" ];
      };
      "flathub.org" = {
        urls = [{ template = "https://flathub.org/apps/search/{searchTerms}"; }];
        icon = "${ffIcons}/flathub.ico";
        definedAliases = [ "@flat" ];
      };
      "GitHub" = {
        urls = [{ template = "https://github.com/search?q={searchTerms}&ref=opensearch"; }];
        icon = "${ffIcons}/github.ico";
        definedAliases = [ "@github" ];
      };
      "AlternativeTo" = {
        urls = [{ template = "https://alternativeto.net/browse/search/?q={searchTerms}"; }];
        icon = "${ffIcons}/alternativeto.ico";
        definedAliases = [ "@alternative" ];
      };
      "brew.sh" = {
        urls = [{ template = "https://formulae.brew.sh/?search={searchTerms}"; }];
        icon = "${ffIcons}/brew.ico";
        definedAliases = [ "@brew" ];
      };
      "Ubuntu Packages" = {
        urls = [{ template = "http://packages.ubuntu.com/search?suite=default&section=all&arch=any&searchon=names&keywords={searchTerms}"; }];
        icon = "${ffIcons}/ubuntu.png";
        definedAliases = [ "@ubuntu" ];
      };
      "NPM" = {
        urls = [{ template = "https://npmjs.org/search?q={searchTerms}"; }];
        icon = "${ffIcons}/npm.png";
        definedAliases = [ "@npm" ];
      };
      "Arch Packages" = {
        urls = [{ template = "https://archlinux.org/packages/?q={searchTerms}"; }];
        icon = "${ffIcons}/archlinux.ico";
        definedAliases = [ "@aur" ];
      };
      "pypi.org" = {
        urls = [{ template = "https://pypi.org/search/"; params = [{ name = "q"; value = "{searchTerms}"; }]; }];
        icon = "${ffIcons}/pypi.ico";
        definedAliases = [ "@python" ];
      };
      "NuGet" = {
        urls = [{ template = "https://www.nuget.org/packages?q={searchTerms}"; }];
        icon = "${ffIcons}/nuget.ico";
        definedAliases = [ "@dotnet" "@nuget" "@csharp" ];
      };
      # ── Social Media ─────────────────────────────────────────────────
      "Reddit - Google" = {
        urls = [{ template = "http://www.google.com/search?q={searchTerms}+site%3Areddit.com"; }];
        icon = "${ffIcons}/reddit.ico";
      };
      reddit = {
        name = "Reddit";
        urls = [{ template = "https://www.reddit.com/search/?q={searchTerms}"; }];
        icon = "${ffIcons}/reddit.ico";
        definedAliases = [ "@reddit" ];
      };
      "Hacker News Search" = {
        urls = [{ template = "https://hn.algolia.com/?query={searchTerms}&sort=byPopularity&prefix&page=0&dateRange=all&type=story"; }];
        icon = "${ffIcons}/hackernews.ico";
        definedAliases = [ "@hacker" ];
      };
      # ── Gaming ─────────────────────────────────────────────────
      "Steam" = {
        urls = [{ template = "https://store.steampowered.com/search/?term={searchTerms}"; }];
        icon = "${ffIcons}/steam.ico";
        definedAliases = [ "@steam" ];
      };
      "Lutris" = {
        urls = [{ template = "https://lutris.net/games?q={searchTerms}"; }];
        icon = "${ffIcons}/lutris.ico";
        definedAliases = [ "@lutris" ];
      };
      "ProtonDB" = {
        urls = [{ template = "https://www.protondb.com/search?q={searchTerms}"; }];
        icon = "${ffIcons}/protondb.ico";
        definedAliases = [ "@protondb" ];
      };
      "Scryfall" = {
        urls = [{ template = "https://scryfall.com/search?q={searchTerms}"; }];
        icon = "${ffIcons}/scryfall.ico";
        definedAliases = [ "@scry" ];
      };
      "IGDB game search" = {
        urls = [{ template = "http://igdb.com/search?utf8=✓&q={searchTerms}&commit=search"; }];
        icon = "${ffIcons}/igdb.png";
      };
      "vndb.org" = {
        urls = [{ template = "https://vndb.org/v"; params = [{ name = "sq"; value = "{searchTerms}"; }]; }];
        icon = "${ffIcons}/vndb.ico";
        definedAliases = [ "@visualnovel" ];
      };
      # ── Reading ─────────────────────────────────────────────────
      "Goodreads" = {
        urls = [{ template = "http://www.goodreads.com/search?q={searchTerms}"; }];
        icon = "${ffIcons}/goodreads.ico";
        definedAliases = [ "@books" ];
      };
      # ── Video ─────────────────────────────────────────────────
      youtube = {
        name = "YouTube";
        urls = [{ template = "https://www.youtube.com/results?search_query={searchTerms}&search=Search"; }];
        icon = "${ffIcons}/youtube.ico";
        definedAliases = [ "@yt" ];
      };
      "Rumble" = {
        urls = [{ template = "https://rumble.com/search/video?q={searchTerms}"; }];
        icon = "${ffIcons}/rumble.ico";
        definedAliases = [ "@rumble" ];
      };
      "Twitch" = {
        urls = [{ template = "https://www.twitch.tv/search?term={searchTerms}"; }];
        icon = "${ffIcons}/twitch.ico";
        definedAliases = [ "@twitch" ];
      };
      "AniList Anime" = {
        urls = [{ template = "https://anilist.co/search/anime?search={searchTerms}"; }];
        icon = "${ffIcons}/anilist.ico";
        definedAliases = [ "@anime" ];
      };
      "TMDB" = {
        urls = [{ template = "https://www.themoviedb.org/search?query={searchTerms}"; }];
        icon = "${ffIcons}/tmdb.ico";
        definedAliases = [ "@tmdb" ];
      };
      "Trakt" = {
        urls = [{ template = "http://trakt.tv/search?utf8=✓&query={searchTerms}"; }];
        icon = "${ffIcons}/trakt.ico";
        definedAliases = [ "@trakt" ];
      };
      "Wikitubia (en)" = {
        urls = [{ template = "https://youtube.fandom.com/wiki/Special:Search?search={searchTerms}&opensearch=1"; }];
        icon = "${ffIcons}/wikitubia.png";
      };
      # ── Audio ─────────────────────────────────────────────────
      "Last.fm" = {
        urls = [{ template = "http://www.last.fm/search?m=all&q={searchTerms}"; }];
        icon = "${ffIcons}/lastfm.ico";
        definedAliases = [ "@last" ];
      };
      "Last.fm - Tracks" = {
        urls = [{ template = "http://www.last.fm/search?q={searchTerms}&type=track"; }];
        icon = "${ffIcons}/lastfm.ico";
        definedAliases = [ "@music" ];
      };
      # ── Shopping ─────────────────────────────────────────────────
      "Amazon UK" = {
        urls = [{ template = "https://www.amazon.co.uk/s?k={searchTerms}"; }];
        icon = "${ffIcons}/amazon-uk.ico";
        definedAliases = [ "@amazon" ];
      };
      "Temu.com" = {
        urls = [{ template = "https://www.temu.com/search_result.html?search_key={searchTerms}&search_method=user"; }];
        icon = "${ffIcons}/temu.png";
        definedAliases = [ "@temu" ];
      };
      "Aliexpress" = {
        urls = [{ template = "https://www.aliexpress.com/wholesale?catId=0&initiative_id=SB_20190730094114&SearchText={searchTerms}&switch_new_app=n"; }];
        icon = "${ffIcons}/aliexpress.ico";
        definedAliases = [ "@ali" ];
      };
      # ── Political ─────────────────────────────────────────────────
      "Wikispooks (en)" = {
        urls = [{ template = "https://wikispooks.com/w/index.php?title=Special:Search&search={searchTerms}"; }];
        icon = "${ffIcons}/wikispooks.ico";
      };
      "Conservapedia (en)" = {
        urls = [{ template = "https://conservapedia.com/index.php?title=Special:Search&search={searchTerms}"; }];
        icon = "${ffIcons}/conservapedia.png";
        definedAliases = [ "@conservapedia" ];
      };
      "Grokipedia" = {
        urls = [{ template = "https://grokipedia.com/search?q={searchTerms}"; }];
        icon = "${ffIcons}/grokipedia.ico";
        definedAliases = [ "@grok" ];
      };
    };
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
      # Default identity (1 = VictorVow); use `git su [1|2|3]` to switch per-repo
      # Identity 2 (USER2):      22418751+USER2@users.noreply.github.com,      key GPGKEY2
      # Identity 3 (USER3): 11584262+USER3@users.noreply.github.com, key GPGKEY3
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
      # Commit-identity-only fallback for non-Bash contexts (VS Code, GUIs,
      # scripts, subshells). Bash overrides `git su` with a function in
      # shell.nix that also realigns push auth (GITHUB_TOKEN + gh active
      # account). See docs/system/git-identity-management.md.
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
          set3 = "git config user.name 'USER3'"
            + " && git config user.email '11584262+USER3@users.noreply.github.com'"
            + " && git config user.signingkey 'GPGKEY3'"
            + " && echo 'switched -> USER3 (identity 3)'";
        in
          "!f() { case \"$1\" in"
          + " 1) ${set1};;"
          + " 2) ${set2};;"
          + " 3) ${set3};;"
          + " \"\") echo \"current: $(git config user.name) <$(git config user.email)>\";;"
          + " *) echo 'usage: git su [1|2|3]';;"
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
    nativeMessagingHosts = [ pkgs.kdePackages.plasma-browser-integration ];

    # Cookie exceptions — populated from xsy8besa.PRIME permissions.sqlite.
    # Sites listed in Allow keep their cookies even with sanitizeOnShutdown.
    #
    # These sites can track whatever I do on them and that it's me the same 
    # user visiting each time despite VPN pseudononymisation. Additionally 
    # local attacks (evil maid) can see my account info / steal cookies.
    policies.Cookies.Allow = [
      "http://localhost:8080"
      "http://localhost:8384"
      "http://localhost:8193"
      "https://.claude.com"
      "https://.geforcenow.com"
      "https://accounts.google.com"

      # AWS
      "https://.amazon.com"
      "https://.aws.com"
      "https://.awspartner.com"
      "https://.skillbuilder.aws"
      "https://.signin.aws"
      "https://.steampowered.com"    # "https://.steampowered.com" didn't work
      "https://13-ttrss.example.com"  # "https://.example.com" didn't work
      "https://.ts.net"   # Tailscale
      "https://9433uf4rgkf7.shares.zrok.io/"    # Calibre # "https://.zrok.io" didn't work
      "https://account.booking.com"
      "https://account.nuffieldhealth.com"
      "https://accounts.firefox.com"
      "https://accounts.spotify.com"
      "https://aiostreams.elfhosted.com"
      "https://anilist.co"
      "https://app.addy.io"
      "https://app.element.io"
      "https://apps.axahealth.co.uk"
      "https://auth.mozilla.auth0.com"
      "https://auth.openai.com" 
      "https://auth.scribd.com" # uses email 2FA
      "https://auth.rumble.com"
      "https://backloggd.com"
      "https://bank.barclays.co.uk"
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
      "https://login.coinbase.com"
      "https://login.live.com"
      "https://login.mailbox.org"
      "https://login.nvgs.nvidia.com"
      "https://login.tailscale.com"
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
      "https://roadmap.sh"
      "https://slack.com"
      "https://sso.crunchyroll.com"
      "https://steamcommunity.com"
      "https://steamdb.info"
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
    };

    profiles.minimal-persistent = {
      id = 3;
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
    };

    profiles.dev-edition-default = {
      id = 4;

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

  # Global prettier defaults. Prettier walks up from the file being formatted, so
  # anything under ~/ without a closer .prettierrc inherits this. MDX files get a
  # very large printWidth so JSX inside MDX doesn't get reflowed onto multiple
  # lines on save.
  home.file.".prettierrc.json".text = builtins.toJSON {
    overrides = [
      {
        files = "*.mdx";
        options = {
          printWidth = 9999;
          proseWrap  = "preserve";
        };
      }
    ];
  };

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

      keybindings = [
        # Ctrl+; → Tasks: Run Task (open the task picker)
        { key = "ctrl+;"; command = "workbench.action.tasks.runTask"; }
      ];

      userSettings = {
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
      "workbench.colorTheme" = "Default Dark Modern";

      # ── Claude Code ────────────────────────────────────────────────────────────
      "claudeCode.preferredLocation" = "panel";

      # ── Continue ───────────────────────────────────────────────────────────────
      # yaml.schemas intentionally omitted: version-specific Continue paths become
      # stale on every extension update; Continue manages its own schema registration.

      # ── vscode-neovim ──────────────────────────────────────────────────────────
      "extensions.experimental.affinity" = { "asvetliakov.vscode-neovim" = 1; };

      # ── Misc extension settings ─────────────────────────────────────────────────
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
    };
  };

  # ── Zed Editor settings ────────────────────────────────────────────────────────
  programs.zed-editor = {
    enable = true;
    # enableMcpIntegration = true;
    # extensions = [ "swift" "nix" "xy-zed" ];
    mutableUserKeymaps = false;
    mutableUserSettings = false;
    mutableUserTasks = false;
    # userKeymapss = 
    #   [
    #     {
    #       context = "Workspace";
    #       bindings = {
    #         ctrl-shift-t = "workspace::NewTerminal";
    #       };
    #     };
    #   ];

    # userSettings = 
    #   {
    #     features = {
    #       copilot = false;
    #     };
    #     telemetry = {
    #       metrics = false;
    #     };
    #     vim_mode = false;
    #     ui_font_size = 16;
    #     buffer_font_size = 16;
    #   };

  };


  # ── VSCodium ──────────────────────────────────────────────────────────────────
  # Binary via pkgs.vscodium (see vscodiumPkg let-binding at top of file).
  # programs.vscode only manages one editor, so settings live in xdg.configFile
  # and extensions are declared via pkgs.vscode-with-extensions in vscodiumPkg.

  # lowPrio: VSCodium and VS Code share locale file paths under lib/vscode/locales/.
  # Defer to VS Code on collisions so home.packages buildEnv resolves cleanly.
  home.packages = [ (lib.lowPrio vscodiumPkg) ];

  xdg.configFile."VSCodium/User/settings.json" = {
    force = true;
    source = jsonFormat.generate "vscodium-settings" {
      "diffEditor.ignoreTrimWhitespace" = false;
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
      # any child process. Without scrubbing, marktext.appimage's Electron binary
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
  };

  xdg.configFile."VSCodium/User/keybindings.json" = {
    force = true;
    source = jsonFormat.generate "vscodium-keybindings" [
      # Ctrl+; → Tasks: Run Task (open the task picker)
      { key = "ctrl+;"; command = "workbench.action.tasks.runTask"; }
    ];
  };

  home.file.".local/bin/marktext-wrap" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Launch marktext.appimage with a clean env so it works when spawned from
      # a VSCode/VSCodium extension host (which sets ELECTRON_RUN_AS_NODE=1).
      exec setsid env -u ELECTRON_RUN_AS_NODE -u NODE_OPTIONS DESKTOPINTEGRATION=1 \
        "${config.home.homeDirectory}/AppImages/marktext.appimage" --no-sandbox "$@"
    '';
  };

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
    enable  = true;
    package = pkgs.llm-agents.claude-code;
    # enableMcpIntegration — not available until HM 26.05

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

  };

  # ── Claude Code skills (home.file for correct subdirectory structure) ────────
  # programs.claude-code.skills (current HM rev) generates flat .claude/skills/<name>.md
  # but Claude Code 2.x requires .claude/skills/<name>/SKILL.md — use home.file directly.

  home.file.".claude/skills/nix-switch/SKILL.md".text = ''
    ---
    description: Run home-manager switch and show any new news items.
    ---
    1. If the user tells you to run `hms` then instead run `home-manager switch --flake ~/Documents/ESSENTIALS/installs/nix#boss` since you don't have access to `hms` from your Bash shell.
    2. If you see "warning: Git tree <filepath> has uncommitted changes" then just ignore that warning.
    3. If it failed, show the full error and suggest a fix.
    4. Don't run `home-manager news` unless it's part of the update.sh script.
  '';

  home.file.".claude/skills/git-commit/SKILL.md".text = ''
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

  home.file.".claude/skills/direnv-ignored/SKILL.md".text = ''
    ---
    description: Setup nix-direnv in this repo without having to commit it.
    ---
    1. Create `.envrc` in the top-level of repo with the content `use flake "path:$PWD/.nix"`.
    2. Append to the repo `.git/info/exclude` this content: `.nix/`.
    3. Create `.nix/flake.nix` with the packages needed in this project environment.
    4. Execute `direnv allow` in order to activate nix-direnv and setup the project environment.
  '';

  home.file.".claude/skills/dbox-status/SKILL.md".text = ''
    ---
    description: Show status of distrobox containers and their key packages.
    ---
    1. Run `dbl` to list containers and their running state.
    2. For each container, state its purpose and key packages:
       - dev: build tools (gcc, clang, cmake, ninja, gdb, valgrind), Python, Node
       - media: ffmpeg, OBS, kdenlive, HandBrake, mpv, yt-dlp
    3. Suggest next steps based on current context.
  '';

  home.file.".claude/skills/wl-copy/SKILL.md".text = ''
    ---
    description: Copy text from Claude Code's messages to the clipboard directly to eliminate formatting issues.
    ---
    1. A user selecting text to copy and paste from Claude Code's messages has indenting and new line issues.
    2. Use `wl-copy` to copy your last message, it should look something like this:
      - wl-copy << 'EOF'
        Here's a bunch of text...
        EOF
        echo "Copied to clipboard"
    3. Make sure to eliminate any formatting issues before copying text.
  '';

  home.file.".claude/skills/yt-summary/SKILL.md".text = ''
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
       cat /tmp/yt-summary*.vtt | grep -v '^WEBVTT' | grep -v '^Kind:' | grep -v '^Language:' | grep -v '^$' | grep -v '^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]' | grep -v '^[0-9]*$' | grep -v '^\s*\$' | sed 's/<[^>]*>//g' | awk '!seen[$0]++'
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

  # ── Codex ──────────────────────────────────────────────────────────────────────

  programs.codex = {
    enable  = true;
    package = pkgs.llm-agents.codex;
    # enableMcpIntegration — not available until HM 26.05
  };

  # ── Gemini CLI ─────────────────────────────────────────────────────────────────
  # enableMcpIntegration merges programs.mcp.servers → settings.mcpServers, which
  # causes HM to write ~/.gemini/settings.json as a read-only Nix store symlink.
  # OAuth tokens live in ~/.gemini/oauth_creds.json (unmanaged), so the symlink
  # no longer blocks login (home-manager#8654). The auth selection is preserved
  # here so gemini-cli doesn't re-prompt on launch.

  programs.gemini-cli = {
    enable   = true;
    package  = pkgs.llm-agents.gemini-cli;
    # enableMcpIntegration — not available until HM 26.05
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
