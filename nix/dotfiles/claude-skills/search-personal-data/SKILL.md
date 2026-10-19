---
name: search-personal-data
description: Find something in the user's own data — documents and files on this laptop, Logseq notes, Calibre ebook highlights, open or past Firefox tabs, past agent sessions — by picking the right store and its read-only search command. Use when the user asks "where did I put / save / read / note…", "do I have anything on X", "find my notes/highlights/tabs about…", or when a task needs facts that live in their files rather than on the web.
---

The map of the user's data stores is `~/Projects/installs/docs/system/data-stores.md`: for each kind of data, where it lives and the exact command to search it, with tested examples and known gotchas. **Read it before the first search in a session.** It is the source of truth; this skill only covers how to use it. If something in it turns out to be wrong (a path moved, a command fails), tell the user and offer to fix the doc.

## Steps

1. **Pick the stores.** Map the request to stores using the doc's table. When it's unclear where something lives, search the likely stores in parallel rather than one after another, e.g. a topic the user "read about" could be in Calibre highlights, Recoll documents, Logseq and past tabs.

2. **Use the right tool per file type.** The doc says which formats `rg` handles and which need Recoll. In short: `rg` for anything stored as text (notes, Markdown, data files, code, Sidebery snapshots), `recollq` for PDF/Office/EPUB/HTML documents in `~/Documents`, `~/Downloads` and `~/Media`. A Recoll miss doesn't mean the file doesn't exist: text and code types are deliberately not in its content index, and it's refreshed hourly.

3. **Hand over to the dedicated skill where one exists**, instead of reinventing its commands:
   - Logseq notes → `logseq-cli`
   - past agent sessions → `search-agent-history`
   - contents of a live Firefox page → `firefox-live-debug`

4. **Report** what you found with something the user can open: file paths, URLs, book titles, Logseq block ids. Say which stores you searched and came up empty in, so they know what was covered.

## Rules

- **Read-only.** Don't modify, move or re-index anything in these stores while searching. Writing (e.g. adding Logseq blocks) is a separate request.
- **Scope searches.** Point `rg`/`fd` at a specific folder, never at all of `~` (~2.8 TB, mostly games, vaults and video).
- **Stay out of `~/Vaults`** (encrypted Plasma vaults) unless the user asks for it explicitly.
- **Calibre:** always query a copy of `metadata.db`, never the file on the NFS mount (SQLite locking over NFS; Calibre on lord-ubuntu may be writing to it). Delete the copy when done.
