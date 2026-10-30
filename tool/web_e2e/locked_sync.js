// Sync with locked drives: what sync does while some of a wallet's private
// drives are locked, as they are unlocked one at a time and in a batch, while
// a sync runs, when one is forgotten, and after a reload. See
// docs/WEB_E2E_TESTING.md, "Sync with locked drives".
//
//   node locked_sync.js
//
// Same wallet, credentials and set-up as locked_drives.js, in a fresh
// E2E_DIR: launch.js running, then `login.js fresh`, so the sign-in password
// has opened its own drive and every other drive is locked. It turns
// auto-sync on (every AUTO_SYNC_SECONDS, default 30) through the stored
// config, so background syncs tick during the run, and puts the stored
// config back at the end. Every password is typed from the locked-drives
// files and never printed.
//
// Each sync is read from the app's console (launch.js writes it to
// $E2E_DIR/console.log): "Starting Sync" starts one (it is logged before the
// one-at-a-time guard, so a refused start logs it too), "Syncing N chosen
// drives" is the sync after an unlock. A sync that logs "Error syncing
// drives", "Sync completed with N errors" or a page error fails the run, as
// does a "could not be synced" banner. GraphQL requests and gateway errors
// are counted per background sync, from this script's own view of the
// page's requests, and printed: they must not grow from one tick to the next.
//
// Screenshots: $E2E_DIR/shots/lsync-*.png. Exits non-zero on the first check
// that fails.
const { chromium } = require('playwright-core');
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { E2E_DIR, CDP_PORT, ensureDirs, mainPage } = require('./config');

const DIR = process.env.LOCKED_DRIVES ||
  path.join(os.homedir(), '.config', 'ardrive-e2e', 'locked-drives');
const AUTO_SYNC_SECONDS = Number(process.env.AUTO_SYNC_SECONDS || 30);
const FAILED_SYNC = /Error syncing drives|Sync completed with \d+ errors|Error syncing single drive|PAGEERROR/;

