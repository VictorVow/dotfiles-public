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
#   Text extracted:   PDF, EPUB, DOCX, DOC, XLSX, XLS, PPTX, ODT, ODS, ODP, RTF, HTML, XML,
#                     Markdown, TXT, CSV, JSON, source code (py, js, ...)
#   Metadata only:    MP3 (ID3 tags), MP4 (container tags)
#   Archives:         ZIP members are indexed individually (by their own type)
#   File name only:   images (rclimg fails: its Perl script can't find JSON.pm in the nixpkgs
#                     build, so no EXIF; there's no OCR either), video (MKV), RAR (python
#                     rarfile module missing), MOBI, AZW3, TAR/TAR.GZ (handlers disabled by
#                     default), SVG (no text in the sample)
# Every file outside skippedNames is still findable by name (`recollq -f <name>`).
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
      "skippedNames+" = [
        "node_modules"
        ".venv"
        "venv"
        "target"
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
