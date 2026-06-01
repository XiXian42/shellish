'use strict';

const crypto = require('crypto');

function safeHistoryKey(cwd) {
  const text = String(cwd || '');
  const base = text.replace(/[^a-zA-Z0-9_\-]/g, '_').slice(-48) || 'cwd';
  const hash = crypto.createHash('sha256').update(text).digest('hex').slice(0, 12);
  return `${base}_${hash}`;
}

module.exports = { safeHistoryKey };
