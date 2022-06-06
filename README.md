# ArDrive Web

![deploy](https://github.com/ardriveapp/ardrive-web/workflows/deploy/badge.svg)
[![contributions welcome](https://img.shields.io/badge/contributions-welcome-brightgreen.svg?style=flat)](https://github.com/ardriveapp/ardrive-web/issues)

The ArDrive Web App allows a user to log in to securely view, upload and manage their ArDrive files.

Have any questions? Join the ArDrive Discord channel for support, news and updates. https://discord.gg/ya4hf2H

## Setting up the Development Environment

Install lefthook for your platform from the intructions [here](https://github.com/evilmartians/lefthook/blob/master/docs/other.md).
This will enable the use of git hooks.
After installing lefthook you need to enable it by running:

```shell
lefthook install
```

If your environment is using homebrew, install the Flutter SDK with its cask as shown below. Alternatively, visit the [Flutter Installation Instructions][https://flutter.dev/docs/get-started/install] to get the Flutter SDK up and running for your OS / local setup.

```shell
# with homebrew

brew install --cask flutter
```

Then, generate the package imports with:

```shell
flutter pub get
```

Whenever changing branches or initially setting up, compile the codebase to resolve errors:

```shell
flutter pub run build_runner build --delete-conflicting-outputs
```

Then, to begin code generation and watch for changes, run:

```shell
flutter packages pub run build_runner watch
```

Finally, to start a development instance for web, run:

```shell
flutter run -d Chrome
```

All changes made to `dev` will be continuously deployed to [staging.ardrive.io](https://staging.ardrive.io). All PRs from this repo merging into `dev` will trigger a preview build that can be shared freely.

## Release

To create a release to [app.ardrive.io](https://app.ardrive.io), first merge any changes from `dev` into `master` that are required, and publish a new release through the GitHub UI with the tag name matching the pattern `v*` eg. `v1.0.1`.

This will trigger a GitHub Action that will deploy `master` to production.