(async () => {
  const drives = JSON.parse(fs.readFileSync(path.join(DIR, 'drives.json'), 'utf8'));
  const passwords = JSON.parse(fs.readFileSync(path.join(DIR, 'passwords.json'), 'utf8'));
  ensureDirs();
  const browser = await chromium.connectOverCDP(`http://127.0.0.1:${CDP_PORT}`);
  const page = await mainPage(browser);
  const wait = (ms) => page.waitForTimeout(ms);
  const shot = async (name) => {
    await page.mouse.move(1, 1);
    await wait(300);
    const file = `${E2E_DIR}/shots/lsync-${name}.png`;
    await page.screenshot({ path: file });
    console.log('SHOT', file);
  };
  const labels = () => page.evaluate(() => {
    const all = [];
    const walk = (root) => root.querySelectorAll('*').forEach((e) => {
      if (e.tagName === 'FLT-SEMANTICS') all.push(e);
      if (e.shadowRoot) walk(e.shadowRoot);
    });
    walk(document);
    return all.map((e) => {
      const r = e.getBoundingClientRect();
      return {
        label: (e.getAttribute('aria-label') || e.innerText || '').trim().replace(/\s+/g, ' '),
        x: Math.round(r.x + r.width / 2),
        y: Math.round(r.y + r.height / 2),
        w: Math.round(r.width),
      };
    }).filter((n) => n.label && n.x > 0);
  });
  const has = async (text) => (await labels()).some((n) => n.label.includes(text));
  const check = async (what, ok) => {
    if (!ok) {
      await shot('FAILED');
      console.log('FAIL', what);
      process.exit(1);
    }
    console.log('PASS', what);
  };
  const until = async (test, ms = 30000) => {
    for (const end = Date.now() + ms; Date.now() < end; await wait(500)) {
      if (await test()) return true;
    }
    return false;
  };

  // The app's console since [from], as launch.js wrote it.
  const consoleLog = path.join(E2E_DIR, 'console.log');
  const logSize = () => (fs.existsSync(consoleLog) ? fs.statSync(consoleLog).size : 0);
  const logSince = (from) => (fs.existsSync(consoleLog)
    ? fs.readFileSync(consoleLog, 'utf8').slice(from) : '');
  const count = (text, re) => (text.match(new RegExp(re.source, 'g')) || []).length;
  // A failed sync since [from], by the line it logged; null when none.
  const failedSyncSince = (from) => {
    const line = logSince(from).split('\n').find((l) => FAILED_SYNC.test(l));
    return line ? line.slice(0, 200) : null;
  };

  // What the page asks of GraphQL and of gateways, counted here.
  const requests = { graphql: 0, data: 0, failed: 0 };
  page.on('request', (r) => {
    if (/\/graphql/.test(r.url())) requests.graphql++;
    else if (/\/[A-Za-z0-9_-]{43}(\?|$)/.test(r.url())) requests.data++;
  });
  page.on('response', (r) => { if (r.status() >= 400) requests.failed++; });
  page.on('requestfailed', () => requests.failed++);
  const snapshot = () => ({ ...requests });
  const delta = (a, b) => ({ graphql: b.graphql - a.graphql, data: b.data - a.data, failed: b.failed - a.failed });

  const enableTree = async () => {
    for (const end = Date.now() + 60000; Date.now() < end; await wait(1000)) {
      await page.evaluate(() => {
        const find = (root) => {
          const hit = root.querySelector('flt-semantics-placeholder');
          if (hit) return hit;
          for (const e of root.querySelectorAll('*')) {
            const inner = e.shadowRoot && find(e.shadowRoot);
            if (inner) return inner;
          }
          return null;
        };
        find(document)?.click();
      });
      await wait(1000);
      if ((await labels()).length > 0) return;
    }
  };
  // A screen reader's activation: see locked_drives.js.
  const activate = async (text) => page.evaluate((wanted) => {
    const all = [];
    const walk = (root) => root.querySelectorAll('*').forEach((e) => {
      if (e.tagName === 'FLT-SEMANTICS') all.push(e);
      if (e.shadowRoot) walk(e.shadowRoot);
    });
    walk(document);
    const label = (e) => (e.getAttribute('aria-label') || e.innerText || '').trim().replace(/\s+/g, ' ');
    const hit = all.find((e) => label(e) === wanted) || all.find((e) => label(e).startsWith(wanted));
    if (!hit) return false;
    hit.click();
    return true;
  }, text);
  const typeInField = async (secret) => {
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
    await page.keyboard.insertText(secret);
    await wait(300);
    await page.keyboard.press('Enter');
  };

  const lockedRows = async () => (await labels())
    .filter((n) => n.label.includes('Private drive, Locked') && n.w > 200)
    .sort((a, b) => a.y - b.y);
  const lockedCount = async () => (await lockedRows()).length;
  const unlockButtonOf = async (row) => (await labels())
    .filter((n) => n.label === 'Unlock' && Math.abs(n.y - row.y) < 60)
    .sort((a, b) => Math.abs(a.y - row.y) - Math.abs(b.y - row.y))[0];
  const dialogDriveId = async () => {
    for (const n of await labels()) {
      const m = n.label.match(/([0-9a-f]{6})(?:\.\.\.|…)([0-9a-f]{4})/);
      if (!m) continue;
      const hit = drives.find((d) => d.driveId.startsWith(m[1]) && d.driveId.endsWith(m[2]));
      if (hit) return hit;
    }
    return null;
  };
  // Opens the dialog of the locked row whose drive [pick] chooses, sets the
  // two boxes, and types that drive's own password. Never printed.
  const unlock = async (what, pick, { tryOthers = true } = {}) => {
    for (const row of await lockedRows()) {
      const button = await unlockButtonOf(row);
      await page.mouse.click(button.x, button.y);
      await check(`${what}: the dialog opens`, await until(() => has('Unlock drive'), 10000));
      const drive = await dialogDriveId();
      if (drive && pick(drive)) {
        if (!tryOthers && await has('Try on my other locked drives')) {
          await activate('Try on my other locked drives');
          await wait(400);
        }
        await typeInField(passwords[drive.password]);
        await check(`${what}: the dialog closes`,
          await until(async () => !(await has('Unlock drive')), 30000));
        return drive;
      }
      await page.keyboard.press('Escape');
      await until(async () => !(await has('Unlock drive')), 5000);
    }
    await check(`${what}: a locked row for the drive`, false);
    return null;
  };

  // A reload, then the sign-in password again ("Welcome back").
  const run = (args) => new Promise((resolve, reject) => {
    const child = spawn('node', [path.join(__dirname, 'login.js'), ...args],
      { stdio: ['ignore', 'inherit', 'inherit'], env: process.env });
    child.on('error', reject);
    child.on('exit', (code) => (code === 0 ? resolve()
      : reject(new Error(`login.js ${args.join(' ')} exited ${code}`))));
  });
  const loginDrive = drives.find((d) => d.password === 'login');
  const reloadAndUnlock = async () => {
    await page.reload();
    await wait(8000);
    await run(['unlock']);
    await enableTree();
    await until(() => has(loginDrive.name), 90000);
    await wait(5000);
  };

  // Auto-sync on, every AUTO_SYNC_SECONDS. The stored config wins over the
  // build's (see CLAUDE.md, "Config Resolution"), so this lasts until it is
  // put back. Read before any change, and put back at the end.
  const storedConfig = await page.evaluate(() => localStorage.getItem('flutter.config'));
  await check('a stored config to change', storedConfig !== null);
  const setAutoSync = () => page.evaluate(([raw, seconds]) => {
    const config = JSON.parse(JSON.parse(raw));
    config.autoSync = true;
    config.autoSyncIntervalInSeconds = seconds;
    localStorage.setItem('flutter.config', JSON.stringify(JSON.stringify(config)));
  }, [storedConfig, AUTO_SYNC_SECONDS]);

  // The next [n] background syncs: each must end without an error, and is
  // counted. Returns the requests each cost.
  const ticks = async (what, n) => {
    const costs = [];
    for (let i = 0; i < n; i++) {
      const from = logSize();
      const before = snapshot();
      const started = await until(() => /Starting Sync/.test(logSince(from)),
        (AUTO_SYNC_SECONDS + 60) * 1000);
      await check(`${what}: background sync ${i + 1} starts`, started);
      // Ended: the next one has not started, and nothing says Syncing.
      await wait(AUTO_SYNC_SECONDS * 1000 - 3000);
      const failed = failedSyncSince(from);
      await check(`${what}: background sync ${i + 1} ends without an error${failed ? ` (${failed})` : ''}`,
        failed === null);
      costs.push(delta(before, snapshot()));
    }
    console.log(`COST ${what}: ${costs.map((c) => `gql=${c.graphql} data=${c.data} failed=${c.failed}`).join(' | ')}`);
    return costs;
  };
  const noFailureBanner = async (what) => check(`${what}: no "could not be synced" banner`,
    !(await has('could not be synced')) && !(await has('Sync incomplete')));

  await page.setViewportSize({ width: 1440, height: 900 });
  await setAutoSync();
  await reloadAndUnlock();

  const all = drives.length;
  const locked0 = all - 1;

  // 1. One of N open, the rest locked: background syncs run clean, and cost
  //    the same each time.
  await check(`1 of ${all} open: ${locked0} drives are locked`,
    await until(async () => await lockedCount() === locked0, 90000));
  await shot('1-one-open');
  const costs = await ticks(`1 of ${all} open`, 3);
  await check('later background syncs cost no more requests than the second',
    costs[2].graphql <= costs[1].graphql);
  await check('and no gateway errors repeat', costs[2].failed <= costs[1].failed);
  await noFailureBanner('1 of N open');
  await check('the locked drives stay locked, and listed', await lockedCount() === locked0);

  // 2. Unlock one, "Try on my other locked drives" unticked: only that drive
  //    opens, and the sync after it covers that drive alone. A background
  //    sync later does not open the others with its password.
  const shared = drives.filter((d) => d.password === 'other');
  let from = logSize();
  const first = await unlock('unlock one, try-others off', (d) => d.password === 'other', { tryOthers: false });
  await check('one drive fewer is locked', await until(async () => await lockedCount() === locked0 - 1, 30000));
  await check('the sync after it covers the one drive',
    await until(() => /Syncing 1 chosen drives/.test(logSince(from)), 60000));
  await check('its name is listed', await until(() => has(first.name), 30000));
  await ticks('after one unlock', 1);
  await check('a background sync left the drives sharing its password locked',
    await lockedCount() === locked0 - 1);
  await shot('2-one-unlocked');

  // 3. Unlock with "Try on my other locked drives": the drives sharing the
  //    password open together, and the sync after covers exactly those.
  from = logSize();
  if (shared.length > 1) {
    await unlock('unlock with try-others', (d) => d.password === 'other' && d.driveId !== first.driveId);
    const opened = shared.length - 1;
    await check(`${opened} more open`, await until(async () => await lockedCount() === locked0 - shared.length, 30000));
    await check(`the sync after it covers ${opened} drive(s)`,
      await until(() => new RegExp(`Syncing ${opened} chosen drives`).test(logSince(from)), 60000));
  }
  await noFailureBanner('after the unlocks');

  // 4. Unlock while a sync runs: the unlocked drive is synced once the
  //    running one ends, and the running one is not disturbed.
  const lastLocked = await lockedCount();
  if (lastLocked > 0) {
    from = logSize();
    await check('a background sync is running',
      await until(() => /Starting Sync/.test(logSince(from)), (AUTO_SYNC_SECONDS + 60) * 1000));
    await unlock('unlock during a sync', () => true);
    await check('one drive fewer is locked', await until(async () => await lockedCount() === lastLocked - 1, 30000));
    await check('the unlocked drive is synced after',
      await until(() => /Syncing 1 chosen drives/.test(logSince(from)), 90000));
    await check('and nothing failed', failedSyncSince(from) === null);
    await shot('4-unlock-during-sync');
  }

  // 5. Stop syncing, mid-sync: it stops, says nothing failed, and the next
  //    background sync runs as usual.
  from = logSize();
  await check('a background sync starts',
    await until(() => /Starting Sync/.test(logSince(from)), (AUTO_SYNC_SECONDS + 60) * 1000));
  const stopped = await until(async () => (await activate('Stop syncing')), 5000);
  if (stopped) {
    await check('it stops', await until(() => /Sync cancelled by user|Requesting sync cancellation/.test(logSince(from)), 30000));
    await shot('5-stopped');
    await check('a stop is not a failure', failedSyncSince(from) === null);
    await noFailureBanner('after Stop');
    await ticks('after Stop', 1);
  } else {
    console.log('NOTE the sync ended before Stop syncing could be pressed');
  }

  // 6. Forget one drive on this device: it stays open and synced this
  //    session, and is locked after a reload while the rest open.
  const forgotten = first;
  const rows = (await labels()).filter((n) => n.label.includes(forgotten.name) && n.w > 200)
    .sort((x, y) => x.y - y.y);
  await page.mouse.click(rows[0].x - Math.floor(rows[0].w / 2) + 40, rows[0].y);
  await wait(1500);
  // The button sits at the foot of the details panel, below the fold at
  // 1440x900 once every drive is open: scrolled into view, so its node is
  // in the tree.
  await page.mouse.move(1250, 600);
  await page.mouse.wheel(0, 1200);
  await wait(1000);
  await check('the details panel offers "Forget on this device"',
    await until(() => has('Forget on this device'), 20000));
  await activate('Forget on this device');
  await check('it then says "Not remembered"', await until(() => has('Not remembered'), 10000));
  await ticks('after Forget', 1);
  await check('the forgotten drive is still open this session', await has(forgotten.name));
  const openBeforeReload = all - await lockedCount();

  // 7. A reload: the remembered drives open from this device with nothing
  //    asked, the forgotten one is locked, and background syncs run clean.
  await reloadAndUnlock();
  await check('after a reload, only the forgotten drive is newly locked',
    await until(async () => all - await lockedCount() === openBeforeReload - 1, 90000));
  await ticks('after a reload', 2);
  await noFailureBanner('after a reload');
  await shot('7-after-reload');

  await page.evaluate((raw) => localStorage.setItem('flutter.config', raw), storedConfig);
  console.log('DONE');
  process.exit(0);
})().catch((e) => { console.log('ERROR', e.message); process.exit(1); });
