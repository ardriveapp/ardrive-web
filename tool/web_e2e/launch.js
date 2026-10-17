// Starts headless Chromium on the web app and keeps it running, with a guard
// that stops tests from spending AR or Turbo Credits. Other scripts attach to
// it over CDP (see step.js). Read docs/WEB_E2E_TESTING.md first.
//
//   node launch.js
//
// Everything it writes goes under E2E_DIR (default ~/.cache/ardrive-e2e):
// profile/ (the browser profile, so a login survives restarts), net.log
// (every POST and every guard decision), console.log, shots/.
//
// The guard, on every request the page makes:
// - Wallet-paid (AR) uploads: POST /tx, POST /chunk and GET /tx/{id}/status,
//   to any host, never reach a real gateway. AR_UPLOADS=chaos (the default)
//   sends them to the local fake gateway (chaos_gateway.py on CHAOS_URL);
//   AR_UPLOADS=dryrun lets them through to https://ar-io.dev only while it
//   answers as a dry-run gateway; AR_UPLOADS=block refuses them.
// - Turbo uploads to the real (production and staging) services: an upload of
//   up to TURBO_FREE_BYTES (107520, Turbo's free size) goes through; anything
//   bigger, and any multipart upload, is refused unless TURBO_PAID=1.
// - Turbo top-ups on the real payment service are always refused.
// - Development builds (PR previews) use testnet Turbo services: free, wiped
//   after a few days. Their uploads and payments are not guarded.
// A refused request is answered with a 503 and logged as BLOCKED.
//
// FAKE_AR_BALANCE=<winston> answers wallet balance lookups with that amount,
// so the app allows an AR-paid upload the test wallet can't afford. Only
// with AR_UPLOADS=chaos or block, so nothing is ever really sent.
//
// File choosers are answered here with the paths queued in
// $E2E_DIR/nextfiles.json (a JSON array), then the queue is cleared. It has
// to be this process: Playwright only hands over files above 50 MB from the
// process that launched the browser. The wallet keyfile is only ever handed
// over to login.js's chooser, and nothing from the credentials folder at all,
// so a test can never upload either.
const { chromium } = require('playwright-core');
const fs = require('fs');
const path = require('path');
const { E2E_DIR, APP_URL, CDP_PORT, CREDENTIALS, chromePath, ensureDirs, keyfilePath } = require('./config');

