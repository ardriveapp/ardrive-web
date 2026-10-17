// Settings shared by the e2e scripts. Each can be overridden by an environment
// variable of the same name. The test wallet's keyfile path and password are
// read from a local file outside the repo (CREDENTIALS, default
// ~/.config/ardrive-e2e/env) and never printed. See docs/WEB_E2E_TESTING.md.
const fs = require('fs');
const os = require('os');
const path = require('path');

const E2E_DIR = process.env.E2E_DIR || path.join(os.homedir(), '.cache', 'ardrive-e2e');
const APP_URL = process.env.APP_URL || 'http://127.0.0.1:8090/';
const CDP_PORT = Number(process.env.CDP_PORT || 9223);
const CREDENTIALS = process.env.CREDENTIALS || path.join(os.homedir(), '.config', 'ardrive-e2e', 'env');

function ensureDirs() {
  fs.mkdirSync(path.join(E2E_DIR, 'shots'), { recursive: true });
}

// CHROME, or the newest Chromium Playwright has downloaded.
function chromePath() {
  if (process.env.CHROME) return process.env.CHROME;
  const cache = path.join(os.homedir(), '.cache', 'ms-playwright');
  const builds = fs.existsSync(cache)
    ? fs.readdirSync(cache).filter((d) => /^chromium-\d+$/.test(d))
        .sort((a, b) => Number(b.split('-')[1]) - Number(a.split('-')[1]))
    : [];
  for (const build of builds) {
    for (const dir of ['chrome-linux', 'chrome-linux-arm64', 'chrome-linux64']) {
      const exe = path.join(cache, build, dir, 'chrome');
      if (fs.existsSync(exe)) return exe;
    }
  }
  throw new Error('No Chromium found. Run `npx playwright-core install chromium` here, or set CHROME.');
}

// KEY=VALUE lines. Environment variables win over the file.
function credentials() {
  const found = {};
  if (fs.existsSync(CREDENTIALS)) {
    for (const line of fs.readFileSync(CREDENTIALS, 'utf8').split('\n')) {
      const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/);
      if (m) found[m[1]] = m[2].replace(/^(['"])(.*)\1$/, '$2');
    }
  }
  const keyfile = process.env.ARDRIVE_E2E_KEYFILE || found.ARDRIVE_E2E_KEYFILE;
  const password = process.env.ARDRIVE_E2E_PASSWORD || found.ARDRIVE_E2E_PASSWORD;
  if (!keyfile || !password) {
    throw new Error(`Set ARDRIVE_E2E_KEYFILE and ARDRIVE_E2E_PASSWORD in ${CREDENTIALS} (see docs/WEB_E2E_TESTING.md)`);
  }
  if (!fs.existsSync(keyfile)) throw new Error(`ARDRIVE_E2E_KEYFILE does not exist: ${keyfile}`);
  return { keyfile, password };
}

// The test wallet's address (public, not a secret): ARDRIVE_E2E_ADDRESS in
// the credentials file or the environment.
function address() {
  if (process.env.ARDRIVE_E2E_ADDRESS) return process.env.ARDRIVE_E2E_ADDRESS;
  if (!fs.existsSync(CREDENTIALS)) return null;
  const m = fs.readFileSync(CREDENTIALS, 'utf8').match(/^\s*ARDRIVE_E2E_ADDRESS\s*=\s*['"]?([A-Za-z0-9_-]{43})['"]?\s*$/m);
  return m ? m[1] : null;
}

// The keyfile's path alone, or null, for guards that must not fail when no
// credentials are set up.
function keyfilePath() {
  try { return credentials().keyfile; } catch (e) { return null; }
}

module.exports = { E2E_DIR, APP_URL, CDP_PORT, CREDENTIALS, ensureDirs, chromePath, credentials, keyfilePath, address };
