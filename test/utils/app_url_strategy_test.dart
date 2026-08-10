import 'dart:io';

import 'package:ardrive/utils/app_url_strategy.dart';
import 'package:ardrive/utils/legacy_share_link.dart';
import 'package:ardrive/utils/shared_file_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the URL strategy flag', () {
    test('defaults to hash routing', () {
      // Path routing asks the host for `/share/{fileId}` and `/view/{txId}` as
      // real paths. Until SPA rewrites exist on the app host and on
      // gateway-served deployments, every direct visit and every refresh of
      // one of those URLs is a 404 - so the default is not a preference, it is
      // the only value that works. See lib/utils/app_url_strategy.dart.
      expect(kAppUrlStrategy, AppUrlStrategy.hash);
    });

    test('hash routing writes links on the route it has always used', () {
      expect(
        AppUrlStrategy.hash.sharedFileRoute,
        SharedFileLinkRoute.legacy,
      );
      expect(
        AppUrlStrategy.hash.fileKeyPlacement,
        SharedFileLinkKeyPlacement.hashQuery,
      );
      expect(AppUrlStrategy.hash.linkPrefix, '/#');
    });

    test('path routing writes links on /share, with the key in a fragment',
        () {
      expect(AppUrlStrategy.path.sharedFileRoute, SharedFileLinkRoute.share);
      expect(
        AppUrlStrategy.path.fileKeyPlacement,
        SharedFileLinkKeyPlacement.fragment,
      );
      expect(AppUrlStrategy.path.linkPrefix, isEmpty);
    });

    test('configuring the default strategy changes nothing', () {
      // Hash routing is the engine's own default; installing it explicitly
      // could only introduce a difference where there is none today. (Off the
      // web `setUrlStrategy` is a no-op, so this asserts it does not throw.)
      expect(configureAppUrlStrategy, returnsNormally);
    });
  });

  group('the boot shim in web/index.html', () {
    // The shim runs before Flutter loads, so it cannot import any of this. It
    // is a transliteration of `rewriteLegacyShareLink`, and these are what
    // hold the two together: the flag, the pattern, and the shape of what the
    // rewrite produces.
    final indexHtml = File('web/index.html').readAsStringSync();

    test('is armed by the same flag the app is', () {
      const enabled = kAppUrlStrategy == AppUrlStrategy.path;

      expect(
        indexHtml,
        contains('window.ardriveUsePathUrlStrategy = $enabled;'),
        reason: 'web/index.html and kAppUrlStrategy have to be flipped '
            'together: the shim must not rewrite legacy links onto a path '
            'that the app is not being served on.',
      );
    });

    test('matches legacy links with the pattern this package specifies', () {
      // The Dart pattern, escaped for a JavaScript string literal.
      final jsPattern = legacyShareLinkPattern.replaceAll(r'\', r'\\');

      expect(indexHtml, contains(jsPattern));
    });

    test('rewrites onto the canonical route, with the key in the fragment',
        () {
      expect(indexHtml, contains("'/share/'"));
      expect(indexHtml, contains("'#k='"));
      expect(indexHtml, contains('history.replaceState'));
    });

    test('never puts a caught error into the console', () {
      // The URL the shim builds ends in `#k=<key>`, and a browser that refuses
      // a `replaceState` quotes the URL it refused in the message it throws.
      // Passing that error to `console.warn` would print the recipient's file
      // key into a place an extension can read and a screenshot can carry
      // away. `lib/utils/shared_file_link.dart` applies the same rule to the
      // same value: the reason travels, the value never does.
      expect(
        indexHtml,
        contains("console.warn('Legacy share link shim failed');"),
      );
      expect(
        RegExp(r'console\.(warn|error|log)\([^)]*,\s*e\s*\)')
            .hasMatch(indexHtml),
        isFalse,
        reason: 'the caught error is the one thing in this shim that can be '
            'holding the key',
      );
    });

    test('runs before Flutter is loaded', () {
      // `replaceState` after the router has read the location would leave the
      // app on one route and the address bar on another.
      expect(
        indexHtml.indexOf('ardriveUsePathUrlStrategy'),
        lessThan(indexHtml.indexOf('flutter.js')),
      );
    });
  });

  group('what web/index.html is served with', () {
    final indexHtml = File('web/index.html').readAsStringSync();

    test('never sends the app\'s own route in a Referer header', () {
      // Harmless under hash routing, where the browser strips the fragment
      // anyway - and a prerequisite for flipping to path routing, where the
      // route *is* the link: `/share/{fileId}?v=2&n=...&ct=...` would ride
      // along on every subresource request the page makes, gateways included,
      // and `n` and `ct` are private-file secrets. See the prerequisite list in
      // lib/utils/app_url_strategy.dart.
      expect(
        indexHtml,
        contains('<meta name="referrer" content="strict-origin" />'),
      );
    });
  });
}
