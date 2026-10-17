# Web app end-user testing

How to test the web app the way a user uses it: a real build in headless
Chromium (Chrome), logged in with the team's test wallet, clicking through
dialogs, uploading files and checking the result. The tools are in
`tool/web_e2e/`. Agents and people use the same steps.

Unit and widget tests can't show what a user sees or what the app sends to
the network. Use this for anything that touches upload, payment, login or a
dialog's layout. It is also how a fix gets proven before merge: a screenshot
of the result, and the network log showing where each request went.

## Rules

These hold for every run.

1. **Credentials stay on the machine.** The test wallet's keyfile and password
   live only in a local credentials file (below). Never put them, or the
   keyfile's path, in git, a PR, an issue, a comment, a log you share, an
   agent memory, or an upload. Never print, `cat` or open the keyfile: the
   scripts pass it to the browser by path. The same goes for private drive
   passwords.
2. **Don't spend.** `launch.js` blocks spending by default:
   - Wallet-paid (AR) uploads go to a local fake gateway, never to Arweave.
   - On the real Turbo services (production and staging builds), uploads go
     through only if each item is within Turbo's free size (105 KiB).
     Anything bigger is refused.
   - Top-ups on the real Turbo payment service are always refused.
   - PR preview builds use testnet Turbo, which is free, so their Turbo
     uploads aren't blocked (see *Which build to test*).
   A real AR upload, or a paid upload on real Turbo (`TURBO_PAID=1`), needs a
   human's go-ahead first, every time.
3. **Upload only test data, only to test drives.** Use random bytes (see
   *Test files*), never real documents. Upload to *Private Drive Test* or a
   `UAT-TESTONLY-DELETEME` drive. Anything uploaded for real is permanent.

## One-time setup

**Node and Chromium.** In `tool/web_e2e/`:

```bash
npm install                            # playwright-core, pinned
npx playwright-core install chromium   # skip if ~/.cache/ms-playwright has one
```

To use a different browser binary, set `CHROME=/path/to/chrome`.

**Credentials file.** Ask the wallet's owner for the keyfile and password.
Keep the keyfile outside every repository, then create
`~/.config/ardrive-e2e/env`:

```bash
mkdir -p ~/.config/ardrive-e2e && chmod 700 ~/.config/ardrive-e2e
cat > ~/.config/ardrive-e2e/env <<'EOF'
ARDRIVE_E2E_KEYFILE=/absolute/path/to/the/test-wallet-keyfile.json
ARDRIVE_E2E_PASSWORD=<the password>
EOF
chmod 600 ~/.config/ardrive-e2e/env
```

Environment variables of the same names override the file. `CREDENTIALS`
points the scripts at a different file.

## Which build to test

| Testing | Use | Turbo there |
|---|---|---|
| A pull request | Its preview, at the URL the github-actions bot posts on the PR | Testnet: free, data wiped after a few days |
| A release candidate | https://staging.ardrive.io (`dev` deploys there) | Real: the guard is on |
| A change not pushed yet | A local build (below) | Depends on the config you build with |

Point the browser at it with `APP_URL`, for example
`APP_URL=https://ardrive-web--pr2274-….web.app/ node launch.js`. Each URL is a
separate site to the browser, so each needs its own login and first sync.

PR previews are built with the development config:
- Turbo uploads and payments go to testnet services (`upload.services.ar-io.dev`,
  `payment.services.ar-io.dev`), which cost nothing. Files up to 5 MiB are
  free, so the payment choice only appears for bigger files.
- The test wallet has no testnet Turbo Credits (as of October 2026), so a
  paid Turbo upload on a preview shows the not-enough-credits state.
- Wallet-paid uploads still go to the default gateway, turbo-gateway.com,
  which is mainnet, so the guard handles them as everywhere else.

`launch.js` reads which Turbo services are real from `assets/config/`, and
prints what it guards when it starts.

## Running a test

### 1. Build and serve the branch under test

Skip this when testing a preview or staging.

Build a production release, the same as users get:

```bash
flutter build web --release --dart-define=environment=production \
  --pwa-strategy=none --no-web-resources-cdn --dart2js-optimization=O1
```

Copy `build/web` somewhere stable first, so a later build or branch switch
can't change it under the browser, then serve the copy:

```bash
python3 -I -m http.server 8090 --bind 127.0.0.1   # run from the copy
```

The scripts expect the app at `http://127.0.0.1:8090/`; `APP_URL` changes it.

### 2. Start the fake gateway and the browser

In `tool/web_e2e/`, each in the background:

```bash
python3 -I chaos_gateway.py 8850 ~/.cache/ardrive-e2e/chaos-state.json
node launch.js        # prints READY when the app has loaded
```

`launch.js` keeps the browser running, and other scripts attach to it. Its
profile is in `~/.cache/ardrive-e2e/profile`, so a login and synced drives
survive restarts. Run only one at a time: a second one can't open the
profile.

### 3. Log in

```bash
node login.js           # new profile: Log In, Import Wallet, keyfile, password
node login.js unlock    # profile already logged in: just the password
```

The app asks for the password each time the browser starts, so after a
restart use `unlock`. Check the last screenshot,
`~/.cache/ardrive-e2e/shots/login-4-done.png`: it should show the drive list.

A new profile has synced nothing. Open *All drives* and choose
**Sync All Drives** once (about two minutes) before opening a drive.

### 4. Drive the app

```bash
node step.js <name> '<async JS>'
```

Each step runs its JS against the page, then saves a screenshot to
`~/.cache/ardrive-e2e/shots/<name>.png`. Read the screenshot before you
decide the next step.

