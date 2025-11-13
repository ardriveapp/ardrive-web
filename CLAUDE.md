# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ArDrive Web is a Flutter-based web application (with mobile support) for secure, permanent decentralized storage on Arweave. It implements the ArFS (Arweave File System) specification and supports encrypted private drives, public drives, and various upload/download methods.

## Development Commands

### Initial Setup
```bash
# Install lefthook for git hooks
lefthook install

# Install Flutter SDK dependencies
flutter pub get

# Install script runner globally
flutter pub global activate script_runner

# Run full setup (clean, pub get for all packages, build_runner)
scr setup
```

### Code Generation
```bash
# Build generated code once (Drift, JSON serialization, Artemis GraphQL)
flutter pub run build_runner build --delete-conflicting-outputs

# Watch for changes and rebuild automatically
flutter packages pub run build_runner watch
```

### Running the App
```bash
# Development environment (web)
flutter run -d chrome --dart-define=environment=development

# Production environment (web)
flutter run -d chrome --dart-define=environment=production

# Mobile flavors
flutter run --flavor=development
flutter run --flavor=production
```

### Testing
```bash
# Run all tests (main app + all packages)
scr test
# or
./scripts/run_tests.sh

# Run tests for main app only
flutter test

# Run a single test file
flutter test test/path/to/test_file.dart

# Run tests with coverage
flutter test --coverage
```

### Code Quality
```bash
# Analyze code
flutter analyze

# Check Flutter version matches requirements
scr check-flutter

# Check database schema consistency
scr check-db
```

### Building
```bash
# Build for web
flutter build web --dart-define=environment=production

# Build for Android
flutter build apk --flavor=production

# Build for iOS
flutter build ios --flavor=production
```

## Architecture Overview

### High-Level Structure

ArDrive follows a **Clean Architecture** pattern with clear separation:

1. **Presentation Layer** (`lib/pages/`, `lib/components/`) - UI and user interaction
2. **State Management** (`lib/blocs/`) - BLoC/Cubit pattern with flutter_bloc
3. **Domain Layer** (`lib/core/`, `lib/entities/`) - Business logic and ArFS entities
4. **Data Layer** (`lib/models/`, `lib/services/`) - Persistence and external services

### Key Directories

- **`lib/blocs/`** - State management using flutter_bloc (35+ cubits/blocs for different features)
- **`lib/services/`** - External integrations (Arweave, ArConnect, Turbo, Config, Auth)
- **`lib/entities/`** - ArFS specification entities (Drive, File, Folder, Snapshot, License)
- **`lib/models/`** - Drift database ORM layer with tables and DAOs
- **`lib/core/`** - Business logic, repositories, upload/download orchestration
- **`lib/pages/`** - Route-based UI pages
- **`lib/components/`** - Reusable UI components
- **`lib/authentication/`** - Multi-path authentication (ArConnect, JSON wallet, biometrics)
- **`lib/sync/`** - Drive synchronization with Arweave
- **`packages/`** - Internal shared libraries (see below)

### State Management Pattern

Uses **flutter_bloc** with:
- **Cubits** for simpler state (ProfileCubit, DrivesCubit, UploadCubit, SyncCubit)
- **Blocs** for event-driven state (UploadBloc, FileShareBloc, FsEntryMoveBloc)
- **RxDart** for complex stream combinations
- All state classes are immutable with subclasses (Loading, Success, Error)

Key state flow:
```
User Action → Cubit/Bloc → Repository → Service/DAO → External API/Database
                ↓
            State Update → UI Rebuild
```

### Database Layer (Drift ORM)

12 tables with reactive queries:
- `profiles` - User wallets and authentication
- `drives`, `drive_revisions` - Drive metadata and history
- `folder_entries`, `folder_revisions` - Folder structure and history
- `file_entries`, `file_revisions` - File metadata and history
- `licenses` - License metadata (UDL, CC)
- `network_transactions` - Transaction tracking
- `arns_records` - ArNS name registrations
- `ant_records` - Ant token records

Schema version: 27 (see `lib/models/database/database.dart`)

**Important**: When modifying database schema:
1. Update table definitions in `lib/models/database/`
2. Increment schema version in Database class
3. Add migration in `onUpgrade` method
4. Run `flutter pub run build_runner build --delete-conflicting-outputs`
5. Generate test migration: See `test/generated_migrations/`

### Local Packages (`packages/`)

Internal libraries used throughout the app:

- **`ardrive_ui`** - Design system, reusable UI components, theme
- **`ardrive_uploader`** - File upload abstraction with AR/Turbo strategies
- **`ardrive_crypto`** - Encryption/decryption (AES, RSA), key derivation
- **`ardrive_io`** - Cross-platform file I/O abstractions
- **`ardrive_utils`** - Common utilities and extensions
- **`ardrive_logger`** - Centralized logging with Sentry integration
- **`arconnect`** - ArConnect wallet extension bridge (web-only)
- **`arfs`** - ArFS specification entities
- **`ario_sdk`** - Ario service SDK for ArNS name resolution
- **`pst`** - PST token service for voting power
- **`file_saver`** - File download to disk
- **`flutter_file_picker`** - Custom file picker implementation

When working on these packages, run tests from their directories:
```bash
cd packages/ardrive_ui
flutter test
```

### Upload Flow

