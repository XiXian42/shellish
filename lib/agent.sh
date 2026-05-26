#!/usr/bin/env bash
# shellish/lib/agent.sh — detect & invoke the configured agent backend

SHELLISH_SUPPORTED_AGENTS=("pi" "omp" "claude" "codex")

# shellcheck source=lib/spinner.sh
source "$(dirname "${BASH_SOURCE[0]}")/spinner.sh"

# ── detect which agents are available on this system ──────────────────────────
shellish_detect_agents() {
  local found=()
  local a
  for a in "${SHELLISH_SUPPORTED_AGENTS[@]}"; do
    if command -v "$a" &>/dev/null; then
      found+=("$a")
    fi
  done
  echo "${found[@]}"
}

# ── prompt user to pick a default agent ───────────────────────────────────────
shellish_pick_agent() {
  local -a available
  read -r -a available <<< "$(shellish_detect_agents)"

  if [[ ${#available[@]} -eq 0 ]]; then
    echo "" >&2
    echo "  ✗ No supported agent found on this system." >&2
    echo "  Install one of: pi, omp, claude (Claude Code), codex (OpenAI Codex CLI)" >&2
    echo "" >&2
    return 1
  fi

  echo "" >&2
  echo "  Available agents on this system:" >&2
  echo "" >&2
  local i=1
  local a
  for a in "${available[@]}"; do
    local extra=""
    case "$a" in
      pi)     extra="(pi — earendil coding agent)" ;;
      omp)    extra="(omp — earendil coding agent)" ;;
      claude) extra="(Claude Code — Anthropic)" ;;
      codex)  extra="(Codex CLI — OpenAI)" ;;
    esac
    printf "    %d) %-10s  %s\n" "$i" "$a" "$extra" >&2
    ((i++))
  done

  echo "" >&2
  printf "  Which agent should shellish use by default? [1-%d, default=1]: " "${#available[@]}" >&2

  local choice
  read -r choice </dev/tty
  choice="${choice:-1}"

  # validate
  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#available[@]} )); then
    echo "  Invalid choice, using '${available[0]}'" >&2
    choice=1
  fi

  local selected="${available[$((choice-1))]}"
  echo "$selected"
}

# ── build the correct invocation for each agent ───────────────────────────────
shellish_build_cmd() {
  local agent="$1"
  local prompt="$2"
  case "$agent" in
    pi)
      # pi takes the prompt as positional args; use -p for non-interactive
      echo "pi -p $(printf '%q' "$prompt")"
      ;;
    claude)
      # claude takes the prompt as a positional argument
      echo "claude $(printf '%q' "$prompt")"
      ;;
    codex)
      echo "codex $(printf '%q' "$prompt")"
      ;;
    *)
      echo "$agent $(printf '%q' "$prompt")"
      ;;
  esac
}

# ── main entry point called by the CLI ────────────────────────────────────────
# Usage: shellish_run_agent <prompt>
shellish_run_agent() {
  local prompt="$*"

  # Source config helpers
  # shellcheck source=lib/config.sh
  source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

  local agent
  agent="$(config_get agent)"

  if [[ -z "$agent" ]]; then
    echo "  ✗ No agent configured. Run: shellish config"
    return 1
  fi

  if ! command -v "$agent" &>/dev/null; then
    echo "  ✗ Configured agent '$agent' not found in PATH."
    echo "    Run: shellish config   to pick a different one."
    return 1
  fi

  # Pass CWD as context via env so agents that read it can use it
  export SHELLISH_CWD="$PWD"
  export SHELLISH_PROMPT="$prompt"

  # run.js handles rendering, history saving, and exit code.
  _shellish_stream_agent "$agent" "$prompt"
  return $?
}

# ── internal: run one agent via run.js (handles prompt, render, history) ──────
_shellish_stream_agent() {
  local agent="$1"
  local prompt="$2"
  local run_js
  run_js="$(dirname "${BASH_SOURCE[0]}")/run.js"
  # --from-shell activates typo-detection mode in context.js + render.js
  if [[ "${SHELLISH_FROM_SHELL:-}" == "1" ]]; then
    node "$run_js" --from-shell "$agent" "$PWD" "$prompt"
  else
    node "$run_js" "$agent" "$PWD" "$prompt"
  fi
}
