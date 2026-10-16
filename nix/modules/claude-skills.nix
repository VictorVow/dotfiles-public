# Claude Code user skills (~/.claude/skills/<name>/SKILL.md).
# Own skills are plain folders in nix/dotfiles/claude-skills/<name>/ (SKILL.md + any helper
# files), linked in automatically; third-party skills are linked from pinned flake inputs.
#
# Which agents see these (researched 2026-10): all use the same SKILL.md format
# (folder + frontmatter name/description, loaded on demand) but scan different dirs:
#   Claude Code — ~/.claude/skills, project .claude/skills (+ plugin skills)
#   OpenCode    — ~/.config/opencode/skills, plus ~/.claude/skills and ~/.agents/skills
#                 (project: .opencode/, .claude/, .agents/ skills dirs)
#   Codex       — ~/.agents/skills, /etc/codex/skills, bundled ~/.codex/skills/.system
#                 (project: .agents/skills up to repo root). Does NOT read .claude/.
#   Antigravity — ~/.gemini/config/skills (all flavours; IDE also ~/.gemini/antigravity/skills,
#                 CLI also ~/.gemini/antigravity-cli/skills, ~/.gemini/skills)
#                 (project: .agents/skills). Does NOT read .claude/.
#   Devin CLI   — ~/.config/devin/skills, ~/.agents/skills, plus ~/.claude/skills via its
#                 Claude Code import (read_config_from.claude, default on). In Zed (ACP) the
#                 slash menu is empty; type " /name" (leading space) — see docs/system/claude-code.md.
# Deliberately only deployed to ~/.claude/skills → Claude Code + OpenCode (the primary
# agents). To reach Codex/Antigravity too, also deploy to ~/.agents/skills and
# ~/.gemini/config/skills — but OpenCode reads both ~/.claude and ~/.agents, so it would
# see each skill twice (same-name dedup behaviour unverified).
{ lib, orca, ... }:

let
  skillsDir = ../dotfiles/claude-skills;
  # Every subdirectory of skillsDir is a skill — adding a folder is all it takes.
  skillNames = lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir skillsDir));
in
{
  home.file = lib.mkMerge [
    # ── Own skills ─────────────────────────────────────────────────────────────
    # Claude Code 2.x requires .claude/skills/<name>/SKILL.md (programs.claude-code.skills in
    # the current HM rev generates flat <name>.md files, so use home.file). recursive = per-file
    # symlinks inside a real <name>/ dir, so Claude Code can still drop files in it.
    (lib.listToAttrs (map (name: {
      name  = ".claude/skills/${name}";
      value = { source = skillsDir + "/${name}"; recursive = true; };
    }) skillNames))

    {
      # ── Orca skills (github:stablyai/orca, flake = false input, pinned in flake.lock) ──
      # Declarative replacement for `npx skills add https://github.com/stablyai/orca
      # --skill orca-cli --skill orchestration --global`. Orca itself is AppMan-installed
      # and updates independently, so these may lag/lead the app's CLI slightly.
      ".claude/skills/orca-cli".source      = "${orca}/skills/orca-cli";
      ".claude/skills/orchestration".source = "${orca}/skills/orchestration";
      # Shared root read by Codex etc.; Orca counts it as coverage for every detected
      # agent, so this stops it prompting to install for non-Claude CLIs.
      ".agents/skills/orca-cli".source      = "${orca}/skills/orca-cli";
      ".agents/skills/orchestration".source = "${orca}/skills/orchestration";
    }
  ];
}
