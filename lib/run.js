#!/usr/bin/env node
// shellish/lib/run.js
//
// Orchestrates a single agent call:
//   1. Build full prompt (system rules + memory + history + user request)
//   2. Spawn the agent, pipe JSON output through render.js
//   3. Collect the last 256 chars of rendered text output
//   4. Save to history
//
// Usage:
//   node run.js <agent> <cwd> <user-prompt>
//
// The script exits with the agent's exit code.

'use strict';

const { spawn, execFileSync } = require('child_process');
const path         = require('path');;
const fs           = require('fs');
const os           = require('os');
const readline     = require('readline');

const LIB_DIR      = __dirname;
const CONTEXT_JS   = path.join(LIB_DIR, 'context.js');
const RENDER_JS    = path.join(LIB_DIR, 'render.js');
const SAFE_RM_DIR  = path.join(os.tmpdir(), `shellish-safe-rm-${process.pid}`);

// ── args ──────────────────────────────────────────────────────────────────────
// Usage: node run.js [--from-shell] <agent> <cwd> <user-prompt>
const rawArgs = process.argv.slice(2);
const FROM_SHELL = rawArgs[0] === '--from-shell';
const posArgs    = FROM_SHELL ? rawArgs.slice(1) : rawArgs;
const [AGENT, CWD, ...PROMPT_PARTS] = posArgs;
const USER_PROMPT = PROMPT_PARTS.join(' ');

if (!AGENT || !CWD || !USER_PROMPT) {
  process.stderr.write('Usage: node run.js [--from-shell] <agent> <cwd> <user-prompt>\n');
  process.exit(1);
}

// ── build prompt synchronously via context.js ─────────────────────────────────
function buildPrompt() {
  const buildCmd = FROM_SHELL ? 'build-shell' : 'build';
  try {
    return execFileSync(process.execPath, [CONTEXT_JS, buildCmd, CWD, USER_PROMPT], {
      encoding: 'utf8',
      maxBuffer: 1024 * 1024,
    });
  } catch (e) {
    process.stderr.write(`context.js build failed: ${e.message}\n`);
    return USER_PROMPT;  // fallback to raw prompt
  }
}

// ── save history ───────────────────────────────────────────────────────────────
function saveHistory(replyTail) {
  try {
    execFileSync(process.execPath, [CONTEXT_JS, 'save', CWD, USER_PROMPT, replyTail], {
      encoding: 'utf8',
    });
  } catch { /* non-fatal */ }
}


// ── agent command builder ──────────────────────────────────────────────────────
// ── session / safe-rm setup ──────────────────────────────────────────────────
const SESSION_ID = `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
const ALLOW_FILE = path.join(os.tmpdir(), `.shellish-allow-${SESSION_ID}`);

function getConfirmDanger() {
  try {
    const cfg = fs.readFileSync(
      path.join(os.homedir(), '.config', 'shellish', 'config'), 'utf8');
    const m = cfg.match(/^confirm_danger=(.+)$/m);
    return m ? m[1].trim() : 'ask';
  } catch { return 'ask'; }
}

function setupSafeRmBin() {
  const confirm = getConfirmDanger();
  if (confirm === 'allow') return null;

  fs.mkdirSync(SAFE_RM_DIR, { recursive: true });

  if (process.platform === 'win32') {
    // Windows: write a .cmd wrapper that calls node safe-rm.js
    const safeRmJs = path.join(LIB_DIR, 'safe-rm.js');
    const wrapper  = path.join(SAFE_RM_DIR, 'rm.cmd');
    fs.writeFileSync(wrapper,
      `@echo off\nnode "${safeRmJs}" %*\n`);
  } else {
    // Unix: shell script wrapper
    const safeRmSh = path.join(LIB_DIR, 'safe-rm.sh');
    const wrapper  = path.join(SAFE_RM_DIR, 'rm');
    fs.writeFileSync(wrapper,
      `#!/usr/bin/env bash\nexec ${safeRmSh} "$@"\n`, { mode: 0o755 });
  }

  return { dir: SAFE_RM_DIR };
}

function cleanupSession(safeRmInfo) {
  try { fs.rmSync(SAFE_RM_DIR, { recursive: true, force: true }); } catch { }
}

// ── confirm listener ────────────────────────────────────────────────────────
// Polls SESSION_DIR for req.<pid> files written by safe-rm.sh.
// Prompts the user, writes res.<pid> with the answer.

const POLL_MS = 100;

