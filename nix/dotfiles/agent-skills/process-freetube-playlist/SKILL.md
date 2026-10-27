---
name: process-freetube-playlist
description: >-
  Work through a FreeTube playlist synced to WatchSync (e.g. `/process-freetube-playlist Comedy`): summarise each video with the youtube-summary skill, write the summary to Markdown files or as child blocks in Logseq, then remove the video from the playlist. Manual mode (default) removes each video only after the user approves its summary; auto mode runs the whole queue unattended.
allowed-tools: Bash Read Write Agent Skill AskUserQuestion
compatibility: "Requires a reachable WatchSync server (tailnet), FreeTube's settings.db with watchSyncToken, yt-dlp, and — for Logseq output — the logseq CLI and a running DB graph"

---
Arguments: `$ARGUMENTS` = the FreeTube playlist name (e.g. `Comedy`, or a playlist `_id` like `watchLater`). Remaining words: a Logseq target (a block `[[<uuid>]]`/uuid or a page name) to write summaries under, and/or the mode `auto` or `manual`. Defaults: no Logseq target → Markdown files in `/tmp/freetube-playlist/<Playlist>/`; no mode → ask with AskUserQuestion (options "Manual (Recommended)" / "Auto"). Ask for the playlist name if it's missing.

The helper is `scripts/watchsync-playlist.py` (run it directly; it's a `uv run --script`). It prints JSON. Below, `wsp` means that script. It reads the WatchSync URL, the SYNC_TOKEN (from FreeTube's own `settings.db` — `WATCHSYNC_TOKEN` env overrides), and the `ftproc` clientId (see Notes).

**Modes.** Videos are always processed one at a time, in playlist order, never in parallel.

- **auto**: keep going through the playlist without waiting for the user, removing each video once its summary is written, until the playlist is empty (or the user interrupts). Keep per-video messages to one line so the context lasts.
- **manual** (default): after each video's summary is written, stop at the review gate (step 4e′). Remove the video from the playlist and move on only once the user approves.

## Steps

1. **Load `youtube-summary`** with the Skill tool, once, at the start — step 4b follows it. If a Logseq target was given, also load `logseq-add-md-to-blocks` and use its steps 1–2 to pick the graph and check the target.

2. **List the playlist:** `wsp list "<playlist>"`. It prints `{_id, playlistName, videos[]}` in playlist order, each entry `{playlistItemId, videoId, title, author, lengthSeconds, url}`. If the list is empty, report that and stop. Keep the `_id` — `remove` also accepts names but `_id` is unambiguous. `wsp playlists` lists every playlist (names, counts) if the name lookup fails.

   **Logseq target given: find or create the playlist group block.** All videos go under one H3 block titled with the playlist name, as the first child of the target. First look for an existing one: `logseq show -g <graph> --uuid <target-uuid>` (or the `logseq-tree.py` helper if `show` fails) and check whether a child already titled `<playlistName>` exists. If not, create it:
   ```
   logseq upsert block -g <graph> --target-uuid <target-uuid> --pos first-child \
     --content "### <playlistName>" --output json
   ```
   Note its block id (`group id`). Re-use it across videos and across runs — never create a second group block for the same playlist. Don't collapse it; the per-video blocks inside are collapsed instead.

3. **Track state** in `/tmp/freetube-playlist/<Playlist>/` (one dir per playlist): after each video is written, `touch` a marker file `<playlistItemId>.done` so a re-run can skip it (`test -f`). On a fresh run, check markers against the `wsp list` output before processing each video.

