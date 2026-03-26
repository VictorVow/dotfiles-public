#!/usr/bin/env bash
# Called on UserPromptSubmit — clears the dedupe state so the next
# Stop/Notification after Claude responds will send a fresh notification.
DEDUPE_DIR="${XDG_RUNTIME_DIR:-/tmp}/claude-notify-dedupe"
TMUX_CTX=""
if [[ -n "${TMUX:-}" ]]; then
    TMUX_CTX=$(tmux display-message -p '#S:#W.#P' 2>/dev/null || true)
fi
DEDUPE_KEY=$(printf '%s' "${TMUX_CTX:-default}" | tr '/:. ' '_')
rm -f "${DEDUPE_DIR}/${DEDUPE_KEY}" 2>/dev/null || true
