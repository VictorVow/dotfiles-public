## Meta

This file is maintained by `update.sh` and updated during system updates.

**Structure:**
- **Meta** (this section): Documents the structure and formatting of this file.
- **News**: Unread entries only — `[read]` entries are excluded.

**Formatting rules for the News section:**
- Content is filtered output of `home-manager news` — do not hand-edit it.
- Each news entry starts with a `* DATE [unread]` header.
- Entries are separated by blank lines.

**Update behaviour:** `update.sh` compares new unread news against the stored
News section and prompts before overwriting (Y/n, default Y). Skipped in
non-interactive (cron) sessions.

Last updated: 2026-03-27 20:51:21

## News

* 2026-03-25 17:18:02 [unread]

  A new module is available: `programs.grype`
  
  Grype is a vulnerability scanner for container images and filesystems.
  


* 2026-03-22 18:14:47 [unread]

  A new module is available: 'programs.atool'.
  
  Atool is a commandline archive manager that can create,
  view, and extract archives. It uses common packages
  like gnutar, p7zip, unrar, and zip as backends.
  


* 2026-03-06 23:08:53 [unread]

  
        A new module is available: `programs.ttyper`
  
        ttyper is a terminal-based typing test.
      


* 2026-03-04 18:33:31 [unread]

  
        A new module is available: `programs.macchina`
  
        Macchina is a system information frontend with an emphasis on performance.
      


* 2026-02-06 21:46:14 [unread]

  A new module is available: `services.mpdris2-rs`
  
  Adds a module for mpdris2-rs, a lightweight implementation of the MPD to D-Bus bridge.
  
