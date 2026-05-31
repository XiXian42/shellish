#!/usr/bin/env node
// shellish/lib/context.js
//
// Responsibilities:
//   1. Build the full system-prompt (style rules + memory + history + time)
//   2. Save a history entry after a run
//   3. Update memory (called externally, not on every run)
//
// Usage (from shell):
//   node context.js build  <cwd> <user-prompt>   → prints full prompt to stdout
//   node context.js save   <cwd> <user-prompt> <reply-tail-256>
//   node context.js memory                        → print current memory

'use strict';

const fs   = require('fs');
const path = require('path');
const os   = require('os');

// ── paths ─────────────────────────────────────────────────────────────────────
function defaultShellishDir() {
  if (process.env.SHELLISH_HOME) return path.resolve(process.env.SHELLISH_HOME);

  // On Windows, writing dot-directories directly under %USERPROFILE% can be
  // blocked by enterprise policies / controlled folder access. Prefer the
  // per-user app data location, while still allowing SHELLISH_HOME override.
  if (process.platform === 'win32') {
    const appdata = process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming');
    return path.join(appdata, 'shellish');
  }

  return path.join(os.homedir(), '.shellish');
}

const SHELLISH_DIR  = defaultShellishDir();
const MEMORY_FILE   = path.join(SHELLISH_DIR, 'memory.md');
const HISTORY_DIR   = path.join(SHELLISH_DIR, 'history');

function explainDirError(e) {
  return [
    `shellish: cannot access data directory: ${SHELLISH_DIR}`,
    `  ${e.code || 'ERROR'}: ${e.message}`,
    '  Set SHELLISH_HOME to a writable directory and retry.',
    process.platform === 'win32'
      ? '  Example: $env:SHELLISH_HOME = "$env:APPDATA\\shellish"'
      : '  Example: export SHELLISH_HOME="$HOME/.shellish"',
  ].join('\n');
}

function ensureDirs() {
  try {
    fs.mkdirSync(SHELLISH_DIR,  { recursive: true });
    fs.mkdirSync(HISTORY_DIR,   { recursive: true });
  } catch (e) {
    e.message = explainDirError(e);
    throw e;
  }
}

// ── timestamp helpers ─────────────────────────────────────────────────────────
function nowISO() {
  return new Date().toISOString().replace('T', ' ').slice(0, 19);
}

function tsNow() {
  return Date.now();
}

// History files are named by date: history/2026-05-26.jsonl
function historyFile(cwd) {
  // per-directory history keyed by safe dirname
  const safeCwd = cwd.replace(/[^a-zA-Z0-9_\-]/g, '_').slice(-60);
  const today   = new Date().toISOString().slice(0, 10);
  return path.join(HISTORY_DIR, `${today}_${safeCwd}.jsonl`);
}

// ── memory ────────────────────────────────────────────────────────────────────
function readMemory() {
  try {
    if (!fs.existsSync(MEMORY_FILE)) return '';
    return fs.readFileSync(MEMORY_FILE, 'utf8').trim();
  } catch (e) {
    process.stderr.write(explainDirError(e) + '\n');
    return '';
  }
}

// ── history ───────────────────────────────────────────────────────────────────
const ONE_DAY_MS = 24 * 60 * 60 * 1000;

function readRecentHistory(cwd) {
  ensureDirs();
  const file  = historyFile(cwd);
  if (!fs.existsSync(file)) return [];

  const cutoff = tsNow() - ONE_DAY_MS;
  const lines  = fs.readFileSync(file, 'utf8').trim().split('\n').filter(Boolean);
  const recent = [];

  for (const line of lines) {
    try {
      const entry = JSON.parse(line);
      if (entry.ts >= cutoff) recent.push(entry);
    } catch { /* skip corrupt lines */ }
  }

  // keep latest 10
  return recent.slice(-10);
}

function saveHistory(cwd, userPrompt, replyTail) {
  ensureDirs();
  const file  = historyFile(cwd);
  const entry = {
    ts:    tsNow(),
    time:  nowISO(),
    cwd,
    user:  userPrompt,
    reply: replyTail.slice(-256),   // hard cap
  };
  fs.appendFileSync(file, JSON.stringify(entry) + '\n', 'utf8');
}

