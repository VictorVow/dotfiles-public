---
name: wl-copy
description: Copy text from Claude Code's messages to the clipboard directly in order to eliminate formatting issues.
---
1. A user selecting text to copy and paste from Claude Code's messages has indenting and new line issues.
2. Use `wl-copy` to copy your last message, it should look something like this:
  - wl-copy << 'EOF'
    Here's a bunch of text...
    EOF
    echo "Copied to clipboard"
3. Make sure to eliminate any formatting issues before copying text.
