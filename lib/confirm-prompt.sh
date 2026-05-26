#!/usr/bin/env bash
# shellish/lib/confirm-prompt.sh
# Called synchronously by run.js to get user confirmation.
# stdout: the user's answer (y / a / N)

ARGS="$*"

R=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
YELLOW=$'\033[33m'; CYAN=$'\033[36m'

# Try to find a writable tty for output and readable tty for input
if [[ -w /dev/tty && -r /dev/tty ]]; then
  TTY=/dev/tty
elif [[ -t 2 ]]; then
  TTY=/dev/stderr
else
  # No tty at all (CI / piped) — default deny
  echo "N"
  exit 0
fi

printf "\n  ${YELLOW}⚠️  rm${R} ${BOLD}%s${R}\n" "$ARGS" > "$TTY"
printf "  ${DIM}→ will move to trash, not permanently delete${R}\n\n" > "$TTY"
printf "  ${CYAN}[y]${R} allow once  ${CYAN}[a]${R} allow all (this session)  ${CYAN}[N]${R} deny  " > "$TTY"

answer=""
if [[ -r /dev/tty ]]; then
  read -r answer < /dev/tty
elif [[ -t 0 ]]; then
  read -r answer
else
  answer="N"
fi

printf "\n" > "$TTY"
echo "${answer:-N}"
