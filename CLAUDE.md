# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Setup and Build
```bash
# Initial setup - install dependencies and generate code
scr setup

# Generate code (run after changing .drift files or GraphQL schemas)
flutter pub run build_runner build --delete-conflicting-outputs

# Watch for changes during development
flutter packages pub run build_runner watch

# Check Flutter version compliance
scr check-flutter

# Database schema validation
scr check-db
```

### Testing
```bash
# Run all tests (main app + all packages)
scr test

# Run main app tests only
flutter test

# Run tests for specific package
cd packages/ardrive_ui && flutter test

# Run specific test file
flutter test test/blocs/upload_cubit_test.dart
```

### Running the App
```bash
# Development environment (web)
flutter run -d chrome --dart-define=environment=development

# Production environment (web)
flutter run -d chrome --dart-define=environment=production

# Mobile development
flutter run --flavor=development

# Mobile production
flutter run --flavor=production
```

### Code Quality
```bash
# Analyze code
flutter analyze

# Format code
dart format .

# Lint check (via lefthook pre-commit)
lefthook run pre-commit
```

## Architecture Overview

ArDrive is a Flutter web/mobile application for decentralized file storage on Arweave blockchain.

### Core Architecture Patterns

**State Management**: BLoC pattern with Cubits
- Complex features (uploads, sync, file operations) use event-driven BLoCs
- Simple UI state uses Cubits
- Dependency injection via Provider

**Database**: Drift ORM with SQL generation
- Schema versioning with migrations in `drift_schemas/` (current: version 27)
- Core entities: drives, files, folders, licenses, ARNS records, ANT records, network transactions
- DAOs provide repository pattern for data access
- Database resets for schema versions < 24

**Upload System**: Multi-strategy architecture
- Direct Arweave uploads vs Turbo bundled uploads
- Payment methods: AR tokens or Turbo credits
- Upload handles abstract different upload patterns
- Real-time progress tracking with cancellation

### Key Components

**Authentication**: Multi-wallet support (ArConnect, keyfile, Ethereum)
**Encryption**: End-to-end encryption for private drives
**ARNS Integration**: Decentralized naming system via `ario_sdk`
**GraphQL**: Artemis-generated clients for Arweave gateway queries
**Packages**: Modular local packages in `/packages/` directory:
- `ardrive_ui` - UI Design Library with Storybook
- `ardrive_crypto` - Cryptography utilities
- `ardrive_uploader` - Upload functionality
- `ardrive_utils` - Shared utilities
- `ario_sdk` - ARNS integration
- `arconnect` - Wallet connection
- `pst` - Profit Sharing Token functionality
- `ardrive_logger` - Logging utilities

### File Structure

- `lib/blocs/` - State management (BLoCs/Cubits)
- `lib/models/` - Database models and DAOs
- `lib/services/` - External integrations (Arweave, payments, auth)
- `lib/pages/` - UI screens and routing
- `lib/components/` - Reusable UI components
- `packages/` - Local modular packages
- `test/` - Unit and integration tests

### Database Schema

When modifying database schema:
1. Update `.drift` files in `lib/models/tables/` or `lib/models/queries/`
2. Run `flutter pub run build_runner build --delete-conflicting-outputs`
3. Update migration logic in `lib/models/database/database.dart` if needed
4. Run `scr check-db` to validate schema changes

### Adding New Features

1. Create BLoC/Cubit in `lib/blocs/`
2. Add models/DAOs if database changes needed
3. Create UI components in `lib/components/` or pages in `lib/pages/`
4. Add tests in corresponding `test/` directories
5. Update routing in `lib/pages/app_router_delegate.dart` if needed

### Commit Message Format

Use conventional commit prefixes (lowercase):
- `fix:` - Bug fixes
- `feat:` - New features  
- `perf:` - Performance improvements
- `docs:` - Documentation changes
- `style:` - Formatting changes
- `refactor:` - Code refactoring
- `test:` - Adding missing tests
- `chore:` - Chore tasks

Include detailed changes list after summary line if not self-explanatory.

### Environment Configuration

The app uses three environments (development, staging, production) with config files in `assets/config/`. Use `--dart-define=environment=<env>` to specify environment when running.

### Code Generation

The codebase uses several code generation tools:
- **Artemis**: GraphQL client generation from schema in `lib/services/arweave/graphql/`
- **Drift**: Database schema and DAO generation from `.drift` files
- **JSON Serialization**: Model serialization via `json_annotation`

Build configuration in `build.yaml` specifies output paths and options.

### Key Dependencies

- **Flutter SDK**: 3.19.6 (exact version required)
- **Dart SDK**: >=3.2.0 <4.0.0
- **State Management**: flutter_bloc ^8.1.1
- **Database**: drift ^2.12.1
- **GraphQL**: artemis ^7.0.0-beta.13
- **Testing**: mocktail, bloc_test, golden tests
- **Mobile**: Firebase integration (Crashlytics, Core)

### Development Tools

- **Lefthook**: Git hooks for pre-commit/pre-push validation
- **Script Runner**: Access to custom scripts via `scr` command
- **Flutter Lints**: Code quality enforcement
- **Golden Tests**: UI regression testing support

### Custom Gateway

For testing with custom Arweave gateways, set `flutter.arweaveGatewayUrl` in browser localStorage:
```js
localStorage.setItem('flutter.arweaveGatewayUrl', '"https://my.custom.url"');
```

### Release Process

- **Staging**: All changes to `dev` branch auto-deploy to staging.ardrive.io
- **Production**: Merge `dev` to `master`, create GitHub release with `v*` tag pattern
- **Preview Builds**: PRs to `dev` trigger shareable preview builds