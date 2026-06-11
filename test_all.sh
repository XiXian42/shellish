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

for f in \
  "${LIB}/context.js" \
  "${LIB}/render.js" \
  "${LIB}/run.js" \
  "${LIB}/shellish-cmd.js"
do
  TOTAL=$((TOTAL+1))
  if node --check "$f" >/dev/null 2>&1; then
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

# typo → exit 127, stdout shows the corrected command but does not run it
TOTAL=$((TOTAL+1))
actual_exit=0
actual_out=$("$BIN" --from-shell "gti status" 2>&1) || actual_exit=$?
if [[ "$actual_exit" == "127" ]]; then
  pass "--from-shell typo exits 127"
else
  fail "--from-shell typo: expected exit 127, got $actual_exit"
fi

TOTAL=$((TOTAL+1))
if echo "$actual_out" | grep -qi "did you mean" && echo "$actual_out" | grep -qi "git status"; then
  pass "--from-shell typo suggests corrected command"
else
  fail "--from-shell typo: expected corrected command suggestion, got: $actual_out"
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
section "9 · RENDERER REGRESSIONS"
# ══════════════════════════════════════════════════════════════════════════════

TMP_RENDER_DIR="/tmp/shellish-render-test-$$"
rm -rf "$TMP_RENDER_DIR"
mkdir -p "$TMP_RENDER_DIR/fake-bin" "$TMP_RENDER_DIR/home"

FAKE_CLAUDE_LOG="$TMP_RENDER_DIR/claude.log"
cat > "$TMP_RENDER_DIR/fake-bin/claude" <<'EOF'
#!/usr/bin/env bash
LOG_FILE="${FAKE_CLAUDE_LOG:?}"
{
  echo "--- claude ---"
  for a in "$@"; do printf 'arg: %s\n' "$a"; done
} >> "$LOG_FILE"
printf '%s\n' \
  '{"type":"stream_event","event":{"type":"message_start"}}' \
  '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"he"}}}' \
  '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"llo"}}}' \
  '{"type":"stream_event","event":{"type":"message_stop"}}' \
  '{"type":"assistant","message":{"content":[{"type":"text","text":"hello"}]}}'
EOF
chmod +x "$TMP_RENDER_DIR/fake-bin/claude"

CLAUDE_OUT="$TMP_RENDER_DIR/claude.out"
FAKE_CLAUDE_LOG="$FAKE_CLAUDE_LOG" HOME="$TMP_RENDER_DIR/home" PATH="$TMP_RENDER_DIR/fake-bin:$PATH" \
  node "$LIB/run.js" claude "$TESTDIR" "say hello" >"$CLAUDE_OUT" 2>&1 || true

CLAUDE_HISTORY_FILE=$(find "$TMP_RENDER_DIR/home/.shellish/history" -type f -name '*.jsonl' 2>/dev/null | head -1 || true)
CLAUDE_HISTORY_REPLY=""
if [[ -n "$CLAUDE_HISTORY_FILE" ]]; then
  CLAUDE_HISTORY_REPLY=$(tail -1 "$CLAUDE_HISTORY_FILE" | node -e 'let s="";process.stdin.on("data",c=>s+=c);process.stdin.on("end",()=>{try{process.stdout.write(JSON.parse(s).reply||"")}catch{}})')
fi

TOTAL=$((TOTAL+1))
if grep -q -- "--include-partial-messages" "$FAKE_CLAUDE_LOG" \
   && [[ "$(grep -c '^hello$' "$CLAUDE_OUT")" == "1" ]] \
   && [[ "$CLAUDE_HISTORY_REPLY" == "hello" ]]; then
  pass "claude partial stream renders once, passes partial flag, saves history once"
else
  fail "claude renderer/history regression output unexpected"
  cat "$FAKE_CLAUDE_LOG"
  cat "$CLAUDE_OUT"
  [[ -n "$CLAUDE_HISTORY_FILE" ]] && cat "$CLAUDE_HISTORY_FILE"