- **Clicking.** Flutter draws the UI on a canvas, so most clicks are
  `await page.mouse.click(x, y)` at coordinates read off the last screenshot.
  The viewport is always 1440×900. Menu items need a hover before the click.
- **Labels.** `labels()` lists the accessibility labels Flutter exposes, with
  their centres, and `clickLabel(text)` clicks one. Many widgets have no
  label, so the screenshot is the source of truth.
- **Choosing files.** `queueFiles([paths])` sets what the next file chooser
  receives. Use it before the click that opens the chooser. Files of any
  size work.
- **Waiting.** `await wait(ms)` pauses. The upload dialog needs about 15 s to
  price a small file and 30–45 s for files of 50 MB and up.

Example: open the test drive and start an upload.

```bash
node step.js open-drive "await page.evaluate(() => { location.hash = '#/drives/7cea4056-3cd0-47ab-85f6-529fcfbe4c53/folders/884d1508-c9ec-463f-8519-679564aa8498'; }); await wait(8000);"
node step.js upload-dialog "queueFiles(['$HOME/.cache/ardrive-e2e/files/e2e-free-50k.bin']); await page.mouse.click(120, 132); await wait(1500); await page.mouse.move(290, 137); await wait(300); await page.mouse.click(290, 137); await wait(15000);"
```

These positions held in October 2026. Confirm them on a screenshot, since
layout changes move them:

| What | x, y |
|---|---|
| **New** button | 120, 132 |
| New → Upload file (hover, then click) | 290, 137 |
| Upload dialog: **Upload** | 853, 696 |
| Upload dialog: **Cancel** | 745, 696 |
| Upload dialog: Turbo Credits / Wallet (AR) card | 720, 488 / 720, 565 |
| Problem with Upload: **Close** | 793, 566 |
| Profile button (top right) | 1332, 57 |

### 5. Check the result

- **Screenshots** show what the user saw.
- **`~/.cache/ardrive-e2e/net.log`** has one JSON line per guard decision and
  per other POST:
  - `chaos`: an AR request answered by the fake gateway
  - `dryrun`: an AR request sent to ar-io.dev in dry-run mode
  - `turbo`: a free Turbo upload, with its size in bytes
  - `BLOCKED`: something refused, with the reason
  - `post`: any other POST
  - `filechooser`: a file chooser was answered
- **`python3 -I chaos_report.py ~/.cache/ardrive-e2e/chaos-state.json`**
  checks every AR transaction the app sent: was every byte stored, was every
  proof valid. It prints `OK` or `PROBLEMS`.
- **`~/.cache/ardrive-e2e/console.log`** is the app's console output, for
  errors.
- **The wallet's AR balance** should be unchanged after a run:
  `curl https://arweave.net/wallet/<address>/balance`, using the address shown
  on the profile button.

### 6. Clean up

Stop `launch.js`, the gateway and the web server by PID. Find them with
`ps -eo pid,comm,args`. Don't use `pkill -f`: its pattern matches the shell
running it, which kills your own command.

## Test recipes

**Test files.** Use random bytes, so a file uploaded for real is never
anybody's data:

```bash
python3 -c "import os; open('e2e-300k.bin','wb').write(os.urandom(300*1024))"
```

**Free Turbo upload.** Use a file under 100 KiB on the default *Turbo Credits*
option. The dialog says it's free, and `net.log` shows `turbo` lines under
107520 bytes. On production or staging this is a real, permanent upload. On a
preview it goes to testnet, shown as `post` lines to
`upload.services.ar-io.dev`, and files up to 5 MiB are free.

**Paid Turbo upload (blocked).** On production or staging, use a file over
105 KiB on Turbo Credits. The app shows *Problem with Upload*, and `net.log`
shows `BLOCKED`. The small metadata item may already have gone through, which
leaves a failed entry for that file in the drive.

**Wallet-paid upload.** Choose the *Wallet (AR)* card, then **Upload**.
`net.log` shows `chaos` lines for `/tx` and `/chunk`, and `chaos_report.py`
prints `OK`. Nothing reaches Arweave, so the file stays pending in the drive.

**Uploads that keep failing and retrying.** Start the gateway with a failure
rate, for example `python3 -I chaos_gateway.py 8850 <state> 0.3`. The gateway
then randomly answers with errors, stalls and dropped connections. Re-Upload
from the problem dialog until it finishes, then run `chaos_report.py`.

**A file the test wallet can't afford.** Start
`FAKE_AR_BALANCE=100000000000000 node launch.js` (100 AR, in winston) and
upload through the fake gateway. This only works with `AR_UPLOADS=chaos` or
`block`.

**Against a real gateway, without mainnet.** ar-io.dev runs in dry-run mode:
it accepts headers and chunks and forwards nothing to Arweave.
1. Start `AR_UPLOADS=dryrun node launch.js`.
2. In the app, switch to ar-io.dev under Settings → Switch Gateway.
3. Upload. `launch.js` re-checks that ar-io.dev is still in dry-run mode
   before every header, and blocks the header if it isn't.

## Known quirks

- **Deep link to an unsynced drive.** On a new profile, a link straight to a
  drive that hasn't been synced opens a different drive (the first in the
  list). Sync all drives first.
- **The sidebar highlight** can stay on a different drive than the one shown.
- **A file name the drive already has** brings up *A duplicate file found*
  (Cancel or Replace) before the upload dialog. Earlier test runs leave
  names behind, so read the screenshot before clicking Upload.
- **Two launchers** can't share the profile. The second fails with
  `SingletonLock: File exists`. Stop the first.
- **Accessibility on.** Turning on Flutter's accessibility mode changes what
  sits on top of the canvas and breaks coordinate clicks on menus. Leave it
  off.
