# Agent skills (~/.claude/skills/<name>/SKILL.md), following the Agent Skills spec
# (https://agentskills.io / https://github.com/agentskills/agentskills).
# Own skills are plain folders in nix/dotfiles/agent-skills/<name>/ (SKILL.md + any helper
# files), linked in automatically; third-party skills are linked from pinned flake inputs.
#
# Which agents see these (researched 2026-10): all use the same SKILL.md format
# (folder + frontmatter name/description, loaded on demand) but scan different dirs:
#   Claude Code — ~/.claude/skills, project .claude/skills (+ plugin skills)
#   OpenCode    — ~/.config/opencode/skills, plus ~/.claude/skills and ~/.agents/skills
#                 (project: .opencode/, .claude/, .agents/ skills dirs). v2 invokes skills
#                 as `@name`, not `/name` — slash wrappers are generated below.
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
# see each skill twice (same-name dedup behaviour unverified). Exceptions: logseq-cli, and the
# ~/.config/opencode/skills mirror for Orca's pre-session `/` menu (both below).
{ lib, orca, context7, logseq-fork, rea, impeccable, hostProfile, ... }:

let
  skillsDir = ../dotfiles/agent-skills;
  # Skills that only make sense on the desktop: they need a browser, distrobox, the
  # clipboard/GUI, the Logseq checkout, or desktop-only data stores. Left out on
  # servers (lord-ubuntu). system-update-* used to be here but their SKILL.md now
  # resolves ~/installs vs ~/Projects/installs per host.
  desktopOnlySkills = [
    "chromium-live-debug" "firefox-live-debug" "firefox-extension-development" "process-firefox-synced-tabs" "dbox-status" "md-open" "wl-copy"
    "logseq-add-md-to-blocks" "logseq-comparisons-update" "logseq-research"
    "process-hacker-news-favourites" "search-personal-data"
    "nix-switch"
  ];
  # Every subdirectory of skillsDir is a skill — adding a folder is all it takes.
  allSkillNames = lib.attrNames (lib.filterAttrs (_: type: type == "directory") (builtins.readDir skillsDir));
  # Impeccable (github:pbakaus/impeccable, flake = false input) — design skill whose
  # flagship /impeccable live mode drives a real browser, so it ships desktop-only.
  # Each harness build differs (command syntax + bundled agent TOMLs), so we link the
  # matching per-harness copy rather than one generic folder.
  withImpeccable = !hostProfile.isServer;
  skillNames =
    if hostProfile.isServer
    then lib.subtractLists desktopOnlySkills allSkillNames
    else allSkillNames;
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

      # ── Context7 docs lookup (github:upstash/context7, flake = false input) ──────────
      # Declarative equivalent of `npx ctx7 setup` in "CLI + Skills" mode (instead of
      # the Context7 MCP server). The skill runs `npx ctx7@latest library|docs …`;
      # anonymous use works, CONTEXT7_API_KEY / `ctx7 login` only raise rate limits.
      ".claude/skills/find-docs".source = "${context7}/skills/find-docs";

      # ── Logseq CLI (own fork, github:VictorVow/logseq @ fork, flake = false input) ───
      # Same source the locally-built `logseq` binary is compiled from, so the skill
      # always documents the CLI actually installed. Also in ~/.agents/skills:
      # Codex/Devin read it, and `logseq skill show|install` looks for
      # ~/.agents/skills/logseq-cli/SKILL.md. OpenCode sees it twice.
      ".claude/skills/logseq-cli".source = "${logseq-fork}/.agents/skills/logseq-cli";
      ".agents/skills/logseq-cli".source = "${logseq-fork}/.agents/skills/logseq-cli";

      # ── REA reverse-engineering skill (github:morluto/rea, flake = false input) ──
      # Instructions for the `rea` MCP server registered in ai-agents.nix
      # (`npx rea-agents@latest --mcp`). Also in ~/.agents/skills so Codex/Devin
      # see it; OpenCode dedups by name.
      ".claude/skills/reverse-engineer-anything".source = "${rea}/.agents/skills/reverse-engineer-anything";
      ".agents/skills/reverse-engineer-anything".source = "${rea}/.agents/skills/reverse-engineer-anything";
    }

    # ── Impeccable design skill (github:pbakaus/impeccable, flake = false input) ──
    # Desktop-only: /impeccable live drives a real browser. Per-harness builds:
    # the .claude copy goes to ~/.claude/skills (Claude Code + OpenCode v2), the
    # .agents copy to ~/.agents/skills (Codex + Devin CLI; OpenCode dedups by
    # name). The engine binary self-downloads to ~/.impeccable/bin/ on first run —
    # nothing writable is needed inside the store path.
    (lib.optionalAttrs withImpeccable {
      ".claude/skills/impeccable".source = "${impeccable}/.claude/skills/impeccable";
      ".agents/skills/impeccable".source = "${impeccable}/.agents/skills/impeccable";
    })

    # ── Orca native chat (OpenCode) ─────────────────────────────────────────────────
    # Orca only asks an ACP agent for its commands once the session is live (after the
    # first message); before that its `/` menu lists the skills it scans itself, and for
    # OpenCode that's ~/.config/opencode/skills + ~/.agents/skills — ~/.claude/skills
    # counts as Claude-only. Mirror the skills not already in ~/.agents/skills here.
    # opencode1 doesn't read this dir (XDG_CONFIG_HOME=~/.opencode1/config); v2 does.
    (lib.listToAttrs (map (name: {
      name  = ".config/opencode/skills/${name}";
      value = { source = skillsDir + "/${name}"; recursive = true; };
    }) skillNames))
    { ".config/opencode/skills/find-docs".source = "${context7}/skills/find-docs"; }
    { ".config/opencode/skills/reverse-engineer-anything".source = "${rea}/.agents/skills/reverse-engineer-anything"; }
    # OpenCode-flavoured build for Orca's pre-session `/` menu scan of
    # ~/.config/opencode/skills — v2 would dedup it against the .claude copy
    # anyway, and this one carries OpenCode's allowed-tools frontmatter.
    (lib.optionalAttrs withImpeccable {
      ".config/opencode/skills/impeccable".source = "${impeccable}/.opencode/skills/impeccable";
    })

    # ── OpenCode slash commands ─────────────────────────────────────────────────────
    # OpenCode (v1 and v2) discovers ~/.claude/skills but never lists skills in the `/`
    # menu (v2's own syntax is `@skill-id`). A thin commands/<name>.md per skill restores
    # `/<name> [args]` the way Claude Code does it — for v2 in ~/.config/opencode and for
    # opencode1 in its isolated ~/.opencode1/config/opencode. reverse-engineer-anything
    # is v2-only: opencode1 has the REA MCP server disabled (ai-agents.nix).
    (lib.listToAttrs (lib.concatMap ({ dir, extra }: map (name: {
      name  = "${dir}/commands/${name}.md";
      value.text = ''
        ---
        description: Run the ${name} skill
        ---
        Load the `${name}` skill with the skill tool and follow its instructions.

        $ARGUMENTS
      '';
    }) (skillNames ++ [ "orca-cli" "orchestration" "find-docs" ]
                      ++ lib.optionals withImpeccable [ "impeccable" ] ++ extra))
      [ { dir = ".config/opencode";           extra = [ "reverse-engineer-anything" ]; }
        { dir = ".opencode1/config/opencode"; extra = [ ]; } ]))
  ];
}
