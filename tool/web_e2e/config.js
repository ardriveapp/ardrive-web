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

// CHROME, or the Chromium build the installed playwright-core was made for.
// A newer build does not do: with Chrome 156 under playwright-core 1.48 the
// viewport fell back to 1440x700, then 780x380 after each reconnect, and
// login.js's coordinate clicks hit the wrong buttons.
function chromePath() {
  if (process.env.CHROME) return process.env.CHROME;
  const cache = path.join(os.homedir(), '.cache', 'ms-playwright');
  let revision;
  try {
    const manifest = path.join(path.dirname(require.resolve('playwright-core')), 'browsers.json');
    revision = JSON.parse(fs.readFileSync(manifest, 'utf8')).browsers.find((b) => b.name === 'chromium').revision;
  } catch (e) {}
  const build = revision && `chromium-${revision}`;
  for (const dir of ['chrome-linux', 'chrome-linux-arm64', 'chrome-linux64']) {
    const exe = build && path.join(cache, build, dir, 'chrome');
    if (exe && fs.existsSync(exe)) return exe;
  }
  throw new Error(`No ${build || 'Chromium'} found. Run \`npx playwright-core install chromium\` in tool/web_e2e, or set CHROME.`);
}

// The tab launch.js opened. A second tab, opened during a test, can come
// first in the browser's own list, so steps find this one by its target id,
// which launch.js records.
async function mainPage(browser) {
  const pages = browser.contexts()[0].pages();
  let id = null;
  try { id = fs.readFileSync(path.join(E2E_DIR, 'main-target'), 'utf8').trim(); } catch (e) {}
  if (id) {
    for (const page of pages) {
      const session = await page.context().newCDPSession(page);
      const { targetInfo } = await session.send('Target.getTargetInfo');
      await session.detach();
      if (targetInfo.targetId === id) return page;
    }
  }
  if (pages.length !== 1) throw new Error(`launch.js's tab is gone and ${pages.length} others are open; restart launch.js`);
  return pages[0];
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

module.exports = { E2E_DIR, APP_URL, CDP_PORT, CREDENTIALS, ensureDirs, chromePath, mainPage, credentials, keyfilePath, address };
