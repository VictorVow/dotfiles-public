Read `README.md` at least once per agent session. From there decide from there which particular directories and/or files (if any) are directly relevant to the task. If the README is insufficient to narrow the identify what files/directory are relevant then next start with `ls -R` in this current directory.

If you need to make changes within this repo that affect the high-level repo structure then update that section of the README. 

When you see a `> Decision`, `> Summary` or similar quote block near the top of Markdown files do not edit or create that - it's only for the user to create, not agents.

If asked to change config/packages/system use `rg` (Ripgrep) to search for it in this repository, as this will likely be the canonical place to make changes. 

Self-hosted services (Headscale, Forgejo, Stremio, Calibre, RSS, etc.) and the servers they run on (lord-ubuntu, VPSes) are NOT managed here — they live in separate repos  on `lord-ubuntu` server within `/home/lord/Projects/Self-Hosted/`). When troubleshooting or looking for a self-hosted service/tool, start with that directory's `README.md` (repo map).