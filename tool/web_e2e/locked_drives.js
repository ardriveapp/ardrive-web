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
const { spawn } = require('child_process');
const crypto = require('crypto');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { E2E_DIR, CDP_PORT, APP_URL, ensureDirs, mainPage } = require('./config');

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
    .filter((n) => n.label.includes('Private drive, Locked') && n.w > 200)
    .sort((a, b) => a.y - b.y);
  const lockedIds = (ids) => [...ids].sort();
  // The row's Unlock: beside the status in the table, on the card's last
  // line at phone width - the nearest one, either way.
  const unlockButtonOf = async (row) => (await labels())
    .filter((n) => n.label === 'Unlock' && Math.abs(n.y - row.y) < 60)
    .sort((a, b) => Math.abs(a.y - row.y) - Math.abs(b.y - row.y))[0];
  // The field has focus whenever the dialog is waiting: it opens focused, and
  // every answer but success hands focus back with the text selected. A click
  // is not needed, and a click on a label node outside the field would land
  // on the barrier and close the dialog.
  const typeInField = async (secret) => {
    await page.keyboard.press('Control+A');
    await page.keyboard.press('Backspace');
    // insertText, not type: type drops characters a US keyboard has no key
    // for, and the Unicode drive's password has some.
    await page.keyboard.insertText(secret);
    await wait(300);
    await page.keyboard.press('Enter');
  };

  // Turns Flutter's accessibility tree on, which a reload turns off again.
  // The placeholder sits in a shadow root.
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
  // Activates the node labelled [text] the way a screen reader does. Menus
  // and overlays take a mouse click on what is behind them while the tree is
  // on (#2347); activation reaches the node itself.
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

  // R1-R5: "Remember on this device" (3.0 password design, P2). Starts with
  // every drive open, each unlocked above with Remember on (the default).
  const loginDrive = drives.find((d) => d.password === 'login');
  const shared = drives.filter((d) => d.password === 'other');
  const unicodeDrive = drives.find((d) => d.password === 'unicode');
  // login.js, without blocking this process: a tab it opens waits for
  // every CDP client attached to the browser, this one included, to let it
  // start, so a synchronous call would leave that tab hanging.
  const run = (args) => new Promise((resolve, reject) => {
    const child = spawn('node', [path.join(__dirname, 'login.js'), ...args],
      { stdio: ['ignore', 'inherit', 'inherit'], env: process.env });
    child.on('error', reject);
    child.on('exit', (code) => (code === 0 ? resolve()
      : reject(new Error(`login.js ${args.join(' ')} exited ${code}`))));
  });
  // A reload is a new session: Welcome back, the device password, then the
  // drive list as discovery leaves it.
  // A start whose OPFS open timed out falls back to an empty IndexedDB
  // database and shows the landing page, though the profile is still in
  // OPFS: seen on a loaded machine, and not what is under test here. Said,
  // and reloaded once more.
  const consoleLog = path.join(E2E_DIR, 'console.log');
  const reloadOnce = async () => {
    const from = fs.existsSync(consoleLog) ? fs.statSync(consoleLog).size : 0;
    await page.reload();
    for (let t = 0; t < 60; t++) {
      await wait(1000);
      const fresh = fs.existsSync(consoleLog)
        ? fs.readFileSync(consoleLog, 'utf8').slice(from) : '';
      if (/\[web-db\] the database is on OPFS/.test(fresh)) return true;
      if (/\[web-db\] the OPFS database did not open/.test(fresh)) return false;
    }
    return true;
  };
  const reload = async () => {
    if (!(await reloadOnce())) {
      console.log('NOTE the OPFS open timed out on this start; reloading again');
      await reloadOnce();
    }
    await wait(3000);
  };
  const reloadAndUnlock = async () => {
    await reload();
    await run(['unlock']);
    await enableTree();
    await until(() => has(loginDrive.name), 90000);
    await wait(8000);
  };
  const signInFresh = async () => {
    try {
      await run(['fresh']);
    } catch (e) {
      // login.js reads the landing page's labels in a second tab, whose
      // load can outlast its 30 s on a loaded machine. Once more.
      console.log('NOTE login.js fresh failed once; trying again');
      await reload();
      await run(['fresh']);
    }
    await enableTree();
    await until(() => has(loginDrive.name), 120000);
    await wait(8000);
  };
  const lockedCount = async () => (await lockedRows()).length;
  // Selecting a drive's row shows its details beside the list.
  const selectRow = async (name) => {
    const hit = (await labels()).filter((n) => n.label.includes(name) && n.w > 200)
      .sort((x, y) => x.y - y.y)[0];
    if (!hit) throw new Error(`no row for ${name}`);
    await page.mouse.click(hit.x - Math.floor(hit.w / 2) + 40, hit.y);
    await wait(1500);
  };
  const storageReport = () => page.evaluate(async () => {
    const names = indexedDB.databases ? (await indexedDB.databases()).map((d) => d.name) : [];
    let resets = [];
    try {
      const dir = await (await navigator.storage.getDirectory()).getDirectoryHandle('ardrive-db');
      for await (const key of dir.keys()) if (key.includes('-reset-')) resets.push(key);
    } catch (e) {}
    return { names, resets };
  });
  // What earlier builds left: the sql.js store and a reset copy. Planted so
  // sign-out has something to delete; none of it holds anything.
  const plantOlderStores = () => page.evaluate(async () => {
    await new Promise((resolve, reject) => {
      const open = indexedDB.open('moor_databases');
      open.onupgradeneeded = () => open.result.createObjectStore('moor_databases');
      open.onsuccess = () => { open.result.close(); resolve(); };
      open.onerror = () => reject(open.error);
    });
    const root = await navigator.storage.getDirectory();
    const dir = await root.getDirectoryHandle('ardrive-db', { create: true });
    const file = await dir.getFileHandle('ardrive-reset-1761000000000', { create: true });
    const w = await file.createWritable();
    await w.write(new Uint8Array([1, 2, 3]));
    await w.close();
  });

  // The drive the open unlock dialog is for, read from the dialog itself: it
  // names the drive by its shortened ID ("6939b9...8885"). Matched against
  // drives.json, so the password typed is always that drive's, whatever
  // order the rows are in.
  const dialogDriveId = async () => {
    for (const n of await labels()) {
      const m = n.label.match(/([0-9a-f]{6})(?:\.\.\.|\u2026)([0-9a-f]{4})/);
      if (!m) continue;
      const hit = drives.find((d) => d.driveId.startsWith(m[1]) && d.driveId.endsWith(m[2]));
      if (hit) return hit.driveId;
    }
    return null;
  };
  // The password of the drive the open dialog is for. Never printed.
  const dialogPassword = async (what) => {
    const id = await dialogDriveId();
    await check(`${what}: the dialog names a drive of this wallet`, id !== null);
    return passwords[drives.find((d) => d.driveId === id).password];
  };
  // Opens the first locked row's dialog, types that drive's own password,
  // and fails unless one drive fewer is locked afterwards.
  const unlockFirstLocked = async (what) => {
    const lockedBefore = await lockedCount();
    const row = (await lockedRows())[0];
    await check(`${what}: there is a locked drive`, row !== undefined);
    const button = await unlockButtonOf(row);
    await page.mouse.click(button.x, button.y);
    await check(`${what}: the dialog opens`, await until(() => has('Unlock drive'), 10000));
    await typeInField(await dialogPassword(what));
    await check(what, await until(async () => await lockedCount() < lockedBefore, 30000));
  };

  async function rememberCases() {
    await page.setViewportSize({ width: 1440, height: 900 });
    await wait(1500);
    const [a, b] = shared;

    // R3, part 1: Forget on this device, from the drive's details.
    await selectRow(a.name);
    await check('the details panel offers "Forget on this device"',
      await until(() => has('Forget on this device'), 20000));
    await shot('r0-details');
    await activate('Forget on this device');
    await check('it then says "Not remembered"', await until(() => has('Not remembered'), 10000));
    await check('and the drive stays open this session', await has(a.name));
    await shot('r0-forgotten');

    // R1 and R3: a reload opens every remembered drive with no drive
    // prompt; the forgotten one is locked.
    await reloadAndUnlock();
    await check('R1: remembered drives open after a reload, with no prompt',
      (await has(b.name)) && (await has(unicodeDrive.name)));
    await check('R3: the forgotten drive is locked again', await lockedCount() === 1);
    await shot('r1-reload');

    // R2: unlocked with Remember off, it is locked again next session.
    let lockedRow = (await lockedRows())[0];
    let unlockButton = await unlockButtonOf(lockedRow);
    await page.mouse.click(unlockButton.x, unlockButton.y);
    await check('the dialog offers "Remember on this device"',
      await until(() => has('Remember on this device'), 10000));
    await activate('Remember on this device');
    await wait(500);
    await shot('r2-remember-off');
    await typeInField(await dialogPassword('R2'));
    await check('it opens', await until(async () => await lockedCount() === 0, 30000));
    await reloadAndUnlock();
    await check('R2: unlocked with Remember off, it is locked after a reload',
      await lockedCount() === 1);
    await shot('r2-reload');

    // R4: sign-out forgets everything, and the copies older builds left go.
    await unlockFirstLocked('the drive locked by R2 opens again');
    await plantOlderStores();
    const before = await storageReport();
    await check('(the older stores are planted)',
      before.names.includes('moor_databases') && before.resets.length > 0);
    await profileMenu();
    await check('the profile menu offers "Forget all on this device"',
      await until(() => has('Forget all on this device'), 10000));
    await shot('r4-profile-menu');
    await activate('Log out');
    await check('signed out', await until(() => has('Log in'), 30000));
    await wait(3000);
    const after = await storageReport();
    await check('R4: sign-out deleted the sql.js store', !after.names.includes('moor_databases'));
    await check('R4: and every reset copy', after.resets.length === 0);
    await signInFresh();
    await check('R4: signed in again, every other drive is locked',
      await until(async () => await lockedCount() === drives.length - 1, 60000));
    await shot('r4-after-sign-out');

    // R5: cleared site storage falls back to locked; passwords still open.
    await unlockFirstLocked('R5: a drive is unlocked, and so remembered, before');
    const session = await page.context().newCDPSession(page);
    await session.send('Storage.clearDataForOrigin', { origin: new URL(APP_URL).origin, storageTypes: 'all' });
    await session.detach();
    await reload();
    await signInFresh();
    await check('R5: with site storage cleared, the drives are locked',
      await until(async () => await lockedCount() === drives.length - 1, 60000));
    await unlockFirstLocked('R5: and their passwords still open them');
    await shot('r5-cleared');

    // Forget all on this device: every drive, the sign-in password's own
    // included, is locked next session.
    await profileMenu();
    await until(() => has('Forget all on this device'), 10000);
    await activate('Forget all on this device');
    await check('Forget all asks first, saying how many',
      await until(() => has('on this device?'), 10000));
    await shot('r6-forget-all-confirm');
    await activate('Forget');
    await wait(2000);
    await reload();
    await run(['unlock']);
    await enableTree();
    await check('after Forget all, every private drive is locked',
      await until(async () => await lockedCount() === drives.length, 90000));
    await shot('r6-forget-all');
  }

  // The profile menu opens from the wallet button at the top right, found
  // by where it is: its label is the wallet's short address.
  const openProfileMenu = async () => {
    const opened = await page.evaluate(() => {
      const all = [];
      const walk = (root) => root.querySelectorAll('*').forEach((e) => {
        if (e.tagName === 'FLT-SEMANTICS') all.push(e);
        if (e.shadowRoot) walk(e.shadowRoot);
      });
      walk(document);
      const hit = all.filter((e) => {
        const r = e.getBoundingClientRect();
        return r.width > 0 && r.x + r.width / 2 > 1150 && r.y + r.height / 2 < 90
          && /\.\.\./.test(e.getAttribute('aria-label') || e.innerText || '');
      }).sort((a, b) => b.getBoundingClientRect().x - a.getBoundingClientRect().x)[0];
      if (!hit) return false;
      hit.click();
      return true;
    });
    if (!opened) await page.mouse.click(1320, 57);
    await wait(1500);
  };
  const profileMenu = async () => {
    await page.mouse.move(1, 1);
    for (let attempt = 1; attempt <= 3; attempt++) {
      await openProfileMenu();
      if (await until(() => has('Log out'), 5000)) return true;
      console.log(`NOTE the profile menu did not open (try ${attempt})`);
    }
    return false;
  };

  await page.setViewportSize({ width: 1440, height: 900 });
  // The placeholder sits in a shadow root.
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

  if (process.env.SKIP_REMEMBER !== '1') await rememberCases();

  console.log('DONE');
  process.exit(0);
})().catch((e) => { console.log('ERROR', e.message); process.exit(1); });
