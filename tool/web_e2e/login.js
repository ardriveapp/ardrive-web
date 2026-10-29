// Logs the test wallet in to the browser launch.js started.
//
//   node login.js          from the landing page (a new profile, or after
//                          logging out): Log in, Recovery phrase or keyfile,
//                          Choose a keyfile, then the password
//   node login.js unlock   the profile already has the wallet and the app is
//                          asking for the password ("Welcome back"), as it
//                          does each time the browser starts
//
// The keyfile goes in by path through the file chooser and the password is
// typed from the credentials file; neither is printed. Screenshots of each
// stage land in $E2E_DIR/shots/login-*.png. Check the last one: it should
// show the drive list.
//
// Buttons are found by their labels, not by fixed coordinates, so a new
// layout doesn't send a click to the wrong button. Flutter exposes labels
// only with its accessibility tree on, and with the tree on later clicks on
// menus land on what's behind them (#2347). So the labels are read in a
// second tab, which is closed again, and the clicks go to the same places in
// launch.js's tab, where the tree stays off. The keyfile panel is checked by
// its recovery phrase field, which takes focus when it opens, and a step that
// didn't land is tried again.
//
// The password field has focus when its dialog opens, and Enter submits it.
// The test wallet has used ArDrive before, so after the keyfile the app asks
// for its existing password; a wallet new to ArDrive gets a create-password
// screen instead, which this does not handle.
const { chromium } = require('playwright-core');
const fs = require('fs');
const { E2E_DIR, CDP_PORT, ensureDirs, mainPage, credentials } = require('./config');

const LOG_IN = 'Log in';
const PHRASE_OR_KEYFILE = 'Recovery phrase or keyfile';
const CHOOSE_KEYFILE = 'Choose a keyfile';

// The accessibility labels Flutter exposes in [page], with their centres.
const labels = (page) => page.evaluate(() => {
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
    };
  }).filter((n) => n.label && n.x > 0);
});

// Where [text] is in [page], waiting up to [ms] for it to appear.
async function find(page, text, ms = 30000) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    const all = await labels(page);
    const hit = all.find((n) => n.label === text) || all.find((n) => n.label.startsWith(text));
    if (hit) return hit;
    await page.waitForTimeout(250);
  }
  throw new Error(`nothing labelled "${text}"`);
}

// Where the buttons of the fresh-profile path are, read in a second tab of
// the same size with the accessibility tree on.
async function buttonPlaces(main) {
  const tab = await main.context().newPage();
  try {
    await tab.setViewportSize(main.viewportSize() || { width: 1440, height: 900 });
    await tab.goto(main.url());
    // The placeholder that turns the tree on is inside a shadow root, which
    // Playwright's $ looks into. Click it until labels appear.
    const end = Date.now() + 90000;
    while (Date.now() < end && (await labels(tab)).length === 0) {
      const placeholder = await tab.$('flt-semantics-placeholder');
      if (placeholder) await placeholder.evaluate((e) => e.click()).catch(() => {});
      await tab.waitForTimeout(1000);
    }
    const places = {};
    places.logIn = await find(tab, LOG_IN, 60000);
    // Builds before the fix for it can put the welcome panel back over
    // Log in, when Log in is pressed early: press it again.
    for (let attempt = 1; !places.phraseOrKeyfile; attempt++) {
      await tab.mouse.click(places.logIn.x, places.logIn.y);
      try {
        places.phraseOrKeyfile = await find(tab, PHRASE_OR_KEYFILE, 5000);
      } catch (e) {
        if (attempt === 3) throw e;
      }
    }
    await tab.mouse.click(places.phraseOrKeyfile.x, places.phraseOrKeyfile.y);
    places.chooseKeyfile = await find(tab, CHOOSE_KEYFILE);
    return places;
  } finally {
    await tab.close();
  }
}

// The focused field's tag and type, looking inside shadow roots. Never its
// value.
const focusedField = (page) => page.evaluate(() => {
  let el = document.activeElement;
  while (el && el.shadowRoot && el.shadowRoot.activeElement) el = el.shadowRoot.activeElement;
  return el ? `${el.tagName} ${el.type || ''}`.trim() : '';
});
// The password field has focus when its dialog opens.
const passwordFocused = async (page) => (await focusedField(page)) === 'INPUT password';
// So has the recovery phrase field, a textarea, when the keyfile panel opens.
const phraseFocused = async (page) => (await focusedField(page)).startsWith('TEXTAREA');

async function waitFor(check, ms, page) {
  const end = Date.now() + ms;
  while (Date.now() < end) {
    if (await check()) return true;
    await page.waitForTimeout(250);
  }
  return false;
}

(async () => {
  const mode = process.argv[2] || 'fresh';
  if (!['fresh', 'unlock'].includes(mode)) {
    console.error('usage: node login.js [unlock]');
    process.exit(2);
  }
  const { keyfile, password } = credentials();
  ensureDirs();
  const browser = await chromium.connectOverCDP(`http://127.0.0.1:${CDP_PORT}`);
  const page = await mainPage(browser);
  const wait = (ms) => page.waitForTimeout(ms);
  const shot = async (n) => {
    await page.screenshot({ path: `${E2E_DIR}/shots/login-${n}.png` });
    console.log('SHOT', `${E2E_DIR}/shots/login-${n}.png`);
  };

  if (mode === 'fresh') {
    const places = await buttonPlaces(page);
    await shot('1-landing');
    let atKeyfile = false;
    for (let attempt = 1; attempt <= 3 && !atKeyfile; attempt++) {
      await page.mouse.click(places.logIn.x, places.logIn.y);
      await wait(1500);
      await page.mouse.click(places.phraseOrKeyfile.x, places.phraseOrKeyfile.y);
      atKeyfile = await waitFor(() => phraseFocused(page), 10000, page);
      if (!atKeyfile) console.log(`the keyfile panel didn't open (try ${attempt})`);
    }
    if (!atKeyfile) {
      await shot('2-no-keyfile-panel');
      console.log('FAILED: the keyfile panel never opened');
      process.exit(1);
    }
    await wait(1000);
    await shot('2-import');
    // launch.js answers the chooser with this queue, and hands the keyfile
    // over only while the marker says the chooser is this login's.
    fs.writeFileSync(`${E2E_DIR}/login-chooser`, '');
    fs.writeFileSync(`${E2E_DIR}/nextfiles.json`, JSON.stringify([keyfile]));
    const chosen = Date.now();
    await page.mouse.click(places.chooseKeyfile.x, places.chooseKeyfile.y);
    // "Loading wallet details...", then the password.
    if (!(await waitFor(() => passwordFocused(page), 90000, page))) {
      await shot('3-no-password');
      console.log('FAILED: no password field 90 s after the keyfile was chosen');
      process.exit(1);
    }
    console.log(`password asked ${((Date.now() - chosen) / 1000).toFixed(1)} s after the keyfile was chosen`);
  } else if (!(await waitFor(() => passwordFocused(page), 30000, page))) {
    await shot('3-no-password');
    console.log('FAILED: no password field');
    process.exit(1);
  }
  await shot('3-password');
  await page.keyboard.type(password, { delay: 20 });
  await wait(300);
  await page.keyboard.press('Enter');
  // The first sync of the drive list takes a while on a new profile.
  await wait(mode === 'fresh' ? 60000 : 30000);
  await shot('4-done');
  process.exit(0);
})();
