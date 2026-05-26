# shellish — bash hook
# Sourced by ~/.bashrc via: source /path/to/shell/bashrc.bash
# Note: bash uses command_not_found_handle (no trailing 'r')

_shellish_bin() {
  if command -v shellish &>/dev/null; then
    command -v shellish
  else
    echo ""
  fi
}

command_not_found_handle() {
  local raw_input="$*"
  local bin
  bin="$(_shellish_bin)"

  if [[ -z "$bin" ]]; then
    echo "bash: $1: command not found" >&2
    return 127
  fi

  "$bin" --from-shell "$raw_input"
  return $?
}
