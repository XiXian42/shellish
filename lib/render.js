#!/usr/bin/env node
// shellish/lib/render.js
// Streaming renderer for pi and codex JSON output.
//
// Usage:
//   pi    -p "..." --mode json        | node render.js --agent pi
//   codex exec --json "..."           | node render.js --agent codex
//
// ── Pi event shapes ───────────────────────────────────────────────────────────
//   message_update + assistantMessageEvent.type = "text_delta"  → stream chars
//   tool_execution_start  { toolName, args }                     → tool + spinner
//   tool_execution_end    { toolName, isError, result.content }  → result line
//   agent_end                                                    → done
//
// ── Codex event shapes ────────────────────────────────────────────────────────
//   turn.started                                                    → thinking spinner
//   item.started   { item: { type:"command_execution", command } }  → tool + spinner
//   item.completed { item: { type:"command_execution", ... } }      → result line
//   item.completed { item: { type:"agent_message", text } }         → print text
//   turn.completed                                                   → done
//
// ── Claude event shapes ───────────────────────────────────────────────────────
//   system                                                          → ignore
//   assistant { message.content[].type = "tool_use"  }             → tool + spinner
//   user      { message.content[].type = "tool_result" }           → result line
//   assistant { message.content[].type = "text" }                  → print text
//   result                                                          → done
//
// Neither codex nor claude has token-level streaming; we show spinners to fill
// the wait and print text whole when it arrives.

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

  // Wait until we have a complete first line or >40 chars (sentinel is short)
  const firstNl = textBuf.indexOf('\n');
  const hasLine = firstNl !== -1;
  const tooLong = textBuf.length > 40;
  if (!hasLine && !tooLong) return;

  const firstLine = hasLine ? textBuf.slice(0, firstNl) : textBuf;
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

  if (t === 'tool_execution_end') {
    const isErr  = !!obj.isError;
    const texts  = (obj.result?.content || [])
      .filter(c => c.type === 'text').map(c => c.text);
    printToolEnd(isErr, texts.join(''));
    return;
  }

  if (t === 'agent_end') {
    spinner.stop();
    ensureNl();
  }
}

// ── Codex handlers ────────────────────────────────────────────────────────────
// Track which item IDs we've already shown a tool-start for
const _codexSeen = new Set();

function handleCodex(obj) {
  const t    = obj.type || '';
  const item = obj.item || {};

  // ── turn.started: start "thinking" spinner immediately ──────────────────
  if (t === 'turn.started') {
    spinner.start('thinking…');
    return;
  }

  // ── command starting ─────────────────────────────────────────────────────
  if (t === 'item.started' && item.type === 'command_execution') {
    _codexSeen.add(item.id);
    printToolStart('bash', fmtCmd(item.command || ''));
    return;
  }

  // ── command finished ─────────────────────────────────────────────────────
  if (t === 'item.completed' && item.type === 'command_execution') {
    const isErr = item.exit_code !== 0;
    printToolEnd(isErr, item.aggregated_output || '');
    // restart thinking spinner — agent is processing the result
    spinner.start('thinking…');
    return;
  }

  // ── agent reply: no token streaming, print whole text ───────────────────
  if (t === 'item.completed' && item.type === 'agent_message') {
    spinner.stop();
    ensureNl();
    emitText((item.text || '') + '\n');
    return;
  }

  // ── all done ─────────────────────────────────────────────────────────────
  if (t === 'turn.completed') {
    spinner.stop();
    ensureNl();
  }
}

// ── Claude handlers ──────────────────────────────────────────────────────────
function handleClaude(obj) {
  const t = obj.type || '';

  if (t === 'system') return;  // ignore noisy hook/init events

  // assistant turn: tool_use or text
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
      if (c.type === 'text' && c.text) {
        spinner.stop();
        ensureNl();
        emitText(c.text + (c.text.endsWith('\n') ? '' : '\n'));
      }
    }
    return;
  }

  // user turn: tool results
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
        spinner.start('thinking…');  // agent is processing the result
      }
    }
    return;
  }

  if (t === 'result') { spinner.stop(); ensureNl(); }
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
