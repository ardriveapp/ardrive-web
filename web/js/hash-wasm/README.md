# hash-wasm, Argon2id only

`argon2.umd.min.js` is `dist/argon2.umd.min.js` from the npm package
[hash-wasm](https://www.npmjs.com/package/hash-wasm) 4.12.0 (MIT, see
`LICENSE`), unchanged. The WebAssembly is inside the file.

Tarball integrity, as the npm registry lists it:
`sha512-+/2B2rYLb48I/evdOIhP+K/DD2ca2fgBjp6O+GBEnCDk2e4rpeXIK8GvIyRPjTezgmWn9gmKwkQjjx6BtqDHVQ==`

It is loaded on first use by `LazyLoader.loadArgon2` (`web/js/lazy_loader.js`)
to open or publish a private page with a password, and nowhere else. The Dart
side is `lib/publication/domain/sealed/sealing_platform_web.dart`; the browser
test `test/publication/sealed/sealing_browser_test.dart` runs it against the
reference vectors.

To update: download the new tarball, check its integrity against the
registry, copy the same file, and run the browser tests.
