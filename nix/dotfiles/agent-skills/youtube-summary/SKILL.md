---
name: youtube-summary
description: Summarise a YouTube video using yt-dlp subtitles.
allowed-tools: Bash Write Read Edit
compatibility: "Requires yt-dlp"

---

The user will provide a YouTube URL and optionally an output file path.

## Steps

1. **Get the video title:**

   ```
   yt-dlp --print title "<URL>"
   ```

2. **Download subtitles** — prefer manual subs over auto-generated:

   ```
   yt-dlp --write-sub --sub-lang "en.*" --skip-download --sub-format vtt -o "/tmp/youtube-summary" "<URL>" 2>&1
   ```

   Check if any `.vtt` files were written. If none were found (no manual subs), fall back to auto-generated:

   ```
   yt-dlp --write-auto-sub --sub-lang "en.*" --skip-download --sub-format vtt -o "/tmp/youtube-summary" "<URL>" 2>&1
   ```

3. **Extract clean text** from the VTT file (pick the `en-orig` variant if present, otherwise `en`):

   ```
   cat /tmp/youtube-summary*.vtt | grep -v '^WEBVTT' | grep -v '^Kind:' | grep -v '^Language:' | grep -v '^$' | grep -v '^[0-9][0-9]:[0-9][0-9]:[0-9][0-9]' | grep -v '^[0-9]*$' | grep -v '^\s*\$' | sed 's/<[^>]*>//g' | awk '!seen[$0]++'
   ```

4. **Summarise** the transcript into a Markdown document with:
   - H1: the video title
   - **Source:** link to the video
   - **Summary** section: a short (2–4 sentence) overview
   - Subsections (H3) for each major topic discussed, with a paragraph each
   - A "Misc" or "Other Topics" subsection for brief tangents

5. **Write** the summary to the path the user specified. If no path was given, then save it into `/tmp/youtube-summary/` as a Markdown file.

6. **Open** the Markdown file using `md path/to/file`

7. **Clean up** the temp files:
   ```
   rm -f /tmp/youtube-summary*.vtt
   ```
