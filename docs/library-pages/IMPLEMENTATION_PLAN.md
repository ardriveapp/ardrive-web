# Library pages: implementation plan

The design is `docs/LIBRARY_PAGES.md` (v2, agreed). This file is how to build
it: phases in order, the code seams each phase touches, the tests that prove
it, and the rules for testing against real services. Read the design first,
then `CLAUDE.md`, `docs/DRIVE_STATE_ARTIFACT.md` §2 and §4, and
`docs/WEB_E2E_TESTING.md`.

Each phase is one pull request to `dev` (phase 2 may be two). Do not start a
phase before the previous one is merged.

## Ground rules

- **Credentials.** The test wallet's keyfile path and password live only in
  `~/.config/ardrive-e2e/env`. Never print, copy, commit or upload them, or
  echo the keyfile path. Never dump DOM input values in a browser script (the
  password field is one of them). Drive keys are secrets too: write them to
  `chmod 600` files, never to output, and crop screenshots that show a key
  field.
- **Spending.** The test wallet (`iKryOe…ncoRjA`) has Turbo credits and may be
  used for phase 0 and phase 1 uploads, as Phil authorized on 2026-10-21.
  Report the cost of every paid upload. Prefer free sizes (under 105 KiB)
  wherever a test allows. Anything else needs Phil's go-ahead first.
- **Merges and force-pushes are Phil's.** A guard blocks both. Open PRs, run
  CI, report; Phil merges.
- **Browser tests** use `tool/web_e2e/` with your own `E2E_DIR`, `CDP_PORT`
  and app port; other sessions run the same tools on this machine. Kill only
  PIDs you recorded. On WSL, run the harness from a Linux-side copy (see
  `docs/WEB_E2E_TESTING.md`, Known quirks).
- **Flutter on this machine** is the Windows 3.19.6 SDK via
  `/mnt/c/Windows/System32/cmd.exe /c "C:\Users\phili\fvm\versions\3.19.6\bin\flutter.bat …"`.
  Commit with `LEFTHOOK=0`. Run `flutter analyze` without filtering its
  output, and `dart format` only the files you changed.

## Phase 0: compressed viewer bundle

Goal: every release's web build is on Arweave gzipped, and a staging channel
exists to test library mode before a release.

1. **Staging deploy to Arweave.** Add an Arweave deploy step to
   `.github/workflows/staging.yaml`, mirroring production's, with
   `ar-io/ar-io-deploy@v1.1.0` (or later, pinned), `compress: gzip`, and no
   ArNS update for now (`deploy` without `arns-name` uploads only). Record the
   manifest ID in the job summary.
2. **Production deploy.** In `.github/workflows/production.yaml`, pin
   `ar-io/ar-io-deploy@v1.1.0`+, add `compress: gzip`. Keep its ArNS inputs.
   Source maps: add `compress-exclude` only if needed; better, delete
   `build/web/*.map` before the deploy step (they are not needed on Arweave).
3. **Warm-up.** After each deploy, a step reads every path of the new manifest
   once through `https://turbo-gateway.com/<manifest>/<path>` and
   `https://ar.io/<manifest>/<path>`.
4. **Verify by hand before merging:** run the staging deploy once (or locally
   with `npx @ar.io/deploy upload --compress gzip` and the test wallet), then:
   - every `.js` and `.wasm` path returns `Content-Encoding: gzip` through
     turbo-gateway.com, ar.io and ardrive.net, on the sandboxed route;
   - the app boots at `https://turbo-gateway.com/<manifest>/` in a fresh
     headless Chromium, and total transfer is under 10 MB (today: 37.6 MB);
   - record cost, transfer size and time in the PR.

Done when: a compressed staging bundle boots through all three gateways.
Production's change merges with it, and Phil merges.

## Phase 1: library mode (public)

Goal: a hand-built page at a raw manifest URL opens a public drive and a
public folder, read-only, in library chrome, with no request outside the
serving host and its gateway.

### 1.1 Detection and start-up (`lib/library/`, `lib/main.dart`)

- New `lib/library/` feature, laid out like `lib/drive_state/`
  (`data/`, `domain/`, `presentation/`).
- `LibraryMode` (domain): reads `<meta name="ardrive-library">` from the
  document once, before `_initializeServices()`. Web only; always off
  elsewhere. Unit-test the parser with a stubbed reader.
- `LibraryConfig` (domain): parses `library.json` (design §`library.json`).
  Reject unknown `version` above what this build supports with a typed error
  (drives the "needs a newer ArDrive" screen). Unit tests for every field,
  missing fields, private without cipher tags, and HTML in title/description
  (kept as plain text).
