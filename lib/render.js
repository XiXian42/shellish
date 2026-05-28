#!/usr/bin/env node
// shellish/lib/render.js
// Streaming renderer for pi / omp / claude / codex JSON output.
//
// Usage:
//   pi     -p "..." --mode json        | node render.js --agent pi
//   omp    -p "..." --mode json        | node render.js --agent omp
//   claude -p "..." --output-format stream-json
//                                      | node render.js --agent claude
//   codex  exec --json "..."           | node render.js --agent codex
//
// ── Pi / OMP event shapes ─────────────────────────────────────────────────────
//   turn_start                                                      → thinking spinner
//   message_update + assistantMessageEvent.type = "text_delta"      → stream chars
//   tool_execution_start  { toolName, args }                        → tool + spinner
//   tool_execution_update { partialResult.content }                 → tool output
//   tool_execution_end    { toolName, isError, result.content }     → result line
//   message_end / turn_end / agent_end                              → done
//
// ── Codex event shapes ────────────────────────────────────────────────────────
//   turn.started                                                    → thinking spinner
//   item.started   { item: { type:"command_execution", command } }  → tool + spinner
//   item.completed { item: { type:"command_execution", ... } }      → result line
//   item.completed { item: { type:"agent_message", text } }         → print text
//   turn.completed / message_end / agent_end                        → done
//
// ── Claude event shapes ───────────────────────────────────────────────────────
//   stream_event { type:"message_start" }                           → thinking spinner
//   stream_event { type:"content_block_delta", delta.text }         → stream chars
//   stream_event { type:"message_stop" }                            → stop spinner
//   assistant { message.content[].type = "tool_use"  }              → tool + spinner
//   user      { message.content[].type = "tool_result" }            → result line
//   assistant { message.content[].type = "text" }                   → final-text fallback
//   result / message_end / turn_end / agent_end                     → done

'use strict';

const readline = require('readline');

// ── CLI arg ────────────────────────────────────────────────────────────────────
const AGENT = process.argv.includes('--agent')
  ? process.argv[process.argv.indexOf('--agent') + 1]
  : 'pi';

const SESSION_DIR = process.argv.includes('--session-dir')
  ? process.argv[process.argv.indexOf('--session-dir') + 1]
  : null;

// ── ANSI ──────────────────────────────────────────────────────────────────────
const R = '\x1b[0m', DIM = '\x1b[2m', BOLD = '\x1b[1m',
      CYAN = '\x1b[36m', YELLOW = '\x1b[33m',
      GREEN = '\x1b[32m', RED = '\x1b[31m';

const write = s => process.stdout.write(s);

// ── Spinner ───────────────────────────────────────────────────────────────────
const FRAMES  = ['⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏'];
const SPIN_W  = 64;

const IS_TTY = process.stdout.isTTY;

const spinner = {
  _timer: null,
  _frame: 0,
  _label: '',

  start(label = '') {
    this.stop();
    this._label = label;
    this._frame = 0;
    if (!IS_TTY) return;   // non-tty: no animation, just track state
    this._timer = setInterval(() => {
      // Pause spinner while run.js is showing a confirmation prompt
      if (SESSION_DIR) {
        try {
          require('fs').accessSync(require('path').join(SESSION_DIR, '.prompting'));
          return;  // file exists — skip this frame
        } catch { /* not prompting, continue */ }
      }
      const f = FRAMES[this._frame++ % FRAMES.length];
      write(`\r  ${CYAN}${f}${R}  ${DIM}${this._label}${R}`);
    }, 80);
  },

  stop() {
    if (this._timer) {
      clearInterval(this._timer);
      this._timer = null;
      write('\r' + ' '.repeat(SPIN_W) + '\r');  // erase spinner line
    }
    this._label = '';
  },

  get running() { return IS_TTY ? this._timer !== null : this._label !== ''; },
};

// ── output state ──────────────────────────────────────────────────────────────
let needNl      = false;
let textBuf     = '';     // buffer early text to detect __TYPO__ sentinel
let typoChecked = false;

const TYPO_RE = /^__TYPO__:\s*(.+)/;

function ensureNl() {
  if (needNl) { write('\n'); needNl = false; }
}