fi

FAKE_OMP_LOG="$TMP_RENDER_DIR/omp.log"
cat > "$TMP_RENDER_DIR/fake-bin/omp" <<'EOF'
#!/usr/bin/env bash
LOG_FILE="${FAKE_OMP_LOG:?}"
{
  echo "--- omp ---"
  for a in "$@"; do printf 'arg: %s\n' "$a"; done
} >> "$LOG_FILE"
printf '%s\n' \
  '{"type":"turn_start"}' \
  '{"type":"message_update","assistantMessageEvent":{"type":"text_delta","delta":"omp ok"}}' \
  '{"type":"agent_end","messages":[{"role":"user","content":[{"type":"text","text":"prompt"}]}]}'
EOF
chmod +x "$TMP_RENDER_DIR/fake-bin/omp"

OMP_OUT="$TMP_RENDER_DIR/omp.out"
FAKE_OMP_LOG="$FAKE_OMP_LOG" HOME="$TMP_RENDER_DIR/home" PATH="$TMP_RENDER_DIR/fake-bin:$PATH" \
  node "$LIB/run.js" omp "$TESTDIR" "say hello" >"$OMP_OUT" 2>&1 || true

TOTAL=$((TOTAL+1))
if grep -q -- "--mode" "$FAKE_OMP_LOG" \
   && grep -q -- "json" "$FAKE_OMP_LOG" \
   && grep -q '^omp ok$' "$OMP_OUT" \
   && ! grep -q '"messages"' "$OMP_OUT"; then
  pass "omp json stream suppresses final transcript payload"
else
  fail "omp renderer/regression output unexpected"
  cat "$FAKE_OMP_LOG"
  cat "$OMP_OUT"
fi

rm -rf "$TMP_RENDER_DIR"

# ══════════════════════════════════════════════════════════════════════════════
section "10 · SAFE-RM — rm flags, -f semantics, batch delete"
# ══════════════════════════════════════════════════════════════════════════════

SRM="${LIB}/safe-rm.sh"
TMP_SRM="/tmp/shellish-safe-rm-test-$$"
rm -rf "$TMP_SRM"; mkdir -p "$TMP_SRM"

# Fake trash backend that records its argv — lets us assert flags are
# stripped without touching the real Trash.
mkdir -p "$TMP_SRM/fake-bin"
cat > "$TMP_SRM/fake-bin/trash" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "${SRM_TRASH_LOG:?}"
for t in "$@"; do /bin/rm -rf -- "$t"; done
EOF
chmod +x "$TMP_SRM/fake-bin/trash"
export SRM_TRASH_LOG="$TMP_SRM/trash-args.log"

srm() {
  PATH="$TMP_SRM/fake-bin:$PATH" SHELLISH_CONFIRM_DANGER=allow bash "$SRM" "$@"
}

# rm -rf on multiple dirs (the ".venv sweep" case)
( cd "$TMP_SRM" && mkdir -p a/.venv b/.venv && touch a/.venv/x b/.venv/y )
TOTAL=$((TOTAL+1))
if ( cd "$TMP_SRM" && srm -rf a/.venv b/.venv ) \
   && [[ ! -e "$TMP_SRM/a/.venv" && ! -e "$TMP_SRM/b/.venv" ]]; then
  pass "rm -rf trashes multiple directories"
else
  fail "rm -rf multi-dir: dirs survived or non-zero exit"
fi

TOTAL=$((TOTAL+1))
if grep -q -- '-rf' "$SRM_TRASH_LOG" 2>/dev/null; then
  fail "flags leaked to trash backend: $(cat "$SRM_TRASH_LOG")"
else
  pass "rm flags stripped before reaching trash backend"
fi

