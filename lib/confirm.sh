#!/usr/bin/env bash
# shellish/lib/confirm.sh — intercept dangerous operations before execution

# Patterns that require user confirmation before the agent can proceed.
# These are matched against the *proposed commands* the agent wants to run.

SHELLISH_DANGER_PATTERNS=(
  # Deletion
  '\brm\b'
  '\brmdir\b'
  '\btrash\b'
  # Privilege escalation
  '\bsudo\b'
  '\bsu\b'
  # Destructive git
  '\bgit\s+(reset|clean|push\s+.*--force|rebase)\b'
  # Package managers
  '\b(npm|yarn|pnpm|pip|pip3|brew)\s+(uninstall|remove|purge)\b'
  # Overwriting
  '\b(mv|cp)\b.*\s+-f\b'
  # Remote execution
  'curl\s.*\|\s*(bash|sh|zsh)'
  'wget\s.*\|\s*(bash|sh|zsh)'
  # Permissions / ownership
  '\b(chmod|chown)\b'
  # Disk formatting (never auto-run)
  '\b(mkfs|fdisk|diskutil\s+erase)\b'
)

# Returns 0 if the command string contains a dangerous pattern
shellish_is_dangerous() {
  local cmd="$*"
  local pattern
  for pattern in "${SHELLISH_DANGER_PATTERNS[@]}"; do
    if echo "$cmd" | grep -qiE "$pattern"; then
      return 0
    fi
  done
  return 1
}

# Interactive confirmation prompt.
# Usage: shellish_confirm_danger "rm -rf ./build"
# Returns 0 if user approves, 1 if rejected.
shellish_confirm_danger() {
  local proposed_cmd="$1"
  local reason="${2:-This operation may be destructive}"

  echo ""
  echo "  ⚠️  ${reason}"
  echo ""
  echo "  Proposed command:"
  echo "  ┌─────────────────────────────────────────┐"
  # indent each line of the command
  while IFS= read -r line; do
    printf "  │  \033[33m%s\033[0m\n" "$line"
  done <<< "$proposed_cmd"
  echo "  └─────────────────────────────────────────┘"
  echo ""
  printf "  Proceed? [y/N] "

  local answer
  # Read from /dev/tty so it works even when stdin is a pipe
  read -r answer </dev/tty

  if [[ "$answer" == "y" || "$answer" == "Y" ]]; then
    return 0
  fi
  echo "  ✗ Cancelled."
  return 1
}
