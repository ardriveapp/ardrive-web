# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ArDrive Web is a Flutter-based application for secure, permanent storage on Arweave. It supports web, iOS, and Android platforms.

## Essential Commands

### Setup and Dependencies
```bash
# Initial setup (clean, get dependencies, and generate code)
scr setup

# Install script runner globally (required for scr commands)
flutter pub global activate script_runner

# Watch for code generation changes during development
flutter pub run build_runner watch --delete-conflicting-outputs
```

### Running the Application
```bash
# Web development
flutter run -d chrome --dart-define=environment=development

# Web production
flutter run -d chrome

# Mobile development
flutter run --flavor=development

# Mobile production
flutter run --flavor=production
```

### Testing
```bash
# Run all tests with analysis (includes package tests)
scr test

# Run Flutter tests only
flutter test

# Run specific test file
flutter test test/path/to/test_file.dart

# Run integration tests
flutter test integration_test/
```

### Code Generation
```bash
# One-time code generation
flutter pub run build_runner build --delete-conflicting-outputs

# Watch mode for continuous generation
flutter pub run build_runner watch --delete-conflicting-outputs

# Generate code for ario_sdk package
cd packages/ario_sdk && flutter pub run build_runner build --delete-conflicting-outputs && cd ../..
```

### Linting and Analysis
```bash
# Run Flutter analyzer
flutter analyze

# Format code
dart format lib/ test/ packages/
```

### Git Hooks and Validation
```bash
# Check Flutter version (must be 3.19.6)
scr check-flutter

# Check database schema version updates
scr check-db

# Deploy to Arweave
scr deploy-to-arweave
```

## High-Level Architecture

### Core Structure
- **`lib/`** - Main application code using BLoC pattern for state management
  - **`blocs/`** - Business logic components (Blocs and Cubits)
  - **`core/`** - Core functionality including ARFS (Arweave File System) implementation
  - **`entities/`** - Arweave-specific data models
  - **`models/`** - Database models using Drift (SQLite)
    - **`daos/`** - Data Access Objects for database operations
    - **`database/`** - Database configuration and schema version (current: v27)
    - **`tables/`** - Drift table definitions (`.drift` files)
    - **`queries/`** - Drift query definitions
  - **`pages/`** - Application screens and routing
  - **`services/`** - External service integrations
    - **`arweave/graphql/`** - GraphQL queries for Arweave data
  - **`utils/`** - Shared utilities
  - **`arns/`** - AR.IO Name Service integration
  - **`authentication/`** - Login and authentication flows
  - **`sync/`** - Data synchronization with Arweave
  - **`gar/`** - Gateway Access Revocation functionality

### Modular Packages
- **`packages/ardrive_ui/`** - Reusable UI component library with Storybook
- **`packages/ardrive_crypto/`** - Cryptographic operations and wallet management
- **`packages/ardrive_uploader/`** - File upload handling with chunking support
- **`packages/ardrive_http/`** - HTTP client wrapper with retry logic
- **`packages/ardrive_utils/`** - Common utilities shared across packages
- **`packages/ardrive_logger/`** - Logging infrastructure
- **`packages/ardrive_io/`** - File system abstraction for web and mobile
- **`packages/arconnect/`** - ArConnect wallet integration
- **`packages/ario_sdk/`** - AR.IO SDK for name service integration
- **`packages/pst/`** - Profit Sharing Token implementation
- **`packages/arfs/`** - ARFS entity definitions

### Key Architectural Patterns
1. **State Management**: BLoC pattern with flutter_bloc
   - Use Cubits for simple state management
   - Use Blocs for complex state with events
   - State files follow pattern: `*_state.dart`
   - Event files follow pattern: `*_event.dart`

2. **Database**: Drift (formerly Moor) for local SQLite storage
   - Schema definitions in `lib/models/tables/*.drift`
   - Generated files have `.g.dart` extension
   - Database schema version in `lib/models/database/database.dart` (line 33)
   - Migrations must update schema version when tables change
   - Current schema version: 27

3. **Code Generation**: Uses build_runner for:
   - Drift database code
   - JSON serialization (json_serializable)
   - GraphQL operations via Artemis (`.graphql` files in `lib/services/arweave/graphql/`)
   - Route generation
   - Test mocks (using mocktail)

4. **Multi-platform Support**:
   - Shared codebase with platform-specific implementations
   - Web uses custom gateway URL support via localStorage
   - Mobile includes biometric authentication via local_auth
   - Platform checks via `kIsWeb` and `Platform` class

### Development Workflow
1. Always run `flutter pub run build_runner watch --delete-conflicting-outputs` during development
2. Install lefthook (`lefthook install`) for git hooks
3. Git hooks via lefthook (`lefthook.yml`):
   - Pre-commit: Enforces Flutter version 3.19.6 (`lefthook/version_checker.sh`)
   - Pre-push: Validates database schema version updates (`lefthook/database_checker.sh`)
4. Commit messages follow convention from `.cursorrules`:
   - `fix:` for bug fixes
   - `feat:` for new features
   - `perf:` for performance improvements
   - `docs:` for documentation changes
   - `style:` for formatting changes
   - `refactor:` for code refactoring
   - `test:` for adding tests
   - `chore:` for maintenance tasks
5. CI/CD:
   - `dev` branch automatically deploys to [staging.ardrive.io](https://staging.ardrive.io)
   - Production releases via GitHub UI with tags `v*` (e.g., `v1.0.1`) deploy to [app.ardrive.io](https://app.ardrive.io)

### Testing Strategy
- Unit tests for business logic in `test/`
- Integration tests in `integration_test/`
- Widget tests for UI components
- Test configuration in `dart_test.yaml` and `dart_test_base.yaml`:
  - 30-second default timeout
  - Test file pattern: `test_*.dart`
  - JSON test reporter outputs to `reports/web/tests.json`
- Mocks generated with mocktail package
- Run tests for all packages via `scr test` script (executes `scripts/run_tests.sh`)

### Important Notes
- **Flutter version must be exactly 3.19.6** (enforced by git hooks and `scr check-flutter`)
- The project uses script_runner (`scr`) instead of npm scripts
- Multiple app flavors: development, staging, production
- Firebase Crashlytics configured for error tracking
- Custom gateway URLs supported via `flutter.arweaveGatewayUrl` in localStorage:
  ```js
  localStorage.setItem('flutter.arweaveGatewayUrl', '"https://my.custom.url"');
  ```
- Artemis generates GraphQL code from `.graphql` files in `lib/services/arweave/graphql/`
- External dependencies:
  - arweave-dart from GitHub
  - ardrive_http from GitHub
  - flutter_dropzone from GitHub (custom fork)
- Default shells configured in `pubspec.yaml` for script_runner:
  - Unix-like systems: `/bin/sh`
  - Windows: `cmd.exe`