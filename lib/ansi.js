'use strict';

function supportsAnsi(stream = process.stdout) {
  if (process.env.NO_COLOR) return false;
  if (process.env.FORCE_COLOR && process.env.FORCE_COLOR !== '0') return true;
  if (process.platform === 'win32') {
    if (process.env.TERM_PROGRAM === 'vscode') return true;
    if (process.env.WT_SESSION || process.env.ConEmuANSI === 'ON' || process.env.ANSICON) return true;
  }
  return !!stream.isTTY;
}

function codes(stream = process.stdout) {
  const on = supportsAnsi(stream);
  const c = n => on ? `\x1b[${n}m` : '';
  return {
    enabled: on,
    R: c(0), BOLD: c(1), DIM: c(2),
    RED: c(31), GREEN: c(32), YELLOW: c(33), CYAN: c(36),
  };
}

// Terminal display width: CJK/fullwidth chars and emoji occupy 2 columns.
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

// Truncate so the result renders in at most `width` columns (appending `…`,
// itself 1 column, when truncation happens).
function truncateDisplay(s, width) {
  s = String(s || '');
  if (displayWidth(s) <= width) return s;
  let out = '';
  let used = 0;
  for (const ch of [...s]) {
    const w = displayWidth(ch);
    if (used + w > width - 1) break;
    out += ch;
    used += w;
  }
  return out + '…';
}

module.exports = { supportsAnsi, codes, displayWidth, padDisplay, truncateDisplay };
