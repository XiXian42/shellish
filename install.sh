#!/usr/bin/env bash
# shellish installer
# Usage: curl -fsSL https://raw.githubusercontent.com/XiXian42/shellish/main/install.sh | bash
set -euo pipefail

SHELLISH_VERSION="0.1.0"
SHELLISH_REPO="https://github.com/XiXian42/shellish"
SHELLISH_RAW="https://raw.githubusercontent.com/XiXian42/shellish/main"

# For local dev install: if this script lives next to bin/ use it directly
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"

INSTALL_DIR="${SHELLISH_INSTALL_DIR:-${HOME}/.local/share/shellish}"
BIN_DIR="${SHELLISH_BIN_DIR:-${HOME}/.local/bin}"

# ── color helpers ──────────────────────────────────────────────────────────────
bold()  { printf "\033[1m%s\033[0m" "$*"; }
green() { printf "\033[32m%s\033[0m" "$*"; }
cyan()  { printf "\033[36m%s\033[0m" "$*"; }
red()   { printf "\033[31m%s\033[0m" "$*"; }
dim()   { printf "\033[2m%s\033[0m"  "$*"; }

hr() { echo "  ─────────────────────────────────────────────"; }

# ── banner ─────────────────────────────────────────────────────────────────────
echo ""
echo "  $(bold shellish) $(dim "v${SHELLISH_VERSION}") — natural language shell agent"
echo "  $(dim "$SHELLISH_REPO")"
hr
echo ""

# ── check dependencies ────────────────────────────────────────────────────────
need() {
  if ! command -v "$1" &>/dev/null; then
    echo "  $(red "✗") Required tool not found: $1"
    exit 1
  fi
}
need bash
need git || need curl   # need at least one download method

# ── detect shell ──────────────────────────────────────────────────────────────
CURRENT_SHELL="$(basename "${SHELL:-bash}")"
echo "  Detected shell : $(bold "$CURRENT_SHELL")"
echo "  Install dir    : $(bold "$INSTALL_DIR")"
echo "  Bin dir        : $(bold "$BIN_DIR")"
echo ""

# ── download / copy files ─────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR" "$BIN_DIR"

if [[ -d "${SCRIPT_DIR}/bin" ]]; then
  # Local dev install — just copy
  echo "  $(cyan "→") Local install from: $SCRIPT_DIR"
  cp -r "${SCRIPT_DIR}/bin"   "$INSTALL_DIR/"
  cp -r "${SCRIPT_DIR}/lib"   "$INSTALL_DIR/"
  cp -r "${SCRIPT_DIR}/shell" "$INSTALL_DIR/"
else
  # Remote install via git clone or curl
  echo "  $(cyan "→") Downloading shellish…"
  if command -v git &>/dev/null; then
    git clone --depth=1 "$SHELLISH_REPO" "$INSTALL_DIR" 2>&1 | sed 's/^/    /'
  else
    # Fallback: download individual files via curl
    for f in \
      bin/shellish \
      lib/agent.sh lib/config.sh lib/confirm.sh lib/context.js \
      lib/detect.sh lib/render.js lib/run.js lib/spinner.sh \
      lib/safe-rm.sh lib/confirm-prompt.sh \
      shell/zshrc.zsh shell/bashrc.bash; do
      mkdir -p "${INSTALL_DIR}/$(dirname "$f")"
      curl -fsSL "${SHELLISH_RAW}/${f}" -o "${INSTALL_DIR}/${f}"
    done
  fi
fi

# ── make binary executable and symlink ────────────────────────────────────────
chmod +x "${INSTALL_DIR}/bin/shellish"
chmod +x "${INSTALL_DIR}/lib/safe-rm.sh"
chmod +x "${INSTALL_DIR}/lib/confirm-prompt.sh"

if [[ -L "${BIN_DIR}/shellish" || -f "${BIN_DIR}/shellish" ]]; then
  rm -f "${BIN_DIR}/shellish"
fi
ln -s "${INSTALL_DIR}/bin/shellish" "${BIN_DIR}/shellish"

echo "  $(green "✓") Installed shellish → ${BIN_DIR}/shellish"
echo ""

# ── ensure BIN_DIR is in PATH ──────────────────────────────────────────────────
if [[ ":${PATH}:" != *":${BIN_DIR}:"* ]]; then
  echo "  $(cyan "!") ${BIN_DIR} is not in your PATH."
  echo "    Add this to your shell rc file:"
  echo ""
  echo "      export PATH=\"${BIN_DIR}:\$PATH\""
  echo ""
fi

# ── detect available agents ───────────────────────────────────────────────────
echo "  Checking for supported agents…"
echo ""
FOUND_AGENTS=()
for agent in pi omp claude codex; do
  if command -v "$agent" &>/dev/null; then
    printf "    $(green "✓") %-10s  %s\n" "$agent" "$(command -v "$agent")"
    FOUND_AGENTS+=("$agent")
  else
    printf "    $(dim "✗") %-10s  not found\n" "$agent"
  fi
