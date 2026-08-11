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

# Initial setup (clean, get deps, run code generation)
scr setup

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

Use lowercase for commit messages. Include Jira ticket ID at the end when working on a tracked issue. Include a detailed list of changes after the summary line if the changes are not self-explanatory.

Example: `fix: properly manage snapshot transaction IDs lifecycle PE-8753`

### PR Titles

PR titles must follow the pattern `PE-{number}: {description}` (enforced by CI). Example: `PE-8753: Fix snapshot transaction lifecycle`

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
`manifest/`, `drive_explorer/`, `gift/`, `gar/`, `user/`. Follow the layout of the
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
| `build` | Build utilities |

Note: The `ario_sdk` package requires separate code generation - `scr setup` handles this automatically.

### Database (Drift ORM)

- Main database: `lib/models/database/database.dart` (currently `schemaVersion => 29`)
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
in the wild must keep resolving. Current shapes: `/drives/{driveId}`,
`/drives/{driveId}/folders/{folderId}`, and `/file/{fileId}/view`, where a private
file carries its key as the `fileKey` query parameter (base64). Note the app uses
Flutter's default **hash** URL strategy, so everything after the `#` — including that
pseudo-query — stays in the browser and is never sent to a server.

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

## Key Patterns

### Adding a New Feature
1. Create folder in `lib/blocs/[feature]/`
2. Add cubit with states
3. Wire up in dependency injection
4. Add UI components in `lib/components/` or feature folder

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

### CI Pipeline
CI runs `scr setup` → `flutter analyze` → `scr test`. Ensure these all pass locally before pushing. PR title format (`PE-{number}: {description}`) is enforced by a separate CI check (`pr_title_check.yaml`).

### Git Hooks (Lefthook)
- **Pre-commit**: Validates Flutter version matches 3.19.6
- **Pre-push**: Validates database schema version is incremented when `.drift` files change

## Design Documents

The `docs/` directory contains internal design documents, including `ArweaveFS.md` (the ArFS file system protocol specification — entity types, transaction tags, privacy model) and implementation plans for sync and upload improvements. Consult these before making changes to sync, ArFS entities, or transaction handling.

## Deployment

- Changes to `dev` branch auto-deploy to [staging.ardrive.io](https://staging.ardrive.io)
- PRs to `dev` trigger preview builds
- Production releases: merge `dev` → `master`, then create GitHub release with tag `v*` (e.g., `v1.0.1`)

## Custom Gateway Configuration

For testing with a custom Arweave gateway, set in browser console:
```js
localStorage.setItem('flutter.arweaveGatewayUrl', '"https://my.custom.url"');
// Remove with: localStorage.removeItem('flutter.arweaveGatewayUrl');
```

Reload the page after changing the gateway URL.
