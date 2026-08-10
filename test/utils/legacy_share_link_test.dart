import 'package:ardrive/utils/legacy_share_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fileId = '8f3c2a10-6f4e-4c7a-9b2e-1d2f3a4b5c6d';
  const driveId = '00000000-0000-0000-0000-000000000002';

  // 43 base64url characters whose last character carries only 4 significant
  // bits - the shape of a file key.
  const fileKey = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopQ';
  const otherKey = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';

  const dataTxId = 'nS7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWeR';

  /// The part of [location] a server would be sent - everything before the
  /// fragment.
  String serverVisiblePartOf(String location) =>
      location.split('#').first;

  group('rewriteLegacyShareLink', () {
    test('moves a legacy key out of the query and into the fragment', () {
      final rewritten =
          rewriteLegacyShareLink('/file/$fileId/view?fileKey=$fileKey');

      expect(rewritten, '/share/$fileId#k=$fileKey');

      // The property the whole shim exists for: nothing a server is sent
      // carries the key.
      expect(serverVisiblePartOf(rewritten!), isNot(contains(fileKey)));
      expect(serverVisiblePartOf(rewritten), isNot(contains('fileKey')));
    });

    test('rewrites a keyless legacy link', () {
      expect(
        rewriteLegacyShareLink('/file/$fileId/view'),
        '/share/$fileId',
      );
    });

    test('an empty key parameter leaves no fragment behind', () {
      // An empty parameter is an absent key, not a mangled one - and it must
      // not travel on into the query either way.
      expect(
        rewriteLegacyShareLink('/file/$fileId/view?fileKey='),
        '/share/$fileId',
      );
    });

    test('carries a v2 hash link across with its encoding intact', () {
      // Phase 1 shipped v2 links on the hash route; they match the same
      // pattern and must survive the move with every parameter in place.
      final rewritten = rewriteLegacyShareLink(
        '/file/$fileId/view?v=2&dtx=$dataTxId&n=Q3%20Report.pdf'
        '&ct=application%2Fpdf&k=$fileKey',
      );

      expect(
        rewritten,
        '/share/$fileId?v=2&dtx=$dataTxId&n=Q3%20Report.pdf'
        '&ct=application%2Fpdf#k=$fileKey',
      );
      expect(serverVisiblePartOf(rewritten!), isNot(contains(fileKey)));
    });

    test('the v2 key parameter wins over the legacy one', () {
      // §4.2 precedence, applied before either name can reach a query.
      final rewritten = rewriteLegacyShareLink(
        '/file/$fileId/view?fileKey=$otherKey&k=$fileKey',
      );

      expect(rewritten, '/share/$fileId#k=$fileKey');
      expect(rewritten, isNot(contains(otherKey)));
    });

    test('a damaged key is moved, not dropped', () {
      // The page has to be able to say the link arrived damaged rather than
      // silently asking for a key, which it can only do if the key gets there.
      final damaged = fileKey.substring(0, 41);

      expect(
        rewriteLegacyShareLink('/file/$fileId/view?fileKey=$damaged'),
        '/share/$fileId#k=$damaged',
      );
    });

    test('leaves drive links alone', () {
      // Drive hashes are untouched this cycle - and a rewrite of one would be
      // a rewrite to a route that does not exist.
      expect(
        rewriteLegacyShareLink('/drives/$driveId?name=My%20Drive&driveKey=x'),
        isNull,
      );
    });

    test('matches nothing but the legacy shared file route', () {
      expect(rewriteLegacyShareLink('/file/$fileId'), isNull);
      expect(rewriteLegacyShareLink('/file/$fileId/viewer'), isNull);
      expect(rewriteLegacyShareLink('/file/$fileId/view/extra'), isNull);
      expect(rewriteLegacyShareLink('/share/$fileId'), isNull);
      expect(rewriteLegacyShareLink('/sign-in'), isNull);
      expect(rewriteLegacyShareLink(''), isNull);
    });
  });

  group('normalizeHashRouteLocation', () {
    test('is a no-op for every location the hash strategy produces', () {
      // There the router's location is already everything after the first `#`,
      // so anything left in the fragment is a real fragment.
      for (final location in [
        '/',
        '/sign-in',
        '/drives/$driveId?name=My%20Drive&driveKey=$otherKey',
        '/file/$fileId/view?fileKey=$fileKey',
        '/file/$fileId/view?v=2&k=$fileKey',
        '/file/$fileId/view?v=2#k=$fileKey',
      ]) {
        expect(normalizeHashRouteLocation(location), location);
      }
    });

    test('is a no-op for a path route with a real fragment', () {
      const location = '/share/$fileId?v=2&dtx=$dataTxId#k=$fileKey';

      expect(normalizeHashRouteLocation(location), location);
    });

    test('resolves a legacy link that arrived on the path strategy', () {
      // The host only ever saw `/`; `PathUrlStrategy` hands the fragment over
      // verbatim, and this is the only thing that keeps permanent links alive
      // when the shim did not run.
      expect(
        normalizeHashRouteLocation('/#/file/$fileId/view?fileKey=$fileKey'),
        '/share/$fileId#k=$fileKey',
      );
    });

    test('resolves a drive link that arrived on the path strategy', () {
      // Not a shared file route, so it is handed back as the route it names
      // rather than rewritten - drive links are untouched this cycle, and
      // "untouched" has to include "still works".
      expect(
        normalizeHashRouteLocation(
          '/#/drives/$driveId?name=My%20Drive&driveKey=$otherKey',
        ),
        '/drives/$driveId?name=My%20Drive&driveKey=$otherKey',
      );
    });

    test('leaves a fragment that is not a route alone', () {
      expect(normalizeHashRouteLocation('/#k=$fileKey'), '/#k=$fileKey');
      expect(normalizeHashRouteLocation('/#'), '/#');
    });
  });
}
