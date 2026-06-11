# shellish — zsh hook
# Sourced by ~/.zshrc via: source /path/to/shell/zshrc.zsh

command_not_found_handler() {
  # Reentrancy guard. Everything this handler calls must already exist:
  # if any callee is itself missing (e.g. this function was inherited by an
  # environment that lost its helpers), zsh would fire the handler again for
  # that callee and recurse until FUNCNEST. The guard breaks the cycle; for
  # the same reason the shellish lookup is inlined with `command -v`
  # (a builtin) instead of a helper function.
  if [[ -n "${_SHELLISH_CNF_ACTIVE:-}" ]]; then
    print -u2 "zsh: command not found: $1"
    return 127
  fi
  local _SHELLISH_CNF_ACTIVE=1

  local raw_input="$*"
  local bin
  bin="$(command -v shellish 2>/dev/null)"

  if [[ -z "$bin" ]]; then
    # shellish not in PATH — fall back to normal behavior
    print -u2 "zsh: command not found: $1"
    return 127
  fi

  "$bin" --from-shell "$raw_input"
  return $?
}
