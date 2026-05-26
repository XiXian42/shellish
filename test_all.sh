#!/usr/bin/env bash
# /tmp/shellish-test/test_all.sh
# Full test suite for shellish — run from anywhere.
set -euo pipefail

TESTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="${TESTDIR}/lib"
BIN="${TESTDIR}/bin/shellish"

# ── colour helpers ─────────────────────────────────────────────────────────────
RED='\033[31m'; GREEN='\033[32m'; YELLOW='\033[33m'
CYAN='\033[36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'
pass() { printf "${GREEN}  ✓${RESET}  %s\n" "$*"; }
fail() { printf "${RED}  ✗  FAIL${RESET}  %s\n" "$*"; FAILURES=$((FAILURES+1)); }
info() { printf "${CYAN}  →${RESET}  %s\n" "$*"; }
section() { echo ""; printf "${BOLD}${CYAN}══ %s ══${RESET}\n" "$*"; echo ""; }

FAILURES=0
TOTAL=0

# ── assert helpers ─────────────────────────────────────────────────────────────
assert_eq() {
  local desc="$1" got="$2" want="$3"
  TOTAL=$((TOTAL+1))
  if [[ "$got" == "$want" ]]; then
    pass "$desc"
  else
    fail "$desc  (got='${got}' want='${want}')"
  fi
}

assert_exit() {
  local desc="$1" want_exit="$2"
  shift 2
  TOTAL=$((TOTAL+1))
  local actual_exit=0
  "$@" &>/dev/null || actual_exit=$?
  if [[ "$actual_exit" == "$want_exit" ]]; then
    pass "$desc (exit=$actual_exit)"
  else
    fail "$desc (got exit=$actual_exit, want=$want_exit)"
  fi
}

assert_output_contains() {
  local desc="$1" pattern="$2"
  shift 2
  TOTAL=$((TOTAL+1))
  local out
  out=$("$@" 2>&1) || true
  if echo "$out" | grep -q "$pattern"; then
    pass "$desc"
  else
    fail "$desc — pattern '${pattern}' not found in output:"
    echo "$out" | sed 's/^/      /'
  fi
}

# ── setup: isolated config for tests ──────────────────────────────────────────
export HOME_ORIG="$HOME"
export SHELLISH_TEST_CONFIG="/tmp/shellish-test-config-$$"
mkdir -p "$SHELLISH_TEST_CONFIG/shellish"
cat > "$SHELLISH_TEST_CONFIG/shellish/config" <<EOF
agent=pi
confirm_danger=ask
EOF

# Override config path used by config.sh
export SHELLISH_CONFIG_FILE="$SHELLISH_TEST_CONFIG/shellish/config"
# patch config.sh to honour this env var
source_config_patched() {
  SHELLISH_CONFIG_DIR="$SHELLISH_TEST_CONFIG/shellish"
  SHELLISH_CONFIG_FILE="$SHELLISH_TEST_CONFIG/shellish/config"
  source "${LIB}/config.sh"
}

cleanup() {
  rm -rf "$SHELLISH_TEST_CONFIG"
}
trap cleanup EXIT

# ══════════════════════════════════════════════════════════════════════════════
section "1 · SYNTAX CHECK — all shell files"
# ══════════════════════════════════════════════════════════════════════════════
for f in \
  "${TESTDIR}/bin/shellish" \
  "${LIB}/agent.sh" \
  "${LIB}/config.sh" \
  "${LIB}/confirm.sh" \
  "${LIB}/detect.sh" \
  "${TESTDIR}/shell/zshrc.zsh" \
  "${TESTDIR}/shell/bashrc.bash"
do
  TOTAL=$((TOTAL+1))
  if bash -n "$f" 2>/dev/null; then
    pass "syntax ok: $(basename "$f")"
  else
    fail "syntax error: $f"
  fi
done

# ══════════════════════════════════════════════════════════════════════════════
section "2 · CONFIG — read / write"
# ══════════════════════════════════════════════════════════════════════════════
source_config_patched

config_set agent pi
assert_eq "config_set + config_get: pi" "$(config_get agent)" "pi"

config_set agent claude
assert_eq "config_set overwrites old value: claude" "$(config_get agent)" "claude"

config_set agent pi
config_set confirm_danger deny
assert_eq "config_get confirm_danger: deny" "$(config_get confirm_danger)" "deny"

