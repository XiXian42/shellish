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
const cfg          = require('./config-win');

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
  return cfg.get('confirm_danger') || 'ask';
}

function setupSafeRmBin() {
  fs.mkdirSync(SAFE_RM_DIR, { recursive: true });

  if (process.platform === 'win32') {
    // Windows: write .cmd wrappers that call node safe-rm.js. These catch
    // cmd.exe/native-shell usage; PowerShell aliases are reduced by prompt
    // policy and by injected PATH for external rm.
    const safeRmJs = path.join(LIB_DIR, 'safe-rm.js');
    for (const name of ['shellish-trash', 'shellish-rm', 'rm', 'del', 'erase', 'rmdir', 'rd']) {
      const wrapper = path.join(SAFE_RM_DIR, `${name}.cmd`);
      fs.writeFileSync(wrapper, `@echo off\r\n"${process.execPath}" "${safeRmJs}" %*\r\n`, 'utf8');
    }
  } else {
    // Unix: shell script wrapper
    const safeRmSh = path.join(LIB_DIR, 'safe-rm.sh');
    for (const name of ['shellish-trash', 'shellish-rm', 'rm']) {
      const wrapper = path.join(SAFE_RM_DIR, name);
      fs.writeFileSync(wrapper,
        `#!/usr/bin/env bash\nexec ${safeRmSh} "$@"\n`, { mode: 0o755 });
    }
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
        killProcessTree(agentProc);
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

    const icon = process.platform === 'win32' && !process.env.WT_SESSION ? '!' : '⚠️';
    process.stdout.write(
      `\n  ${YELLOW}${icon}  rm${R} ${BOLD}${argsStr}${R}\n` +
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

    // Windows (PowerShell) or fallback: read from process.stdin. We
    // intentionally use `terminal: !!process.stdout.isTTY` (instead of
    // always true) so IDEs that report isTTY=false don't enter raw
    // mode and silently swallow keypresses. The `close` handler is a
    // safety net only — by the time it fires, `answered` is already
    // true from the `line` path, so `done` is a no-op.
    const rl = require('readline').createInterface({
      input: process.stdin,
      output: process.stdout,
      terminal: !!process.stdout.isTTY,
    });
    rl.once('line',  line => { rl.close(); done(line); });
    rl.once('close', ()   => { if (!answered) done('N'); });
  });
}

// Resolve a Windows agent's real command path. Implementation lives in
// lib/agent-resolver.js so it can be unit-tested in isolation.
const { resolveAgentCommand } = require('./agent-resolver');

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
    POWERSHELL_UPDATECHECK: 'Off',
  };

  // Per-agent argument recipe. Each agent speaks its own CLI; keep the
  // divergence here so the resolution code stays simple.
  const recipes = {
    pi:     (prompt) => ['-p', prompt, '--mode', 'json'],
    omp:    (prompt) => ['-p', prompt, '--mode', 'json'],
    claude: (prompt) => [
      '-p', prompt,
      '--output-format', 'stream-json',
      '--verbose',
      '--include-partial-messages',
      // --dangerously-skip-permissions disables claude's own file-op
      // blocking so our fake rm (PATH injection) handles confirmation.
      '--dangerously-skip-permissions',
    ],
    codex:  (prompt) => [
      'exec', '--json',
      '--dangerously-bypass-approvals-and-sandbox',
      prompt,
    ],
  };
  const buildArgs = recipes[AGENT] || ((prompt) => [prompt]);

  const resolved = resolveAgentCommand(AGENT, env);
  return {
    cmd: resolved.cmd,
    args: [...resolved.args, ...buildArgs(fullPrompt)],
    env,
    displayCmd: resolved.displayCmd,
    shell: resolved.shell,
  };
}

// ── main ──────────────────────────────────────────────────────────────────────
async function main() {
  try {
    if (!fs.statSync(CWD).isDirectory()) throw new Error('not a directory');
  } catch (e) {
    process.stderr.write(`shellish: cannot access cwd '${CWD}': ${e.message}\n`);
    process.exit(1);
  }

  const fullPrompt = buildPrompt();

  const safeRmInfo = setupSafeRmBin();
  const safeRmBin  = safeRmInfo ? safeRmInfo.dir : null;
  const { cmd, args, env, displayCmd, shell } = agentCmd(fullPrompt, safeRmBin, safeRmInfo);

  // Spawn agent. `shell: true` is needed on Windows to resolve PATHEXT
  // (.cmd / .bat shims) and to run the .cmd shim with its quoted
  // arguments intact; on POSIX we always invoke directly.
  const spawnOpts = {
    cwd: CWD,
    env,
    stdio: ['ignore', 'pipe', 'inherit'],
  };
  if (shell) spawnOpts.shell = true;
  const agent = spawn(cmd, args, spawnOpts);
  agent.once('error', e => {
    process.stderr.write(
      `shellish: failed to start agent '${AGENT}' using ${displayCmd || cmd}\n` +
      `  ${e.code || 'ERROR'}: ${e.message}\n` +
      `  Try running: shellish config\n` +
      `  If this is the first run, run '${AGENT}' directly once to finish login/setup.\n`
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
function killProcessTree(proc) {
  if (!proc || !proc.pid) return;
  try {
    if (process.platform === 'win32') {
      execFileSync('taskkill', ['/PID', String(proc.pid), '/T', '/F'], { stdio: 'ignore' });
    } else {
      proc.kill('SIGTERM');
    }
  } catch {
    try { proc.kill('SIGTERM'); } catch { }
  }
}

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
