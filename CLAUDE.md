# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development Commands

**Required Flutter version: 3.19.6** - Run `scr check-flutter` to verify.

```bash
# First-time setup: install lefthook for git hooks (https://github.com/evilmartians/lefthook)
lefthook install

# Activate script_runner globally (needed for scr commands)
flutter pub global activate script_runner
# Ensure scr is in your PATH (add via export if needed)

# Initial setup (clean, get deps, run code generation, compile the web DB worker)
scr setup

# Recompile the web database worker after editing web/db_worker.dart or
# lib/models/database/web_worker/ (output web/db_worker.js is gitignored)
bash tool/build_db_worker.sh

# Run code generation (after changing models, database, or .drift files)
flutter pub run build_runner build --delete-conflicting-outputs

# Watch mode for code generation during development
flutter packages pub run build_runner watch

# Run web app (development flavor)
flutter run -d chrome --dart-define=environment=development

# Run web app (production flavor)
flutter run -d chrome --dart-define=environment=production

# Run mobile app
flutter run --flavor=development
flutter run --flavor=production

# Run tests (runs main app + all packages with test directories)
scr test

# Run main app tests only
flutter test

# Run a single test file
flutter test test/path/to/test_file.dart

# Run the browser-only tests (@TestOn('browser')) in headless Chrome; plain
# `flutter test` skips them. Serves web/ on :8099 and rebuilds the DB worker.
bash tool/browser_tests.sh

# Run a measurement test (tagged `measurement`, skipped by default)
flutter test <path> --run-skipped --tags=measurement

# Run static analysis (run before committing)
flutter analyze

# Check Flutter version
scr check-flutter

# Check database migrations
scr check-db
```

## Git Conventions

### Commit Messages

Use conventional commit prefixes (lowercase):
- `fix:` bug fixes
- `feat:` new features
- `perf:` performance improvements
- `ui:` UI/design improvements
- `ux:` UX improvements
- `refactor:` code refactoring
- `nit:` small code cleanups
- `docs:` documentation changes
- `style:` formatting changes
- `test:` adding tests
- `chore:` maintenance tasks

Use lowercase for commit messages. Include a detailed list of changes after the summary line if the changes are not self-explanatory. There are no ticket IDs: the team no longer uses Jira, so don't add `PE-` numbers to commits, branches or PR titles.

Example: `fix: properly manage snapshot transaction IDs lifecycle`

## Code Style

- Use single quotes for strings (`prefer_single_quotes` lint rule is enabled)
- Generated files (`**.g.dart`), GraphQL files (`lib/services/arweave/graphql/`), and ario_sdk models (`packages/ario_sdk/lib/src/models/`) are excluded from analysis
- Platform-specific directories (`macos/`, `ios/`, `android/`, `web/`), `drift_schemas/`, `docs/`, and `scripts/` are also excluded from analysis

## Architecture Overview

### State Management (BLoC Pattern)

The app uses Flutter BLoC extensively:
- **Cubits** for simpler state (e.g., `DrivesCubit`, `ProfileCubit`, `UploadCubit`)
- **Blocs** for event-driven complex workflows (e.g., `BulkImportBloc`, `FsEntryMoveBloc`)

Dependencies are injected via constructor. Streams are combined using `Rx.combineLatest()` from RxDart.

### Main Directory Structure

```text
lib/
├── main.dart              # Entry point, DI setup
├── app_shell.dart         # Root shell with nav, sidebar, layout
├── pages/                 # Top-level pages and routing
├── blocs/                 # Feature-specific cubits/blocs (30+)
├── components/            # Reusable UI dialogs and forms
├── core/                  # Core business logic
│   ├── arfs/              # ArFS file system (repository/, entities/, use_cases/)
│   ├── crypto/            # Cryptographic operations
│   └── upload/            # Upload pipeline & cost calculation
├── services/              # External integrations (arweave/, authentication/, config/)
├── models/                # Drift database, DAOs, domain models
├── entities/              # Serializable data entities
├── sync/                  # Drive sync mechanism (domain/, data/, utils/)
├── turbo/                 # Turbo upload service and payments
└── utils/                 # Helpers including dependency_injection_utils.dart
```

Not all features live under `blocs/`. Newer, self-contained features are top-level
directories under `lib/` that bundle their own bloc + repository + UI — e.g. `arns/`
(data/domain/presentation), `sync/`, `turbo/`, `download/`, `sharing/`, `search/`,
`manifest/`, `drive_explorer/`, `gar/`, `user/`. Follow the layout of the
nearest comparable feature rather than defaulting to `blocs/`.

