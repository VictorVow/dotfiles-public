- This machine is one of several on a Tailscale tailnet. List them all with `tailscale status`. Each machine has a different username  e.g. `ssh lord@lord-ubuntu` (/home/lord/), `ssh boss@boss-laptop`(/home/boss/),`ssh don@headscale`.
- Always read the [README.md](http://README.md) and [AGENTS.md](http://AGENTS.md) of your current repo first before beginning a task. 
- When doing full-text search you should start in the current repo instead of a much larger part of the filesystem. 
- To find something in the user's own data (documents, Logseq notes, Calibre highlights, Firefox tabs, past agent sessions), use the `search-personal-data` skill; its map of stores and commands is within the `installs` repo, under `nix/dotfiles/agent-skills/search-personal-data/references/data-stores.md`.

## Git repos

- Always look for the repo issue template before posting an issue, and pull request templates before posting a PR. 

## Styling

- Never use emdashes in any messages, ever.
- When creating MD files do not use hard wrapping, reflow the text. If you're editing an MD file and notice hard wrapping then ask the user if they want it removed also.