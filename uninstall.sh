#!/usr/bin/env bash
# shellish uninstaller
set -euo pipefail

INSTALL_DIR="${SHELLISH_INSTALL_DIR:-${HOME}/.local/share/shellish}"
BIN_DIR="${SHELLISH_BIN_DIR:-${HOME}/.local/bin}"
CONFIG_DIR="${HOME}/.config/shellish"

bold()  { printf "\033[1m%s\033[0m" "$*"; }
green() { printf "\033[32m%s\033[0m" "$*"; }
red()   { printf "\033[31m%s\033[0m" "$*"; }
dim()   { printf "\033[2m%s\033[0m" "$*"; }

echo ""
echo "  $(bold "shellish uninstaller")"
echo ""
printf "  Remove shellish completely? [y/N] "
read -r confirm </dev/tty
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
  echo "  Aborted."
  exit 0
fi

# Remove hook from shell rc files
for rc in "${HOME}/.zshrc" "${HOME}/.bashrc"; do
  if grep -q 'shellish' "$rc" 2>/dev/null; then
    tmp=$(mktemp)
    sed '/# ── shellish hook/,/# ──────.*──$/d' "$rc" > "$tmp"
    mv "$tmp" "$rc"
    echo "  $(green "✓") Removed hook from $rc"
  fi
done

# Remove symlink
if [[ -L "${BIN_DIR}/shellish" ]]; then
  rm -f "${BIN_DIR}/shellish"
  echo "  $(green "✓") Removed ${BIN_DIR}/shellish"
fi

# Remove install dir
if [[ -d "$INSTALL_DIR" ]]; then
  rm -rf "$INSTALL_DIR"
  echo "  $(green "✓") Removed $INSTALL_DIR"
fi

# Ask whether to remove config
if [[ -d "$CONFIG_DIR" ]]; then
  printf "  Remove config at $CONFIG_DIR? [y/N] "
  read -r rm_cfg </dev/tty
  if [[ "$rm_cfg" == "y" || "$rm_cfg" == "Y" ]]; then
    rm -rf "$CONFIG_DIR"
    echo "  $(green "✓") Removed $CONFIG_DIR"
  fi
fi

echo ""
echo "  $(green "Done.") shellish has been uninstalled."
echo "  Restart your shell to apply changes."
echo ""
