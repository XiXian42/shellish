#!/usr/bin/env node
// shellish/lib/shellish-cmd.js
// Windows CLI controller — equivalent of bin/shellish (bash) on Unix.
//
// Called by bin/shellish.cmd for all sub-commands and prompt dispatch.

'use strict';

const fs      = require('fs');
const path    = require('path');
const os      = require('os');
const { execFileSync, spawn } = require('child_process');
const readline = require('readline');

const VERSION  = '0.1.0';
const LIB_DIR  = __dirname;
const RUN_JS   = path.join(LIB_DIR, 'run.js');

function windowsAppData() {
  return process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming');
}

const DEFAULT_CFG_FILE = process.platform === 'win32'
  ? path.join(windowsAppData(), 'shellish', 'config')
  : path.join(os.homedir(), '.config', 'shellish', 'config');
const LEGACY_CFG_FILE = path.join(os.homedir(), '.config', 'shellish', 'config');
const CFG_FILE = process.env.SHELLISH_CONFIG_FILE
  || (process.env.SHELLISH_CONFIG_DIR ? path.join(process.env.SHELLISH_CONFIG_DIR, 'config') : DEFAULT_CFG_FILE);

// ── ANSI ──────────────────────────────────────────────────────────────────────
const R    = '\x1b[0m';
const BOLD = '\x1b[1m';
const DIM  = '\x1b[2m';
const GRN  = '\x1b[32m';
const CYAN = '\x1b[36m';
const RED  = '\x1b[31m';

const w = s => process.stdout.write(s);

// ── config helpers ────────────────────────────────────────────────────────────
function readConfigText() {
  const file = fs.existsSync(CFG_FILE) ? CFG_FILE : LEGACY_CFG_FILE;
  const buf = fs.readFileSync(file);
  // Older install.ps1 versions on Windows PowerShell 5.1 wrote UTF-16LE.
  if (buf[0] === 0xff && buf[1] === 0xfe) return buf.toString('utf16le').replace(/^\uFEFF/, '');
  const utf8 = buf.toString('utf8').replace(/^\uFEFF/, '');
  // Heuristic for UTF-16LE without BOM: lots of NUL bytes in odd positions.
  if (utf8.includes('\u0000')) return buf.toString('utf16le').replace(/^\uFEFF/, '');
  return utf8;
}

function cfgGet(key) {
  try {
    const lines = readConfigText().split('\n');
    for (const l of lines) {
      const m = l.match(new RegExp(`^${key}=(.+)$`));
      if (m) return m[1].trim();
    }
  } catch { }
  return '';
}

function cfgSet(key, value) {
  const dir = path.dirname(CFG_FILE);
  fs.mkdirSync(dir, { recursive: true });
  let lines = [];
  try { lines = readConfigText().split('\n'); } catch { }
  const filtered = lines.filter(l => !l.startsWith(`${key}=`));
  filtered.push(`${key}=${value}`);
  fs.writeFileSync(CFG_FILE, filtered.join('\n') + '\n', 'utf8');
}

// ── detect agents ─────────────────────────────────────────────────────────────
const SUPPORTED = ['pi', 'omp', 'claude', 'codex'];

function detectAgents() {
  return SUPPORTED.filter(a => {
    try { execFileSync('where', [a], { stdio: 'ignore' }); return true; }
    catch { return false; }
  });
}

// ── readline helper ───────────────────────────────────────────────────────────
function ask(prompt) {
  return new Promise(resolve => {
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    rl.question(prompt, ans => { rl.close(); resolve(ans.trim()); });
  });
}

// ── commands ──────────────────────────────────────────────────────────────────
async function cmdConfig() {
  w(`\n  ${BOLD}Configure shellish${R}\n\n`);

  const current = cfgGet('agent');
  if (current) {
    w(`  Current agent: ${GRN}${current}${R}\n\n`);
    const ans = await ask('  Change it? [y/N] ');
    if (ans.toLowerCase() !== 'y') { w('  No changes made.\n\n'); return; }
    w('\n');
  }

  const agents = detectAgents();
  if (!agents.length) {
    w(`  ${RED}✗${R} No supported agent found.\n`);
    w('    Install one of: pi, omp, claude, codex\n\n');
    return;
  }

  const descs = { pi: 'earendil coding agent', omp: 'earendil coding agent',
                  claude: 'Claude Code — Anthropic', codex: 'Codex CLI — OpenAI' };
  w('  Available agents:\n\n');
  agents.forEach((a, i) => w(`    ${i+1}) ${a.padEnd(10)}  ${DIM}${descs[a]||''}${R}\n`));
  w('\n');

  const choice = await ask(`  Your choice [1-${agents.length}, default=1]: `);
  const idx = (parseInt(choice, 10) || 1) - 1;
  const chosen = agents[Math.max(0, Math.min(idx, agents.length - 1))];
  cfgSet('agent', chosen);
  w(`\n  ${GRN}✓${R} Default agent set to: ${BOLD}${chosen}${R}\n\n`);

  w('  When the agent deletes files (rm):\n');
  const curDanger = cfgGet('confirm_danger') || 'ask';
  w(`    1) ask    — prompt each time (moves to trash)  ${curDanger==='ask'?'← current':''}\n`);
  w(`    2) allow  — always move to trash silently      ${curDanger==='allow'?'← current':''}\n\n`);
  const dp = await ask('  Choose [1-2, default=1]: ');
  cfgSet('confirm_danger', dp === '2' ? 'allow' : 'ask');
  w(`\n  ${GRN}✓${R} Config saved.\n\n`);
}

