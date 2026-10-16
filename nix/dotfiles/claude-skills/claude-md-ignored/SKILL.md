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