- In `main.dart`, when library mode is on:
  - Config: do not read or write stored config (`ConfigFetcher` must not touch
    `localStorage` key `config`). Start from the flavor asset, then set
    `arweaveGatewayForDataRequest` from the AR.IO detection on the page's own
    host (`ario_gateway_detector.dart`, already splits the hostname), without
    caching the result. Force `autoSync` off.
  - Database: `Database(openLibraryConnection())`, a new opener in
    `lib/models/database/web.dart` that loads `sqlite3.wasm`, registers an
    `InMemoryFileSystem` (see `_sessionFileSystem`), sets `webSqlite`, and
    returns a `WasmDatabase` with no persistence. No Web Lock, no worker, no
    migration from sql.js. The drive state importer must work against it
    (it uses `webSqlite` / `ATTACH`).
  - Skip `refreshHTMLPageAtInterval`.
  - Skip the Solana RPC re-init.
- Analytics: add a static `PlausibleEventTracker.disabled` flag checked in
  `_track` (and any other send path); set it in library mode. Test that no
  event is sent when disabled.

### 1.2 Loading the library (`lib/library/data`, `lib/library/presentation`)

- `LibraryLoader` cubit, states: `loadingSettings`, `needsKey` (phase 3),
  `loadingSnapshot(bytes, total?)`, `importing`, `ready(LibraryConfig)`,
  `failed(LibraryFailure)` with the four failures in the design's error table.
