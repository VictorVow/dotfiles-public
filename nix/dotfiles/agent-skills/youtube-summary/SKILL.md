---
name: youtube-summary
description: Summarise a YouTube video using yt-dlp subtitles, written to a Markdown file or into Logseq under a given block.
allowed-tools: Bash Write Read Edit
compatibility: "Requires yt-dlp; the Logseq output mode also requires the logseq CLI and a running Logseq DB graph"

---

The user will provide a YouTube URL and optionally either an output file path or a Logseq block target (`[[<uuid>]]` or a bare uuid), e.g. `/youtube-summary <url> [[6929822d-455e-4a81-8e9c-6dfdac0292c5]]`.

## Steps

1. **Get the video title, upload date and duration:**

   ```
   yt-dlp --print title --print upload_date --print duration "<URL>"
   ```

   The second line of output is the upload date as `YYYYMMDD` — render it in the summary as e.g. `15 Mar 2024`. If it's `NA` or empty, omit the date. The third line is the duration in seconds — round it to the nearest minute and render it as `~N min` in the summary.

2. **Download the thumbnail** (needed for the Logseq output mode):

   ```
   yt-dlp --write-thumbnail --skip-download -o "/tmp/youtube-summary" "<URL>" 2>&1
   ```

   This writes `/tmp/youtube-summary.<ext>` (usually `.webp` or `.jpg`).

3. **Download subtitles** — prefer manual subs over auto-generated:

   ```
   yt-dlp --write-sub --sub-lang "en.*" --skip-download --sub-format vtt -o "/tmp/youtube-summary" "<URL>" 2>&1
   ```

   Check if any `.vtt` files were written. If none were found (no manual subs), fall back to auto-generated:

   ```
   yt-dlp --write-auto-sub --sub-lang "en.*" --skip-download --sub-format vtt -o "/tmp/youtube-summary" "<URL>" 2>&1
   ```

4. **Extract clean text** from the VTT file (pick the `en-orig` variant if present, otherwise `en`):

   ```
   cat /tmp/youtube-summary*.vtt | grep -v '^WEBVTT' | grep -v '^Kind:' | grep -v '^Language:' | grep -v '^$' | grep -v '^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]' | grep -v '^[0-9]*$' | grep -v '^\s*\$' | sed 's/<[^>]*>//g' | awk '!seen[$0]++'
   ```

5. **Summarise** the transcript into a Markdown document with:
   - H1: the video title
   - **Source:** link to the video, with the channel name, the publish date and the duration rounded to the nearest minute (e.g. `**Source:** [Title — Channel](url) (12 Jan 2024, ~7 min)`)
   - **Summary** section: a short (2–4 sentence) overview
   - Subsections (H3) for each major topic discussed, with a paragraph each
   - A "Misc" or "Other Topics" subsection for brief tangents

6. **Output** — two modes:
   - **Logseq target given:** don't write a `.md` file. Load the `logseq-add-md-to-blocks` skill and import the summary as child blocks under the given block, following that skill's steps (the summary Markdown is the input you'd otherwise write to `/tmp/logseq-md-to-blocks/input.md`). Fit it to the target per that skill's rules: if the target block is itself titled with the video, drop the H1 since the title is already there. Then add the thumbnail as an image block under the same target:
     ```
     logseq upsert asset -g <graph> --path /tmp/youtube-summary.<ext> --target-uuid <uuid> --pos last-child
     ```
   - **Otherwise:** write the summary to the path the user specified. If no path was given, save it into `/tmp/youtube-summary/` as a Markdown file, then **open** it with `md path/to/file`.

7. **Clean up** the temp files:
   ```
   rm -f /tmp/youtube-summary*.vtt /tmp/youtube-summary.webp /tmp/youtube-summary.jpg /tmp/youtube-summary.png
   ```