config_set confirm_danger ask
assert_eq "config_get confirm_danger: ask" "$(config_get confirm_danger)" "ask"

assert_eq "config_get missing key returns empty" "$(config_get nonexistent_key)" ""

# ══════════════════════════════════════════════════════════════════════════════
section "3 · DANGER DETECTION — confirm.sh"
# ══════════════════════════════════════════════════════════════════════════════
source "${LIB}/confirm.sh"

check_danger() {
  local desc="$1" cmd="$2" want="$3"
  TOTAL=$((TOTAL+1))
  if shellish_is_dangerous "$cmd"; then got="dangerous"; else got="safe"; fi
  if [[ "$got" == "$want" ]]; then
    pass "$desc"
  else
    fail "$desc  (got=$got want=$want)  cmd='$cmd'"
  fi
}

# ── should be dangerous ──
check_danger "rm -rf"              "rm -rf ./build"                  dangerous
check_danger "rm with path"        "rm /tmp/foo.txt"                 dangerous
check_danger "sudo"                "sudo apt install vim"            dangerous
check_danger "git reset --hard"    "git reset --hard HEAD"           dangerous
check_danger "git clean"           "git clean -fd"                   dangerous
check_danger "git push --force"    "git push origin main --force"    dangerous
check_danger "curl pipe bash"      "curl https://x.sh | bash"        dangerous
check_danger "wget pipe sh"        "wget -qO- https://x.sh | sh"     dangerous
check_danger "chmod"               "chmod 755 deploy.sh"             dangerous
check_danger "chown"               "chown root:root /etc/hosts"      dangerous
check_danger "npm uninstall"       "npm uninstall lodash"            dangerous
check_danger "pip uninstall"       "pip uninstall requests"          dangerous
check_danger "brew remove"         "brew remove node"                dangerous

# ── should be safe ──
check_danger "ls -la"              "ls -la"                          safe
check_danger "grep recursive"      "grep -r TODO ."                  safe
check_danger "cat file"            "cat README.md"                   safe
check_danger "echo"                "echo hello world"                safe
check_danger "git status"          "git status"                      safe
check_danger "git log"             "git log --oneline -10"           safe
check_danger "npm install"         "npm install"                     safe
check_danger "find"                "find . -name '*.log'"            safe

# ══════════════════════════════════════════════════════════════════════════════
section "4 · INTENT CLASSIFICATION — detect.sh (LLM via pi)"
# ══════════════════════════════════════════════════════════════════════════════
info "This section calls pi -p for each case — takes ~30s total"
echo ""

# Reset config to pi for this section
config_set agent pi
source "${LIB}/detect.sh"

check_nl() {
  local desc="$1" input="$2" want="$3"
  TOTAL=$((TOTAL+1))
  printf "  ${DIM}testing: %-50s${RESET}" "'$input'"
  if shellish_is_natural_language "$input"; then got="agent"; else got="127"; fi
  if [[ "$got" == "$want" ]]; then
    printf "${GREEN}✓ %-6s${RESET}  %s\n" "$got" "$desc"
  else
    printf "${RED}✗ got=%-6s want=%-6s${RESET}  %s\n" "$got" "$want" "$desc"
    FAILURES=$((FAILURES+1))
  fi
}

# ── typos / unknown commands → 127 ──
check_nl "git typo"           "gti status"              "127"
check_nl "python typo"        "pythno3 script.py"       "127"
check_nl "npm typo"           "npmm install"            "127"
check_nl "claude typo"        "cladue"                  "127"
check_nl "node typo"          "nod server.js"           "127"
check_nl "single unknown word" "foobarqux"              "127"
check_nl "docker typo"        "dockre ps"               "127"

# ── natural language → agent ──
check_nl "Chinese task"       "帮我压缩当前目录的所有png"            "agent"
check_nl "Chinese question"   "这个目录下有哪些大文件？"              "agent"
check_nl "Japanese"           "このディレクトリのpngを圧縮して"       "agent"
check_nl "Korean"             "모든 로그 파일을 삭제해줘"            "agent"
check_nl "German"             "Wie kann ich alle logs löschen?"     "agent"
check_nl "Spanish"            "muéstrame todos los archivos grandes" "agent"
check_nl "English git task"   "fix the last git merge conflict"      "agent"
check_nl "English find task"  "find all TODO comments and summarize" "agent"
check_nl "English question"   "why is my build failing?"             "agent"
check_nl "English deploy"     "deploy the app to staging"            "agent"

