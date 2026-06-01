'use strict';

// Resolve a Windows agent's real command path. Returns a spawn spec
// `{ cmd, args, displayCmd, shell }` that works regardless of how the
// agent was installed (npm global, nvm-windows, scoop, fnm, custom
// prefix, or a plain .cmd in PATH).
//
// Strategy:
//   1. Run `where <agent>` to get the .cmd shim path that Windows
//      would use. This is the most authoritative: it follows PATHEXT
//      and the user's actual PATH order.
//   2. Read the shim contents. If it points at a node script (e.g. codex
//      is `node "%dp0%\...\codex.js"`), extract the JS path so we can
//      invoke it directly without a child cmd.exe hop. Otherwise, use
//      the shim as-is with `shell: true` so cmd.exe handles it.
//   3. Fall back to `npm root -g` and probe the well-known
//      `node_modules\@scope\agent\bin\` layout (works on nvm-windows /
//      scoop where `where` might miss the npm-managed install).
//   4. Last resort: return the bare name with `shell: true` so cmd.exe
//      resolves PATHEXT.

const fs   = require('fs');
const path = require('path');
const os   = require('os');
const { execFileSync } = require('child_process');

function resolveAgentCommand(agent, env = process.env) {
  env = { ...process.env, ...(env || {}) };
  const fallback = {
    cmd: agent,
    args: [],
    displayCmd: agent,
    shell: process.platform === 'win32',
  };

  if (process.platform !== 'win32') {
    return { ...fallback, shell: false };
  }

  // (1) `where <agent>` — PATHEXT-resolved, ordered by PATH.
  let shimPath = null;
  try {
    const whereOut = execFileSync('where', [agent], { encoding: 'utf8', env });
    for (const line of whereOut.split(/\r?\n/)) {
      const p = line.trim();
      if (!p) continue;
      // Prefer the first non-WindowsApps hit; WindowsApps aliases are
      // stubs that prompt the user to install the app, not real
      // binaries.
      if (/WindowsApps/i.test(p)) continue;
      shimPath = p;
      break;
    }
  } catch { /* not on PATH */ }

  // (2) Read the shim and decide how to launch the real thing.
  if (shimPath) {
    const resolved = resolveShimTarget(shimPath, env);
    if (resolved) return { ...resolved, shell: false };
    return { cmd: shimPath, args: [], displayCmd: shimPath, shell: true };
  }

  // (3) Probe npm global layout for the well-known scopes.
  const scopeMap = {
    codex:  '@openai',
    claude: '@anthropic-ai',
    pi:     '@earendil-works',
    omp:    '@earendil-works',
  };
  const scope = scopeMap[agent];
  if (scope) {
    const roots = npmGlobalRoots(env);
    for (const root of roots) {
      const js = path.join(root, scope, agent, 'bin', `${agent}.js`);
      if (fs.existsSync(js)) {
        return {
          cmd: process.execPath,
          args: [js],
          displayCmd: `node ${js}`,
          shell: false,
        };
      }
    }
  }

  // (4) Last resort: bare name + shell:true so cmd.exe resolves PATHEXT.
  return fallback;
}

// Inspect a `.cmd` shim and return the underlying target, or null if
// we cannot extract it. Real npm-generated shims use a pattern like
//
//   IF EXIST "%dp0%\node_modules\@scope\name\bin\name.js" (
//     SET "_prog=%dp0%\node_modules\@scope\name\bin\name.js"
//   )
//   "%_prog%" %*
//
// so we look for the quoted `SET _prog=` line and resolve %dp0% against
// the shim's own directory. We also handle the simpler `node "<path>"`
// form in case any shim uses it.
function resolveShimTarget(shimPath) {
  let body = '';
  try { body = fs.readFileSync(shimPath, 'utf8'); } catch { return null; }
  if (!body) return null;

  const shimDir = path.dirname(shimPath);

  // Windows shims use backslashes; we normalise to the platform
  // separator so the same code works when exercised on POSIX test
  // machines and on real Windows. Then resolve %dp0% against the
  // shim's own directory.
  const tryTail = (raw) => {
    if (!raw) return null;
    const native = String(raw).split(/[\\\/]/).join(path.sep);
    const replaced = native.replace(/%dp0%/gi, shimDir);
    const candidates = [path.resolve(replaced)];
    for (const c of candidates) {
      try { if (fs.existsSync(c)) return c; } catch { /* ignore */ }
    }
    return null;
  };

  // Form 1: SET "_prog=%dp0%\path\to\file.js"
  const mProg = body.match(/SET\s+"_prog=([^"]+\.js)"/i);
  if (mProg) {
    const c = tryTail(mProg[1]);
    if (c) return { cmd: process.execPath, args: [c], displayCmd: `node ${c}` };
  }

  // Form 2: SET _prog=path\to\file.js (no quotes — uncommon but harmless).
  const mProgBare = body.match(/\bSET\s+_prog=([^\s"]+\.js)/i);
  if (mProgBare) {
    const c = tryTail(mProgBare[1]);
    if (c) return { cmd: process.execPath, args: [c], displayCmd: `node ${c}` };
  }

  // Form 3: node "<path>\file.js" — simpler shims.
  const mNode = body.match(/(?:^|\s)node\s+"([^"]+\.js)"/i);
  if (mNode) {
    const c = tryTail(mNode[1]);
    if (c) return { cmd: process.execPath, args: [c], displayCmd: `node ${c}` };
  }

  return null;
}

function npmGlobalRoots(env = process.env) {
  const roots = new Set();
  // (a) `npm root -g` — honors user's npm config and prefix.
  try {
    const out = execFileSync('npm', ['root', '-g'], { encoding: 'utf8', env }).trim();
    if (out) roots.add(out);
  } catch { }
  // (b) Default npm prefix (%AppData%\npm\node_modules on Windows).
  const appdata = env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming');
  roots.add(path.join(appdata, 'npm', 'node_modules'));
  // (c) nvm-windows layout: %NVM_HOME%\vXX.X.X\node_modules.
  if (env.NVM_HOME) {
    const nvm = env.NVM_HOME;
    try {
      for (const v of fs.readdirSync(nvm)) {
        roots.add(path.join(nvm, v, 'node_modules'));
      }
    } catch { }
  }
  // (d) fnm: %FNM_DIR%\node-versions\<version>\installation\node_modules.
  if (env.FNM_DIR) {
    const fnm = env.FNM_DIR;
    try {
      const versions = path.join(fnm, 'node-versions');
      if (fs.existsSync(versions)) {
        for (const v of fs.readdirSync(versions)) {
          roots.add(path.join(versions, v, 'installation', 'node_modules'));
        }
      }
    } catch { }
  }
  return [...roots];
}

module.exports = { resolveAgentCommand, resolveShimTarget, npmGlobalRoots };
