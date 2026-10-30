import 'package:ardrive/components/sandboxed_transaction_view/arweave_sandbox_url.dart';
import 'package:flutter_test/flutter_test.dart';

/// The origin an untrusted transaction is allowed to render itself on.
///
/// If this is wrong, "Open sandboxed" opens something on an origin nobody
/// intended - which is the one failure this whole feature is built to avoid -
/// so the expected subdomains here are independently computed (base32 of the
/// id's 32 bytes, RFC 4648, lower case, unpadded) rather than recorded from the
/// implementation.
void main() {
  const gateway = 'https://arweave.net';

  group('arweaveSandboxSubdomain', () {
    test('encodes a transaction id as its gateway subdomain', () {
      expect(
        arweaveSandboxSubdomain('j48SFG4GgnFej4tCqKU2iUgI4alFArg_8o8pVLiGujI'),
        'r6hrefdoa2bhcxuprnbkrjjwrfearynjiublqp7sr4uvjoegxiza',
      );

      expect(
        arweaveSandboxSubdomain('S1QzT9YbPo8iU7yT6rE5wQ4aS3dF2gH1jK0lZxCvBnM'),
        'jnkdgt6wdm7i6istxsj6vmjzyehbus3xixnad5mmvuswoefpazzq',
      );
    });

    test('covers both ends of the base64url alphabet', () {
      // The final character of a 43-character id carries only 4 significant
      // bits, so it must be one whose low 2 bits are zero - '8' (index 60).
      // '-' (62) and '_' (63) are not, and an id ending in either is not
      // canonical base64 and does not decode at all.
      expect(
        arweaveSandboxSubdomain('${'-' * 42}8'),
        '7px3567px3567px3567px3567px3567px3567px3567px3567pxq',
      );

      expect(
        arweaveSandboxSubdomain('${'_' * 42}8'),
        '${'7' * 51}q',
      );
    });

    test('produces a label that is legal in DNS', () {
      final subdomain =
          arweaveSandboxSubdomain('j48SFG4GgnFej4tCqKU2iUgI4alFArg_8o8pVLiGujI')!;

      expect(subdomain.length, 52);
      expect(RegExp(r'^[a-z2-7]+$').hasMatch(subdomain), isTrue);
    });
  });

  group('decodeTransactionId', () {
    test('accepts a 43 character base64url id and yields 32 bytes', () {
      expect(
        decodeTransactionId('j48SFG4GgnFej4tCqKU2iUgI4alFArg_8o8pVLiGujI')
            ?.length,
        32,
      );
    });

    test('rejects anything that is not one', () {
      for (final candidate in [
        '',
        'short',
        'a' * 42,
        'a' * 44,
        // A path traversal, a subdomain injection and a scheme, each of which
        // would be catastrophic if it reached a URL builder.
        '../../etc/passwd',
        'evil.example.com/${'a' * 25}',
        'javascript:alert(1)aaaaaaaaaaaaaaaaaaaaaaa',
        // Base64 rather than base64url: `+` and `/` are not id characters, and
        // `/` in particular would open a path.
        '${'+' * 21}${'/' * 22}',
      ]) {
        expect(
          decodeTransactionId(candidate),
          isNull,
          reason: 'accepted "$candidate"',
        );
      }
    });
  });

  group('arweaveSandboxUrl', () {
    test('points at the per-transaction subdomain of the given gateway', () {
      expect(
        arweaveSandboxUrl(
          txId: 'j48SFG4GgnFej4tCqKU2iUgI4alFArg_8o8pVLiGujI',
          gatewayUrl: Uri.parse(gateway),
        ),
        'https://r6hrefdoa2bhcxuprnbkrjjwrfearynjiublqp7sr4uvjoegxiza'
        '.arweave.net/j48SFG4GgnFej4tCqKU2iUgI4alFArg_8o8pVLiGujI',
      );
    });

    test('uses the gateway it was given, never a constant', () {
      final url = arweaveSandboxUrl(
        txId: 'j48SFG4GgnFej4tCqKU2iUgI4alFArg_8o8pVLiGujI',
        gatewayUrl: Uri.parse('https://turbo-gateway.com'),
      );

      expect(url, contains('.turbo-gateway.com/'));
      expect(url, isNot(contains('arweave.net')));
    });

    test('keeps an explicit port and does not invent one', () {
      expect(
        arweaveSandboxUrl(
          txId: 'j48SFG4GgnFej4tCqKU2iUgI4alFArg_8o8pVLiGujI',
          gatewayUrl: Uri.parse('http://localhost:1984'),
        ),
        startsWith('http://r6hrefdoa2bhcxuprnbkrjjwrfearynjiublqp7sr4uvjoegxiza'
            '.localhost:1984/'),
      );

      expect(
        arweaveSandboxUrl(
          txId: 'j48SFG4GgnFej4tCqKU2iUgI4alFArg_8o8pVLiGujI',
          gatewayUrl: Uri.parse(gateway),
        ),
        isNot(contains(':443')),
      );
    });

    test('refuses to build a URL from something that is not an id', () {
      expect(
        arweaveSandboxUrl(
          txId: 'evil.example.com',
          gatewayUrl: Uri.parse(gateway),
        ),
        isNull,
      );
    });
  });
}