# ══════════════════════════════════════════════════════════════════════════════
section "5 · CLI — shellish version / status / help"
# ══════════════════════════════════════════════════════════════════════════════
# Override config lookup in the binary via env
export SHELLISH_CONFIG_DIR="$SHELLISH_TEST_CONFIG/shellish"

assert_output_contains "shellish version prints version" "0\." \
  "$BIN" version

assert_output_contains "shellish help shows USAGE" "USAGE" \
  "$BIN" help

assert_output_contains "shellish status shows agents" "pi" \
  "$BIN" status

assert_output_contains "shellish status shows config file path" "config" \
  "$BIN" status

# ══════════════════════════════════════════════════════════════════════════════
section "6 · CLI --from-shell routing"
# ══════════════════════════════════════════════════════════════════════════════
info "Testing --from-shell: typo should exit 127, NL should call agent"
echo ""

# typo → exit 127, stderr contains "command not found"
TOTAL=$((TOTAL+1))
actual_exit=0
actual_stderr=$("$BIN" --from-shell "gti status" 2>&1 >/dev/null) || actual_exit=$?
if [[ "$actual_exit" == "127" ]]; then
  pass "--from-shell typo exits 127"
else
  fail "--from-shell typo: expected exit 127, got $actual_exit"
fi

TOTAL=$((TOTAL+1))
if echo "$actual_stderr" | grep -qi "command not found"; then
  pass "--from-shell typo prints 'command not found'"
else
  fail "--from-shell typo: expected 'command not found' in stderr, got: $actual_stderr"
fi

# NL → agent is invoked (pi will run and produce output, exit 0)
TOTAL=$((TOTAL+1))
nl_out=$("$BIN" --from-shell "帮我列出当前目录" 2>&1) || true
if echo "$nl_out" | grep -qi "pi\|shellish\|directory\|目录\|文件\|bin\|lib"; then
  pass "--from-shell Chinese NL routes to pi and gets output"
else
  fail "--from-shell Chinese NL: unexpected output: $(echo "$nl_out" | head -3)"
fi

# ══════════════════════════════════════════════════════════════════════════════
section "7 · AGENT DETECTION — agent.sh"
# ══════════════════════════════════════════════════════════════════════════════
source "${LIB}/agent.sh"

TOTAL=$((TOTAL+1))
detected="$(shellish_detect_agents)"
if echo "$detected" | grep -q "pi"; then
  pass "shellish_detect_agents finds pi"
else
  fail "shellish_detect_agents did not find pi (got: '$detected')"
fi

# ══════════════════════════════════════════════════════════════════════════════
section "8 · EDGE CASES"
# ══════════════════════════════════════════════════════════════════════════════

# Empty input
TOTAL=$((TOTAL+1))
empty_out=$( "$BIN" "" 2>&1 ) || true
if echo "$empty_out" | grep -q "Empty prompt"; then
  pass "empty prompt rejected with message"
else
  fail "empty prompt should print error message (got: $empty_out)"
fi

# --from-shell with empty string → should exit 127 (not NL)
TOTAL=$((TOTAL+1))
empty_shell_exit=0
"$BIN" --from-shell "" 2>/dev/null || empty_shell_exit=$?
if [[ "$empty_shell_exit" == "127" || "$empty_shell_exit" == "1" ]]; then
  pass "--from-shell empty string returns non-zero"
else
  fail "--from-shell empty string: unexpected exit $empty_shell_exit"
fi

# shellish run with no agent configured → clear error
TOTAL=$((TOTAL+1))
config_set agent ""
no_agent_out=$("$BIN" "do something" 2>&1) || true
if echo "$no_agent_out" | grep -qi "not configured\|setup\|config"; then
  pass "no agent configured → helpful error shown"
else
  fail "no agent configured: expected setup prompt, got: $no_agent_out"
fi
config_set agent pi   # restore

# ══════════════════════════════════════════════════════════════════════════════
section "RESULTS"
# ══════════════════════════════════════════════════════════════════════════════
echo ""
PASSED=$((TOTAL - FAILURES))
if [[ "$FAILURES" -eq 0 ]]; then
  printf "  ${GREEN}${BOLD}All $TOTAL tests passed.${RESET}\n"
else
  printf "  ${RED}${BOLD}$FAILURES / $TOTAL tests FAILED.${RESET}\n"
fi
echo ""
exit "$FAILURES"
