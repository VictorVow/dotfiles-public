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