async function runConfirmListener(safeRmInfo, agentProc) {
  if (!safeRmInfo) return;
  const dir = safeRmInfo.dir;

  while (true) {
    if (!fs.existsSync(dir)) break;

    let reqFiles;
    try { reqFiles = fs.readdirSync(dir).filter(f => f.startsWith('req.')); }
    catch { break; }

    for (const reqFile of reqFiles) {
      const pid     = reqFile.slice(4);
      const reqPath = path.join(dir, reqFile);
      const resPath = path.join(dir, `res.${pid}`);

      let argsStr;
      try { argsStr = fs.readFileSync(reqPath, 'utf8').trim(); }
      catch { continue; }
      try { fs.unlinkSync(reqPath); } catch { continue; }
      if (!argsStr) continue;

      const promptingFlag = path.join(dir, '.prompting');
      try { fs.writeFileSync(promptingFlag, ''); } catch { }

      const answer = await promptUser(argsStr);

      try { fs.unlinkSync(promptingFlag); } catch { }

      const a = (answer || 'N').toLowerCase();
      if (a !== 'y' && a !== 'a') {
        // User denied — unblock safe-rm.sh then kill agent immediately
        try { fs.writeFileSync(resPath, 'N'); } catch { }
        process.stdout.write('\n  \x1b[31m✗\x1b[0m  Cancelled.\n\n');
        try { agentProc.kill('SIGTERM'); } catch { }
        return;
      }
      try { fs.writeFileSync(resPath, answer); } catch { }
    }

    await new Promise(r => setTimeout(r, POLL_MS));
  }
}

function promptUser(argsStr) {
  // Cross-platform inline prompt — no shell script dependency.
  // On Unix we open /dev/tty directly; on Windows process.stdin works fine
  // in PowerShell (it is a real tty).
  return new Promise(resolve => {
    const R = '\x1b[0m', BOLD = '\x1b[1m', DIM = '\x1b[2m',
          YELLOW = '\x1b[33m', CYAN = '\x1b[36m';

    process.stdout.write(
      `\n  ${YELLOW}⚠️  rm${R} ${BOLD}${argsStr}${R}\n` +
      `  ${DIM}→ will move to trash, not permanently delete${R}\n\n` +
      `  ${CYAN}[y]${R} allow once  ` +
      `${CYAN}[a]${R} allow all (this session)  ` +
      `${CYAN}[N]${R} deny  `
    );

    let answered = false;
    const done = ans => {
      if (answered) return;
      answered = true;
      process.stdout.write('\n');
      resolve((ans || 'N').trim());
    };

    // Unix: open /dev/tty for isolated read even when stdin is piped
    if (process.platform !== 'win32') {
      try {
        const net   = require('net');
        const ttyFd = fs.openSync('/dev/tty', 'r+');
        const ttyIn = new net.Socket({ fd: ttyFd, readable: true, writable: false });
        const rl    = require('readline').createInterface({ input: ttyIn });
        rl.once('line',  line => { rl.close(); ttyIn.destroy(); done(line); });
        rl.once('close', ()   => done('N'));
        return;
      } catch { /* fall through to stdin */ }
    }

    // Windows (PowerShell) or fallback: read from process.stdin
    const rl = require('readline').createInterface({
      input: process.stdin, output: process.stdout, terminal: true,
    });
    rl.once('line',  line => { rl.close(); done(line); });
    rl.once('close', ()   => done('N'));
  });
}

function findWindowsCodexJs(env) {
  if (process.platform !== 'win32') return null;

  const candidates = [];
  const add = p => { if (p && !candidates.includes(p)) candidates.push(p); };

  // npm global install layout: <prefix>\codex.cmd and
  // <prefix>\node_modules\@openai\codex\bin\codex.js
  for (const dir of (env.PATH || '').split(path.delimiter)) {
    if (!dir) continue;
    add(path.join(dir, 'node_modules', '@openai', 'codex', 'bin', 'codex.js'));
  }

  try {
    const npmRoot = execFileSync('npm', ['root', '-g'], { encoding: 'utf8' }).trim();
    add(path.join(npmRoot, '@openai', 'codex', 'bin', 'codex.js'));
  } catch { }

  try {
    const whereOut = execFileSync('where', ['codex'], { encoding: 'utf8' });
    for (const line of whereOut.split(/\r?\n/)) {
      const p = line.trim();
      if (!p) continue;
      const dir = path.dirname(p);
      add(path.join(dir, 'node_modules', '@openai', 'codex', 'bin', 'codex.js'));
    }
  } catch { }

  return candidates.find(p => {
    try { return fs.existsSync(p); } catch { return false; }
  }) || null;
}

function agentCmd(fullPrompt, safeRmBin, safeRmInfo) {
  const sep = path.delimiter;
  const pathEnv = safeRmBin
    ? `${safeRmBin}${sep}${process.env.PATH}`
    : process.env.PATH;
  const env = {
    ...process.env,
    PATH: pathEnv,
    SHELLISH_CWD: CWD,
    SHELLISH_PROMPT: USER_PROMPT,
    SHELLISH_CONFIRM_DANGER: getConfirmDanger(),
    SHELLISH_SESSION_ID: SESSION_ID,
    SHELLISH_SESSION_DIR: SAFE_RM_DIR,
  };

  switch (AGENT) {
    case 'pi':
    case 'omp':
      return { cmd: AGENT, args: ['-p', fullPrompt, '--mode', 'json'], env };

    case 'claude':
      // --dangerously-skip-permissions disables claude's own file-op blocking
      // so our fake rm (PATH injection) handles confirmation instead.
      return { cmd: 'claude', args: ['-p', fullPrompt,
        '--output-format', 'stream-json', '--verbose', '--include-partial-messages',
        '--dangerously-skip-permissions'], env };

    case 'codex': {
      const args = ['exec', '--json',
        '--dangerously-bypass-approvals-and-sandbox', fullPrompt];
      const codexJs = findWindowsCodexJs(env);
      if (codexJs) {
        return { cmd: process.execPath, args: [codexJs, ...args], env,
          displayCmd: `node ${codexJs}` };
      }
      return { cmd: 'codex', args, env, displayCmd: 'codex' };
    }

    default:
      return { cmd: AGENT, args: [fullPrompt], env };
  }
}