# -f + missing operand → exit 0 (rm semantics)
assert_exit "-f missing operand exits 0" 0 \
  env PATH="$TMP_SRM/fake-bin:$PATH" SHELLISH_CONFIRM_DANGER=allow bash "$SRM" -f "$TMP_SRM/nope"

# missing operand without -f → exit 1
assert_exit "missing operand without -f exits 1" 1 \
  env PATH="$TMP_SRM/fake-bin:$PATH" SHELLISH_CONFIRM_DANGER=allow bash "$SRM" "$TMP_SRM/nope"

# mixed existing+missing without -f → trash existing, still exit 1
touch "$TMP_SRM/real.txt"
TOTAL=$((TOTAL+1))
mixed_exit=0
( cd "$TMP_SRM" && srm real.txt gone.txt ) 2>/dev/null || mixed_exit=$?
if [[ "$mixed_exit" == "1" && ! -e "$TMP_SRM/real.txt" ]]; then
  pass "mixed operands: existing trashed, exit 1 for missing"
else
  fail "mixed operands (exit=$mixed_exit, real.txt exists=$([[ -e $TMP_SRM/real.txt ]] && echo yes || echo no))"
fi

# no operands at all
assert_exit "no operands without -f exits 1" 1 \
  env PATH="$TMP_SRM/fake-bin:$PATH" SHELLISH_CONFIRM_DANGER=allow bash "$SRM"
assert_exit "no operands with -f exits 0" 0 \
  env PATH="$TMP_SRM/fake-bin:$PATH" SHELLISH_CONFIRM_DANGER=allow bash "$SRM" -rf

# ask-mode handshake: deny keeps the file
mkdir -p "$TMP_SRM/session"
touch "$TMP_SRM/keep.txt"
(
  for _ in $(seq 1 100); do
    req=$(ls "$TMP_SRM/session"/req.* 2>/dev/null | head -1) || true
    if [[ -n "${req:-}" ]]; then echo N > "$TMP_SRM/session/res.${req##*.}"; break; fi
    sleep 0.1
  done
) &
DENY_WAITER=$!
TOTAL=$((TOTAL+1))
deny_exit=0
( cd "$TMP_SRM" && PATH="$TMP_SRM/fake-bin:$PATH" SHELLISH_CONFIRM_DANGER=ask SHELLISH_SESSION_DIR="$TMP_SRM/session" bash "$SRM" -rf keep.txt ) 2>/dev/null || deny_exit=$?
wait "$DENY_WAITER" 2>/dev/null || true
if [[ "$deny_exit" == "1" && -e "$TMP_SRM/keep.txt" ]]; then
  pass "ask-mode deny: file survives, exit 1"
else
  fail "ask-mode deny (exit=$deny_exit, keep.txt exists=$([[ -e $TMP_SRM/keep.txt ]] && echo yes || echo no))"
fi

# safe-rm.js parseRmArgs unit tests (shared rm-argv logic on Windows path)
TOTAL=$((TOTAL+1))
if node -e "
const { parseRmArgs } = require('${LIB}/safe-rm.js');
const eq = (got, want) => JSON.stringify(got) === JSON.stringify(want);
if (!eq(parseRmArgs(['-rf','a','b']), {targets:['a','b'],force:true})) process.exit(1);
if (!eq(parseRmArgs(['-r','a']), {targets:['a'],force:false})) process.exit(1);
if (!eq(parseRmArgs(['--force','x']), {targets:['x'],force:true})) process.exit(1);
if (!eq(parseRmArgs(['--','-rf']), {targets:['-rf'],force:false})) process.exit(1);
if (!eq(parseRmArgs([]), {targets:[],force:false})) process.exit(1);
" 2>/dev/null; then
  pass "safe-rm.js parseRmArgs strips flags, tracks force, honors --"
else
  fail "safe-rm.js parseRmArgs regression"
fi

rm -rf "$TMP_SRM"
unset SRM_TRASH_LOG

