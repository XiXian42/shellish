#!/usr/bin/env node
// shellish/lib/safe-rm.js
// Windows drop-in rm replacement. Moves targets to Recycle Bin with optional
// shellish confirmation handshake.

'use strict';

const fs   = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

// Split rm-style argv into { targets, force }. Flags are dropped (recursion
// is implied when trashing a directory); -f / --force is remembered so
// missing operands can follow rm semantics (silently ignored).
function parseRmArgs(raw) {
  let pastDash = false;
  let force = false;
  const targets = [];
  for (const a of raw) {
    if (a === '--' && !pastDash) { pastDash = true; continue; }
    if (!pastDash && a.startsWith('-')) {
      if (a === '--force' || /^-[a-zA-Z]*f/.test(a)) force = true;
      continue;
    }
    targets.push(a);
  }
  return { targets, force };
}

const RAW_ARGS     = process.argv.slice(2);
const PARSED       = parseRmArgs(RAW_ARGS);
const ARGS         = PARSED.targets;
const FORCE        = PARSED.force;
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

function findOnPath(exe) {
  try {
    const out = execFileSync('where', [exe], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] });
    return out.split(/\r?\n/).map(s => s.trim()).find(Boolean) || '';
  } catch { return ''; }
}

// Pick the best PowerShell available. SHELLISH_POWERSHELL overrides everything.
function pwshExe() {
  if (process.env.SHELLISH_POWERSHELL) return process.env.SHELLISH_POWERSHELL;
  if (process.platform === 'win32') {
    const onPathPwsh = findOnPath('pwsh.exe') || findOnPath('pwsh');
    if (onPathPwsh) return onPathPwsh;
    const standardPwsh = 'C:/Program Files/PowerShell/7/pwsh.exe';
    try { if (fs.existsSync(standardPwsh)) return standardPwsh; } catch { /* ignore */ }
    const onPathWindowsPs = findOnPath('powershell.exe') || findOnPath('powershell');
    if (onPathWindowsPs) return onPathWindowsPs;
  }
  return 'powershell.exe';
}

function toRecycleBin(targets) {
  if (!targets.length) return;

  const missing = targets.filter(t => !fs.existsSync(path.resolve(t)));
  if (missing.length && !FORCE) die(EXIT_NOT_FOUND, `path not found: ${missing.join(', ')}`);
  // -f: rm semantics — ignore missing operands silently.
  targets = targets.filter(t => fs.existsSync(path.resolve(t)));
  if (!targets.length) return;

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

function main() {
  if (!ARGS.length) {
    if (FORCE) process.exit(0);
    die(1, 'missing operand');
  }

  if (CONFIRM === 'allow') trashOrExit();

  if (SESSION_DIR && fs.existsSync(ALLOW_FILE)) trashOrExit();

  if (!SESSION_DIR || !fs.existsSync(SESSION_DIR)) trashOrExit();

  const pid     = process.pid;
  const reqFile = path.join(SESSION_DIR, `req.${pid}`);
  const resFile = path.join(SESSION_DIR, `res.${pid}`);

  // Show the original argv so the user sees exactly what the agent ran.
  fs.writeFileSync(reqFile, RAW_ARGS.join(' '), 'utf8');

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
}

if (require.main === module) main();

module.exports = { parseRmArgs };