4. **Process the next video** (the first one in the list without a `.done` marker), then come back here for the next.

   a. Note the video's `title`, `url`, `author` and `playlistItemId` for later.

   b. **Summarise** following `youtube-summary` steps 1–4 (yt-dlp title → subtitles → clean transcript → summary Markdown). Adapt it like this:
      - Work in `/tmp/freetube-playlist/<Playlist>/`: write the `.vtt` and `summary-<playlistItemId>.md` there, not `/tmp/youtube-summary*`.
      - If the video has no English subtitles at all, or yt-dlp can't reach it (deleted/private video): mark it `failed` (step 4f) and move on — don't try Invidious or other fallbacks unless the user asks.
      - Use `https://youtu.be/<videoId>` as the URL and keep the FreeTube `title` as the H1 when yt-dlp's title lookup fails or returns "NA".

   c. **Output**, depending on the mode chosen above:
      - *Markdown files:* the summary is already `/tmp/freetube-playlist/<Playlist>/summary-<playlistItemId>.md`. Open it with `md <path>` so the user can read it (skip in auto mode).
      - *Logseq:* write the summary as child blocks under the **group block** from step 2 (not the run's target directly), following `logseq-add-md-to-blocks` steps 4–7 (convert, dry run, write, verify), with `/tmp/freetube-playlist/<Playlist>/blocks-<playlistItemId>.md` as the output file and `--pos first-child` on every command (newest summary at the top of the group). Do **not** append that skill's session-id top-level block — with `first-child` it lands as a sibling inside the group; instead append it as the last child of this summary's heading block after writing (same trick as `process-hacker-news-favourites` step 4e). Re-level with `scripts/../process-hacker-news-favourites/scripts/logseq-headings.py <graph> <heading block db id> --root-level 3 --shift -1 --max-level 4` and collapse the video's top block (`logseq upsert block -g <graph> --id <heading block db id> --update-properties '{:block/collapsed? true}'`).

      The resulting tree under the target:
      ```
      H3  <playlistName>            ← group block, created once in step 2
          H3  <video title>         ← one per video, collapsed
              H2  Summary / topic sections…
          H3  <video title>
              …
      ```
      - Skim the summary Markdown against `logseq-add-md-to-blocks` step 3's link/title rules first (no bare URLs, escape `#` as `\#`, no leading `[[`).

   d. If the write succeeded, `touch /tmp/freetube-playlist/<Playlist>/<playlistItemId>.done`.

   e′. **Manual mode only: review gate.** Tell the user in a few lines which video was summarised (title, author, length) and where the summary is (file path, or graph + target + heading block id). Then ask with AskUserQuestion:
      - "Looks good, continue": remove the video (step 4f), then on to the next video.
      - "Looks good, stop here": remove the video (step 4f), report (step 5) and stop.
      - "Keep it in the playlist": skip removal, mark done, move to the next video (report mentions it was kept).
      - "Needs changes" (user describes via Other/notes): fix the summary — re-run step 4b/4c with the feedback for content changes, edit the file or specific blocks in place for wording — and ask again. Don't remove the video until the user approves.

      If the run ends at this gate without an answer, the marker file means the next run starts at this same gate with the same video, not by re-summarising it. Detect that case: a `.done` marker whose video is **still in** the playlist means "summarised, awaiting review" — go straight to the gate.

   f. **Remove the video:** `wsp remove "<_id>" <playlistItemId>`. Check `ok: true` in the output — if `warning` is set, retry once; if it still fails, tell the user and continue (the summary is safe; the video just stays in the playlist). On any other failure in b–f: record it (a `<playlistItemId>.failed` marker file with the reason), tell the user in one line, and continue with the next video. `failed` markers are retried only if the user asks.

5. **Report** (end of an auto run, or when the user stops a manual one): each video processed (title → file or Logseq target), how many videos remain in the playlist (`wsp list "<_id>"` count), anything marked `failed`, and any videos the user chose to keep.

6. **Commit (auto mode only):** if the run's mode was `auto`, finish by loading the `git-commit` skill and committing any repo changes this session made (skip if there are none). In `manual` mode don't commit unless the user asks.

## Notes

- **Removal mechanism.** WatchSync has no per-video delete endpoint; `wsp remove` GETs the canonical store, drops the entry, and POSTs the playlist back with `lastUpdatedAt = now` — the playlist merge is whole-record last-write-wins, so the freshest copy wins. A device that pushes a *newer* copy before pulling ours can resurrect the video (see WatchSync README → "deletions don't propagate"): rare in practice, and re-running `wsp remove` fixes it. **Never** `DELETE /api/records/playlists/<id>` — its tombstone would make the entire playlist unre-addable.
- **clientId.** `wsp` writes as a pseudo-client so its pushes are attributed: default `ftproc`, stored in `~/.config/freetube-playlist/config.json`. WatchSync assigns its own id to unknown clients and runs their first sync as `existingWins` (add-only — the playlist write would no-op), so `remove` automatically retries with the server-assigned id and saves it to the config. If `remove` still reports `warning`, re-run it or pick a new id with `wsp login --client-id <id>`.
- **Ordering** is the playlist's own order (the `videos` array), not posting time — first video in the playlist is processed first.
- Video entries carry `playlistItemId` (unique per playlist row) **and** `videoId`; always remove by `playlistItemId`, since the same video can appear twice in one playlist.
- State/markers: `/tmp/freetube-playlist/<Playlist>/` (sanitised playlist name). Config: `~/.config/freetube-playlist/config.json`. The WatchSync repo lives at `/home/lord/Projects/Self-Hosted/WatchSync/WatchSync-server` (`ssh lord@lord-ubuntu`) — its README documents the API.
