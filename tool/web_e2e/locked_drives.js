// The locked drives flow: a wallet whose private drives have different
// passwords signs in with one of them, and the others show as locked and are
// unlocked from the drive list. See docs/WEB_E2E_TESTING.md, "Locked drives".
//
//   node locked_drives.js
//
// Needs launch.js running with this wallet's credentials and login.js done
// (both with the same CREDENTIALS and E2E_DIR as this), and the drives
// described in LOCKED_DRIVES (default ~/.config/ardrive-e2e/locked-drives):
//
//   drives.json      [{ name, password, driveId }], password naming a key of
//   passwords.json   { login, other, unicode }: the drive passwords
//
// Every password is typed from those files and never printed. Screenshots
// land in $E2E_DIR/shots/locked-*.png, at 1440x900 and at 390x844. It checks
// each step through the accessibility tree, which it turns on (it uses no
// menus, which is what the tree breaks), and exits non-zero on the first
// check that fails.
const { chromium } = require('playwright-core');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { E2E_DIR, CDP_PORT, ensureDirs, mainPage } = require('./config');

const DIR = process.env.LOCKED_DRIVES ||
  path.join(os.homedir(), '.config', 'ardrive-e2e', 'locked-drives');

const WRONG = 'Wrong password';
const OFFLINE = "Couldn't reach the network. Try again.";

(async () => {
  const drives = JSON.parse(fs.readFileSync(path.join(DIR, 'drives.json'), 'utf8'));
  const passwords = JSON.parse(fs.readFileSync(path.join(DIR, 'passwords.json'), 'utf8'));
  ensureDirs();
  const browser = await chromium.connectOverCDP(`http://127.0.0.1:${CDP_PORT}`);
  const page = await mainPage(browser);
  const wait = (ms) => page.waitForTimeout(ms);
  const shot = async (name, clip) => {
    await page.mouse.move(1, 1);
    await wait(300);
    const file = `${E2E_DIR}/shots/locked-${name}.png`;
    await page.screenshot({ path: file, clip });
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

  // The locked rows, top to bottom. They sort after every readable drive and
  // among themselves by drive id, which is how each is matched to its drive.
  const lockedRows = async () => (await labels())
    .filter((n) => n.label.startsWith('Private drive') && n.w > 200)
    .sort((a, b) => a.y - b.y);
  const lockedIds = (ids) => [...ids].sort();
  const unlockButtonOf = async (row) => (await labels())
    .filter((n) => n.label === 'Unlock' && Math.abs(n.y - row.y) < 20)[0];
  const typeInField = async (secret) => {
    const field = (await labels()).find((n) => n.label.includes('Drive password'));
    await page.mouse.click(field.x, field.y);
    await page.keyboard.press('Control+A');
    await page.keyboard.type(secret, { delay: 10 });
    await page.keyboard.press('Enter');
  };

  await page.setViewportSize({ width: 1440, height: 900 });
  await page.evaluate(() => document.querySelector('flt-semantics-placeholder')?.click());
  await wait(1500);

  // 1. Signed in with the login password: its drive opens, the others are
  //    locked, each with its emoji.
  const lockedDrives = drives.filter((d) => d.password !== 'login');
  await check('every other private drive is listed as locked',
    await until(async () => (await lockedRows()).length === lockedDrives.length, 60000));
  await check('the drive the login password opens is listed by name',
    await has(drives.find((d) => d.password === 'login').name));
  await check('each locked row carries its drive emoji',
    (await lockedRows()).every((row) => row.label.includes('Drive emoji:')));
  await shot('1-list-desktop');

  // 1b. The same at phone width, and the dialog there, while still locked.
  await page.setViewportSize({ width: 390, height: 844 });
  await wait(2500);
  await shot('1-list-phone');
  {
    const phoneRow = (await lockedRows())[0];
    const phoneButton = phoneRow && await unlockButtonOf(phoneRow);
    if (phoneButton) {
      await page.mouse.click(phoneButton.x, phoneButton.y);
      await until(() => has('Unlock drive'), 10000);
      await shot('2-dialog-phone');
      await page.keyboard.press('Escape');
      await until(async () => !(await has('Unlock drive')), 5000);
    } else {
      console.log('NOTE no Unlock button found at phone width');
    }
  }
  await page.setViewportSize({ width: 1440, height: 900 });
  await wait(2500);

  const order = lockedIds(lockedDrives.map((d) => d.driveId));
  const unicode = drives.find((d) => d.password === 'unicode');
  const firstIsUnicode = order[0] === unicode.driveId;

  // 2. The first locked row's Unlock opens the dialog.
  let row = (await lockedRows())[0];
  let button = await unlockButtonOf(row);
  await page.mouse.click(button.x, button.y);
  await check('the unlock dialog opens', await until(() => has('Unlock drive'), 10000));
  await check('it names the drive by its emoji', await has('Drive emoji:'));
  await check('it offers to try the other locked drives', await has('Try on my other locked drives'));
  await shot('2-dialog-desktop');

  // 3. A wrong password says so.
  await typeInField(`wrong-${crypto.randomBytes(6).toString('hex')}`);
  await check('a wrong password says "Wrong password"', await until(() => has(WRONG), 20000));
  await check('and not the network', !(await has(OFFLINE)));
  await shot('3-wrong-password');

  // 4. Offline: the check can't read the drive, and says the network, not the
  //    password.
  const firstPassword = firstIsUnicode ? passwords.unicode : passwords.other;
  await page.context().setOffline(true);
  await typeInField(firstPassword);
  const offlineSaid = await until(() => has(OFFLINE), 30000);
  await page.context().setOffline(false);
  await check('offline says "Couldn\'t reach the network. Try again."', offlineSaid);
  await check('and not "Wrong password"', !(await has(WRONG)));
  await shot('4-network-error');

  // 5. The right password opens it. The Unicode drive was made by core-js,
  //    whose password encoding differs from web's for non-ASCII characters.
  await typeInField(firstPassword);
  await check('the right password closes the dialog',
    await until(async () => !(await has('Unlock drive')), 30000));
  await check('one locked drive fewer',
    await until(async () => (await lockedRows()).length === lockedDrives.length - 1, 30000));
  await shot('5-unlocked');

  // 6. One password, several drives: the two that share it open together.
  row = (await lockedRows())[0];
  button = await unlockButtonOf(row);
  await page.mouse.click(button.x, button.y);
  await until(() => has('Unlock drive'), 10000);
  await typeInField(firstIsUnicode ? passwords.other : passwords.unicode);
  await check('the dialog closes', await until(async () => !(await has('Unlock drive')), 30000));
  const remaining = lockedDrives.length - (firstIsUnicode ? 3 : 2);
  await check(`"Try on my other locked drives" opens the rest (${remaining} left)`,
    await until(async () => (await lockedRows()).length === remaining, 30000));
  await shot('6-try-on-others');
  await check('every drive is listed by name now',
    (await Promise.all(drives.map((d) => has(d.name)))).every(Boolean));

  // 7. Unlocked, at phone width.
  await page.setViewportSize({ width: 390, height: 844 });
  await wait(2500);
  await shot('7-unlocked-phone');
  await page.setViewportSize({ width: 1440, height: 900 });
  await wait(1000);

  console.log('DONE');
  process.exit(0);
})().catch((e) => { console.log('ERROR', e.message); process.exit(1); });
