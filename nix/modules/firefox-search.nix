# Firefox search engines shared by the minimal profiles (extracted from VERTEX).
# Plain attrset, not an HM module — imported by firefox.nix as `ffSearch`.
let
  ffIcons = ../assets/firefox-search-icons;
in
{
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
    "Portable Linux Apps"
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
    "OpenCritic"
    "vndb.org"
    "Goodreads"
    "youtube"
    "Rumble"
    "Twitch"
    "AniList Anime"
    "TMDB"
    "Rotten Tomatoes"
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
    startpage.metaData.hidden = true;
    amazondotcom-us.metaData.hidden = true;

    # ── Custom engines ─────────────────────────────────────────────────

    # ── Search ─────────────────────────────────────────────────
    "Brave" = {
      urls = [ { template = "https://search.brave.com/search?q={searchTerms}"; } ];
      icon = "${ffIcons}/brave.ico";
      definedAliases = [ "@brave" ];
    };
    "Google (Verbatim, De-personalized)" = {
      urls = [ { template = "https://www.google.com/search?q={searchTerms}&tbs=li:1&pws=0"; } ];
      icon = "${ffIcons}/google.ico";
      definedAliases = [ "@google" ];
    };
    "Yandex" = {
      urls = [ { template = "https://yandex.com/search/?text={searchTerms}&from=os&clid=1836587"; } ];
      icon = "${ffIcons}/yandex.ico";
      definedAliases = [ "@yandex" ];
    };
    # ── Utilities ─────────────────────────────────────────────────
    "Thesaurus.com" = {
      urls = [ { template = "https://www.thesaurus.com/browse/{searchTerms}"; } ];
      icon = "${ffIcons}/thesaurus.png";
      definedAliases = [ "@thesaurus" ];
    };
    # ── Software ─────────────────────────────────────────────────
    "Firefox Add-ons" = {
      urls = [ { template = "https://addons.mozilla.org/en-GB/firefox/search/?q={searchTerms}"; } ];
      icon = "${ffIcons}/firefox-addons.ico";
      definedAliases = [
        "@addons"
        "@amo"
        "@firefox"
      ];
    };
    "Mycroft Project" = {
      urls = [ { template = "https://mycroftproject.com/search-engines.html?name={searchTerms}"; } ];
      icon = "${ffIcons}/mycroft.ico";
      definedAliases = [ "@mycroft" ];
    };
    "F-Droid" = {
      urls = [ { template = "https://search.f-droid.org/?q={searchTerms}"; } ];
      icon = "${ffIcons}/f-droid.ico";
      definedAliases = [ "@fdroid" ];
    };
    "Google Play" = {
      urls = [
        { template = "https://play.google.com/store/search?q={searchTerms}&utm_source=opensearch"; }
      ];
      icon = "${ffIcons}/google-play.ico";
      definedAliases = [ "@googleplay" ];
    };
    "NixOS packages" = {
      urls = [ { template = "https://search.nixos.org/packages?query={searchTerms}"; } ];
      icon = "${ffIcons}/nixos-packages.png";
      definedAliases = [ "@nix" ];
    };
    "NUR" = {
      urls = [ { template = "https://nur.nix-community.org/?q={searchTerms}"; } ];
      icon = "${ffIcons}/nur.png";
      definedAliases = [ "@nur" ];
    };
    "NUR (code)" = {
      urls = [
        {
          template = "https://github.com/search?q=repo%3Anix-community%2Fnur-combined+{searchTerms}&type=code";
        }
      ];
      icon = "${ffIcons}/github.ico";
      definedAliases = [ "@nurcode" ];
    };
    "flathub.org" = {
      urls = [ { template = "https://flathub.org/apps/search/{searchTerms}"; } ];
      icon = "${ffIcons}/flathub.ico";
      definedAliases = [ "@flat" ];
    };
    # portable-linux-apps.github.io now supports a `?s=` query param
    # (search is still client-side, but the URL triggers it on load).
    "Portable Linux Apps" = {
      urls = [
        {
          template = "https://portable-linux-apps.github.io/en/index.html?s={searchTerms}";
        }
      ];
      icon = "${ffIcons}/github.ico";
      definedAliases = [
        "@appimage"
        "@appman"
      ];
    };
    "GitHub" = {
      urls = [ { template = "https://github.com/search?q={searchTerms}&ref=opensearch"; } ];
      icon = "${ffIcons}/github.ico";
      definedAliases = [ "@github" ];
    };
    "AlternativeTo" = {
      urls = [ { template = "https://alternativeto.net/browse/search/?q={searchTerms}"; } ];
      icon = "${ffIcons}/alternativeto.ico";
      definedAliases = [ "@alternative" ];
    };
    "brew.sh" = {
      urls = [ { template = "https://formulae.brew.sh/?search={searchTerms}"; } ];
      icon = "${ffIcons}/brew.ico";
      definedAliases = [ "@brew" ];
    };
    "Ubuntu Packages" = {
      urls = [
        {
          template = "http://packages.ubuntu.com/search?suite=default&section=all&arch=any&searchon=names&keywords={searchTerms}";
        }
      ];
      icon = "${ffIcons}/ubuntu.png";
      definedAliases = [ "@ubuntu" ];
    };
    "NPM" = {
      urls = [ { template = "https://npmjs.org/search?q={searchTerms}"; } ];
      icon = "${ffIcons}/npm.png";
      definedAliases = [ "@npm" ];
    };
    "Arch Packages" = {
      urls = [ { template = "https://archlinux.org/packages/?q={searchTerms}"; } ];
      icon = "${ffIcons}/archlinux.ico";
      definedAliases = [ "@aur" ];
    };
    "pypi.org" = {
      urls = [
        {
          template = "https://pypi.org/search/";
          params = [
            {
              name = "q";
              value = "{searchTerms}";
            }
          ];
        }
      ];
      icon = "${ffIcons}/pypi.ico";
      definedAliases = [ "@python" ];
    };
    "NuGet" = {
      urls = [ { template = "https://www.nuget.org/packages?q={searchTerms}"; } ];
      icon = "${ffIcons}/nuget.ico";
      definedAliases = [
        "@dotnet"
        "@nuget"
        "@csharp"
      ];
    };
    # ── Social Media ─────────────────────────────────────────────────
    "Reddit - Google" = {
      urls = [ { template = "http://www.google.com/search?q={searchTerms}+site%3Areddit.com"; } ];
      icon = "${ffIcons}/reddit.ico";
    };
    reddit = {
      name = "Reddit";
      urls = [ { template = "https://www.reddit.com/search/?q={searchTerms}"; } ];
      icon = "${ffIcons}/reddit.ico";
      definedAliases = [ "@reddit" ];
    };
    "Hacker News Search" = {
      urls = [
        {
          template = "https://hn.algolia.com/?query={searchTerms}&sort=byPopularity&prefix&page=0&dateRange=all&type=story";
        }
      ];
      icon = "${ffIcons}/hackernews.ico";
      definedAliases = [ "@hacker" ];
    };
    # ── Gaming ─────────────────────────────────────────────────
    "Steam" = {
      urls = [ { template = "https://store.steampowered.com/search/?term={searchTerms}"; } ];
      icon = "${ffIcons}/steam.ico";
      definedAliases = [ "@steam" ];
    };
    "Lutris" = {
      urls = [ { template = "https://lutris.net/games?q={searchTerms}"; } ];
      icon = "${ffIcons}/lutris.ico";
      definedAliases = [ "@lutris" ];
    };
    "ProtonDB" = {
      urls = [ { template = "https://www.protondb.com/search?q={searchTerms}"; } ];
      icon = "${ffIcons}/protondb.ico";
      definedAliases = [ "@protondb" ];
    };
    "Scryfall" = {
      urls = [ { template = "https://scryfall.com/search?q={searchTerms}"; } ];
      icon = "${ffIcons}/scryfall.ico";
      definedAliases = [ "@scry" ];
    };
    "IGDB game search" = {
      urls = [ { template = "http://igdb.com/search?utf8=✓&q={searchTerms}&commit=search"; } ];
      icon = "${ffIcons}/igdb.png";
      definedAliases = [ "@igdb" ];
    };
    # Open-source algorithm
    "OpenCritic" = {
      urls = [ { template = "https://opencritic.com/search?q={searchTerms}"; } ];
      icon = "${ffIcons}/opencritic.png";
      definedAliases = [ "@opencritic" ];
    };
    "vndb.org" = {
      urls = [
        {
          template = "https://vndb.org/v";
          params = [
            {
              name = "sq";
              value = "{searchTerms}";
            }
          ];
        }
      ];
      icon = "${ffIcons}/vndb.ico";
      definedAliases = [ "@visualnovel" ];
    };
    # ── Reading ─────────────────────────────────────────────────
    "Goodreads" = {
      urls = [ { template = "http://www.goodreads.com/search?q={searchTerms}"; } ];
      icon = "${ffIcons}/goodreads.ico";
      definedAliases = [ "@books" ];
    };
    # ── Video ─────────────────────────────────────────────────
    youtube = {
      name = "YouTube";
      urls = [
        { template = "https://www.youtube.com/results?search_query={searchTerms}&search=Search"; }
      ];
      icon = "${ffIcons}/youtube.ico";
      definedAliases = [ "@youtube" ];
    };
    "Rumble" = {
      urls = [ { template = "https://rumble.com/search/video?q={searchTerms}"; } ];
      icon = "${ffIcons}/rumble.ico";
      definedAliases = [ "@rumble" ];
    };
    "Twitch" = {
      urls = [ { template = "https://www.twitch.tv/search?term={searchTerms}"; } ];
      icon = "${ffIcons}/twitch.ico";
      definedAliases = [ "@twitch" ];
    };
    "AniList Anime" = {
      urls = [ { template = "https://anilist.co/search/anime?search={searchTerms}"; } ];
      icon = "${ffIcons}/anilist.ico";
      definedAliases = [ "@anime" ];
    };
    # Research indicated it's the best uncurated film and TV ratings aggregator
    "TMDB" = {
      urls = [ { template = "https://www.themoviedb.org/search?query={searchTerms}"; } ];
      icon = "${ffIcons}/tmdb.ico";
      definedAliases = [ "@tmdb" ];
    };
    # Research indicated it's the best curated/popular film and TV ratings aggregator
    "Rotten Tomatoes" = {
      urls = [ { template = "https://www.rottentomatoes.com/search?search={searchTerms}"; } ];
      icon = "${ffIcons}/rottentomatoes.png";
      definedAliases = [
        "@rt"
        "@rotten"
      ];
    };
    # Good for quickly finding trailers
    "Trakt" = {
      urls = [ { template = "http://trakt.tv/search?utf8=✓&query={searchTerms}"; } ];
      icon = "${ffIcons}/trakt.ico";
      definedAliases = [ "@trakt" ];
    };
    "Wikitubia (en)" = {
      urls = [
        { template = "https://youtube.fandom.com/wiki/Special:Search?search={searchTerms}&opensearch=1"; }
      ];
      icon = "${ffIcons}/wikitubia.png";
    };
    # ── Audio ─────────────────────────────────────────────────
    "Last.fm" = {
      urls = [ { template = "http://www.last.fm/search?m=all&q={searchTerms}"; } ];
      icon = "${ffIcons}/lastfm.ico";
      definedAliases = [ "@last" ];
    };
    "Last.fm - Tracks" = {
      urls = [ { template = "http://www.last.fm/search?q={searchTerms}&type=track"; } ];
      icon = "${ffIcons}/lastfm.ico";
      definedAliases = [ "@music" ];
    };
    # ── Shopping ─────────────────────────────────────────────────
    "Amazon UK" = {
      urls = [ { template = "https://www.amazon.co.uk/s?k={searchTerms}"; } ];
      icon = "${ffIcons}/amazon-uk.ico";
      definedAliases = [ "@amazon" ];
    };
    "Temu.com" = {
      urls = [
        {
          template = "https://www.temu.com/search_result.html?search_key={searchTerms}&search_method=user";
        }
      ];
      icon = "${ffIcons}/temu.png";
      definedAliases = [ "@temu" ];
    };
    "Aliexpress" = {
      urls = [
        {
          template = "https://www.aliexpress.com/wholesale?catId=0&initiative_id=SB_20190730094114&SearchText={searchTerms}&switch_new_app=n";
        }
      ];
      icon = "${ffIcons}/aliexpress.ico";
      definedAliases = [ "@ali" ];
    };
    # ── Political ─────────────────────────────────────────────────
    "Wikispooks (en)" = {
      urls = [
        { template = "https://wikispooks.com/w/index.php?title=Special:Search&search={searchTerms}"; }
      ];
      icon = "${ffIcons}/wikispooks.ico";
    };
    "Conservapedia (en)" = {
      urls = [
        { template = "https://conservapedia.com/index.php?title=Special:Search&search={searchTerms}"; }
      ];
      icon = "${ffIcons}/conservapedia.png";
      definedAliases = [ "@conservapedia" ];
    };
    "Grokipedia" = {
      urls = [ { template = "https://grokipedia.com/search?q={searchTerms}"; } ];
      icon = "${ffIcons}/grokipedia.ico";
      definedAliases = [ "@grok" ];
    };
  };
}
