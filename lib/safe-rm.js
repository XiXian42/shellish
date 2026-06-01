#!/usr/bin/env node
// shellish/lib/safe-rm.js
// Windows drop-in rm replacement. Moves targets to Recycle Bin with optional
// shellish confirmation handshake.

'use strict';

const fs   = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

function parseRmArgs(raw) {
  let pastDash = false;
  const out = [];
  for (const a of raw) {
    if (a === '--' && !pastDash) { pastDash = true; continue; }
    if (!pastDash && a.startsWith('-')) continue;
    out.push(a);
  }
  return out;
}

const ARGS         = parseRmArgs(process.argv.slice(2));
const CONFIRM      = process.env.SHELLISH_CONFIRM_DANGER || 'ask';
const SESSION_DIR  = process.env.SHELLISH_SESSION_DIR || '';
const ALLOW_FILE   = path.join(SESSION_DIR || '.', '.allow-all');

const EXIT_NOT_FOUND = 3;
const EXIT_TRASH_ERR = 4;

function die(code, msg) {
  if (msg) process.stderr.write(`safe-rm: ${msg}\n`);
  process.exit(code);
}

function psQuote(s) {
  return `'${String(s).replace(/'/g, "''")}'`;
}

// Pick the best PowerShell available. Windows 11 ships PowerShell 7+
// (`pwsh.exe`) by default; legacy 5.1 (`powershell.exe`) may not be
// installed. SHELLISH_POWERSHELL overrides everything.
function pwshExe() {
  if (process.env.SHELLISH_POWERSHELL) return process.env.SHELLISH_POWERSHELL;
  // PowerShell 7 standard install location; if present, prefer it.
  if (process.platform === 'win32') {
    const pwsh = 'C:/Program Files/PowerShell/7/pwsh.exe';
    try { if (fs.existsSync(pwsh)) return pwsh; } catch { /* ignore */ }
  }
  return 'powershell.exe';
}

function toRecycleBin(targets) {
  if (!targets.length) return;

  const missing = targets.filter(t => !fs.existsSync(path.resolve(t)));
  if (missing.length) die(EXIT_NOT_FOUND, `path not found: ${missing.join(', ')}`);

  const arr = targets.map(t => psQuote(path.resolve(t))).join(',');
  const ps = `
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName Microsoft.VisualBasic
$paths = @(${arr})
foreach ($p in $paths) {
  $full = [System.IO.Path]::GetFullPath($p)
  if ([System.IO.Directory]::Exists($full)) {
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory(
      $full,
      [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
      [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
  } elseif ([System.IO.File]::Exists($full)) {
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile(
      $full,
      [Microsoft.VisualBasic.FileIO.UIOption]::OnlyErrorDialogs,
      [Microsoft.VisualBasic.FileIO.RecycleOption]::SendToRecycleBin)
  } else {
    Write-Error "Path not found: $full"
    exit ${EXIT_NOT_FOUND}
  }
  if ([System.IO.File]::Exists($full) -or [System.IO.Directory]::Exists($full)) {
    Write-Error "Path still exists after recycle operation: $full"
    exit ${EXIT_TRASH_ERR}
  }
}
`.trim();

  try {
    execFileSync(pwshExe(), ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', ps], {
      stdio: 'inherit',
      windowsHide: true,
    });
  } catch (e) {
    const status = Number.isInteger(e.status) ? e.status : EXIT_TRASH_ERR;
    process.stderr.write(`safe-rm: PowerShell recycle operation failed (exit ${status})\n`);
    process.exit(status === EXIT_NOT_FOUND || status === EXIT_TRASH_ERR ? status : EXIT_TRASH_ERR);
  }
}

function trashOrExit() {
  toRecycleBin(ARGS);
  process.exit(0);
}

if (CONFIRM === 'allow') trashOrExit();

if (SESSION_DIR && fs.existsSync(ALLOW_FILE)) trashOrExit();

if (!SESSION_DIR || !fs.existsSync(SESSION_DIR)) trashOrExit();

const pid     = process.pid;
const reqFile = path.join(SESSION_DIR, `req.${pid}`);
const resFile = path.join(SESSION_DIR, `res.${pid}`);

fs.writeFileSync(reqFile, ARGS.join(' '), 'utf8');

const start = Date.now();
while (Date.now() - start < 60000) {
  if (fs.existsSync(resFile)) {
    const answer = fs.readFileSync(resFile, 'utf8').trim().toLowerCase();
    try { fs.unlinkSync(resFile); } catch { }
    if (answer === 'y' || answer === 'a') {
      if (answer === 'a') {
        try { fs.writeFileSync(ALLOW_FILE, ''); } catch { }
      }
      trashOrExit();
    }
    process.exit(1);
  }
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 100);
}

try { fs.unlinkSync(reqFile); } catch { }
process.exit(1);
