#!/usr/bin/env bash
# shellish/lib/safe-rm.sh — drop-in rm, coordinates with run.js via temp files
#
# Env vars set by run.js:
#   SHELLISH_CONFIRM_DANGER   ask | allow
#   SHELLISH_SESSION_ID       unique per-run ID
#   SHELLISH_SESSION_DIR      temp dir for req/res files

ARGS=("$@")
CONFIRM="${SHELLISH_CONFIRM_DANGER:-ask}"
SESSION="${SHELLISH_SESSION_ID:-}"
SESSION_DIR="${SHELLISH_SESSION_DIR:-}"
ALLOW_FILE="${SESSION_DIR}/.allow-all"

# ── trash ─────────────────────────────────────────────────────────────────────
do_trash() {
  if command -v trash &>/dev/null; then
    trash "$@"; return $?
  fi
  if [[ "$(uname)" == "Darwin" ]] && command -v osascript &>/dev/null; then
    for t in "$@"; do
      local abs
      abs="$(cd "$(dirname "$t")" 2>/dev/null && pwd)/$(basename "$t")" || abs="$t"
      osascript -e "tell app \"Finder\" to delete POSIX file \"${abs}\"" &>/dev/null
    done
    return 0
  fi
  if command -v gio &>/dev/null; then
    gio trash "$@"; return $?
  fi
  if command -v trash-put &>/dev/null; then
    trash-put "$@"; return $?
  fi
  # freedesktop.org Trash spec: move file + write .trashinfo metadata
  local trash_base="${XDG_DATA_HOME:-$HOME/.local/share}/Trash"
  local files_dir="${trash_base}/files"
  local info_dir="${trash_base}/info"
  mkdir -p "$files_dir" "$info_dir"
  for t in "$@"; do
    local abs name ts dest info
    abs="$(cd "$(dirname "$t")" 2>/dev/null && pwd)/$(basename "$t")" || abs="$t"
    name="$(basename "$t")"
    ts="$(date -u +%Y-%m-%dT%H:%M:%S 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
    dest="${files_dir}/${name}"
    info="${info_dir}/${name}.trashinfo"
    # avoid name collision
    local n=1
    while [[ -e "$dest" ]]; do dest="${files_dir}/${name}.${n}"; info="${info_dir}/${name}.${n}.trashinfo"; ((n++)); done
    mv -- "$t" "$dest" 2>/dev/null || true
    printf '[Trash Info]\nPath=%s\nDeletionDate=%s\n' "$abs" "$ts" > "$info"
  done
}

# ── allow mode ────────────────────────────────────────────────────────────────
if [[ "$CONFIRM" == "allow" ]]; then
  do_trash "${ARGS[@]}"; exit $?
fi

# ── session allow-all ─────────────────────────────────────────────────────────
if [[ -f "$ALLOW_FILE" ]]; then
  do_trash "${ARGS[@]}"; exit $?
fi

# ── ask mode: communicate with run.js via temp files ─────────────────────────
if [[ -z "$SESSION_DIR" || ! -d "$SESSION_DIR" ]]; then
  # fallback: no session dir, just trash silently
  do_trash "${ARGS[@]}"; exit $?
fi

# Write request file (named by PID to support concurrent calls)
REQ_FILE="${SESSION_DIR}/req.$$"
RES_FILE="${SESSION_DIR}/res.$$"
printf '%s' "${ARGS[*]}" > "$REQ_FILE"

# Poll for response (max 60s)
WAITED=0
while [[ $WAITED -lt 600 ]]; do
  if [[ -f "$RES_FILE" ]]; then
    answer=$(cat "$RES_FILE")
    /bin/rm -f "$RES_FILE"   # use real rm to avoid re-intercepting
    break
  fi
  sleep 0.1
  WAITED=$((WAITED + 1))
done

# Clean up req file if still there (timeout)
/bin/rm -f "$REQ_FILE"

answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')

case "$answer" in
  y)
    do_trash "${ARGS[@]}"; exit $?
    ;;
  a)
    touch "$ALLOW_FILE"
    do_trash "${ARGS[@]}"; exit $?
    ;;
  *)
    exit 1
    ;;
esac
