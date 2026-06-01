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

module.exports = { supportsAnsi, codes };