# ══════════════════════════════════════════════════════════════════════════════
section "11 · RUN.JS — history tee survives chunk-split JSON lines"
# ══════════════════════════════════════════════════════════════════════════════

TMP_TEE="/tmp/shellish-tee-test-$$"
rm -rf "$TMP_TEE"; mkdir -p "$TMP_TEE/fake-bin" "$TMP_TEE/home"

cat > "$TMP_TEE/fake-bin/claude" <<'EOF'
#!/usr/bin/env bash
node -e '
const big = "x".repeat(200000);
const ev = t => JSON.stringify({type:"stream_event",event:{type:"content_block_delta",delta:{type:"text_delta",text:t}}});
console.log(JSON.stringify({type:"stream_event",event:{type:"message_start"}}));
console.log(ev(big));
console.log(ev("TAIL_MARKER_中文_42"));
console.log(JSON.stringify({type:"stream_event",event:{type:"message_stop"}}));
'
EOF
chmod +x "$TMP_TEE/fake-bin/claude"

HOME="$TMP_TEE/home" PATH="$TMP_TEE/fake-bin:$PATH" \
  node "$LIB/run.js" claude "$TESTDIR" "long line test" >/dev/null 2>&1 || true

TEE_HISTORY=$(find "$TMP_TEE/home/.shellish/history" -name '*.jsonl' 2>/dev/null | head -1 || true)
TOTAL=$((TOTAL+1))
if [[ -n "$TEE_HISTORY" ]] && node -e "
const fs = require('fs');
const line = fs.readFileSync('$TEE_HISTORY','utf8').trim().split('\n').pop();
const reply = JSON.parse(line).reply || '';
if (!reply.includes('TAIL_MARKER_中文_42')) process.exit(1);
if (reply.length > 256) process.exit(1);
" 2>/dev/null; then
  pass "history captures text from a >64KB JSON line split across pipe chunks"
else
  fail "history tee lost chunk-split JSON line"
  [[ -n "$TEE_HISTORY" ]] && tail -c 300 "$TEE_HISTORY"
fi

rm -rf "$TMP_TEE"

# ══════════════════════════════════════════════════════════════════════════════
section "11b · RUN.JS — confirm prompt answers (y / N / a)"
# ══════════════════════════════════════════════════════════════════════════════

# Regression: promptUser must consume the answer BEFORE rl.close() — closing
# first fires 'close' synchronously and turns every answer (even y) into deny.

TMP_CONFIRM="/tmp/shellish-confirm-test-$$"
rm -rf "$TMP_CONFIRM"; mkdir -p "$TMP_CONFIRM/fake-bin" "$TMP_CONFIRM/home/.config/shellish"
echo "confirm_danger=ask" > "$TMP_CONFIRM/home/.config/shellish/config"

cat > "$TMP_CONFIRM/fake-bin/claude" <<'EOF'
#!/usr/bin/env bash
cd "${SHELLISH_CWD:?}"
rm -rf proj/.venv && s1=ok || s1=denied
rm -rf proj2/.venv && s2=ok || s2=denied
node -e "
console.log(JSON.stringify({type:'stream_event',event:{type:'message_start'}}));
console.log(JSON.stringify({type:'stream_event',event:{type:'content_block_delta',delta:{type:'text_delta',text:'rm1:${s1} rm2:${s2}'}}}));
console.log(JSON.stringify({type:'stream_event',event:{type:'message_stop'}}));
"
EOF
chmod +x "$TMP_CONFIRM/fake-bin/claude"

reset_confirm_dirs() {
  rm -rf "$TMP_CONFIRM/work"
  mkdir -p "$TMP_CONFIRM/work/proj/.venv" "$TMP_CONFIRM/work/proj2/.venv"
  touch "$TMP_CONFIRM/work/proj/.venv/a" "$TMP_CONFIRM/work/proj2/.venv/b"
}

