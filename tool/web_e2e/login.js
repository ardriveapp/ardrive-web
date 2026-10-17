// Logs the test wallet in to the browser launch.js started.
//
//   node login.js          from the landing page (a new profile, or after
//                          logging out): Log In, Import Wallet, Use Keyfile,
//                          then the password
//   node login.js unlock   the profile already has the wallet and the app is
//                          asking for the password ("Welcome back"), as it
//                          does each time the browser starts
//
// The keyfile goes in by path through the file chooser and the password is
// typed from the credentials file; neither is printed. Screenshots of each
// stage land in $E2E_DIR/shots/login-*.png. Check the last one: it should
// show the drive list.
//
// The clicks are coordinates in the 1440x900 viewport. The test wallet has
// used ArDrive before, so after the keyfile the app asks for its existing
// password; a wallet new to ArDrive gets a create-password screen instead,
// which this does not handle.
const { chromium } = require('playwright-core');
const fs = require('fs');
const { E2E_DIR, CDP_PORT, ensureDirs, credentials } = require('./config');

(async () => {
  const mode = process.argv[2] || 'fresh';
  if (!['fresh', 'unlock'].includes(mode)) {
    console.error('usage: node login.js [unlock]');
    process.exit(2);
  }
  const { keyfile, password } = credentials();
  ensureDirs();
  const browser = await chromium.connectOverCDP(`http://127.0.0.1:${CDP_PORT}`);
  const page = browser.contexts()[0].pages()[0];
  const wait = (ms) => page.waitForTimeout(ms);
  const shot = async (n) => {
    await page.screenshot({ path: `${E2E_DIR}/shots/login-${n}.png` });
    console.log('SHOT', `${E2E_DIR}/shots/login-${n}.png`);
  };

  await wait(5000);
  if (mode === 'fresh') {
    await shot('1-landing');
    await page.mouse.click(1075, 481); // Log In
    await wait(3000);
    await page.mouse.click(1075, 537); // Import Wallet
    await wait(3000);
    await shot('2-import');
    // launch.js answers the chooser with this queue, and hands the keyfile
    // over only while the marker says the chooser is this login's.
    fs.writeFileSync(`${E2E_DIR}/login-chooser`, '');
    fs.writeFileSync(`${E2E_DIR}/nextfiles.json`, JSON.stringify([keyfile]));
    await page.mouse.click(719, 688); // Use Keyfile
    await wait(20000); // "Loading wallet details..."
  }
  await shot('3-password');
  await page.mouse.click(719, 536); // Password
  await wait(500);
  await page.keyboard.type(password, { delay: 20 });
  await wait(500);
  await page.mouse.click(719, 628); // Continue
  // The first sync of the drive list takes a while on a new profile.
  await wait(mode === 'fresh' ? 60000 : 30000);
  await shot('4-done');
  process.exit(0);
})();
