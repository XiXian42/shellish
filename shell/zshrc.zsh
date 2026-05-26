# shellish — zsh hook
# Sourced by ~/.zshrc via: source /path/to/shell/zshrc.zsh

# Resolve shellish binary (works whether installed to /usr/local or ~/.local)
_shellish_bin() {
  if command -v shellish &>/dev/null; then
    command -v shellish
  else
    echo ""
  fi
}

command_not_found_handler() {
  local raw_input="$*"
  local bin
  bin="$(_shellish_bin)"

  if [[ -z "$bin" ]]; then
    # shellish not in PATH — fall back to normal behavior
    echo "zsh: command not found: $1" >&2
    return 127
  fi

  "$bin" --from-shell "$raw_input"
  return $?
}
