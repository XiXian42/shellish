#!/usr/bin/env node
// shellish/lib/shellish-cmd.js
// Windows CLI controller — equivalent of bin/shellish (bash) on Unix.
//
// Called by bin/shellish.cmd for all sub-commands and prompt dispatch.

'use strict';

const fs      = require('fs');
const path    = require('path');
const { execFileSync, spawn, spawnSync } = require('child_process');
const readline = require('readline');
const cfg     = require('./config-win');
const ansiLib = require('./ansi');

const VERSION  = '0.1.0';
const LIB_DIR  = __dirname;
const RUN_JS   = path.join(LIB_DIR, 'run.js');

const CFG_FILE = cfg.configFile();

// ── ANSI ──────────────────────────────────────────────────────────────────────
const ANSI = ansiLib.codes(process.stdout);
const R    = ANSI.R;
const BOLD = ANSI.BOLD;
const DIM  = ANSI.DIM;
const GRN  = ANSI.GREEN;
const CYAN = ANSI.CYAN;
const RED  = ANSI.RED;

const w = s => process.stdout.write(s);

function displayWidth(s) {
  s = String(s || '');
  let n = 0;
  for (const ch of [...s]) {
    const cp = ch.codePointAt(0);
    if (cp <= 0x1f || (cp >= 0x7f && cp <= 0x9f)) continue;
    n += /[\u1100-\u115f\u2329\u232a\u2e80-\ua4cf\uac00-\ud7a3\uf900-\ufaff\ufe10-\ufe19\ufe30-\ufe6f\uff00-\uff60\uffe0-\uffe6]/u.test(ch) || cp > 0x1f000 ? 2 : 1;
  }
  return n;
}

function padDisplay(s, width) {
  const pad = Math.max(0, width - displayWidth(s));
  return String(s) + ' '.repeat(pad);
}

// ── config helpers ────────────────────────────────────────────────────────────
function cfgGet(key) { return cfg.get(key); }
function cfgSet(key, value) { return cfg.set(key, value); }

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
  agents.forEach((a, i) => w(`    ${i+1}) ${padDisplay(a, 10)}  ${DIM}${descs[a]||''}${R}\n`));
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
  const agent = cfgGet('agent') || '<not set>';
  w(`    agent         = ${BOLD}${agent}${R}\n`);
  w(`    confirm_danger= ${BOLD}${cfgGet('confirm_danger')||'ask'}${R}\n`);
  if (agent !== '<not set>') {
    const ok = spawnSync(agent, ['--version'], {
      encoding: 'utf8',
      timeout: 15000,
      shell: process.platform === 'win32',
    });
    const healthy = !ok.error && ok.status === 0;
    w(`    agent health  = ${healthy ? GRN+'available'+R : RED+'check failed'+R}\n`);
    if (!healthy) w(`      Try running '${agent}' directly once to finish login/setup.\n`);
  }
  w('\n');
}

const HOOK_BEGIN = '# >>> shellish hook >>>';
const HOOK_END   = '# <<< shellish hook <<<';

function profileCandidates() {
  if (!process.env.USERPROFILE) return [];
  return [
    path.join(process.env.USERPROFILE, 'Documents', 'WindowsPowerShell', 'Microsoft.PowerShell_profile.ps1'),
    path.join(process.env.USERPROFILE, 'Documents', 'PowerShell', 'Microsoft.PowerShell_profile.ps1'),
  ];
}

function stripHookBlocks(src) {
  src = src.replace(/\r?\n?# >>> shellish hook >>>[\s\S]*?# <<< shellish hook <<<\r?\n?/g, '\n');
  src = src.replace(/\r?\n?# shellish hook\r?\n\.\s+".*?shellish[\\/]+shell[\\/]+profile\.ps1"\r?\n?/g, '\n');
  return src.replace(/\n{3,}/g, '\n\n');
}

function cmdInstallHook() {
  const profiles = profileCandidates();
  if (!profiles.length) {
    w(`  ${RED}✗${R} Cannot determine PowerShell profile path.\n`);
    return;
  }

  const hookSrc = path.join(LIB_DIR, '..', 'shell', 'profile.ps1');
  const hookLine = `\n${HOOK_BEGIN}\n. "${hookSrc}"\n${HOOK_END}\n`;

  for (const profilePath of profiles) {
    try {
      fs.mkdirSync(path.dirname(profilePath), { recursive: true });
      const existing = fs.existsSync(profilePath)
        ? fs.readFileSync(profilePath, 'utf8') : '';
      const cleaned = stripHookBlocks(existing).replace(/\s*$/, '');
      fs.writeFileSync(profilePath, cleaned + hookLine, 'utf8');
      w(`  ${GRN}✓${R} Hook installed in ${profilePath}\n`);
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
    const cleaned = stripHookBlocks(src);
    if (cleaned === src) continue;
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