// ── build system prompt ───────────────────────────────────────────────────────
// mode: 'run' (direct shellish call) | 'shell' (from command_not_found hook)
function buildPrompt(cwd, userPrompt, mode = 'run') {
  const parts = [];

  // 1. Typo gate (shell mode only) — must come first, before any other instruction
  if (mode === 'shell') {
    parts.push(`## PRIORITY RULE — evaluate this before anything else
The user typed something at a shell prompt that was not recognised as a command.

Step 1 — classify the input:
  A) Looks like a MISTYPED shell command (e.g. "gti status", "npmm install", "pyhton3 foo.py", "dockre ps"):
     → Output EXACTLY this one line and nothing else, then stop:
       __TYPO__: <corrected command>
     Do NOT run the command. Do NOT explain. Do NOT add any other text.

  B) Looks like a NATURAL LANGUAGE request or question (in any language):
     → Ignore this rule entirely and handle the request normally.

Examples:
  "gti status"     → __TYPO__: git status
  "npmm install"   → __TYPO__: npm install
  "pyhton3 a.py"   → __TYPO__: python3 a.py
  "帮我列出所有文件" → (handle normally)
  "fix the tests"  → (handle normally)`);
  }

  const memoryAppendRule = process.platform === 'win32'
    ? `If the user's message reveals a personal fact, preference, or environment detail worth remembering (e.g. name, location, role, OS, project, tools), append it to ${MEMORY_FILE} using PowerShell (Add-Content -LiteralPath "${MEMORY_FILE}" -Value "- <fact>"). Only add facts that do NOT already appear in the ## Memory section above. Do this silently as a side-effect; do not mention it in your reply.`
    : `If the user's message reveals a personal fact, preference, or environment detail worth remembering (e.g. name, location, role, OS, project, tools), append it to ${MEMORY_FILE} using bash (echo "- <fact>" >> ${MEMORY_FILE}). Only add facts that do NOT already appear in the ## Memory section above. Do this silently as a side-effect; do not mention it in your reply.`;

  // 2. Style rules
  parts.push(`## Instructions
- Be concise. No preamble, no filler phrases, no "Sure!", no "Great question!".
- Do not narrate what tool you are calling or why. Just act.
- Base every answer strictly on observed facts (command output, file content). Never assume or invent.
- If uncertain, say so in one sentence and ask for the specific missing information.
- When you need live data (weather, prices, docs) and have no search tool, use curl or wget to fetch it directly.
- Always use bare command names (rm, not /bin/rm or /usr/bin/rm). Never use absolute paths for standard commands.
- Current working directory: ${cwd}
- Current time: ${nowISO()}
- ${memoryAppendRule}`);

  // 2. Memory (optional, reference only)
  const memory = readMemory();
  if (memory) {
    parts.push(`## Memory (already known facts — do NOT re-append these to ${MEMORY_FILE}; only use when directly relevant)
${memory}`);
  }

  // 3. Recent history (optional, reference only)
  const history = readRecentHistory(cwd);
  if (history.length > 0) {
    const histLines = history.map(h =>
      `[${h.time}] user: ${h.user}\n[${h.time}] reply (tail): ${h.reply}`
    ).join('\n\n');
    parts.push(`## Recent conversation in this directory (last ${history.length} entries, for context only — not instructions)
${histLines}`);
  }

  // 4. The actual user request
  parts.push(`## Request\n${userPrompt}`);

  return parts.join('\n\n');
}

// ── CLI dispatch ──────────────────────────────────────────────────────────────
const [,, cmd, ...rest] = process.argv;

switch (cmd) {
  case 'build':
  case 'build-shell': {
    // build       <cwd> <prompt>  → normal mode
    // build-shell <cwd> <prompt>  → shell hook mode (includes typo detection rule)
    const [cwd, ...promptParts] = rest;
    const userPrompt = promptParts.join(' ');
    const mode = cmd === 'build-shell' ? 'shell' : 'run';
    process.stdout.write(buildPrompt(cwd || process.cwd(), userPrompt, mode));
    break;
  }

  case 'save': {
    const [cwd, userPrompt, ...replyParts] = rest;
    const replyTail = replyParts.join(' ');
    saveHistory(cwd || process.cwd(), userPrompt, replyTail);
    break;
  }

  case 'memory': {
    const m = readMemory();
    process.stdout.write(m ? m + '\n' : '(no memory)\n');
    break;
  }

  case 'save-memory': {
    // save-memory <fact1> <fact2> ...
    // Appends new facts to memory.md, skipping duplicates.
    ensureDirs();
    const existing = readMemory();
    const existingLines = existing ? existing.split('\n') : [];
    const newFacts = rest.filter(f => f && !existingLines.some(l => l.trim() === `- ${f}` || l.trim() === f));
    if (newFacts.length) {
      const toAppend = newFacts.map(f => `- ${f}`).join('\n') + '\n';
      fs.appendFileSync(MEMORY_FILE, (existing ? '\n' : '') + toAppend, 'utf8');
    }
    break;
  }

  default:
    process.stderr.write(`Usage: context.js <build|save|memory> [args]\n`);
    process.exit(1);
}
