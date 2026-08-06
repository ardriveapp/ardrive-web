import 'package:ardrive/utils/open_url.dart';
import 'package:flutter_test/flutter_test.dart';

/// The outbound-navigation filter (`docs/FILE_SHARING_REDESIGN_PLAN.md` §4.3,
/// hardening item 1).
///
/// A transaction can claim to be anything and a link inside it can carry any
/// scheme, so `openUrl` - which every "open this elsewhere" affordance in the
/// app funnels through - hands the platform launcher `https:` and `http:` and
/// nothing else. `javascript:` runs script wherever it is opened, `data:` and
/// `blob:` open an attacker-authored document, and `file:` reads the machine.
void main() {
  group('parseLaunchableUrl accepts', () {
    test('https and http', () {
      expect(parseLaunchableUrl('https://ardrive.io/')?.scheme, 'https');
      expect(parseLaunchableUrl('http://localhost:1984/tx')?.scheme, 'http');
    });

    test('a gateway sandbox URL', () {
      expect(
        parseLaunchableUrl(
          'https://r6hrefdoa2bhcxuprnbkrjjwrfearynjiublqp7sr4uvjoegxiza'
          '.arweave.net/j48SFG4GgnFej4tCqKU2iUgI4alFArg_8o8pVLiGujI',
        ),
        isNotNull,
      );
    });
  });

  group('parseLaunchableUrl rejects', () {
    const rejected = [
      'javascript:alert(document.domain)',
      // Case is not a defence: browsers normalise it and so does this.
      'JaVaScRiPt:alert(1)',
      'data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==',
      'file:///etc/passwd',
      'blob:https://app.ardrive.io/1c5e0d2a-0000-4000-8000-000000000000',
      'vbscript:msgbox(1)',
      'mailto:someone@example.com',
      'ar://arns-name',
      // Leading whitespace and control characters, the classic way to smuggle
      // a scheme past a check that a browser then normalises away.
      '  javascript:alert(1)',
      'java\nscript:alert(1)',
      // Relative references have no destination of their own: a browser would
      // resolve them against whatever page opened them.
      '//evil.example.com/',
      '/share/some-file-id',
      'https://',
      '',
    ];

    for (final url in rejected) {
      test('"${url.replaceAll('\n', r'\n')}"', () {
        expect(parseLaunchableUrl(url), isNull);
      });
    }
  });

  group('openUrl', () {
    test('throws instead of launching a scheme it will not open', () async {
      // The refusal happens before the launcher is reached, which is what makes
      // this assertable at all in a VM test: `canLaunchUrl` would need a
      // platform behind it.
      await expectLater(
        openUrl(url: 'javascript:alert(1)'),
        throwsA(isA<UnsupportedUrlSchemeException>()),
      );

      await expectLater(
        openUrl(url: 'data:text/html,<script>alert(1)</script>'),
        throwsA(isA<UnsupportedUrlSchemeException>()),
      );

      await expectLater(
        openUrl(url: 'file:///etc/passwd'),
        throwsA(isA<UnsupportedUrlSchemeException>()),
      );
    });

    test('allows exactly two schemes', () {
      expect(allowedUrlSchemes, {'https', 'http'});
    });
  });
}
