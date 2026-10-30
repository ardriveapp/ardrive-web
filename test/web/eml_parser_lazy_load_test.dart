// ignore_for_file: avoid_web_libraries_in_flutter
@TestOn('browser')
library;

import 'dart:html' as html;

import 'package:ardrive/services/eml_parser/eml_parser_web.dart';
import 'package:flutter_test/flutter_test.dart';

/// An .eml preview parses with nothing loaded but web/js/lazy_loader.js, as
/// in the app since 2.82.0 took the parser's script tags out of index.html.
///
/// Nothing called `LazyLoader.loadEmlParser()` after that, so
/// `window.ArDriveEmlParser` was never defined and every preview failed.
///
/// Run with `tool/browser_tests.sh`, which CI runs too. It serves `web/` on
/// 127.0.0.1:8099. The loader asks for `./js/...`, so the page's base is
/// pointed there for this file.
void main() {
  const webRoot = 'http://127.0.0.1:8099/';

  late html.BaseElement base;

  setUpAll(() async {
    base = html.BaseElement()..href = webRoot;
    html.document.head!.append(base);

    final loader = html.ScriptElement()..src = '${webRoot}js/lazy_loader.js';
    html.document.head!.append(loader);
    await loader.onLoad.first;
  });

  tearDownAll(() => base.remove());

  test('parses an .eml file, loading the parser on first use', () async {
    const eml = 'From: Alice Example <alice@example.com>\r\n'
        'To: Bob Example <bob@example.com>\r\n'
        'Subject: Lazy loaded\r\n'
        'Date: Thu, 29 Oct 2026 10:00:00 +0000\r\n'
        'MIME-Version: 1.0\r\n'
        'Content-Type: text/plain; charset=utf-8\r\n'
        '\r\n'
        'The body of the message.\r\n';

    final email = await EmlParserWeb.parse(eml);

    expect(email.subject, 'Lazy loaded');
    expect(email.from, contains('alice@example.com'));
    expect(email.to, contains('bob@example.com'));
    expect(email.textBody, contains('The body of the message.'));
  });
}
