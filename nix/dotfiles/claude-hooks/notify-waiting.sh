#!/usr/bin/env bash
set -euo pipefail

LOG="${XDG_RUNTIME_DIR:-/tmp}/claude-notify.log"
trap 'echo "[$(date +%T)] EXIT $?" >> "$LOG"' EXIT
echo "[$(date +%T)] hook start (tmux=${TMUX:-unset})" >> "$LOG"

# ── 1. Fix environment from plasmashell ──────────────────────────────────────
PLASMA_PID=$(pgrep -u "$USER" -x plasmashell 2>/dev/null | head -1 || true)
if [[ -n "$PLASMA_PID" ]]; then
    _penv() { tr '\0' '\n' < "/proc/$PLASMA_PID/environ" 2>/dev/null | grep "^${1}=" | cut -d= -f2- || true; }
    # Always override — stale values (e.g. from pre-suspend tmux sessions) are just as broken as empty ones
    for _var in DBUS_SESSION_BUS_ADDRESS WAYLAND_DISPLAY DISPLAY XDG_RUNTIME_DIR; do
        _val=$(_penv "$_var")
        [[ -n "$_val" ]] && export "$_var=$_val"
    done
    unset -f _penv; unset _var _val
fi

# ── 2a. tmux context ─────────────────────────────────────────────────────────
TMUX_CTX=""
if [[ -n "${TMUX:-}" ]]; then
    TMUX_CTX=$(tmux display-message -p '#S:#W.#P' 2>/dev/null || true)
fi

# ── 2b. Yakuake tab identification ───────────────────────────────────────────
# Runs in a subshell — any failure just yields empty YAKUAKE_TAB, never aborts the script
YAKUAKE_TAB=$(
    [[ -z "${TMUX:-}" ]] && exit 0
    command -v qdbus6 &>/dev/null || exit 0

    TMUX_SESSION=$(tmux display-message -p '#S' 2>/dev/null) || exit 0
    CLIENT_TTY=$(tmux list-clients -F '#{client_tty} #{session_name}' 2>/dev/null | \
        awk -v s="$TMUX_SESSION" '$2==s{print $1}' | head -1) || exit 0
    [[ -n "$CLIENT_TTY" ]] || exit 0

    SHELL_PID=$(ps -t "$CLIENT_TTY" --no-headers -o pid,comm 2>/dev/null | \
        sort -n | head -1 | awk '{print $1}') || exit 0
    [[ -n "$SHELL_PID" ]] || exit 0

    KONSOLE_SESS=""
    while IFS= read -r sess_path; do
        pid=$(qdbus6 org.kde.yakuake "$sess_path" \
            org.kde.konsole.Session.processId 2>/dev/null) || continue
        [[ "$pid" == "$SHELL_PID" ]] || continue
        KONSOLE_SESS="${sess_path##*/Sessions/}"
        break
    done < <(qdbus6 org.kde.yakuake 2>/dev/null | grep '^/Sessions/' || true)
    [[ -n "$KONSOLE_SESS" ]] || exit 0

    WINDOW_ID=""
    while IFS= read -r win_path; do
        curr=$(qdbus6 org.kde.yakuake "$win_path" \
            org.kde.konsole.Window.currentSession 2>/dev/null) || continue
        [[ "$curr" == "$KONSOLE_SESS" ]] || continue
        WINDOW_ID="${win_path##*/Windows/}"
        break
    done < <(qdbus6 org.kde.yakuake 2>/dev/null | grep '^/Windows/' || true)
    [[ -n "$WINDOW_ID" ]] || exit 0

    FIRST_Y=$(qdbus6 org.kde.yakuake /yakuake/sessions \
        org.kde.yakuake.sessionIdList 2>/dev/null | tr ',' '\n' | sort -n | head -1) || exit 0
    FIRST_W=$(qdbus6 org.kde.yakuake 2>/dev/null | grep '^/Windows/' | \
        sed 's|/Windows/||' | sort -n | head -1) || exit 0
    [[ -n "$FIRST_Y" && -n "$FIRST_W" ]] || exit 0

    OFFSET=$(( FIRST_W - FIRST_Y ))
    YAKUAKE_SESS=$(( WINDOW_ID - OFFSET ))
    qdbus6 org.kde.yakuake /yakuake/tabs \
        org.kde.yakuake.tabTitle "$YAKUAKE_SESS" 2>/dev/null
) || true

# ── 3. Deduplicate ───────────────────────────────────────────────────────────
# Stop fires immediately; Notification fires ~10s later for the same event.
# Skip if we already sent a notification for this pane within 60 seconds.
DEDUPE_DIR="${XDG_RUNTIME_DIR:-/tmp}/claude-notify-dedupe"
mkdir -p "$DEDUPE_DIR"
DEDUPE_KEY=$(printf '%s' "${TMUX_CTX:-${YAKUAKE_TAB:-default}}" | tr '/:. ' '_')
DEDUPE_FILE="$DEDUPE_DIR/$DEDUPE_KEY"
NOW=$(date +%s)
if [[ -f "$DEDUPE_FILE" ]]; then
    LAST=$(cat "$DEDUPE_FILE" 2>/dev/null || echo 0)
    AGE=$(( NOW - LAST ))
    if (( AGE < 300 )); then
        echo "[$(date +%T)] deduped (${AGE}s since last for $DEDUPE_KEY)" >> "$LOG"
        exit 0
    fi
fi
echo "$NOW" > "$DEDUPE_FILE"

# ── 4. Notify ─────────────────────────────────────────────────────────────────
NOTIF_TITLE="${YAKUAKE_TAB:-Claude Code}"
NOTIF_BODY=$([[ "${1:-}" == "stop" ]] && echo "Finished" || echo "Waiting for input")
echo "[$(date +%T)] notify: title='$NOTIF_TITLE' body='$NOTIF_BODY' dbus='${DBUS_SESSION_BUS_ADDRESS:-EMPTY}'" >> "$LOG"
if notify-send -u normal -a 'Yakuake' -t 10000 "$NOTIF_TITLE" "$NOTIF_BODY" 2>>"$LOG"; then
    echo "[$(date +%T)] notify-send: ok" >> "$LOG"
else
    echo "[$(date +%T)] notify-send: failed, trying kdialog" >> "$LOG"
    kdialog --passivepopup "$NOTIF_TITLE: $NOTIF_BODY" 8 2>>"$LOG" \
        && echo "[$(date +%T)] kdialog: ok" >> "$LOG" \
        || echo "[$(date +%T)] kdialog: also failed" >> "$LOG"
fi

# ── 5. tmux status flash ──────────────────────────────────────────────────────
if [[ -n "${TMUX:-}" ]]; then
    FLASH="⚡ Claude"
    [[ -n "$YAKUAKE_TAB" ]] && FLASH+=" · $YAKUAKE_TAB"
    [[ -n "$TMUX_CTX"    ]] && FLASH+=" · $TMUX_CTX"
    tmux display-message "$FLASH" 2>/dev/null || true
fi