const AR_UPLOADS = process.env.AR_UPLOADS || 'chaos';
const CHAOS_URL = process.env.CHAOS_URL || 'http://127.0.0.1:8850';
const TURBO_FREE_BYTES = Number(process.env.TURBO_FREE_BYTES || 107520);
const TURBO_PAID = process.env.TURBO_PAID === '1';
const FAKE_AR_BALANCE = process.env.FAKE_AR_BALANCE;
const DRY_RUN_GATEWAY = 'https://ar-io.dev';
const AR_UPLOAD_PATHS = /^https?:\/\/[^/]+\/(tx|chunk|tx\/[^/]+\/status)$/;
// The Turbo services that cost real money, read from the app's own config so
// the guard follows any change there: those of every flavor except
// development. Development builds (PR previews) use the services.ar-io.dev
// Turbo services, which are testnet: free, and wiped after a few days, so
// they are let through. A host the development config shares with another
// flavor is still guarded.
const configs = (() => {
  const dir = path.join(__dirname, '..', '..', 'assets', 'config');
  return fs.readdirSync(dir).filter((f) => f.endsWith('.json'))
    .map((f) => ({ name: f, config: JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')) }));
})();
const origins = (key, flavors) => [...new Set(configs
  .filter(({ name }) => flavors(name))
  .map(({ config }) => config[key]).filter(Boolean).map((u) => new URL(u).origin))];
const isDev = (name) => name === 'dev.json';
const guardedOrigins = (key) => {
  const real = origins(key, (n) => !isDev(n));
  if (!real.length) throw new Error(`no ${key} in assets/config`);
  return real;
};
const testnetOrigins = (key) => origins(key, isDev).filter((o) => !guardedOrigins(key).includes(o));
const originMatcher = (list) => ({ test: (url) => list.some((o) => url.startsWith(o + '/')) });
const TURBO_UPLOAD_ORIGINS = guardedOrigins('defaultTurboUploadUrl');
const TURBO_PAYMENT_ORIGINS = guardedOrigins('defaultTurboPaymentUrl');
const TURBO_TESTNET_ORIGINS = [...testnetOrigins('defaultTurboUploadUrl'), ...testnetOrigins('defaultTurboPaymentUrl')];
const TURBO_UPLOAD = originMatcher(TURBO_UPLOAD_ORIGINS);
const TURBO_PAYMENT = originMatcher(TURBO_PAYMENT_ORIGINS);

if (!['chaos', 'dryrun', 'block'].includes(AR_UPLOADS)) {
  console.error(`AR_UPLOADS must be chaos, dryrun or block, not ${AR_UPLOADS}`);
  process.exit(1);
}
if (FAKE_AR_BALANCE && AR_UPLOADS === 'dryrun') {
  console.error('FAKE_AR_BALANCE needs AR_UPLOADS=chaos or block');
  process.exit(1);
}

ensureDirs();
const net = fs.createWriteStream(`${E2E_DIR}/net.log`, { flags: 'a' });
const log = (o) => net.write(JSON.stringify({ t: new Date().toISOString(), ...o }) + '\n');
const cors = { 'access-control-allow-origin': '*' };
const refuse = (route, why) => {
  const r = route.request();
  log({ ev: 'BLOCKED', method: r.method(), url: r.url().slice(0, 160), why });
  return route.fulfill({ status: 503, headers: cors, body: `blocked by e2e guard: ${why}` });
};

// ar-io.dev runs with ARWEAVE_POST_DRY_RUN: it answers a junk header with 200
// "OK". A gateway that forwards to mainnet answers 400 "Invalid JSON.". Asked
// before every header, so a gateway that changes mid-run can't spend AR.
async function dryRunHolds() {
  try {
    const r = await fetch(`${DRY_RUN_GATEWAY}/tx`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{"id":"x"}',
    });
    return r.status === 200 && (await r.text()).trim() === 'OK';
  } catch (e) {
    return false;
  }
}

// A guard that throws refuses the request: an error must never let one through.
const failClosed = (guard) => async (route) => {
  try {
    return await guard(route);
  } catch (e) {
    return refuse(route, `guard error: ${String(e).slice(0, 120)}`);
  }
};

async function guardArUpload(route) {
  const req = route.request();
  const url = new URL(req.url());
  if (req.method() === 'OPTIONS') {
    return route.fulfill({
      status: 204,
      headers: { ...cors, 'access-control-allow-headers': '*', 'access-control-allow-methods': 'GET, POST, OPTIONS' },
    });
  }
  if (AR_UPLOADS === 'block') return refuse(route, 'AR_UPLOADS=block');
  if (AR_UPLOADS === 'dryrun') {
    if (url.origin !== DRY_RUN_GATEWAY) {
      return refuse(route, `AR_UPLOADS=dryrun only allows ${DRY_RUN_GATEWAY}; switch the app's gateway to it`);
    }
    if (req.method() === 'POST' && url.pathname === '/tx' && !(await dryRunHolds())) {
      return refuse(route, `${DRY_RUN_GATEWAY} is not answering as a dry-run gateway`);
    }
    log({ ev: 'dryrun', method: req.method(), path: url.pathname.slice(0, 60) });
    return route.continue();
  }
  try {
    const res = await route.fetch({ url: CHAOS_URL + url.pathname, timeout: 180000 });
    log({ ev: 'chaos', method: req.method(), path: url.pathname.slice(0, 60), status: res.status() });
    return route.fulfill({
      status: res.status(),
      headers: { ...cors, 'content-type': res.headers()['content-type'] || 'text/plain' },
      body: await res.text(),
    });
  } catch (e) {
    log({ ev: 'chaos', method: req.method(), path: url.pathname.slice(0, 60), status: 'ERR', err: String(e).slice(0, 160) });
    return route.abort();
  }
}

async function guardTurbo(route) {
  const req = route.request();
  if (!['POST', 'PUT'].includes(req.method()) || TURBO_PAID) return route.continue();
  const urlPath = new URL(req.url()).pathname;
  if (urlPath.includes('/chunks/')) return refuse(route, 'multipart Turbo upload (too big to be free); set TURBO_PAID=1');
  const size = (req.postDataBuffer() || Buffer.alloc(0)).length;
  if (size > TURBO_FREE_BYTES) {
    return refuse(route, `Turbo upload of ${size} bytes is over the free ${TURBO_FREE_BYTES}; set TURBO_PAID=1`);
  }
  log({ ev: 'turbo', method: req.method(), path: urlPath.slice(0, 60), bytes: size });
  return route.continue();
}

(async () => {
  const ctx = await chromium.launchPersistentContext(`${E2E_DIR}/profile`, {
    headless: true,
    executablePath: chromePath(),
    viewport: { width: 1440, height: 900 },
    args: ['--no-sandbox', `--remote-debugging-port=${CDP_PORT}`],
  });

  await ctx.route(AR_UPLOAD_PATHS, failClosed(guardArUpload));
  await ctx.route((url) => TURBO_UPLOAD.test(url.href), failClosed(guardTurbo));
  await ctx.route((url) => TURBO_PAYMENT.test(url.href), (route) =>
    route.request().method() === 'GET' ? route.continue() : refuse(route, 'Turbo top-ups are never automated'));
  if (FAKE_AR_BALANCE) {
    await ctx.route(/\/wallet\/[^/]+\/balance$/, (route) => {
      log({ ev: 'fake-balance', winston: FAKE_AR_BALANCE });
      return route.fulfill({ status: 200, headers: cors, body: String(FAKE_AR_BALANCE) });
    });
  }

  // Every other POST, for the record. Requests the guard handles are logged
  // by the guard, with where they really went.
  const guarded = [AR_UPLOAD_PATHS, TURBO_UPLOAD, TURBO_PAYMENT];
  ctx.on('request', (req) => {
    if (req.method() !== 'POST' || guarded.some((re) => re.test(req.url()))) return;
    const u = new URL(req.url());
    if (u.protocol === 'http:' || u.protocol === 'https:') log({ ev: 'post', host: u.host, path: u.pathname.slice(0, 80) });
  });

  const page = ctx.pages()[0] || (await ctx.newPage());
  page.on('filechooser', async (chooser) => {
    const queue = `${E2E_DIR}/nextfiles.json`;
    let files = [];
    try { files = JSON.parse(fs.readFileSync(queue, 'utf8')); } catch (e) {}
    const loginMarker = `${E2E_DIR}/login-chooser`;
    const forLogin = fs.existsSync(loginMarker);
    if (forLogin) fs.rmSync(loginMarker);
    const real = (p) => { try { return fs.realpathSync(p); } catch (e) { return path.resolve(p); } };
    const keyfile = keyfilePath();
    const secret = (p) => (keyfile && real(p) === real(keyfile) && !forLogin) ||
      real(p).startsWith(real(path.dirname(CREDENTIALS)) + path.sep);
    if (files.some(secret)) {
      log({ ev: 'BLOCKED', what: 'filechooser', why: 'a queued file is the wallet keyfile or a credentials file' });
      files = [];
    }
    log({ ev: 'filechooser', files: files.length, login: forLogin });
    try { await chooser.setFiles(files); } catch (e) { log({ ev: 'filechooser-failed', err: e.message.split('\n')[0] }); }
    fs.writeFileSync(queue, '[]');
  });
  const consoleLog = fs.createWriteStream(`${E2E_DIR}/console.log`, { flags: 'a' });
  page.on('console', (m) => consoleLog.write(`${new Date().toISOString()} ${m.type()} ${m.text().replace(/\s+/g, ' ').slice(0, 400)}\n`));
  page.on('pageerror', (e) => consoleLog.write(`${new Date().toISOString()} PAGEERROR ${e.message.slice(0, 400)}\n`));
  page.on('dialog', (d) => { log({ ev: 'dialog', type: d.type(), message: d.message() }); d.dismiss().catch(() => {}); });

  await page.goto(APP_URL);
  console.log(`READY ${APP_URL} cdp=${CDP_PORT} ar_uploads=${AR_UPLOADS} turbo_paid=${TURBO_PAID} dir=${E2E_DIR}`);
  console.log(`guarding Turbo ${[...TURBO_UPLOAD_ORIGINS, ...TURBO_PAYMENT_ORIGINS].join(' ')}`);
  console.log(`testnet Turbo, not guarded: ${TURBO_TESTNET_ORIGINS.join(' ') || 'none'}`);
  await new Promise(() => {});
})();
