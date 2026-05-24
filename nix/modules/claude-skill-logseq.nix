{ ... }:

{
  # Logseq DB-query skill for Claude Code.
  #
  # Kept in its own module (and as a verbatim source file rather than an
  # inline `.text` string) because it is large — far bigger than the small
  # skills in programs.nix. Sourcing the real Markdown keeps it readable,
  # syntax-highlighted and free of Nix string-escaping (''${...}) hazards.
  #
  # Edit nix/dotfiles/claude-skills/logseq-db-queries/SKILL.md to change it.
  home.file.".claude/skills/logseq-db-queries/SKILL.md".source =
    ../dotfiles/claude-skills/logseq-db-queries/SKILL.md;
}
