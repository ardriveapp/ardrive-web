import 'package:ardrive/utils/open_url.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
// Faking the launcher is the only way to assert that a refused URL is never
// handed to the platform, rather than inferring it from a thrown exception.
// The interface arrives transitively through `url_launcher`, as
// `device_info_plus` does in lib/download/limits.dart.
//
// `LinkDelegate` is declared in `link.dart`, which the package's main library
// does not re-export, so overriding `linkDelegate` needs both imports.
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/link.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

/// Stands in for the platform launcher, so that "did not launch" is something
/// a test can assert rather than infer.
class RecordingUrlLauncher extends UrlLauncherPlatform {
  final List<String> launched = [];

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> launch(
    String url, {
    required bool useSafariVC,
    required bool useWebView,
    required bool enableJavaScript,
    required bool enableDomStorage,
    required bool universalLinksOnly,
    required Map<String, String> headers,
    String? webOnlyWindowName,
  }) async {
    launched.add(url);

    return true;
  }
}

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
    late RecordingUrlLauncher launcher;

    setUp(() {
      TestWidgetsFlutterBinding.ensureInitialized();

      launcher = RecordingUrlLauncher();
      UrlLauncherPlatform.instance = launcher;
    });

    test('does not launch a scheme it will not open, and does not throw '
        'either', () async {
      // Nearly every call site fires this and forgets it - `onTap: () =>
      // openUrl(...)` - so a throw from here is an unhandled asynchronous
      // error in whatever zone happened to be running, not something a user or
      // a caller ever sees handled. The refusal is reported by the return
      // value and by the log, and the launcher is never reached.
      for (final url in const [
        'javascript:alert(1)',
        'data:text/html,<script>alert(1)</script>',
        'file:///etc/passwd',
        'blob:https://app.ardrive.io/1c5e0d2a-0000-4000-8000-000000000000',
      ]) {
        expect(await openUrl(url: url), isFalse, reason: url);
      }

      expect(launcher.launched, isEmpty);
    });

    test('launches the schemes it does open', () async {
      expect(await openUrl(url: 'https://ardrive.io/'), isTrue);

      expect(launcher.launched, ['https://ardrive.io/']);
    });

    test('a launcher that fails is logged, never thrown', () async {
      UrlLauncherPlatform.instance = _FailingUrlLauncher();

      // `canLaunchUrl` reaching a platform that is not there used to become an
      // unhandled error at every fire-and-forget call site.
      expect(await openUrl(url: 'https://ardrive.io/'), isFalse);
    });

    test('allows exactly two schemes', () {
      expect(allowedUrlSchemes, {'https', 'http'});
    });
  });
}

/// A platform that cannot answer at all - a missing plugin, a headless test
/// host, a browser that refuses the popup.
class _FailingUrlLauncher extends UrlLauncherPlatform {
  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> canLaunch(String url) async =>
      throw Exception('no launcher on this platform');
}
