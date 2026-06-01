#!/usr/bin/env node
// Test agent resolution. We spawn a child Node process with
// process.platform overridden via NODE_OPTIONS, because lib/run.js runs
// main() at top-level and we cannot import it directly.

const { spawnSync } = require('child_process');
const fs   = require('fs');
const path = require('path');
const os   = require('os');

const here    = __dirname;
const project = path.resolve(here, '..');

// We override process.platform by writing a small adapter that
// re-requires agent-resolver and exercises it. The adapter lives in
// /tmp for the duration of the run.
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'shellish-test-'));

const adapterSrc = `'use strict';
const path = require('path');
const fs   = require('fs');

// Allow forcing platform + env from CLI args
const targetPlatform = process.argv[2];
const env = JSON.parse(process.argv[3] || '{}');
for (const k of Object.keys(env)) process.env[k] = env[k];
Object.defineProperty(process, 'platform', { value: targetPlatform, configurable: true });

const resolver = require(${JSON.stringify(path.join(project, 'lib', 'agent-resolver.js'))});
const r = resolver.resolveAgentCommand(process.argv[4], { PATH: process.argv[5] || '' });
console.log(JSON.stringify(r));

const r2 = resolver.npmGlobalRoots();
console.log('ROOTS:' + JSON.stringify(r2));
`;

const adapterPath = path.join(tmp, 'adapter.js');
fs.writeFileSync(adapterPath, adapterSrc);

function runAdapter(platform, env, agent, pathVal) {
  const res = spawnSync(process.execPath, [
    adapterPath, platform, JSON.stringify(env), agent, pathVal || '',
  ], { encoding: 'utf8' });
  if (res.status !== 0) {
    return { error: res.stderr || res.stdout, stdout: res.stdout };
  }
  const lines = res.stdout.split('\n');
  return {
    resolved: JSON.parse(lines[0]),
    roots: JSON.parse(lines[1].replace(/^ROOTS:/, '')),
  };
}

const results = [];
function record(name, ok, detail) {
  results.push({ name, ok, detail });
  console.log((ok ? '  ✓ ' : '  ✗ ') + name + (detail ? ' — ' + detail : ''));
}

// Test 1: darwin returns shell=false
{
  const r = runAdapter('darwin', {}, 'codex', '/usr/bin');
  record('darwin shell=false', r.resolved && r.resolved.shell === false,
    JSON.stringify(r.resolved));
}

// Test 2: win32 fallback when no shim anywhere
{
  const r = runAdapter('win32', {
    APPDATA: path.join(tmp, 'no-such-appdata'),
    NVM_HOME: path.join(tmp, 'no-such-nvm'),
  }, 'definitely-not-installed-xyz', '');
  record('win32 fallback shell=true', r.resolved && r.resolved.shell === true,
    JSON.stringify(r.resolved));
}

// Test 3: win32 finds codex.js in appdata npm layout.
// We can't fully isolate the test from the host's `npm root -g` (which on
// the macOS dev machine points at a real install), so we test the
// 'appdata default fallback' branch directly: ensure the root is in the
// probed list. (Resolving via the actual install is exercised by the
// integration test on a real Windows runner.)
{
  const r = runAdapter('win32', { APPDATA: tmp }, 'pi', '');
  // pi is in the scopeMap. APPDATA points at /tmp, so npmGlobalRoots
  // will include ${tmp}/npm/node_modules. We can't easily stub npm
  // itself, but we can confirm the function returns a non-empty roots
  // list and the fallback cmd is correct when no .js is present.
  const ok = r.roots && r.roots.includes(path.join(tmp, 'npm', 'node_modules'));
  record('appdata npm root is in probed list', ok, '');
}

// Test 4: win32 claude fallback to shell:true (claude ships a native
// .exe, not a .js, so the npm-global probe should miss and we fall
// through to the bare-name fallback with shell:true).
{
  // Point APPDATA at an empty dir so we don't accidentally pick up the
  // real install's path.
  const emptyAppdata = path.join(tmp, 'empty-claude');
  fs.mkdirSync(emptyAppdata, { recursive: true });
  const r = runAdapter('win32', { APPDATA: emptyAppdata }, 'claude', '');
  const ok = r.resolved && r.resolved.shell === true && r.resolved.cmd === 'claude';
  record('win32 claude fallback to bare-name + shell:true', ok, JSON.stringify(r.resolved));
}

// Test 5: nvm-windows layout found
{
  const nvm = path.join(tmp, 'nvm');
  fs.mkdirSync(path.join(nvm, 'v20.10.0', 'node_modules'), { recursive: true });
  const r = runAdapter('win32', { APPDATA: path.join(tmp, 'empty'), NVM_HOME: nvm }, 'codex', '');
  const ok = r.roots && r.roots.includes(path.join(nvm, 'v20.10.0', 'node_modules'));
  record('nvm root probed', ok, 'roots count: ' + (r.roots ? r.roots.length : 0));
}

// Test 6: fnm layout found
{
  const fnm = path.join(tmp, 'fnm');
  const target = path.join(fnm, 'node-versions', 'v20.0.0', 'installation', 'node_modules');
  fs.mkdirSync(target, { recursive: true });
  const r = runAdapter('win32', { APPDATA: path.join(tmp, 'empty'), FNM_DIR: fnm }, 'codex', '');
  const ok = r.roots && r.roots.includes(target);
  record('fnm root probed', ok, '');
}

// Test 7: appdata default fallback
{
  const emptyAppdata = path.join(tmp, 'empty-appdata');
  fs.mkdirSync(path.join(emptyAppdata, 'npm', 'node_modules'), { recursive: true });
  const r = runAdapter('win32', { APPDATA: emptyAppdata }, 'codex', '');
  const ok = r.roots && r.roots.includes(path.join(emptyAppdata, 'npm', 'node_modules'));
  record('appdata default fallback', ok, '');
}

fs.rmSync(tmp, { recursive: true, force: true });

const pass = results.filter(r => r.ok).length;
console.log(`\n${pass}/${results.length} passed`);
process.exit(pass === results.length ? 0 : 1);
