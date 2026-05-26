#!/usr/bin/env bash
# shellish/lib/spinner.sh — terminal spinner that works in zsh & bash
#
# Usage:
#   spinner_start "思考中"      # starts spinner in background, prints to stderr
#   do_some_slow_work
#   spinner_stop                # kills spinner, clears the line

_SHELLISH_SPINNER_PID=""
_SHELLISH_SPINNER_FRAMES=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')

spinner_start() {
  local label="${1:-}"

  # Don't spin if not connected to a real terminal
  [[ -t 2 ]] || return 0

  # Run spinner loop in background, writing to stderr
  (
    local i=0
    local n=${#_SHELLISH_SPINNER_FRAMES[@]}
    while true; do
      local frame="${_SHELLISH_SPINNER_FRAMES[$((i % n))]}"
      # \r moves to start of line; printf keeps it on one line
      printf "\r  \033[36m%s\033[0m  \033[2m%s\033[0m" "$frame" "$label" >&2
      sleep 0.08
      ((i++)) || true
    done
  ) &
  _SHELLISH_SPINNER_PID=$!

  # Make sure the child is killed even on unexpected exit
  trap 'spinner_stop' INT TERM EXIT
}

spinner_stop() {
  if [[ -n "$_SHELLISH_SPINNER_PID" ]]; then
    kill "$_SHELLISH_SPINNER_PID" 2>/dev/null || true
    wait "$_SHELLISH_SPINNER_PID" 2>/dev/null || true
    _SHELLISH_SPINNER_PID=""
    # Clear the spinner line
    printf "\r\033[2K" >&2
  fi
  # Reset trap to default
  trap - INT TERM EXIT
}
