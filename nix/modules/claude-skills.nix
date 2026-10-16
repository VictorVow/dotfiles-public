# Claude Code user skills (~/.claude/skills/<name>/SKILL.md).
# Inline skills are written here; third-party skills are linked from pinned flake inputs.
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
{ orca, ... }:

{
  # ── Claude Code skills (home.file for correct subdirectory structure) ────────
  # programs.claude-code.skills (current HM rev) generates flat .claude/skills/<name>.md
  # but Claude Code 2.x requires .claude/skills/<name>/SKILL.md — use home.file directly.

  home.file.".claude/skills/nix-switch/SKILL.md".text = ''
    ---
    name: nix-switch
    description: Run home-manager switch and show any new news items.
    ---
    1. If the user tells you to run `hms` then instead run `home-manager switch --flake ~/Projects/installs/nix#boss --no-write-lock-file` since you don't have access to `hms` from your Bash shell.
       - The `--no-write-lock-file` flag is important: only `update.sh` (run via `update-all`) is allowed to advance `flake.lock`. The repo intentionally pins nixpkgs / home-manager to a 2-week-old upstream commit so Hydra's binary cache has caught up — without that pin, ad-hoc switches risk recompiling large packages from source. If a switch fails because it wants to write the lock, surface that to the user (it means something edited `flake.nix` since the last `update-all`); don't drop the flag to "fix" it.
    2. If you see "warning: Git tree <filepath> has uncommitted changes" then just ignore that warning.
    3. If it failed, show the full error and suggest a fix.
    4. Don't run `home-manager news` unless it's part of the update.sh script.
  '';

  home.file.".claude/skills/git-commit/SKILL.md".text = ''
    ---
    name: git-commit
    description: Make a git commit of the changes from this Claude session.
    ---
    - `git add` only the files touched by this session. If there are no files touched by this
      session then give a summary of what files have been changed outside of this session and
      give a commit message suggestion.
    - If executed not in a git repo, then check the child directories for which contain git repos.
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
    - Do not `git push` unless the remote is a example.com URL. If not, then don't unless
      it's necessary because a pull request, workflow action or something else in our intended next steps needs the commit pushed first.

  '';

  home.file.".claude/skills/direnv-ignored/SKILL.md".text = ''
    ---
    name: direnv-ignored
    description: Setup nix-direnv in this repo without having to commit it.
    ---
    1. Create `.envrc` in the top-level of repo with the content `use flake "path:$PWD/.nix"`.
    2. Append to the repo `.git/info/exclude` this content: `.nix/`.
    3. Create `.nix/flake.nix` with the packages needed in this project environment.
    4. Execute `direnv allow` in order to activate nix-direnv and setup the project environment.
  '';

  home.file.".claude/skills/claude-md-ignored/SKILL.md".text = ''
    ---
    name: claude-md-ignored
    description: Add CLAUDE.md and AGENTS.md to this repo without committing them, redirecting CLAUDE.md to AGENTS.md.
    ---
    1. Append to the repo `.git/info/exclude` these two lines, one per line: `CLAUDE.md` then `AGENTS.md`.
    2. Create `AGENTS.md` in the top-level of the repo with placeholder text. Use this content:
       ```
       # Agent instructions

       <!-- Add project-specific agent guidance here. -->
       ```
    3. Create `CLAUDE.md` in the top-level of the repo with exactly this single line of content (no code fence): Read the `AGENTS.md` file now.
  '';

  home.file.".claude/skills/dbox-status/SKILL.md".text = ''
    ---
    name: dbox-status
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
    name: wl-copy
    description: Copy text from Claude Code's messages to the clipboard directly in order to eliminate formatting issues.
    ---
    1. A user selecting text to copy and paste from Claude Code's messages has indenting and new line issues.
    2. Use `wl-copy` to copy your last message, it should look something like this:
      - wl-copy << 'EOF'
        Here's a bunch of text...
        EOF
        echo "Copied to clipboard"
    3. Make sure to eliminate any formatting issues before copying text.
  '';

    home.file.".claude/skills/md-open/SKILL.md".text = ''
    ---
    name: md-open
    description: Save text from Claude Code's messages to a temporary Markdown file and open it in order to more easily read the text.
    ---
    1. Claude Code's messages are rendered in a small tmux pane, which is good for multi-tasking productivity but makes reading long messages a challenge.
    2. Create a file in `/tmp/` with the extension `.md` containing the last message's contents.
    3. Open it with `~/.local/bin/marktext-wrap /tmp/filename.md` — this launches the user's Markdown reader (MarkText) detached via `setsid` with a scrubbed env, so it works from Claude Code's non-interactive shell. Do NOT use the `md` command: it is a `~/.bashrc` shell function and is not available in this shell.
  '';

  home.file.".claude/skills/yt-summary/SKILL.md".text = ''
    ---
    name: yt-summary
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

  home.file.".claude/skills/usage/SKILL.md".text = ''
    ---
    name: usage
    description: Show Claude.ai subscription usage (current 5-hour session + weekly limits) by calling the OAuth usage endpoint that powers /usage.
    allowed_tools:
      - Bash
    user_invocable: true
    ---
    Run the bundled script and print its output verbatim — no extra commentary:

    ```
    python3 ~/.claude/skills/usage/usage.py
    ```

    The script reads the OAuth access token from `~/.claude/.credentials.json`,
    GETs `https://api.anthropic.com/api/oauth/usage`, and prints three lines:

        Current session: N% used (resets in Xh Ym)
        All models: N% used (resets <Weekday> H:MM AM/PM)
        Sonnet only: N% used (resets <Weekday> H:MM AM/PM)

    Endpoint is undocumented and may change without notice.
  '';

  home.file.".claude/skills/usage/usage.py" = {
    executable = true;
    text = ''
      #!/usr/bin/env python3
      import json, sys, urllib.request
      from datetime import datetime, timezone
      from pathlib import Path

      CRED = Path.home() / ".claude" / ".credentials.json"
      URL = "https://api.anthropic.com/api/oauth/usage"

      try:
          token = json.loads(CRED.read_text())["claudeAiOauth"]["accessToken"]
      except Exception as e:
          sys.exit(f"failed to read OAuth token from {CRED}: {e}")

      req = urllib.request.Request(URL, headers={"Authorization": f"Bearer {token}"})
      try:
          with urllib.request.urlopen(req, timeout=10) as r:
              data = json.load(r)
      except Exception as e:
          sys.exit(f"request failed: {e}")

      now = datetime.now(timezone.utc)

      def pct(b):
          return f"{round(b['utilization'])}% used" if b else "n/a"

      def rel(b):
          if not b or not b.get("resets_at"):
              return ""
          t = datetime.fromisoformat(b["resets_at"].replace("Z", "+00:00"))
          secs = max(0, int((t - now).total_seconds()))
          h, m = secs // 3600, (secs % 3600) // 60
          return f"resets in {h}h {m}m"

      def absfmt(b):
          if not b or not b.get("resets_at"):
              return ""
          t = datetime.fromisoformat(b["resets_at"].replace("Z", "+00:00")).astimezone()
          return f"resets {t.strftime('%a %-I:%M %p')}"

      fh = data.get("five_hour")
      sd = data.get("seven_day")
      so = data.get("seven_day_sonnet")

      print(f"Current session: {pct(fh)} ({rel(fh)})")
      print(f"All models: {pct(sd)} ({absfmt(sd)})")
      print(f"Sonnet only: {pct(so)} ({absfmt(so)})")
    '';
  };

  home.file.".claude/skills/logseq-add-md-to-blocks/SKILL.md".text = ''
    ---
    name: logseq-add-md-to-blocks
    description: Import a Markdown file into a Logseq DB graph as a nested block tree (headings, paragraphs, list items, tables, code) under a target block or page, via the logseq CLI.
    allowed_tools:
      - Bash
      - Read
    user_invocable: true
    ---
    The user gives a Markdown file and a destination: a block (`[[<uuid>]]` or a uuid), or a page name. Optionally a graph name.

    ## Steps

    1. **Pick the graph.** If the user named one, use it. If they said "current graph", run `logseq server list` and use the graph whose `owner-source` is `electron` (the one open in the desktop app). If that's ambiguous, ask.

    2. **Check the target exists:** `logseq show -g <graph> --uuid <uuid>` (or `--id`). For a page target, `logseq list page -g <graph>` / `logseq search page`. Note any existing children so you know where new blocks will land.

    3. **Convert** the Markdown into a block outline:
       ```
       mkdir -p /tmp/logseq-md-to-blocks
       ~/Projects/installs/scripts/logseq-md-to-blocks.py <input.md> /tmp/logseq-md-to-blocks/blocks.md
       ```
       Headings become parent blocks (nested by level). Paragraphs and list items become one block each. Tables and code fences stay whole as one block. A list, table or code block after a paragraph ending in ":" nests under it. Skim the output (`cut -c1-110`) and check that the structure looks right.

       Add `--gfw` (before the input path) to give every block that *starts with* a GitHub link a live Git Forge Watcher widget (`{{renderer :gfw, <encoded-url>}}` on the block's second line; plugin source in `~/Projects/Git/Categories/Logseq-ALL/logseq-plugin-git-forge-watcher`). Use it whenever the blocks are about GitHub repos.

    4. **Check for side effects.** `[[...]]` and `#tag` in the text create or link pages in Logseq. Run a dry run and check `would-create-pages`:
       ```
       logseq upsert block -g <graph> --target-uuid <uuid> --pos last-child --dry-run --output json --blocks-file /tmp/logseq-md-to-blocks/blocks.md \
         | python3 -c 'import json,sys;d=json.load(sys.stdin)["data"];print(len(d["ops"][0][1][0]), "blocks;", "new pages:", d["would-create-pages"])'
       ```
       If unexpected pages would be created, tell the user before writing. Use `--target-page "<name>"` instead of `--target-uuid` for a page target.

    5. **Write:** run the same command without `--dry-run` and `--output json`. It prints the new block ids and `Count: N`.

    6. **Verify.** `logseq show` on the target can fail with `Failure(fetch failed)` for large trees. If so, verify with a query instead, and `show --id` a few of the section subtrees:
       ```
       logseq query -g <graph> --query '[:find (count ?c) :where [?p :block/uuid #uuid "<uuid>"] [?c :block/parent ?p]]'
       ```

    7. Report the graph, the target, the block count, and anything that didn't verify.
  '';

  home.file.".claude/skills/logseq-research/SKILL.md".text = ''
    ---
    name: logseq-research
    description: Research a topic (usually "what tools/options exist for X") and write the result as a formatted research outline under a block in the user's Logseq graph, building on the user's existing notes there. Iterate on formatting until the user is happy.
    allowed_tools:
      - Bash
      - Read
      - Write
      - WebSearch
      - WebFetch
    user_invocable: true
    ---
    The user points at a Logseq block (`[[<uuid>]]`) whose children hold their own notes on a topic, usually a list of tools, and names a child block (often "Claude research") to put your research under.

    Uses the `logseq` CLI. See the `logseq-cli` skill for command details and `logseq-add-md-to-blocks` for the import mechanics. Scripts are in `~/Projects/installs/scripts/`.

    ## Steps

    Create a task list with these four tasks and keep it updated:
    1. Do the research
    2. Add it into Logseq
    3. Iterate on formatting until the user is happy (they may delete everything and ask for a re-add in a different format)
    4. Update this skill/scripts with any new formatting choices

    ### 1. Read the user's existing notes first

    - Graph: `logseq server list` → the graph whose `owner-source` is `electron`.
    - Read the **whole** subtree of the topic block, not just the first level: `logseq show -g <graph> --uuid <uuid>`. Also dump it with `--output json` to see properties (headings, collapsed, assets). Look at any image assets (`~/logseq/graphs/<graph>/assets/<asset-uuid>.png`, uuid from a `:logseq.property.asset/checksum` query) with Read.
    - Find the target block's uuid with a query on `:block/title`. Note whether it already has children.
    - The user's existing groupings are a best guess, not a rule. Use whatever structure makes the most sense; overlapping theirs is fine.

    ### 2. Research

    - Cover every tool the user already listed, plus notable ones they missed. Mark the missed ones with "(new)" in their heading.
    - Use the GitHub API rather than web pages for repo facts: `gh api repos/<owner>/<repo> --jq '[.full_name,.stargazers_count,.pushed_at[:10],.license.spdx_id,.language,.description]|@tsv'`. Read READMEs with `gh api repos/<o>/<r>/readme --jq .content | base64 -d`. Use these numbers to *judge* activity and maturity, but don't write star counts or activity into the doc (the widget shows them).
    - Check nixpkgs availability (`nix eval --raw nixpkgs#<pkg>.version`), and check what's already installed in `~/Projects/installs` (`rg` in `nix/modules/`). Write recommendations for the user's actual setup: Kubuntu/KDE, Claude Code + Codex + OpenCode, Zed, GitHub + self-hosted Forgejo.
    - Mark unverified claims as such. Vendor benchmarks are vendor benchmarks.

    ### 3. Write the Markdown, using the house format

    Write to `/tmp/logseq-research/<topic>.md`. The user settled on this format (2026-10-16):

    - **No H1 title.** The target block is the title. Start with one intro paragraph: `Claude research, <date>.`, how the doc is organised, a note that GitHub stats are live in the widgets, and what "(new)" means.
    - **H2 (`##`) for sections.** Typically: `TL;DR for this setup` first, then numbered sections (`## 1. …`) ordered by the workflow, then `Practical habits…` (optional), and `Sources` last.
    - **H3 (`###`) for each tool or option** within a section. The heading is just the link: `### [name](https://github.com/owner/repo)`, plus ` (new)` if the user hadn't listed it. Non-tool items (e.g. "Claude Code built-ins", "Others", "Stacked PRs") get plain-text H3s too. Sources gets H3 subgroups (`Primary`, `Comparisons and articles`).
    - **First child of a tool H3: a one-line fact summary** as a paragraph: license, language, nixpkgs status and package name, oddities (e.g. "MIT, Rust, in nixpkgs (`tuicr`).", "Beta.", "No clear license."). **No star counts, no "active / quiet since" text**, because the Git Forge Watcher widget shows stars, last-commit age and open issues/PRs live.
    - **Then bullets** with what it does, how it fits the user's workflow, and caveats. Keep each bullet to one or two sentences. A tool that appears in two sections gets a short "See section N." entry the second time.
    - Each H2 section opens with a one-sentence paragraph saying what the section covers.
    - The TL;DR is plain bullets with **bold** tool names and no links.
    - No `[[page links]]` or `#tags` in the text (they create pages). No hard wrapping.

    ### 4. Convert and import

    ```
    ~/Projects/installs/scripts/logseq-md-to-blocks.py --gfw /tmp/logseq-research/<topic>.md /tmp/logseq-research/blocks.md
    ```
    `--gfw` adds `{{renderer :gfw, <url-encoded-link>}}` as the second line of every block that starts with a GitHub link. The user requires this on every standalone GitHub-repo block. Check with `grep -c 'renderer :gfw' blocks.md` (it should equal the number of GitHub tool headings).

    Then follow `logseq-add-md-to-blocks` steps 4–6: dry run (`would-create-pages` must be empty), write with `--target-uuid <target> --pos last-child`, and verify. `logseq show` fails on big trees, so check with queries instead:
    ```
    logseq query -g <graph> --query '[:find (count ?c) :where [?p :block/uuid #uuid "<target>"] [?c :block/parent ?p]]'
    logseq query -g <graph> --query '[:find ?lvl (count ?g) :where [?p :block/uuid #uuid "<target>"] [?c :block/parent ?p] [?g :block/parent ?c] [(get-else $ ?g :logseq.property/heading 0) ?lvl]]'
    ```
    In Logseq the stored title loses the `###`. It becomes `:logseq.property/heading 3`, and the widget macro sits on the title's second line.

    ### 5. Formatting loop

    Report the outcome and the current formatting choices, and ask for changes. If the user wants a new format:
    - If they say they deleted the blocks, confirm the target has 0 children (the count query above).
    - If they ask *you* to delete them: `~/Projects/installs/scripts/logseq-clear-children.sh --dry-run <graph> <target>` first, check that the titles are yours (the user may have edited blocks in that subtree, which is expected), then run it without `--dry-run`.
    - Edit the Markdown, re-convert, dry-run, write, verify. Look at any blocks the user edited by hand (`logseq show --uuid`); they show the format they want.

    ### 6. Record new formatting choices

    Once the user calls the format final, update this skill's "house format" section (in `~/Projects/installs/nix/modules/claude-skills.nix`) and the scripts with anything new, then tell the user to run `hms`.
  '';

  # ── Orca skills (github:stablyai/orca, flake = false input, pinned in flake.lock) ──
  # Declarative replacement for `npx skills add https://github.com/stablyai/orca
  # --skill orca-cli --skill orchestration --global`. Orca itself is AppMan-installed
  # and updates independently, so these may lag/lead the app's CLI slightly.
  home.file.".claude/skills/orca-cli".source      = "${orca}/skills/orca-cli";
  home.file.".claude/skills/orchestration".source = "${orca}/skills/orchestration";
  # Shared root read by Codex etc.; Orca counts it as coverage for every detected
  # agent, so this stops it prompting to install for non-Claude CLIs.
  home.file.".agents/skills/orca-cli".source      = "${orca}/skills/orca-cli";
  home.file.".agents/skills/orchestration".source = "${orca}/skills/orchestration";
}