// ── main ──────────────────────────────────────────────────────────────────────
async function main() {
  const fullPrompt = buildPrompt();

  const safeRmInfo = setupSafeRmBin();
  const safeRmBin  = safeRmInfo ? safeRmInfo.dir : null;
  const { cmd, args, env, displayCmd } = agentCmd(fullPrompt, safeRmBin, safeRmInfo);

  // Spawn agent
  const agent = spawn(cmd, args, { env, stdio: ['ignore', 'pipe', 'inherit'] });
  agent.once('error', e => {
    process.stderr.write(
      `shellish: failed to start agent '${AGENT}' using ${displayCmd || cmd}\n` +
      `  ${e.code || 'ERROR'}: ${e.message}\n` +
      `  Try running: shellish config\n`
    );
  });

  // Spawn renderer, reading from agent stdout
  const rendererArgs = [RENDER_JS, '--agent', AGENT];
  if (safeRmInfo) rendererArgs.push('--session-dir', safeRmInfo.dir);
  const renderer = spawn(process.execPath, rendererArgs, {
    stdio: ['pipe', 'inherit', 'inherit'],
  });

  // Pipe agent → renderer
  if (agent.stdout) agent.stdout.pipe(renderer.stdin);
  else renderer.stdin.end();

  // Also tee agent stdout to collect text output for history.
  // render.js emits the rendered text to process.stdout (inherited), so we
  // intercept at the agent JSON level and extract text ourselves.
  let replyBuf = '';

  if (agent.stdout) agent.stdout.on('data', chunk => {
    // Parse JSON lines and extract text deltas / messages for history
    const lines = chunk.toString().split('\n');
    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const obj = JSON.parse(line);
        const text = extractText(obj);
        if (text) {
          replyBuf += text;
          // keep only last 512 chars to avoid huge buffers, we'll trim to 256 at save
          if (replyBuf.length > 512) replyBuf = replyBuf.slice(-512);
        }
      } catch { /* non-JSON line */ }
    }
  });

  // Wait for both processes
  const agentExit    = waitExit(agent);
  const rendererExit = waitExit(renderer);

  // Start confirm listener — pass agent ref so it can kill on deny
  const listenerDone = runConfirmListener(safeRmInfo, agent);

  const [agentCode, rendererCode] = await Promise.all([agentExit, rendererExit]);

  // render.js exits 127 when it detects a __TYPO__ sentinel — don't save history for typos
  if (rendererCode === 127) {
    cleanupSession(safeRmInfo);
    process.exit(127);
  }

  saveHistory(replyBuf.slice(-256));

  cleanupSession(safeRmInfo);
  process.exit(agentCode || rendererCode);
}

// ── extract readable text from a JSON event ───────────────────────────────────
let claudeHistoryHadDelta = false;

function extractText(obj) {
  const t = obj.type || '';

  // pi: text_delta
  if (t === 'message_update') {
    const ame = obj.assistantMessageEvent || {};
    if (ame.type === 'text_delta') return ame.delta || '';
  }

  // codex: agent_message
  if (t === 'item.completed' && obj.item?.type === 'agent_message') {
    return obj.item.text || '';
  }

  // claude: partial stream deltas, with final assistant text as fallback.
  // When --include-partial-messages is enabled, Claude may emit both deltas and
  // a final assistant text payload. Use deltas for real streaming/history and
  // suppress the final duplicate if deltas were seen.
  if (t === 'stream_event') {
    const event = obj.event || {};
    if (event.type === 'message_start') {
      claudeHistoryHadDelta = false;
      return '';
    }
    if (event.type === 'content_block_delta' && event.delta?.type === 'text_delta') {
      claudeHistoryHadDelta = true;
      return event.delta.text || '';
    }
  }

  if (t === 'assistant') {
    if (claudeHistoryHadDelta) return '';
    const parts = (obj.message?.content || [])
      .filter(c => c.type === 'text')
      .map(c => c.text || '');
    return parts.join('');
  }

  return '';
}

// ── promise wrapper for process exit ─────────────────────────────────────────
function waitExit(proc) {
  return new Promise(resolve => {
    proc.on('close', code => resolve(code || 0));
    proc.on('error', ()   => resolve(1));
  });
}

main().catch(e => {
  process.stderr.write(`run.js error: ${e.message}\n`);
  process.exit(1);
});
