---
name: md-open
description: Save text from Claude Code's messages to a temporary Markdown file and open it in order to more easily read the text.
---
1. Claude Code's messages are rendered in a small tmux pane, which is good for multi-tasking productivity but makes reading long messages a challenge.
2. Create a file in `/tmp/` with the extension `.md` containing the last message's contents.
3. Open it with `~/.local/bin/marktext-wrap /tmp/filename.md` — this launches the user's Markdown reader (MarkText) detached via `setsid` with a scrubbed env, so it works from Claude Code's non-interactive shell. Do NOT use the `md` command: it is a `~/.bashrc` shell function and is not available in this shell.
