#!/usr/bin/env bash
# shellish/lib/safe-rm.sh — drop-in rm, coordinates with run.js via temp files
#
# Env vars set by run.js:
#   SHELLISH_CONFIRM_DANGER   ask | allow
#   SHELLISH_SESSION_ID       unique per-run ID
#   SHELLISH_SESSION_DIR      temp dir for req/res files

RAW_ARGS=("$@")
CONFIRM="${SHELLISH_CONFIRM_DANGER:-ask}"
SESSION="${SHELLISH_SESSION_ID:-}"
SESSION_DIR="${SHELLISH_SESSION_DIR:-}"
ALLOW_FILE="${SESSION_DIR}/.allow-all"

# ── parse rm-style argv ───────────────────────────────────────────────────────
# Trash backends (macOS trash, gio, trash-put) reject rm flags like -r / -f —
# recursion is implied by trashing a directory. Strip flags, keep targets,
# remember -f / --force for rm-compatible "ignore missing operands" semantics.
FORCE=0
TARGETS=()
_past_dash=0
for _a in "${RAW_ARGS[@]}"; do
  if [[ $_past_dash -eq 0 ]]; then
    if [[ "$_a" == "--" ]]; then _past_dash=1; continue; fi
    if [[ "$_a" == -* ]]; then
      if [[ "$_a" == "--force" || "$_a" =~ ^-[a-zA-Z]*f ]]; then FORCE=1; fi
      continue
    fi
  fi
  # A leading-dash path (only reachable after --) would read as a flag to the
  # trash backend; ./-x names the same file unambiguously.
  if [[ "$_a" == -* ]]; then _a="./$_a"; fi
  TARGETS+=("$_a")
done

if [[ ${#TARGETS[@]} -eq 0 ]]; then
  [[ $FORCE -eq 1 ]] && exit 0
  echo "safe-rm: missing operand" >&2
  exit 1
fi

# rm semantics for missing operands: -f skips them silently (exit 0 even if
# nothing existed); without -f report each and exit 1, but still trash the
# operands that do exist.
EXISTING=()
MISSING_RC=0
for _t in "${TARGETS[@]}"; do
  if [[ -e "$_t" || -L "$_t" ]]; then
    EXISTING+=("$_t")
  elif [[ $FORCE -eq 0 ]]; then
    echo "safe-rm: cannot remove '$_t': No such file or directory" >&2
    MISSING_RC=1
  fi
done

if [[ ${#EXISTING[@]} -eq 0 ]]; then
  exit $MISSING_RC
fi

# ── trash ─────────────────────────────────────────────────────────────────────
# Percent-encode a path for a freedesktop .trashinfo Path= line (RFC 2396,
# "/" kept verbatim). Iterates bytes so UTF-8 paths encode correctly.
_urlencode_path() {
  local LC_ALL=C
  local s="$1" out="" c hex i
  for ((i = 0; i < ${#s}; i++)); do
    c="${s:i:1}"
    case "$c" in
      [a-zA-Z0-9._~/-]) out+="$c" ;;
      # "'$c" can sign-extend bytes >0x7F on bash 3.2; mask to one byte.
      *) printf -v hex '%%%02X' "$(( $(printf '%d' "'$c") & 0xFF ))"; out+="$hex" ;;
    esac
  done
  printf '%s' "$out"
}

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
  local rc=0
  mkdir -p "$files_dir" "$info_dir"
  for t in "$@"; do
    local abs name ts dest info
    abs="$(cd "$(dirname "$t")" 2>/dev/null && pwd)/$(basename "$t")" || abs="$t"
    name="$(basename "$t")"
    # DeletionDate is local time per the spec
    ts="$(date +%Y-%m-%dT%H:%M:%S)"
    dest="${files_dir}/${name}"
    info="${info_dir}/${name}.trashinfo"
    # avoid name collision
    local n=1
    while [[ -e "$dest" ]]; do dest="${files_dir}/${name}.${n}"; info="${info_dir}/${name}.${n}.trashinfo"; ((n++)); done
    if ! mv -- "$t" "$dest" 2>/dev/null; then
      echo "safe-rm: failed to move '$t' to trash" >&2
      rc=1
      continue
    fi
    printf '[Trash Info]\nPath=%s\nDeletionDate=%s\n' "$(_urlencode_path "$abs")" "$ts" > "$info"
  done
  return $rc
}

# Trash the existing targets; combine with missing-operand status like rm.
trash_and_exit() {
  do_trash "${EXISTING[@]}"
  local rc=$?
  [[ $rc -eq 0 ]] && rc=$MISSING_RC
  exit $rc
}

# ── allow mode ────────────────────────────────────────────────────────────────
if [[ "$CONFIRM" == "allow" ]]; then
  trash_and_exit
fi

# ── session allow-all ─────────────────────────────────────────────────────────
if [[ -f "$ALLOW_FILE" ]]; then
  trash_and_exit
fi

# ── ask mode: communicate with run.js via temp files ─────────────────────────
if [[ -z "$SESSION_DIR" || ! -d "$SESSION_DIR" ]]; then
  # fallback: no session dir, just trash silently
  trash_and_exit
fi

# Write request file (named by PID to support concurrent calls).
# Show the original argv so the user sees exactly what the agent ran.
REQ_FILE="${SESSION_DIR}/req.$$"
RES_FILE="${SESSION_DIR}/res.$$"
printf '%s' "${RAW_ARGS[*]}" > "$REQ_FILE"

# Poll for response (max 60s)
WAITED=0
answer=""
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
    trash_and_exit
    ;;
  a)
    touch "$ALLOW_FILE"
    trash_and_exit
    ;;
  *)
    exit 1
    ;;
esac