Note: `lib/l10n/` holds the ARB translation files; `lib/l11n/` is unrelated to
localization despite the name — it holds validation message helpers.

### Local Packages (in `packages/`)

| Package | Purpose |
|---------|---------|
| `ardrive_ui` | Design system & UI components |
| `ardrive_io` | File I/O abstraction (web/mobile/desktop) |
| `ardrive_uploader` | Upload protocol handling |
| `ardrive_crypto` | Cryptography wrapper |
| `ardrive_utils` | Utility functions |
| `ardrive_logger` | Centralized logging |
| `arfs` | ArFS protocol implementation |
| `ario_sdk` | ARIO protocol SDK |
| `arconnect` | ArConnect wallet bridge |
| `pst` | Profit Sharing Token operations |
| `file_saver` | File saving abstraction |
| `flutter_file_picker` | File picker fork |

Note: The `ario_sdk` package requires separate code generation - `scr setup` handles this automatically.

UI is built from `ardrive_ui` (`ArDriveButtonNew`, `ArDriveStandardModalNew`,
`ArDriveTypographyNew`, `colorTokens`, plus `ArDriveLink`, `ArDriveNotice`, `ArDriveEmptyState`,
`ArDriveSpinner`, `ArDriveBottomSheet`, `ArDriveCopyField`, `ArDriveSpacing`/`ArDriveRadius`).
The `New` suffix is historical: the older components it replaced are deleted.
`test/design_system_guard_test.dart` fails on a literal or Material colour, or a raw
spinner or progress bar, outside `ardrive_ui`'s style files, except where its lists give a reason.
`packages/ardrive_ui/README.md` says which piece to use where, including the three button sizes.
Don't draw a one-off version of something the design system has; if it falls short, fix it there.
Menus are `ArDriveDropdown`, `ArDriveSubmenu`, `ArDriveMenuAnchor`, `ArDriveChoiceMenu` or
`ArDriveSelectField`, not Material's, reactive_forms' or flutter_portal's (clicks miss them
with the accessibility tree on, and the guard test fails on them). They build in the
navigator's overlay, so their content can't read a page's own providers; see the README's
Menus section.

### Database (Drift ORM)

- Main database: `lib/models/database/database.dart` (currently `schemaVersion => 32`)
- Table definitions: `lib/models/tables/*.drift`
- DAOs: `DriveDao`, `ProfileDao`, `ARNSDao`
- Drift codegen options live in `build.yaml` (`named_parameters: true`); the same file
  configures Artemis GraphQL generation from `lib/services/arweave/graphql/`
- After schema changes: bump `schemaVersion` in `database.dart` and run code generation
- Pre-push hook (`lefthook/database_checker.sh`) compares `lib/models/tables` against
  the upstream branch and fails if `schemaVersion` was not incremented. It diffs
  `@{u}...HEAD`, so it only works with an upstream tracking branch set.
- Migration test fixtures in `drift_schemas/` and `test/generated_migrations/` only
  cover v17–v19 — they were not kept current with later schema versions. Don't assume
  a schema bump is covered by migration tests.
- Pre-commit hook validates the correct Flutter version is installed

### Web Database

On web, the database is SQLite compiled to wasm (`web/sqlite3.wasm`), opened by
`lib/models/database/web.dart`. The preferred path runs it on OPFS in a dedicated
worker (`web/db_worker.dart` → `web/db_worker.js`, built by `tool/build_db_worker.sh`,
worker side in `lib/models/database/web_worker/`). If `db_worker.js` is missing or the
worker can't open, it falls back to IndexedDB on the main thread, so a forgotten worker
build degrades silently rather than failing. One tab owns the database through a Web
Lock (`ardrive-database`); other tabs work on a session copy. `web/sqlite3.wasm` must
match the resolved `sqlite3` package (`tool/check_wasm_version.sh`) or startup dies with
a `LinkError`. Drift's own OPFS mode was rejected because it needs cross-origin
isolation headers, which break media previews and Stripe and can't be set when served
from AR.IO gateways. `docs/WEB_DATABASE.md` has the measurements and rationale.

`web/worker.js` is a different worker and is live even though nothing in the repo names
it: the `isolated_worker` package (a transitive dependency) loads it by that filename at
runtime. Before calling any `web/` asset unused, search the pub cache too, not just the repo.

### Key Services

- **ArDriveAuth** (`services/authentication/`) - Wallet auth, biometrics
- **ArweaveService** (`services/arweave/`) - Node interaction, GraphQL
- **ConfigService** (`services/config/`) - App config, flavors
- **TurboUploadService** (`turbo/services/`) - Bundled uploads, payments
- **LicenseService** (`services/license/`) - UDL/licensing metadata attached to uploads