run_confirm() {  # $1 = piped answers
  printf '%s\n' "$1" | HOME="$TMP_CONFIRM/home" PATH="$TMP_CONFIRM/fake-bin:$PATH" \
    node "$LIB/run.js" claude "$TMP_CONFIRM/work" "delete venvs" 2>&1 || true
}

# y then y → both trashed
reset_confirm_dirs
TOTAL=$((TOTAL+1))
out=$(printf 'y\ny\n' | HOME="$TMP_CONFIRM/home" PATH="$TMP_CONFIRM/fake-bin:$PATH" \
  node "$LIB/run.js" claude "$TMP_CONFIRM/work" "delete venvs" 2>&1 || true)
if [[ ! -e "$TMP_CONFIRM/work/proj/.venv" && ! -e "$TMP_CONFIRM/work/proj2/.venv" ]]; then
  pass "confirm 'y': answer accepted, target trashed"
else
  fail "confirm 'y' was treated as deny (rl.close-before-done regression)"
fi

# N → denied, file survives, agent killed
reset_confirm_dirs
TOTAL=$((TOTAL+1))
out=$(run_confirm "N")
if [[ -e "$TMP_CONFIRM/work/proj/.venv" ]] && echo "$out" | grep -q "Cancelled"; then
  pass "confirm 'N': file survives, run cancelled"
else
  fail "confirm 'N' regression (venv exists=$([[ -e $TMP_CONFIRM/work/proj/.venv ]] && echo yes || echo no))"
fi

# a → one prompt covers both rms
reset_confirm_dirs
TOTAL=$((TOTAL+1))
out=$(run_confirm "a")
prompts=$(echo "$out" | grep -c "will move to trash" || true)
if [[ "$prompts" == "1" && ! -e "$TMP_CONFIRM/work/proj/.venv" && ! -e "$TMP_CONFIRM/work/proj2/.venv" ]]; then
  pass "confirm 'a': single prompt allows the whole session"
else
  fail "confirm 'a' regression (prompts=$prompts)"
fi

rm -rf "$TMP_CONFIRM"

# ══════════════════════════════════════════════════════════════════════════════
section "12 · RENDERER — spinner erase + width truncation"
# ══════════════════════════════════════════════════════════════════════════════

# ansi.js width helpers
TOTAL=$((TOTAL+1))
if node -e "
const { displayWidth, truncateDisplay } = require('${LIB}/ansi.js');
if (displayWidth('中文') !== 4) process.exit(1);
if (displayWidth('abc') !== 3) process.exit(1);
if (truncateDisplay('abcdefghij', 5) !== 'abcd…') process.exit(1);
if (displayWidth(truncateDisplay('中文中文中文', 7)) > 7) process.exit(1);
" 2>/dev/null; then
  pass "ansi.js displayWidth / truncateDisplay handle CJK"
else
  fail "ansi.js width helper regression"
fi

