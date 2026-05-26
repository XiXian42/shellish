#!/usr/bin/env node
// shellish/lib/safe-rm.js
// Windows drop-in rm replacement.
// Invoked via rm.cmd wrapper injected into PATH by run.js.
//
// Env vars (set by run.js):
//   SHELLISH_CONFIRM_DANGER   ask | allow
//   SHELLISH_SESSION_ID       unique per-run ID
//   SHELLISH_SESSION_DIR      temp dir for req/res handshake files

'use strict';

const fs   = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const ARGS        = process.argv.slice(2).filter(a => !a.startsWith('-')); // strip flags
const CONFIRM     = process.env.SHELLISH_CONFIRM_DANGER || 'ask';
const SESSION_DIR = process.env.SHELLISH_SESSION_DIR || '';
const ALLOW_FILE  = path.join(SESSION_DIR, '.allow-all');

// ── move a single file/dir to the Windows Recycle Bin ─────────────────────────
function toRecycleBin(target) {
  const abs = path.resolve(target);
  // Shell.Application COM via PowerShell
  const ps = `
$shell = New-Object -ComObject Shell.Application
$item  = $shell.Namespace(0).ParseName('${abs.replace(/'/g, "''")}')
if ($item) { $item.InvokeVerb('delete') } else { exit 1 }
`.trim();
  execSync(`powershell -NoProfile -Command "${ps.replace(/\n/g, ' ')}"`,
    { stdio: 'inherit' });
}

// ── allow mode: silently trash everything ─────────────────────────────────────
if (CONFIRM === 'allow') {
  for (const t of ARGS) { try { toRecycleBin(t); } catch { process.exit(1); } }
  process.exit(0);
}

// ── session allow-all already granted ────────────────────────────────────────
if (SESSION_DIR && fs.existsSync(ALLOW_FILE)) {
  for (const t of ARGS) { try { toRecycleBin(t); } catch { process.exit(1); } }
  process.exit(0);
}

// ── ask mode: write req file, poll for res ────────────────────────────────────
if (!SESSION_DIR || !fs.existsSync(SESSION_DIR)) {
  // No session dir — silently trash (edge case)
  for (const t of ARGS) { try { toRecycleBin(t); } catch { process.exit(1); } }
  process.exit(0);
}

const pid     = process.pid;
const reqFile = path.join(SESSION_DIR, `req.${pid}`);
const resFile = path.join(SESSION_DIR, `res.${pid}`);

fs.writeFileSync(reqFile, ARGS.join(' '));

// Poll for response (max 60 s)
const start = Date.now();
while (Date.now() - start < 60000) {
  if (fs.existsSync(resFile)) {
    const answer = fs.readFileSync(resFile, 'utf8').trim().toLowerCase();
    try { fs.unlinkSync(resFile); } catch { }
    if (answer === 'y' || answer === 'a') {
      if (answer === 'a') {
        try { fs.writeFileSync(ALLOW_FILE, ''); } catch { }
      }
      for (const t of ARGS) { try { toRecycleBin(t); } catch { process.exit(1); } }
      process.exit(0);
    }
    // denied
    process.exit(1);
  }
  // Synchronous sleep (we're a tiny subprocess, blocking is fine)
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100);
}

// Timeout — clean up and deny
try { fs.unlinkSync(reqFile); } catch { }
process.exit(1);