Identity is not Arweave-only: alongside JWK keyfiles and the ArConnect browser
extension (`packages/arconnect`, `lib/services/arconnect/`), there are Ethereum and
Solana providers (`lib/services/ethereum/`, `lib/services/solana/`) including ENS/SNS
name resolution. When touching auth or signing, check which identity types a code
path must support rather than assuming an Arweave wallet.

### Routing

Uses Flutter's `RouterDelegate` pattern (not go_router or similar packages). Core files in `lib/pages/`:
- `app_router_delegate.dart` - Navigation state management
- `app_route_information_parser.dart` - Route parsing
- `app_route_path.dart` - Route path definitions

Share links are parsed here and are effectively permanent public API — links already
in the wild must keep resolving. `docs/SHARE_LINKS.md` is the spec (routes, the full
parameter vocabulary, the optional `d` payload); link building/parsing lives in
`lib/utils/shared_file_link.dart`. Emitted shapes: `/file/{fileId}/view`,
`/view/{txId}`, `/drives/{driveId}`, `/drives/{driveId}/folders/{folderId}`. A private
file's key travels as `k` (v2, preferred in the fragment) or `fileKey` (v1, honored
forever); a private drive's as `driveKey`. `/share/{fileId}` and path-routed forms are
parsed but not yet served, so don't emit them. The app uses the **hash** URL strategy
(`lib/utils/app_url_strategy.dart`), so everything after the `#` stays in the browser
and is never sent to a server.

### Dependency Injection

Manual IoC via factory functions in `lib/utils/dependency_injection_utils.dart`. Services are provided via `MultiRepositoryProvider` and `MultiBlocProvider` in `main.dart`.

### App Flavors & Config Resolution

Three flavors configured: `development`, `staging`, `production`. Affects gateway URLs, upload limits, and feature flags. Config files are in `assets/config/` (dev.json, staging.json, prod.json), deserialized into `AppConfig` (`lib/services/config/app_config.dart`).

**Config is not read straight from the asset JSON at runtime.** `ConfigFetcher.fetchConfig()` (`lib/services/config/config_fetcher.dart`) resolves it in layers:

1. Load the flavor's `assets/config/<flavor>.json` as the default.
2. If a config is already persisted in local storage under the key `config`, use that instead.
3. The stored copy is only replaced when the asset config's `configVersion` is **greater** than the stored one.

Consequence worth remembering: **editing `assets/config/*.json` has no effect for anyone who has already run the app unless you also bump `configVersion`** (or clear the stored config via dev tools / `localStorage.removeItem('flutter.config')`). This is the most common "my config change did nothing" trap.

For first-time users with no stored config, `ConfigFetcher` also probes whether the app is being served from an AR.IO gateway and, if so, points `arweaveGatewayForDataRequest` at it. The detection result is cached in local storage per hostname (`arIOGatewayDetectionResult_<host>`), so it runs once, not per load.

Notable `AppConfig` flags: `useTurboUpload` / `useTurboPayment`, `allowedDataItemSizeForTurbo`, `enableSyncFromSnapshot`, `autoSync` + `autoSyncIntervalInSeconds`, `uploadThumbnails`, `maxConcurrentDataFetches`.

### Localization

The app supports multiple languages via ARB files in `lib/l10n/`: English, Spanish, Hindi, Japanese, Chinese (Simplified and HK). Strings are accessed via Flutter's generated `AppLocalizations`.

### Design System

UI is built from `packages/ardrive_ui`; its README says which components and
tokens to use. The
cross-platform standard behind it, in values, is published at
`https://ardrive.io/brand-kit/design-system.md` from the public-site repo, with
a machine summary at `https://ardrive.io/brand-kit/agents.json`. A change to a
token, the type scale or a component's look updates both.

## Key Patterns

### Adding a New Feature
1. Place it per the directory-structure note above: `lib/blocs/[feature]/` for a small
   cubit, or a top-level `lib/[feature]/` modeled on the nearest comparable feature
2. Add cubit/bloc with states
3. Wire up in dependency injection
4. Add UI components in the feature folder, or `lib/components/` if shared

### Upload Flow
`UploadCubit` → file validation → cost calculation → payment selection → `UploadRepository` → `TurboUploadService` or standard uploader → database update → sync

The protocol-level work lives in `packages/ardrive_uploader/lib/src/`. Key seams:
`metadata_generator.dart` builds ArFS metadata, `data_bundler.dart` assembles ANS-104
bundles, and `upload_strategy.dart` + `upload_dispatcher.dart` choose between the two
transports — `turbo_streamed_upload.dart` (Turbo bundler service) and
`d2n_streamed_upload.dart` (direct-to-node). `upload_controller.dart` / `upload_task.dart`
carry progress and cancellation back to the UI. Changing upload behavior usually means
editing the package, not `lib/blocs/upload/`.

