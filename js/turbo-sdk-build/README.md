# Turbo SDK Browser Bundle

This directory contains build configuration to bundle `@ardrive/turbo-sdk` and `@ar.io/sdk` together for browser usage.

## Why is this needed?

Both SDKs must share the same Buffer polyfill to avoid type mismatches when passing signer objects (like ArconnectSigner) to TurboFactory. This build uses Vite to create a unified bundle with shared polyfills - the same approach used by turbo-app.

## When to rebuild

Rebuild the bundle when:
- Upgrading `@ardrive/turbo-sdk` version
- Upgrading `@ar.io/sdk` version
- Adding new exports from either SDK

## How to rebuild

```bash
cd web/js/turbo-sdk-build
npm install
npm run build
```

The output `turbo-sdk.bundle.min.js` is created in the parent directory (`web/js/`).

## Committing

The built bundle is committed to the repo. This ensures:
- Consistent builds across all environments
- No Node.js dependency in Flutter CI pipeline
- Faster CI builds

## Current SDK Versions

See `package.json` for current versions:
- `@ardrive/turbo-sdk`: 1.39.2 (adds base-ario support)
- `@ar.io/sdk`: 3.14.0