```
UploadCubit (orchestrator)
  → FileSelection
  → PaymentEvaluation (TurboCostCalculator or AR cost)
  → FilePreparation (FileRepository)
  → MetadataGeneration (ARFSUploadMetadataGenerator)
  → UploadExecution (ArDriveUploader from ardrive_uploader package)
    → Bundle signing
    → Transaction creation
    → Arweave/Turbo submission
  → Database update (DriveDao)
```

Upload methods:
- **Turbo** - Fast, credit-based uploads via Turbo service
- **AR** - Traditional Arweave transaction-based uploads

### Download Flow

```
ArDriveDownloader
  → Metadata fetch (ArweaveService)
  → Data download with streaming
  → Decryption (if private file using ardrive_crypto)
  → File save (IOFileAdapter from ardrive_io)
```

### Authentication Flow

Multi-path authentication via `ArDriveAuth`:
- **ArConnect** - Browser extension wallet (web-only)
- **JSON Wallet** - File-based wallet with password
- **Biometric** - Fingerprint/face unlock with secure storage

Profile management:
- Multiple profiles supported per wallet
- Wallet encryption with argon2 key derivation
- Balance tracking for both AR and Turbo credits

### Synchronization

`SyncCubit` + `SyncRepository` handle drive sync:
- Periodic sync via `combineLatest` on profile + drives stream
- Fetches drive/folder/file transactions from Arweave GraphQL
- Updates local Drift database
- Snapshot support for faster initial sync

## Important Patterns and Conventions

### Commit Messages

Follow conventional commits (see `.cursorrules`):
- `feat:` - New features
- `fix:` - Bug fixes
- `perf:` - Performance improvements
- `docs:` - Documentation changes
- `style:` - Formatting changes
- `refactor:` - Code refactoring
- `test:` - Adding tests
- `chore:` - Chore tasks

Use lowercase, be concise, include change details if not self-explanatory.

### App Flavors

Three environments:
- **development** - Local development
- **staging** - Staging environment (auto-deploys from `dev` branch to staging.ardrive.io)
- **production** - Production environment (deploys from `master` to app.ardrive.io)

### GraphQL Code Generation

ArDrive uses Artemis for GraphQL code generation. Schema and queries are in:
- Schema: `lib/services/arweave/graphql/schema.graphql`
- Queries: `lib/services/arweave/graphql/queries/*.graphql`
- Fragments: `lib/services/arweave/graphql/fragments/*.graphql`
- Generated output: `lib/services/arweave/graphql/graphql_api.dart`

When modifying GraphQL queries, run build_runner to regenerate.

### Testing Approach

- **Unit tests** - Test individual functions, cubits, services
- **Widget tests** - Test UI components
- **Integration tests** - Test full flows (in `test_driver/`)
- **Mocking** - Uses `mocktail` for mocking dependencies

Test structure mirrors `lib/` structure. Use `test_utils/` for shared test utilities.

### Git Hooks

Lefthook runs pre-commit and pre-push hooks:
- **pre-commit**: Flutter version check
- **pre-push**: Database schema consistency check

Install with `lefthook install`.

## Common Tasks

### Adding a New Feature

1. Determine which layer the feature belongs to (presentation, state, domain, data)
2. Create necessary entities/models if dealing with new data structures
3. Add database tables/DAOs if persistence is needed (remember migrations!)
4. Implement repository interface and concrete implementation in `lib/core/`
5. Create Cubit/Bloc for state management in `lib/blocs/`
6. Build UI components in `lib/components/` and pages in `lib/pages/`
7. Wire up in `app_shell.dart` or relevant parent widget
8. Add tests mirroring the structure in `test/`
9. Run build_runner if using code generation
10. Test in development environment before creating PR

### Modifying Upload/Download Logic

- Upload logic: `lib/blocs/upload/`, `lib/core/upload/`, `packages/ardrive_uploader/`
- Download logic: `lib/download/`, `lib/core/download_service.dart`
- Cost calculation: `lib/blocs/upload/upload_cubit.dart` (TurboCostCalculator, UploadCostEstimateCalculatorForAR)

### Working with ArFS Entities

ArFS entities are in `lib/entities/` and represent the Arweave File System specification:
- `DriveEntity`, `FolderEntity`, `FileEntity` - Core entities
- `SnapshotEntity` - Drive snapshots for faster sync
- `LicenseEntity` - UDL and Creative Commons licenses

These entities are serialized to JSON for Arweave transactions. When modifying, ensure compliance with ArFS spec.

### Updating Dependencies

Main dependencies are in `pubspec.yaml`. Many are git-based or path-based:
- Git dependencies: Use specific refs/commits for stability
- Path dependencies: Local packages in `packages/`

When updating:
1. Update `pubspec.yaml`
2. Run `flutter pub get`
3. Run full test suite
4. Check for breaking changes in changelogs

### Custom Gateway Configuration

For testing with custom Arweave gateways, use browser console:
```javascript
localStorage.setItem('flutter.arweaveGatewayUrl', '"https://my.custom.url"');
```

## Deployment

- **Staging** (`dev` branch): Auto-deploys to staging.ardrive.io
- **Production** (`master` branch): Create GitHub release with tag `v*` (e.g., `v1.0.1`) to trigger deployment to app.ardrive.io

## Additional Resources

- ArFS Specification: https://github.com/ArweaveTeam/arweave-standards/blob/master/ans/ANS-104.md
- Flutter SDK: 3.19.6 (enforced by version checker)
- Dart SDK: >=3.2.0 <4.0.0