Note the cipher used is size-dependent: files under `maxSizeSupportedByGCMEncryption`
(100 MiB, `packages/ardrive_uploader/lib/src/constants.dart`) are AES256-GCM, larger
ones AES256-CTR. That boundary shapes the download and decryption paths too.

### Sync Flow
`SyncCubit` → Arweave GraphQL queries → snapshot validation → local database update → UI refresh

Sync lives in `lib/sync/`, not `lib/blocs/`: `domain/cubit/sync_cubit.dart` orchestrates,
`domain/repositories/sync_repository.dart` does the work, `data/snapshot_validation_service.dart`
validates snapshots before trusting them, and `utils/batch_processor.dart` chunks
drive-history processing. Two things to know before editing: `domain/ghost_folder.dart`
handles folders referenced by files whose own metadata was never found (a normal state,
not corruption), and `domain/sync_failure_simulator.dart` exists for deliberately
injecting failures when testing recovery paths.

### Testing
- Unit tests use `mocktail` for mocking
- BLoC tests use `bloc_test` package
- Test utilities in `test/test_utils/` (fake data generators, mock users, custom matchers, mocked dependencies, fake implementations)
- `scr test` runs `flutter test` on the main app plus discovers and runs tests in `packages/*/test` directories, also running `flutter analyze` on each package

### End-user testing in the browser
`docs/WEB_E2E_TESTING.md` covers testing a real web build in headless Chromium, logged in with the
team's test wallet: login, uploads (Turbo and wallet-paid), dialogs, screenshots, network log.
Use it to prove anything that touches upload, payment, login or a dialog's layout: `/web-e2e`
(skill in `.claude/skills/web-e2e/`) tests the current branch, or a PR, branch, link or area of the
app given after it, from a plan written from the change, and `/web-e2e release` runs the release
checklist on staging. No ticket or PR number is required. The tools are in `tool/web_e2e/`. `launch.js` blocks spending by default: wallet-paid uploads go to a local fake
gateway, paid Turbo uploads and top-ups are refused. PR previews expire; for an old PR, build
it locally as the guide describes. The test wallet's keyfile and password live
only in `~/.config/ardrive-e2e/env`. Never commit, print or upload them, or any private drive
password.

### CI Pipeline
CI (`.github/workflows/test.yml`) generates code once (`generate`), then runs `flutter analyze`, the app's tests in four shards (`tool/ci_test_shard.sh`), the packages' tests (`SKIP_APP=1 scripts/run_tests.sh`) and `bash tool/browser_tests.sh` in parallel. The final `test-and-lint` job is green only when all of them are. Locally, `scr test` and `bash tool/browser_tests.sh` cover the same ground. A new push to a PR cancels the run for the push before it, and a closed PR's Firebase preview is deleted (`pr-closed.yaml`).

The deploy workflows build the web app with `--dart2js-optimization=O2`, which minifies: a class's name in a release build is not its source name, so never compare `runtimeType.toString()` or a default `toString()` against a string. `docs/WEB_LOAD_TIME.md` covers that and the start-up path (what may run before the first frame, the sign-in panel drawn before the database answers).

### Git Hooks (Lefthook)
- **Pre-commit**: Validates Flutter version matches 3.19.6
- **Pre-push**: Validates database schema version is incremented when `.drift` files change

## Design Documents

The `docs/` directory contains internal design documents, including `ArweaveFS.md` (the ArFS file system protocol specification — entity types, transaction tags, privacy model) and implementation plans for sync and upload improvements. Consult these before making changes to sync, ArFS entities, or transaction handling. `docs/BROWSER_WALLET_IDENTITIES.md` holds the Ethereum and Solana sign-in derivations; it is an ArDrive client convention, not part of ArFS.