// All text output goes through here.
// Buffers until we can confirm whether it starts with __TYPO__.
function emitText(s) {
  if (typoChecked) {
    if (spinner.running) spinner.stop();
    write(s);
    needNl = s.length > 0 && !s.endsWith('\n');
    return;
  }

  textBuf += s;

  // Fast path: typo sentinel always starts with "__TYPO__:".
  // If the first char is not "_", this cannot be a typo correction, so flush
  // immediately and preserve real streaming for normal answers.
  if (!textBuf.startsWith('_')) {
    typoChecked = true;
    if (spinner.running) spinner.stop();
    write(textBuf);
    needNl = textBuf.length > 0 && !textBuf.endsWith('\n');
    textBuf = '';
    return;
  }

  // It starts with "_" — wait until we can tell whether it is the sentinel.
  const sentinelPrefix = '__TYPO__:';
  const firstNl = textBuf.indexOf('\n');
  if (textBuf.startsWith(sentinelPrefix) && firstNl === -1) return;
  if (sentinelPrefix.startsWith(textBuf) && firstNl === -1) return;

  const firstLine = firstNl !== -1 ? textBuf.slice(0, firstNl) : textBuf;
  const m = firstLine.match(TYPO_RE);

  if (m) {
    spinner.stop();
    const corrected = m[1].trim();
    write(`\n  ${DIM}did you mean:${R}  ${BOLD}${corrected}${R}\n\n`);
    process.exit(127);
  }

  // Not a typo — flush and continue
  typoChecked = true;
  if (spinner.running) spinner.stop();
  write(textBuf);
  needNl = textBuf.length > 0 && !textBuf.endsWith('\n');
  textBuf = '';
}

// ── shared helpers ─────────────────────────────────────────────────────────────
function fmtCmd(cmd) {
  cmd = (cmd || '').replace(/\n/g, ' ').trim();
  return cmd.length > 80 ? cmd.slice(0, 80) + '…' : cmd;
}

function printToolStart(name, cmdBrief) {
  spinner.stop();
  ensureNl();
  write(`\n  ${DIM}⚙  ${YELLOW}${name}${R}${DIM}  ${cmdBrief}${R}\n`);
  needNl = false;
  spinner.start(`running ${name}  ${cmdBrief}`);
}

function printToolOutput(out) {
  if (!out) return;
  spinner.stop();
  ensureNl();
  const lines = String(out).replace(/\n$/, '').split('\n');
  for (const line of lines) write(`  ${DIM}│ ${line}${R}\n`);
  needNl = false;
  spinner.start('thinking…');
}

function printToolEnd(isErr, out) {
  spinner.stop();
  const icon = isErr ? `${RED}✗${R}` : `${GREEN}✓${R}`;
  if (out) {
    const lines   = out.trim().split('\n');
    const preview = lines[0].slice(0, 120);
    const more    = lines.length > 1 ? `  ${DIM}(+${lines.length - 1} lines)${R}` : '';
    write(`  ${icon}  ${DIM}${preview}${more}${R}\n`);
  } else {
    write(`  ${icon}  ${DIM}(done)${R}\n`);
  }
  needNl = false;
}

// ── Pi handlers ───────────────────────────────────────────────────────────────
function handlePi(obj) {
  const t = obj.type || '';

  if (t === 'turn_start') {
    spinner.start('thinking…');
    return;
  }

  if (t === 'message_update') {
    const ame = obj.assistantMessageEvent || {};
    if (ame.type === 'text_delta') emitText(ame.delta || '');
    return;
  }

  if (t === 'tool_execution_start') {
    const name = obj.toolName || '?';
    const args = obj.args || {};
    const cmd  = args.command
      ? fmtCmd(args.command)
      : args.path || Object.values(args)[0] || '';
    printToolStart(name, cmd);
    return;
  }

  if (t === 'tool_execution_update') {
    const texts = (obj.partialResult?.content || [])
      .filter(c => c.type === 'text').map(c => c.text).join('');
    printToolOutput(texts);
    return;
  }

  if (t === 'tool_execution_end') {
    const isErr  = !!obj.isError;
    const texts  = (obj.result?.content || [])
      .filter(c => c.type === 'text').map(c => c.text);
    printToolEnd(isErr, texts.join(''));
    spinner.start('thinking…');
    return;
  }

  if (t === 'message_end' || t === 'turn_end' || t === 'agent_end') {
    spinner.stop();
    ensureNl();
    return;
  }

  return;
}

