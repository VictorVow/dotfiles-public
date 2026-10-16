---
name: dbox-status
description: Show status of distrobox containers and their key packages.
---
1. Run `dbl` to list containers and their running state.
2. For each container, state its purpose and key packages:
   - dev: build tools (gcc, clang, cmake, ninja, gdb, valgrind), Python, Node
   - media: ffmpeg, OBS, kdenlive, HandBrake, mpv, yt-dlp
3. Suggest next steps based on current context.