The drive state artifact (a published SQLite file of a drive's parsed state, imported in bulk instead of replaying history; additive to snapshots) is specified in `docs/DRIVE_STATE_ARTIFACT.md`, with bound decisions in `docs/drive-state/DECISIONS.md`, cross-repo status in `docs/drive-state/DELIVERY_PLAN.md`, and the SQLite-format proposal and measurements in `docs/drive-state/SQLITE_ARTIFACT.md`. Users see the word "snapshot" for both the old JSON snapshots and drive state artifacts.

Users see "deployment" for an Arweave manifest the app creates or updates (New deployment, Update deployments, the file type), while code, docs and the ArFS spec keep saying manifest. The word "manifest" stays in front of users only where it means any manifest: Import from manifest, and the one-line explanation that a deployment is stored as an Arweave manifest.

ArNS names (naming deployments, public files and publications; the Names page; record changes paid in Turbo credits and approved by a linked Solana wallet) are specified in `docs/NAMES.md`, which is also the terminology standard for names across ArDrive apps. The feature is behind the `enableArNS` config flag.

## Deployment

- Changes to `dev` auto-deploy to [staging.ardrive.io](https://staging.ardrive.io)
  (`staging.yaml`, GitHub Pages). A green run is not a live site: Pages publishes a few
  minutes later behind a 10-minute CDN cache, so check `last-modified` on
  `https://staging.ardrive.io/main.dart.js` before testing staging.
- PRs get a Firebase preview build with the **development** config (testnet Turbo); the
  URL is in the github-actions comment on the PR, and it expires.
- Production: **the merge to `master` is the deploy** (`production.yaml` runs on push to
  `master`; nothing runs on a tag or release, whatever the README says). Publish the
  GitHub release `v*` after that run is green, pinned to the merge commit. PRs into
  `master` get no CI (`pr.yaml` ignores `master`), so `dev` is where a change is validated.
- Merge release PRs (`dev` → `master`) with a merge commit, never a squash: squashing
  breaks the shared history and makes the next release PR conflict.
- **No rollback below 3.0.** From 3.0 the local profile is in format 2, and the older
  database stores a rollback build would fall back to are deleted (`docs/WEB_DATABASE.md`
  §4). A build before 3.0 can't read a format 2 profile: it reports a wrong password, and
  its *Use a different account* deletes the wallet saved on the device. Fix forward instead.
  A newer format than a build knows shows "saved by a newer version", with Reload only.
- `dev`'s `pubspec.yaml` version is not bumped after releases, so staging reports an
  older version than production.
- Production also puts the build on Arweave **gzipped** (`--compress gzip`: each file is
  stored compressed with a `Content-Encoding: gzip` tag, about 20 MB instead of 77) and
  without source maps, with `ar-io/ar-io-deploy` (pinned by commit), and moves the ArNS
  name. Pushes to `dev` never touch Arweave. To try publication mode on Arweave before a
  release, run *Staging build to Arweave* (`staging-arweave.yaml`) by hand on a branch: it
  uploads a staging build the same way, paid by the deploy wallet, with no ArNS name, and
  puts the manifest ID in the job summary (`docs/PUBLICATIONS.md`).
  Each upload then reads every path through turbo-gateway.com and ardrive.net with
  `tool/warm_arweave_manifest.sh <manifest-id>`, which also fails on a gateway sending gzip
  bytes without the header. A new upload can 404 on a gateway other than
  turbo-gateway.com for a while after it lands: that's propagation, not a broken deploy.

## Working alongside other agents

Several agents (and people) work on this repo at once, often from the same machine.

- Work in your own git worktree on your own branch
  (`git worktree add ../ardrive-web-wt-<name> -b <branch> origin/dev`), not by switching
  branches in a checkout someone else may be using. A new worktree has no generated
  files: run `scr setup` there before building or testing.
- Uncommitted changes, branches and worktrees you didn't create belong to someone else.
  Don't stash, revert, commit, delete or reformat them; some local branches exist on
  this machine only.
- Before writing after any pause, run `git status` and `git log <your last sha>..HEAD`.
  Commits or changes you didn't make mean another agent is on the branch: stop and ask.
- Never edit source while a test suite is running in the same tree; the run compiles
  files as it reaches them, so its result would mix old and new code.
- Run `dart format` on the files you changed, never on a folder: `dev` carries
  unformatted files, and formatting a folder puts them all in your diff.
- Generated GraphQL (`lib/services/arweave/graphql/*.graphql.dart`) is gitignored and goes
  stale across branches. `flutter analyze` skips generated files and stays green while
  `flutter test` fails to compile; delete both files and rerun `build_runner`.
- Only one e2e browser can use a profile. To run beside another session's `launch.js`,
  give yours its own `E2E_DIR` and `CDP_PORT` (and `CHAOS_URL` if you start a second
  fake gateway) instead of stopping theirs.
- Each push to `dev` starts a staging deploy, and only the commit `dev` points at
  publishes. After merging, check staging serves your commit before testing it there.

## Custom Gateway Configuration

For testing with a custom Arweave gateway, set in browser console:
```js
localStorage.setItem('flutter.arweaveGatewayUrl', '"https://my.custom.url"');
// Remove with: localStorage.removeItem('flutter.arweaveGatewayUrl');
```

Reload the page after changing the gateway URL.
