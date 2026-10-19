{ config, ... }:

# Recoll full-text index over document folders, so agents (and the Recoll GUI) can search
# inside PDFs, Office files, ebooks etc., which `rg` can't read. Query from a shell with
# `recollq '<terms>'` (`-b` for paths only, `-A` for snippets); for code and plain text, `rg`
# over the folder is better and never stale.
#
# services.recoll installs recoll, writes recoll.conf, sets RECOLL_CONFDIR and runs
# `recollindex` (incremental) from a systemd user timer.
#
# Scope is deliberately narrow: the previous hand-made config indexed all of ~, which grew to
# 49 GB and stored the decrypted contents of ~/Vaults in plain text inside the index.
#
# What actually gets searchable content (tested 2026-10-19 against recoll 1.43.9 from nixpkgs,
# one sample file per type from these folders):
#   Text extracted:   PDF, EPUB, DOCX, DOC, XLSX, XLS, PPTX, ODT, ODS, ODP, RTF, HTML
#   Metadata only:    MP3 (ID3 tags), MP4 (container tags)
#   Archives:         ZIP members are indexed individually (by their own type)
#   File name only:   images (rclimg fails: its Perl script can't find JSON.pm in the nixpkgs
#                     build, so no EXIF; there's no OCR either), video (MKV), RAR (python
#                     rarfile module missing), MOBI, AZW3, TAR/TAR.GZ (handlers disabled by
#                     default), SVG (no text in the sample)
#   Excluded on purpose (excludedmimetypes below): TXT, Markdown, CSV, JSON, XML, SQL and
#                     source code. Recoll extracts them fine, but `rg` is the right tool.
# Files outside skippedNames/skippedPaths stay findable by name (`recollq 'filename:*part*'`;
# `recollq -f` file-name mode returned nothing in testing).
let
  home = config.home.homeDirectory;
in
{
  services.recoll = {
    enable = true;
    configDir = "${config.xdg.configHome}/recoll";
    startAt = "hourly";
    settings = {
      topdirs = [
        "~/Documents"
        "~/Downloads"
        "~/Media"
      ];
      # Added to recoll's defaults, which already skip .git, caches, __pycache__ etc.
      # ~/Documents holds ~70 node_modules trees; their JS would dwarf the real documents.
      # *.ja: Firefox/Tor/Mullvad omni.ja bundles (zips of browser JS), ~5k docs each.
      "skippedNames+" = [
        "node_modules"
        ".venv"
        "venv"
        "target"
        "*.ja"
      ];
      # Software, not documents: recoll opens every zip and indexes each member as its own
      # document, so these two folders alone were 160k docs after the first 15k files.
      # /media is recoll's default, kept since setting skippedPaths replaces it.
      skippedPaths = [
        "/media"
        "${home}/Documents/ESSENTIALS/Programs"
        "${home}/Documents/OPTIONAL/WordPress plugins"
      ];
      # Code inside any other zip archive: same problem, never what a document search wants.
      # (Patterns tested against WordPress plugin zips: cut docs ~3x.)
      zipSkippedNames = [
        "*.php"
        "*.js"
        "*.mjs"
        "*.jsm"
        "*.css"
        "*.scss"
        "*.map"
        "*.json"
        "*.svg"
        "*.ftl"
        "*.properties"
        "*.po"
        "*.pot"
        "*.mo"
        "*.twig"
        "*.xhtml"
      ];
      # Plain text, Markdown, code and data formats: `rg` searches these better and never goes
      # stale. In the first full run they were 6 GB of the 6.3 GB of extracted text (mostly
      # ~5k Sidebery tab snapshots in ~/Downloads/Sidebery and git repos under ~/Media),
      # against ~55 MB for every PDF/Office/ebook document combined. Names stay searchable.
      excludedmimetypes = [
        "text/plain"
        "text/markdown"
        "text/x-csv"
        "text/xml"
        "application/xml"
        "application/sql"
        "text/x-ini"
        "application/javascript"
        "text/css"
        "text/x-java"
        "text/x-python"
        "text/x-lua"
        "text/x-c"
        "text/x-c++"
        "text/x-ruby"
        "application/x-perl"
        "application/x-shellscript"
        "text/x-shellscript"
      ];
    };
  };

  # Index in the background: only use CPU/disk when they're otherwise idle.
  systemd.user.services.recollindex.Service = {
    Nice = 19;
    IOSchedulingClass = "idle";
    CPUSchedulingPolicy = "idle";
  };
}