// ── Codex handlers ────────────────────────────────────────────────────────────
// Track which item IDs we've already shown a tool-start for
const _codexSeen = new Set();

function handleCodex(obj) {
  const t    = obj.type || '';
  const item = obj.item || {};

  if (t === 'turn.started') {
    spinner.start('thinking…');
    return;
  }

  if (t === 'item.started' && item.type === 'command_execution') {
    _codexSeen.add(item.id);
    printToolStart('bash', fmtCmd(item.command || ''));
    return;
  }

  if (t === 'item.completed' && item.type === 'command_execution') {
    const isErr = item.exit_code !== 0;
    printToolEnd(isErr, item.aggregated_output || '');
    spinner.start('thinking…');
    return;
  }

  if (t === 'item.completed' && item.type === 'agent_message') {
    spinner.stop();
    ensureNl();
    emitText((item.text || '') + '\n');
    return;
  }

  if (t === 'turn.completed' || t === 'message_end' || t === 'agent_end') {
    spinner.stop();
    ensureNl();
    return;
  }

  return;
}

let claudeMessageHadDelta = false;

// ── Claude handlers ──────────────────────────────────────────────────────────
function handleClaude(obj) {
  const t = obj.type || '';

  if (t === 'system') return;

  if (t === 'stream_event') {
    const event = obj.event || {};
    if (event.type === 'message_start') {
      claudeMessageHadDelta = false;
      spinner.start('thinking…');
      return;
    }
    if (event.type === 'content_block_delta' && event.delta?.type === 'text_delta') {
      claudeMessageHadDelta = true;
      emitText(event.delta.text || '');
      return;
    }
    if (event.type === 'message_stop') {
      spinner.stop();
      ensureNl();
      return;
    }
    return;
  }

  if (t === 'assistant') {
    const content = obj.message?.content || [];
    for (const c of content) {
      if (c.type === 'tool_use') {
        const name = c.name || '?';
        const inp  = c.input || {};
        const cmd  = inp.command ? fmtCmd(inp.command)
                   : inp.path   ? inp.path
                   : String(Object.values(inp)[0] || '');
        printToolStart(name, cmd);
      }
      if (c.type === 'text' && c.text && !claudeMessageHadDelta) {
        spinner.stop();
        ensureNl();
        emitText(c.text + (c.text.endsWith('\n') ? '' : '\n'));
      }
    }
    return;
  }

  if (t === 'user') {
    const content = obj.message?.content || [];
    for (const c of content) {
      if (c.type === 'tool_result') {
        const isErr = !!c.is_error;
        const raw   = c.content;
        const out   = Array.isArray(raw)
          ? raw.filter(x => x.type === 'text').map(x => x.text).join('')
          : String(raw || '');
        printToolEnd(isErr, out);
        spinner.start('thinking…');
      }
    }
    return;
  }

  if (t === 'result' || t === 'message_end' || t === 'turn_end' || t === 'agent_end') {
    spinner.stop();
    ensureNl();
    return;
  }

  return;
}

// ── main ──────────────────────────────────────────────────────────────────────
// Start spinner immediately — stopped as soon as first text or tool arrives
spinner.start('thinking…');

const rl = readline.createInterface({ input: process.stdin, crlfDelay: Infinity });

rl.on('line', raw => {
  raw = raw.trim();
  if (!raw) return;
  let obj;
  try { obj = JSON.parse(raw); } catch { return; }
  if      (AGENT === 'codex')  handleCodex(obj);
  else if (AGENT === 'claude') handleClaude(obj);
  else                         handlePi(obj);
});

rl.on('close', () => {
  // Flush any remaining buffered text (handles case where sentinel arrives
  // without a trailing newline and no more data follows)
  if (!typoChecked && textBuf) {
    const m = textBuf.match(TYPO_RE);
    if (m) {
      spinner.stop();
      write(`\n  ${DIM}did you mean:${R}  ${BOLD}${m[1].trim()}${R}\n\n`);
      process.exit(127);
    }
    // not a typo — flush
    typoChecked = true;
    if (spinner.running) spinner.stop();
    write(textBuf);
    needNl = !textBuf.endsWith('\n');
    textBuf = '';
  }
  spinner.stop();
  ensureNl();
});

process.on('SIGINT', () => { spinner.stop(); ensureNl(); process.exit(130); });