done
echo ""

if [[ ${#FOUND_AGENTS[@]} -eq 0 ]]; then
  echo "  $(red "✗") No supported agent found."
  echo "    Please install one of: pi, claude (Claude Code), codex (OpenAI Codex CLI)"
  echo "    Then run: shellish config"
  echo ""
  exit 0
fi

# ── pick default agent (interactive) ─────────────────────────────────────────
hr
echo ""
echo "  $(bold "Choose your default agent")"
echo ""
i=1
for a in "${FOUND_AGENTS[@]}"; do
  case "$a" in
    pi)     desc="pi — earendil coding agent" ;;
    omp)    desc="omp — earendil coding agent" ;;
    claude) desc="Claude Code — Anthropic" ;;
    codex)  desc="Codex CLI — OpenAI" ;;
    *)      desc="$a" ;;
  esac
  printf "    %d) %-10s  $(dim "%s")\n" "$i" "$a" "$desc"
  ((i++))
done
echo ""
printf "  Your choice [1-%d, default=1]: " "${#FOUND_AGENTS[@]}"
read -r AGENT_CHOICE </dev/tty
AGENT_CHOICE="${AGENT_CHOICE:-1}"

if ! [[ "$AGENT_CHOICE" =~ ^[0-9]+$ ]] || \
   (( AGENT_CHOICE < 1 || AGENT_CHOICE > ${#FOUND_AGENTS[@]} )); then
  AGENT_CHOICE=1
fi
CHOSEN_AGENT="${FOUND_AGENTS[$((AGENT_CHOICE-1))]}"

# ── save config ────────────────────────────────────────────────────────────────
SHELLISH_CONFIG_DIR="${HOME}/.config/shellish"
mkdir -p "$SHELLISH_CONFIG_DIR"
cat > "${SHELLISH_CONFIG_DIR}/config" <<EOF
agent=${CHOSEN_AGENT}
confirm_danger=ask
EOF

echo ""
echo "  $(green "✓") Default agent: $(bold "$CHOSEN_AGENT")"
echo ""

# ── install shell hook ────────────────────────────────────────────────────────
hr
echo ""
echo "  $(bold "Install shell hook?")"
echo "  This lets you type natural language directly at the prompt"
echo "  without any 'shellish' prefix."
echo ""
printf "  Install hook into ~/.${CURRENT_SHELL}rc? [Y/n] "
read -r HOOK_CHOICE </dev/tty
HOOK_CHOICE="${HOOK_CHOICE:-Y}"

if [[ "$HOOK_CHOICE" == "y" || "$HOOK_CHOICE" == "Y" ]]; then
  # determine rc file and hook source
  case "$CURRENT_SHELL" in
    zsh)
      RC_FILE="${ZDOTDIR:-$HOME}/.zshrc"
      HOOK_SOURCE="${INSTALL_DIR}/shell/zshrc.zsh"
      ;;
    bash)
      RC_FILE="${HOME}/.bashrc"
      HOOK_SOURCE="${INSTALL_DIR}/shell/bashrc.bash"
      ;;
    *)
      echo "  $(red "✗") Unsupported shell for auto-hook: $CURRENT_SHELL"
      HOOK_CHOICE="n"
      ;;
  esac

  if [[ "$HOOK_CHOICE" != "n" ]]; then
    if grep -q 'shellish' "$RC_FILE" 2>/dev/null; then
      echo "  $(green "✓") Hook already present in $RC_FILE — skipping"
    else
      cat >> "$RC_FILE" <<HOOKEOF

# ── shellish hook (added by shellish install.sh) ────────────────────────────
source "${HOOK_SOURCE}"
# ────────────────────────────────────────────────────────────────────────────
HOOKEOF
      echo "  $(green "✓") Hook added to $RC_FILE"
    fi
  fi
fi

# ── done ──────────────────────────────────────────────────────────────────────
echo ""
hr
echo ""
echo "  $(green "$(bold "shellish installed successfully!")")"
echo ""
echo "  Next steps:"
echo "    1. Restart your shell  $(dim "or")  source ~/${CURRENT_SHELL}rc"
echo "    2. Try it:"
echo "       $(cyan "shellish \"list all png files in this directory\"")"
if [[ "$HOOK_CHOICE" == "y" || "$HOOK_CHOICE" == "Y" ]]; then
  echo "       $(dim "or just type at the prompt:")"
  echo "       $(cyan "list all png files in this directory")"
fi
echo ""
echo "  Other commands:"
echo "    shellish config          — change agent or settings"
echo "    shellish status          — show current setup"
echo "    shellish uninstall-hook  — remove shell hook"
echo ""
