'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');

function windowsAppData() {
  return process.env.APPDATA || path.join(os.homedir(), 'AppData', 'Roaming');
}

function defaultConfigFile() {
  return process.platform === 'win32'
    ? path.join(windowsAppData(), 'shellish', 'config')
    : path.join(os.homedir(), '.config', 'shellish', 'config');
}

function legacyConfigFile() {
  return path.join(os.homedir(), '.config', 'shellish', 'config');
}

function configFile() {
  return process.env.SHELLISH_CONFIG_FILE
    || (process.env.SHELLISH_CONFIG_DIR ? path.join(process.env.SHELLISH_CONFIG_DIR, 'config') : defaultConfigFile());
}

function candidates() {
  const file = configFile();
  const out = [file];
  const legacy = legacyConfigFile();
  if (process.platform === 'win32' && legacy !== file) out.push(legacy);
  return out;
}

function decodeConfig(buf) {
  if (buf.length >= 2 && buf[0] === 0xff && buf[1] === 0xfe) {
    return buf.toString('utf16le').replace(/^\uFEFF/, '');
  }
  if (buf.length >= 2 && buf[0] === 0xfe && buf[1] === 0xff) {
    // Node has no utf16be decoder; config is ASCII-ish, swap bytes.
    const swapped = Buffer.allocUnsafe(buf.length - 2);
    for (let i = 2; i + 1 < buf.length; i += 2) {
      swapped[i - 2] = buf[i + 1];
      swapped[i - 1] = buf[i];
    }
    return swapped.toString('utf16le').replace(/^\uFEFF/, '');
  }
  const utf8 = buf.toString('utf8').replace(/^\uFEFF/, '');
  if (utf8.includes('\u0000')) return buf.toString('utf16le').replace(/^\uFEFF/, '');
  return utf8;
}

function readConfigText(file) {
  return decodeConfig(fs.readFileSync(file));
}

function readExistingText() {
  for (const file of candidates()) {
    try { return { file, text: readConfigText(file) }; } catch { }
  }
  return { file: configFile(), text: '' };
}

function get(key) {
  const { text } = readExistingText();
  for (const l of text.split(/\r?\n/)) {
    const m = l.match(new RegExp(`^${key}=(.*)$`));
    if (m) return m[1].trim();
  }
  return '';
}

function set(key, value) {
  const file = configFile();
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const { text } = readExistingText();
  const lines = text.split(/\r?\n/).filter(l => l && !l.startsWith(`${key}=`));
  lines.push(`${key}=${value}`);
  fs.writeFileSync(file, lines.join('\n') + '\n', 'utf8');
}

module.exports = {
  windowsAppData,
  defaultConfigFile,
  legacyConfigFile,
  configFile,
  candidates,
  decodeConfig,
  readConfigText,
  get,
  set,
};