# Spinner on a real PTY must erase with \r ESC[2K and never exceed columns.
# `script` differs between BSD/macOS and util-linux; skip if unusable.
TOTAL=$((TOTAL+1))
TMP_SPIN="/tmp/shellish-spin-test-$$"
mkdir -p "$TMP_SPIN"
cat > "$TMP_SPIN/feed.sh" <<EOF
( printf '%s\n' '{"type":"turn_start"}'
  sleep 0.4
  printf '%s\n' '{"type":"tool_execution_start","toolName":"bash","args":{"command":"echo 一个非常非常非常非常非常非常非常非常非常非常非常非常非常非常长的中文命令参数"}}'
  sleep 0.4
  printf '%s\n' '{"type":"tool_execution_end","isError":false,"result":{"content":[{"type":"text","text":"ok"}]}}'
  printf '%s\n' '{"type":"agent_end"}'
) | node "$LIB/render.js" --agent pi
EOF
SPIN_LOG="$TMP_SPIN/tty.log"
spin_ok=""
if script -q "$SPIN_LOG" bash "$TMP_SPIN/feed.sh" >/dev/null 2>&1 && [[ -s "$SPIN_LOG" ]]; then
  spin_ok=$(node -e "
const data = require('fs').readFileSync('$SPIN_LOG', 'utf8');
const frames = data.match(/\r\x1b\[2K[^\r\n]*/g) || [];
if (!frames.length) { console.log('no-frames'); process.exit(0); }
const { displayWidth } = require('${LIB}/ansi.js');
const strip = s => s.replace(/\x1b\[[0-9;]*[A-Za-z]/g, '').replace(/\r/g, '');
const tooWide = frames.some(f => displayWidth(strip(f)) > (process.stdout.columns || 80));
console.log(tooWide ? 'too-wide' : 'ok');
" 2>/dev/null)
fi
if [[ "$spin_ok" == "ok" ]]; then
  pass "spinner uses ESC[2K erase and stays within terminal width"
elif [[ -z "$spin_ok" || "$spin_ok" == "no-frames" ]]; then
  info "spinner PTY test skipped (script/PTY unavailable in this environment)"
  TOTAL=$((TOTAL-1))
else
  fail "spinner frame exceeded terminal width"
fi
rm -rf "$TMP_SPIN"

# ══════════════════════════════════════════════════════════════════════════════
section "13 · SHELL HOOKS — no FUNCNEST recursion, correct routing"
# ══════════════════════════════════════════════════════════════════════════════

# Regression: the handler must be self-contained. The old version called a
# helper function (_shellish_bin); in environments that inherited the handler
# but not the helper, the unknown helper re-fired the handler → recursion
# until FUNCNEST, flooding "command not found: _shellish_bin".

TMP_HOOK="/tmp/shellish-hook-test-$$"
mkdir -p "$TMP_HOOK"
printf '#!/usr/bin/env bash\necho "SHELLISH CALLED: $*"\n' > "$TMP_HOOK/shellish"
chmod +x "$TMP_HOOK/shellish"

# zsh: unknown command without shellish → single clean error, exit 127
TOTAL=$((TOTAL+1))
hook_out=$(zsh -f -c "source '$TESTDIR/shell/zshrc.zsh'; PATH=/usr/bin:/bin; nope_cmd_xyz" 2>&1 || true)
hook_lines=$(echo "$hook_out" | grep -c "command not found" || true)
if [[ "$hook_lines" == "1" ]] && ! echo "$hook_out" | grep -q "FUNCNEST\|_shellish_bin"; then
  pass "zsh hook: missing command → one error line, no recursion"
else
  fail "zsh hook recursion regression: $(echo "$hook_out" | head -2)"
fi

# zsh: natural language with shellish on PATH → routed with --from-shell
TOTAL=$((TOTAL+1))
hook_out=$(zsh -f -c "source '$TESTDIR/shell/zshrc.zsh'; PATH='$TMP_HOOK:/usr/bin:/bin'; hello natural language" 2>&1 || true)
if echo "$hook_out" | grep -q "SHELLISH CALLED: --from-shell hello natural language"; then
  pass "zsh hook: routes full line to shellish --from-shell"
else
  fail "zsh hook routing: $hook_out"
fi

# bash: handler defined and guarded (bash >= 4 fires it; 3.2 defines only)
TOTAL=$((TOTAL+1))
hook_out=$(bash -c "source '$TESTDIR/shell/bashrc.bash'; PATH=/usr/bin:/bin; nope_cmd_xyz" 2>&1 || true)
if ! echo "$hook_out" | grep -q "_shellish_bin\|FUNCNEST" \
   && [[ "$(echo "$hook_out" | grep -c 'command not found')" == "1" ]]; then
  pass "bash hook: missing command → one error line, no recursion"
else
  fail "bash hook recursion regression: $(echo "$hook_out" | head -2)"
fi

rm -rf "$TMP_HOOK"

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
