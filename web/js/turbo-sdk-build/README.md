# Turbo SDK Browser Bundle

This directory contains build scripts to bundle `@ardrive/turbo-sdk` for browser usage.

## Why is this needed?

The turbo-sdk npm package doesn't include a pre-built browser bundle (as of v1.39.0+).
The SDK's `/web` export has ES modules that need to be bundled together, and some
Node.js built-ins need to be shimmed for browser compatibility.

## How to rebuild

When upgrading the SDK version:

1. Update the version in `package.json`
2. Run:
   ```bash
   cd web/js/turbo-sdk-build
   npm install
   npm run build
   ```
3. The output `turbo-sdk.bundle.min.js` is created in the parent directory (`web/js/`)
4. Commit the updated bundle

## Current SDK Version

See `package.json` for the current version (1.39.2 as of this writing).
