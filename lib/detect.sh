#!/usr/bin/env bash
# shellish/lib/detect.sh
#
# Intent classification: is the user's input a natural-language request
# (route to agent) or a mistyped / unknown shell command (return 127)?
#
# Strategy: ask the configured agent with a tightly scoped system prompt.
# The agent must reply with exactly one word: "yes" or "no".
# We never use regex heuristics — the LLM handles all languages and edge cases.

# shellcheck source=lib/config.sh
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"
# shellcheck source=lib/spinner.sh
source "$(dirname "${BASH_SOURCE[0]}")/spinner.sh"

# ── classification prompt ─────────────────────────────────────────────────────
# Kept in one variable so it's easy to tune.
_SHELLISH_CLASSIFY_PROMPT='You are a shell input classifier. The user typed something at a terminal prompt and the shell did not recognize it as a valid command.

Your job: decide whether the input is a NATURAL LANGUAGE REQUEST that a coding agent should handle, or a MISTYPED / UNKNOWN SHELL COMMAND that should just show a normal "command not found" error.

Rules:
- Reply with ONLY the single word "yes" or "no". No punctuation, no explanation.
- "yes" means: this looks like a natural-language task, question, or instruction (in any language).
- "no"  means: this looks like a shell command the user accidentally misspelled or a program name that is not installed.

Examples:
  Input: gti status          → no   (typo of "git")
  Input: pythno3 script.py   → no   (typo of "python3")
  Input: nod server.js       → no   (typo of "node")
  Input: 帮我压缩当前目录的所有png → yes
  Input: fix the last git merge conflict → yes
  Input: find all TODO comments and summarize them → yes
  Input: Wie kann ich alle logs löschen?  → yes  (German)
  Input: npmm install        → no   (typo of "npm")
  Input: cladue              → no   (typo of "claude")
  Input: list large files older than 7 days → yes

Now classify the following input:'

# ── main exported function ────────────────────────────────────────────────────
# Returns 0 if input should be routed to the agent, 1 otherwise.
# Usage: shellish_is_natural_language "some user input"
shellish_is_natural_language() {
  local input="$*"

  local agent
  agent="$(config_get agent)"

  if [[ -z "$agent" ]]; then
    # No agent configured yet — can't classify, don't intercept
    return 1
  fi

  if ! command -v "$agent" &>/dev/null; then
    return 1
  fi

  # Build the full prompt: system instructions + the actual input
  local full_prompt
  full_prompt="${_SHELLISH_CLASSIFY_PROMPT}

Input: ${input}"

  # Call the agent in non-interactive / print mode and capture the reply.
  # We strip whitespace and lowercase so "Yes\n" → "yes".
  local reply
  spinner_start "classifying…"
  case "$agent" in
    pi)
      reply=$(pi -p "$full_prompt" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
      ;;
    claude)
      reply=$(claude -p "$full_prompt" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
      ;;
    codex)
      reply=$(codex exec "$full_prompt" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
      ;;
    *)
      reply=$("$agent" "$full_prompt" 2>/dev/null | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
      ;;
  esac

  spinner_stop
  if [[ "$reply" == "yes" ]]; then
    return 0
  fi
  return 1
}
