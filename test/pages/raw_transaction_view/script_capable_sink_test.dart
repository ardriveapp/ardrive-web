import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// A source-level guard on the invariant of
/// `docs/FILE_SHARING_REDESIGN_PLAN.md` §4.3:
///
/// > bytes fetched from any transaction id must never become script-capable
/// > content on the `app.ardrive.io` origin.
///
/// The behavioural tests next door prove that today's code renders HTML as
/// source and sends it to the gateway's own origin. This one proves something
/// weaker but longer-lived: that the *sinks* which would break the invariant do
/// not appear in this feature's code at all. A future edit that reaches for
/// `srcdoc` or a blob URL fails here, in a file that says why, rather than
/// silently handing a recipient's `sessionStorage` to a stranger's transaction.
void main() {
  /// Every sink that turns bytes into something a browser will parse or execute
  /// on whatever origin the document is already on.
  const forbiddenSinks = <String, String>{
    'srcdoc': 'parses attacker markup on the embedding origin',
    'innerHtml': 'parses attacker markup into this origin\'s DOM',
    'innerHTML': 'parses attacker markup into this origin\'s DOM',
    'setInnerHtml': 'parses attacker markup into this origin\'s DOM',
    'createObjectUrl': 'a blob URL inherits this origin',
    'createObjectURL': 'a blob URL inherits this origin',
    'EmbedElement': '<embed> executes what it is given',
    'ObjectElement': '<object> executes what it is given',
    'ScriptElement': 'a script element is the sink, by definition',
    'document.write': 'parses attacker markup into this origin\'s DOM',
    'allow-same-origin':
        'hands a sandboxed frame the origin the sandbox exists to withhold',
  };

  /// The code this feature owns.
  final ownedPaths = [
    'lib/pages/raw_transaction_view',
    'lib/components/sandboxed_transaction_view',
    'lib/utils/open_url.dart',
  ];

  /// Full-line comments only, so a `https://` inside a string cannot swallow
  /// the rest of its line and hide something after it.
  String stripComments(String source) {
    final withoutBlocks = source.replaceAll(
      RegExp(r'/\*.*?\*/', dotAll: true),
      '',
    );

    return withoutBlocks
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('//'))
        .join('\n');
  }

  List<File> dartFilesUnder(String path) {
    final entity = FileSystemEntity.typeSync(path);

    if (entity == FileSystemEntityType.file) {
      return [File(path)];
    }

    return Directory(path)
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
  }

  test('the viewer has no code that owns the paths it must not own', () {
    final files = ownedPaths.expand(dartFilesUnder).toList();

    // A guard that guards nothing is worse than no guard: if the feature moves,
    // this fails rather than passing quietly.
    expect(files, isNotEmpty);

    for (final file in files) {
      final source = stripComments(file.readAsStringSync());

      forbiddenSinks.forEach((sink, why) {
        expect(
          source.contains(sink),
          isFalse,
          reason: '${file.path} contains "$sink", which $why '
              '(docs/FILE_SHARING_REDESIGN_PLAN.md §4.3)',
        );
      });
    }
  });

  test('the only frame in the feature navigates, and is sandboxed', () {
    final source = File(
      'lib/components/sandboxed_transaction_view/sandboxed_iframe_web.dart',
    ).readAsStringSync();

    final code = stripComments(source);

    // It points at a URL...
    expect(code, contains('..src = url'));

    // ...and that URL is somebody else's origin, with the frame given none of
    // its own.
    expect(code, contains("setAttribute('sandbox'"));
    expect(code, contains('allow-scripts'));
    expect(code, isNot(contains('allow-same-origin')));
    expect(code, isNot(contains('allow-top-navigation')));
    expect(code, isNot(contains('allow-popups')));
  });

  test('the sandbox URL is built from a gateway, never from this origin', () {
    final source = File(
      'lib/components/sandboxed_transaction_view/arweave_sandbox_url.dart',
    ).readAsStringSync();

    final code = stripComments(source);

    expect(code, contains('gatewayUrl.host'));
    // No gateway hostname is hardcoded here: a deployment behind a private
    // gateway must not quietly reach out to arweave.net.
    expect(code, isNot(contains('arweave.net')));
  });
}