- Steps:
  1. GET `./library.json` (relative to `Uri.base`).
  2. Seed the drive: insert a `drives` row from `library.json` (`driveId`,
     `rootFolderId`, `owner`, `privacy`, name = title for public or `''` for
     private, `lastUpdated` = epoch so the snapshot's drive metadata wins) and
     the root folder placeholder, the way `DriveDao.writeDriveEntity` does.
  3. GET `./snapshot` with progress.
  4. Build `DriveStateArtifactCandidate(txId, ownerAddress: owner,
     tags: snapshot.tags)` and call `DriveStateImporter.import(candidate,
     body, protection: DriveStateProtection.forDrive(privacy, key), 
     expectedOwnerAddress: owner)`. A rejected result maps to "Its data didn't
     pass ArDrive's checks", and the outcome reason is logged.
- The importer runs its own owner check against `candidate.ownerAddress`;
  that is the owner `library.json` names, which is as trustworthy as the page.
  Do not add a GraphQL owner lookup.
- Tests: a cubit test per state transition with fakes; an integration test
  that imports a real fixture artifact (see `test/drive_state_sqlite/`
  fixtures) (the golden fixtures from #2297, under `test/drive_state_sqlite/` and `test/drive_state/`) into an in-memory database through the loader and reads the
  folder tree back.

### 1.3 Router and shell (`lib/pages/app_router_delegate.dart`, `lib/app_shell.dart`)

- In library mode the router has exactly two outcomes: the `LibraryLoader`
  screens until `ready`, then the explorer for the drive at the scope's root.
  Sign-in, get-started, drives list, shared-file and `/view/` routes map to
  the library root. Deep links inside the library (`#/folders/<id>`,
  `?file=<id>`) are honoured when the folder is inside the scope, otherwise
  they land on the root.
- Never start a sync: guard `SyncCubit.startSync`, `startSyncForDrive`,
  `syncMetadataOnly` and the periodic timer with library mode (return without
  emitting `SyncInProgress`). `openDriveAsVisitor`'s sync-on-open must not run.
  Assert in a test that `SyncRepository` is never called in library mode.
- `LibraryShell`: the design's sidebar (icon, title, description, published
  date, Open in ArDrive, Made with ArDrive), top bar (search, theme), cover
  band on the root, and the mobile variants. Reuse `ArDriveTheme`,
  `ArDriveTypographyNew`, existing sidebar and top bar widgets with the
  account parts removed; do not fork the explorer.
- Explorer behaviour in library mode:
  - hide hidden items and their descendants, ghost folders, and failed or
    pending uploads (filter at the query or mapper level, not by hiding rows
    after layout);
  - breadcrumbs and search stop at the scope root;
  - row and toolbar actions: Download, Download folder, Preview, More info,
    Copy link (new: library link to the folder or file); hide everything else
    listed in the design;
  - no New button, FAB, profile card, login, sync indicator, "Show hidden".
- "Open in ArDrive" opens `https://app.ardrive.io/#/drives/<id>` (the 2.90
  visitor flow) in a new tab.

### 1.4 Requests

- Run the app in library mode in headless Chromium and log every request's
  host. Allowed: the page's host and the detected gateway host. Expected
  offenders to remove: `plausible.io`, `upload.ardrive.io` (a Turbo call at
  start), `fonts.gstatic.com` (Flutter font fallback). For fonts, try
  `fontFallbackBaseUrl` in the page's Flutter configuration pointed at a
  bundled `fonts/` path; if that is not available in Flutter 3.19, document
  it as the one exception in the design and move on.

### 1.5 Test page tool (`tool/library_page/`)

A Node script, `build_test_page.mjs`, that builds a page by hand from:
a release manifest ID, a drive ID and root folder ID, an artifact transaction
ID (read its tags from the gateway's GraphQL once, here only), a title and
description. It writes `library.json` and the page `index.html` (head
injection, escaped), builds the page manifest (release paths + page paths,
index and fallback `index.html`), uploads the three small files with
`@ardrive/turbo-sdk` using the test wallet, and prints the page link. Every
upload is under 105 KiB, so it is free. This tool is also the reference
implementation for phase 2's Dart publisher: keep their outputs
byte-comparable (a golden test in phase 2 compares them).

Snapshot for testing: create one for **New Test Drive** (public,
`c863be1f-a725-4554-9a9e-18268ed8a035`, 3 files) with Create snapshot on
staging, which is free at that size. For the folder case use a folder inside
`UAT-TESTONLY-DELETEME` (`e9b05236-…`).

### 1.6 Verify

- Build the branch for staging, deploy it to Arweave compressed (phase 0's
  path), build a test page pinning that bundle, and open it in a fresh
  profile: public drive, public folder, phone width, dark mode, a preview, a
  download, Copy link, search, a deep link outside the scope.
- Network log shows only the allowed hosts.
- Record first-visit transfer, time to the file list, and import time.
- Measure a large public drive (ArConnect Archives, 711 files, or larger) on a
  throttled 4G profile for the phones risk.

## Phase 2: publish (public)

- `LibraryRepository` (data): find published pages by tags (owner, `Type =
  library-page`, `Drive-Id`) through the existing GraphQL client; read a
  page's `library.json` through the gateway.
- `LibraryPublisher` (domain): the Dart version of the phase 1 tool. Inputs:
  scope, chosen snapshot (or "new"), look settings, images. Steps: create
  snapshot if asked (existing `DriveStateCreationService`), process images
  (`packages/ardrive_utils/lib/src/generate_thumbnail.dart` already uses
  `package:image`; crop and re-encode to the design's sizes), resolve the
  viewer release (`libraryViewerManifestSource` config: read the name through
  the gateway, take `x-arns-resolved-id`, GET `/raw/<id>`), write
  `library.json`, `index.html`, the manifest, warm up. Every upload goes
  through the existing Turbo upload path (`ArDriveUploader` data items, the
  user's payment choice). Resumable: keep uploaded transaction IDs per step
  for the dialog's Try again.
- Snapshot list: `GraphQLDriveStateDiscovery` for the drive, owner-filtered;
  "changes since" from the local database (revisions with block height above
  `Block-End`). Refuse above 100 MiB (D5).
- UI: entry points, the five-step dialog (step 4 shows the "link now, name
  later" panel), progress, done, the management section, republish. Copy and
  layout exactly as the design specifies.
- Tests: golden test that the Dart publisher's `library.json`, `index.html`
  and manifest equal the phase 1 tool's for the same inputs; escaping test;
  preconditions on cubit states (syncing, pending uploads, not fully read);
  excluded counts against a fixture drive; republish keeps scope and writes a
  new manifest; image processing sizes and byte budgets.
- e2e: publish New Test Drive and a UAT folder from staging with existing
  snapshots (free), open both links in a fresh profile, republish, check the
  management section's states.

## Phase 3: private

- Unlock screen and `needsKey` state; key from `#/?driveKey=` or typed; typed
  keys never reach the URL; wrong key keeps the text and shows the error.
- Import with `DriveStateProtection` for a private drive; put the key in
  memory (`DriveDao.putDriveKeyInMemory`) so previews, downloads and
  thumbnails decrypt.
- Publish rules: title empty and required; "Choose from this drive" disabled
  for images; the three review-step statements; "Copy link with key".
- Tests: no drive, folder or file name appears in `library.json`,
  `index.html`, the manifest or any tag (scan every byte the publisher
  uploads); decrypt a file below and above the 100 MiB GCM/CTR boundary in
  library mode; wrong key and missing key screens.
- e2e: Private Drive Test (`7cea4056-…`) published from staging; open in a
  fresh profile with the key in the link and typed; reload behaviour.

## Phase 4: names

Blocked on ArNS-on-Solana support in the app (Solana wallet connection,
listing names a wallet owns or controls, setting and removing undername and
base-name records with `@ar.io/sdk` 4.x). When that exists: step 4's picker,
unpublish (remove an undername; point a main name at a shared "no longer
published" page deployed with each release), republish moving the name,
TTL 300 s, and `og:image` on the name's URL.

## Updating the docs as you go

- Phase 0: `CLAUDE.md` Deployment section (compressed Arweave deploys, staging
  channel).
- Phase 1: `DRIVE_STATE_ARTIFACT.md` §2.7, drop "until Library pages ship".
- Each phase: mark its row in the design's Phases table as shipped, with the
  PR number. Record measurements in the design's facts table.
