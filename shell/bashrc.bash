# shellish — bash hook
# Sourced by ~/.bashrc via: source /path/to/shell/bashrc.bash
# Note: bash uses command_not_found_handle (no trailing 'r').
# Requires bash >= 4.0; on older bash (e.g. macOS's 3.2) the handler is
# defined but never fired — harmless, and macOS defaults to zsh anyway.

command_not_found_handle() {
  # Reentrancy guard. Everything this handler calls must already exist:
  # if any callee is itself missing (e.g. this function was inherited by an
  # environment that lost its helpers), bash would fire the handler again
  # for that callee and recurse until FUNCNEST. The guard breaks the cycle;
  # for the same reason the shellish lookup is inlined with `command -v`
  # (a builtin) instead of a helper function.
  if [[ -n "${_SHELLISH_CNF_ACTIVE:-}" ]]; then
    echo "bash: $1: command not found" >&2
    return 127
  fi
  local _SHELLISH_CNF_ACTIVE=1

  local raw_input="$*"
  local bin
  bin="$(command -v shellish 2>/dev/null)"

  if [[ -z "$bin" ]]; then
    echo "bash: $1: command not found" >&2
    return 127
  fi

  "$bin" --from-shell "$raw_input"
  return $?
}
