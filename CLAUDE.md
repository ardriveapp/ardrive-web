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
- Generated files (`**.g.dart`) and GraphQL files (`lib/services/arweave/graphql/`) are excluded from analysis
- Platform-specific directories (`macos/`, `ios/`, `android/`, `web/`) are also excluded from analysis

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

- Main database: `lib/models/database/database.dart`
- Table definitions: `lib/models/tables/*.drift`
- DAOs: `DriveDao`, `ProfileDao`, `ARNSDao`
- After schema changes: bump `schemaVersion` in `database.dart` and run code generation
- Pre-push hook validates schema version is incremented when `.drift` files change

### Key Services

- **ArDriveAuth** (`services/authentication/`) - Wallet auth, biometrics
- **ArweaveService** (`services/arweave/`) - Node interaction, GraphQL
- **ConfigService** (`services/config/`) - App config, flavors
- **TurboUploadService** (`turbo/services/`) - Bundled uploads, payments

### Dependency Injection

Manual IoC via factory functions in `lib/utils/dependency_injection_utils.dart`. Services are provided via `MultiRepositoryProvider` and `MultiBlocProvider` in `main.dart`.

### App Flavors

Three flavors configured: `development`, `staging`, `production`. Affects gateway URLs, upload limits, and feature flags. Config files are in `assets/config/` (dev.json, staging.json, prod.json).

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

### Sync Flow
`SyncCubit` → Arweave GraphQL queries → snapshot validation → local database update → UI refresh

### Testing
- Unit tests use `mocktail` for mocking
- BLoC tests use `bloc_test` package
- Test utilities in `test/test_utils/`
- `scr test` runs main app tests (`flutter test`) plus all packages with test directories

### CI Pipeline
CI runs `scr setup` → `flutter analyze` → `scr test`. Ensure these all pass locally before pushing.

### Git Hooks (Lefthook)
- **Pre-commit**: Validates Flutter version matches 3.19.6
- **Pre-push**: Validates database schema version is incremented when `.drift` files change

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
