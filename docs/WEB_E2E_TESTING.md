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
ARDRIVE_E2E_ADDRESS=<the wallet's 43-character address>
EOF
chmod 600 ~/.config/ardrive-e2e/env
```

The address isn't a secret. `balance.js` uses it, since the app only shows a
shortened one. Environment variables of the same names override the file. `CREDENTIALS`
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

A new profile has synced nothing. *All drives* shows a banner with a
**Sync All Drives** button: use it once (about two minutes) before opening a
drive.

**Test drives.** Open them by double-clicking their row in *All drives*.
- **New Test Drive** (public): use it for anything public-only, such as
  thumbnails, deployments, or publishing a manifest file as a deployment.
- **Private Drive Test** (private): for private uploads. The example link
  below points into it.
- **The three `UAT-TESTONLY-DELETEME` drives**: also fine to use, but they
  share a name, so check which one opened.

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
- **Small text.** Screenshots are 1440×900. To read small text, crop: in a
  step, `await page.screenshot({ path, clip: { x, y, width, height } })`.
  Don't change the device scale: Flutter's layout breaks until a reload, and
  each `step.js` connection resets it anyway.
- **Hover.** `step.js` moves the mouse to a corner before its screenshot. A
  hovered primary button looks like a disabled one.
- **Phone width.** `await page.setViewportSize({ width: 390, height: 844 })`
  switches the app to its phone layout, and it lasts across steps. Set
  1440×900 back afterwards.
- **Waiting.** `await wait(ms)` pauses. The upload dialog needs about 15 s to
  price a small file and 30–45 s for files of 50 MB and up.

Example: open Private Drive Test and start an upload.

```bash
node step.js open-drive "await page.evaluate(() => { location.hash = '#/drives/7cea4056-3cd0-47ab-85f6-529fcfbe4c53/folders/884d1508-c9ec-463f-8519-679564aa8498'; }); await wait(8000);"
node step.js upload-dialog "queueFiles(['$HOME/.cache/ardrive-e2e/files/e2e-free-50k.bin']); await page.mouse.click(120, 132); await wait(1500); await page.mouse.move(290, 137); await wait(300); await page.mouse.click(290, 137); await wait(15000);"
```

These positions held in October 2026. Only the first two and the last are
stable. The dialog rows are a rough guide: the dialog fits its content, so
its buttons and payment rows move with the number of files, the options
shown, and warnings. Always read them off the latest screenshot.

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
  - `turbo`: a free upload to real Turbo, with its size in bytes
  - `turbo-testnet`: an upload to testnet Turbo (PR previews)
  - `BLOCKED`: something refused, with the reason
  - `INJECTED`: a failure made on purpose (see *Failing on purpose*)
  - `post`: any other POST
  - `filechooser`: a file chooser was answered
  - `launch`: the start of a run. Both logs collect every run, so read from
    the last `launch` line (`===== launch` in `console.log`)
- **`python3 -I chaos_report.py ~/.cache/ardrive-e2e/chaos-state.json`**
  checks every AR transaction the app sent: was every byte stored, was every
  proof valid. It prints `OK`, `PROBLEMS`, or `NOTHING STORED` when no
  header reached the gateway. `NOTHING STORED` isn't a pass, unless the test
  failed every header on purpose.
- **`~/.cache/ardrive-e2e/console.log`** is the app's console output, for
  errors.
- **The wallet's AR balance** should be unchanged after a run. Run
  `node balance.js` before and after. It asks turbo-gateway.com, then
  arweave.net, which rate-limits some connections.

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

**Checking thumbnails were made.** Count the upload POSTs in `net.log`
(`turbo` or `turbo-testnet`): an image with thumbnails makes three (data,
thumbnail, metadata), and without makes two.

**Deployments (manifests).** Make one with New → Advanced → New deployment
(free on a preview). Click Advanced and then New deployment in the same step:
the submenu closes again within a second. Uploading into a folder that has one
opens the *Update deployments* panel beside the dialog. It closes with "Close «"
in the header, and Options → Update deployments opens it again. The phone
layout has no panel.

**Payment choice on a preview.** Testnet Turbo makes files up to 5 MiB free,
so the payment cards, and with them wallet-paid upload, only appear for
bigger files. Use 6 MB or more on a preview for any recipe below that needs
them.

**Wallet-paid upload.** Choose the *Wallet (AR)* card, then **Upload**.
`net.log` shows `chaos` lines for `/tx` and `/chunk`, and `chaos_report.py`
prints `OK`. Nothing reaches Arweave, so the file stays pending in the drive.

**Failing on purpose.** Both switches work while everything runs:
- **Wallet-paid failures.** Write a failure rate to the gateway's rate file,
  for example `echo 0.3 > ~/.cache/ardrive-e2e/chaos-state.json.rate`. The
  gateway then randomly answers with errors, stalls and dropped connections.
  - Re-Upload from the problem dialog until it finishes, then run
    `chaos_report.py`.
  - `1.0` fails every request, for a guaranteed problem dialog; `0` stops.
  - Don't restart the gateway to change the rate: a restart loses what it
    has recorded.
- **Turbo failures.** `touch ~/.cache/ardrive-e2e/fail-turbo` answers every
  Turbo upload with an error, on real and testnet Turbo alike; delete the
  file to stop. The metadata upload fails too, so the file may not appear in
  the drive at all.

**An upload bigger than the test wallet can pay for.** Start
`FAKE_AR_BALANCE=100000000000000 node launch.js`. That's 100 AR in winston,
reported as the wallet's balance, so the app lets the upload through to the
fake gateway. This only works with `AR_UPLOADS=chaos` or `block`.

**Against a real gateway, without mainnet.** ar-io.dev runs in dry-run mode:
it accepts headers and chunks and forwards nothing to Arweave.
1. Start `AR_UPLOADS=dryrun node launch.js`.
2. In the app, switch to ar-io.dev under Settings → Switch Gateway.
3. Upload. `launch.js` re-checks that ar-io.dev is still in dry-run mode
   before every header, and blocks the header if it isn't.

## What to test

Don't try to test everything. There are three kinds of run:

### Testing a change

This is the usual run. `/web-e2e` on its own tests the current branch.
You can also give it a pull request, a branch, a link to a build, or an area
of the app ("the upload dialog"); no ticket or PR number is needed. The skill
in `.claude/skills/web-e2e/` walks through it:

1. Read the change and its diff, and write a short test plan before testing.
2. Cover each user-visible change: its normal path, and every state the code
   distinguishes (errors, empty, not enough balance, cancel, retry, free
   versus paid). Check light and dark mode where it's visual.
3. Add the checklist journeys below that touch the same area.
4. Run the plan on the PR's preview (or a local build when there's no PR),
   then report each item with a
   screenshot, plus any bugs and the spending check.

The plan comes from the diff, not from a list, because a list can't know
what a change might break.

### Release checklist

Run on https://staging.ardrive.io before `dev` is merged to `master` for a
production release: `/web-e2e release`. Each line is a journey and what a user
should see. Keep it short: it's the floor, not every case.

| # | Journey | Expected |
|---|---|---|
| 1 | Log in from a new profile (`login.js`) | The drive list shows the wallet's drives |
| 2 | Sync all drives | Every drive says *Synced just now*; no error |
| 3 | Open a public drive, then *Private Drive Test* | Files are listed; private file names are readable |
| 4 | Create a folder in a test drive | It appears in the list |
| 5 | Upload a file under 100 KiB with Turbo | The dialog says it's free; the file appears |
| 6 | Upload a file over 105 KiB | The dialog shows both payment cards, each with its cost and balance. On Turbo the guard blocks it: *Problem with Upload*, a `BLOCKED` line |
| 7 | Wallet-paid upload through the fake gateway, failure rate 0.3 (*Failing on purpose*) | *Problem with Upload*; Re-Upload until it completes; `chaos_report.py` says OK. Closing with unfinished wallet-paid files asks to confirm |
| 8 | Upload a file the wallet can't afford (72 MB with the test wallet) | The wallet card says *Not enough AR*; Upload is disabled; no keep-tab-open warning |
| 9 | Preview an image and a PDF, then download a file | The previews render; the download starts (`await page.waitForEvent('download')` in the step) |
| 10 | Copy a file's share link and open it | The shared file page shows the file |
| 11 | Rename a file, then move it to another folder | The new name and place show, and still do after a sync |
| 12 | Switch to dark mode and back | The drive list and upload dialog are readable in both |
| 13 | Log out and log back in | Login works; the drives are listed |
| 14 | Open a drive, then paste a folder link from another drive into the same tab (`location.hash = '#/drives/…/folders/…'` in a step), then go Back | The linked folder opens and the sidebar moves to its drive; Back returns to the first drive |

### When a bug reaches users

Add a journey for it to the release checklist, in the same change as the fix
if you can. Journey 7 is there because wallet-paid uploads whose chunks
failed were never retried (October 2026). Journey 14 is there because a link
pasted into a tab that already had ArDrive open did nothing (October 2026).
The checklist grows from real failures, not guesses.

## Known quirks

- **On a preview, uploads stay pending.** Testnet data never reaches the
  gateways the app reads from, so previews and thumbnails of files uploaded
  there 404, with a `PAGEERROR` in the console. That's not a bug.

- **The sidebar highlight** can stay on a different drive than the one shown.
- **A file name the drive already has** brings up *A duplicate file found*
  (Cancel or Replace) before the upload dialog. Earlier test runs leave
  names behind, so read the screenshot before clicking Upload.
- **`launch.js` reads which Turbo services are real** from the checkout it
  runs in, not the build under test. Keep the checkout current with `dev`.
- **Two launchers** can't share the profile. The second fails with
  `SingletonLock: File exists`. Stop the first.
- **Accessibility on.** Turning on Flutter's accessibility mode changes what
  sits on top of the canvas and breaks coordinate clicks on menus. Leave it
  off.
