#!/usr/bin/env bash
# shellish/lib/config.sh — read/write persistent config

SHELLISH_CONFIG_DIR="${HOME}/.config/shellish"
SHELLISH_CONFIG_FILE="${SHELLISH_CONFIG_DIR}/config"

config_init() {
  mkdir -p "$SHELLISH_CONFIG_DIR"
  [[ -f "$SHELLISH_CONFIG_FILE" ]] || touch "$SHELLISH_CONFIG_FILE"
}

config_get() {
  local key="$1"
  config_init
  grep "^${key}=" "$SHELLISH_CONFIG_FILE" 2>/dev/null | tail -1 | cut -d= -f2-
}

config_set() {
  local key="$1"
  local value="$2"
  config_init
  # remove old entry, append new
  local tmp
  tmp=$(mktemp)
  grep -v "^${key}=" "$SHELLISH_CONFIG_FILE" > "$tmp" 2>/dev/null || true
  echo "${key}=${value}" >> "$tmp"
  mv "$tmp" "$SHELLISH_CONFIG_FILE"
}