async function cmdStatus() {
  w(`\n  ${BOLD}shellish${R} ${DIM}v${VERSION}${R} — Windows\n\n`);
  const agents = detectAgents();
  w('  Detected agents:\n');
  SUPPORTED.forEach(a => {
    const found = agents.includes(a);
    w(`    ${found ? GRN+'✓'+R : DIM+'✗'+R}  ${a}\n`);
  });
  w(`\n  Config: ${CFG_FILE}\n`);
  w(`    agent         = ${BOLD}${cfgGet('agent')||'<not set>'}${R}\n`);
  w(`    confirm_danger= ${BOLD}${cfgGet('confirm_danger')||'ask'}${R}\n\n`);
}

function profileCandidates() {
  if (!process.env.USERPROFILE) return [];
  return [
    // Windows PowerShell 5.1
    path.join(process.env.USERPROFILE, 'Documents', 'WindowsPowerShell', 'Microsoft.PowerShell_profile.ps1'),
    // PowerShell 7+
    path.join(process.env.USERPROFILE, 'Documents', 'PowerShell', 'Microsoft.PowerShell_profile.ps1'),
  ];
}

function cmdInstallHook() {
  const profiles = profileCandidates();
  if (!profiles.length) {
    w(`  ${RED}✗${R} Cannot determine PowerShell profile path.\n`);
    return;
  }

  const hookSrc = path.join(LIB_DIR, '..', 'shell', 'profile.ps1');
  const hookLine = `\n# shellish hook\n. "${hookSrc}"\n`;

  for (const profilePath of profiles) {
    try {
      fs.mkdirSync(path.dirname(profilePath), { recursive: true });
      const existing = fs.existsSync(profilePath)
        ? fs.readFileSync(profilePath, 'utf8') : '';
      if (existing.includes('shellish')) {
        w(`  ${GRN}✓${R} Hook already present in ${profilePath}\n`);
        continue;
      }
      fs.appendFileSync(profilePath, hookLine, 'utf8');
      w(`  ${GRN}✓${R} Hook added to ${profilePath}\n`);
    } catch (e) {
      w(`  ${RED}✗${R} Failed for ${profilePath}: ${e.message}\n`);
    }
  }
  w(`  Restart PowerShell to activate.\n\n`);
}

function cmdUninstallHook() {
  let removed = false;
  for (const profilePath of profileCandidates()) {
    if (!fs.existsSync(profilePath)) continue;
    const src = fs.readFileSync(profilePath, 'utf8');
    if (!src.includes('shellish')) continue;
    const cleaned = src.replace(/\n# shellish hook\n.*profile\.ps1.*\n/g, '');
    fs.writeFileSync(profilePath, cleaned, 'utf8');
    removed = true;
    w(`  ${GRN}✓${R} Hook removed from ${profilePath}\n`);
  }
  if (!removed) w('  No shellish hook found.\n');
}

function cmdHelp() {
  w(`
  ${BOLD}shellish${R} ${DIM}v${VERSION}${R} — natural language shell agent (Windows)

  ${BOLD}USAGE${R}
    shellish <prompt>            Run a natural-language prompt
    shellish config              Configure default agent
    shellish status              Show current config
    shellish install-hook        Add hook to PowerShell \\$PROFILE
    shellish uninstall-hook      Remove hook
    shellish version             Print version

  ${BOLD}EXAMPLES${R}
    shellish "list all png files in this directory"
    shellish "fix the last git conflict"

`);
}

async function cmdRun(fromShell, ...promptParts) {
  const prompt = promptParts.join(' ');
  if (!prompt) { cmdHelp(); return; }

  let agent = cfgGet('agent');
  if (!agent) {
    w(`\n  ${BOLD}shellish${R} is not configured. Running setup…\n`);
    await cmdConfig();
    agent = cfgGet('agent');
    if (!agent) return;
  }

  w(`\n  ${CYAN}🤖${R} ${BOLD}${agent}${R} ← ${DIM}${prompt}${R}\n\n`);

  if (process.env.SHELLISH_DRY_RUN === '1') {
    w(`DRY_RUN fromShell=${fromShell ? '1' : '0'} prompt=${prompt}\n`);
    return;
  }

  const runArgs = fromShell
    ? ['--from-shell', agent, process.cwd(), prompt]
    : [agent, process.cwd(), prompt];

  const child = spawn(process.execPath, [RUN_JS, ...runArgs], {
    stdio: 'inherit',
    env: process.env,
  });

  child.on('close', code => process.exit(code || 0));
}

// ── dispatch ──────────────────────────────────────────────────────────────────
async function main() {
  const args = process.argv.slice(2);
  const cmd  = args[0] || '';

  switch (cmd) {
    case 'config':         await cmdConfig(); break;
    case 'status':         await cmdStatus(); break;
    case 'install-hook':   cmdInstallHook();  break;
    case 'uninstall-hook': cmdUninstallHook(); break;
    case 'help': case '-h': case '--help': cmdHelp(); break;
    case 'version': case '-v': case '--version':
      w(`shellish v${VERSION}\n`); break;
    case '--from-shell':
      await cmdRun(true, ...args.slice(1)); break;
    default:
      await cmdRun(false, ...args); break;
  }
}

main().catch(e => {
  process.stderr.write(`shellish error: ${e.message}\n`);
  process.exit(1);
});
