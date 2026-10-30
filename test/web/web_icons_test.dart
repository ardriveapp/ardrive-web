import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every icon web/index.html and web/manifest.json name is a file in web/.
///
/// The apple-touch-icon pointed at `icons/Icon-192.png` while the file is
/// `icons/icon-192x192.png`, so an iPhone's home-screen shortcut fell back to
/// a screenshot of the page. Paths are case-sensitive on the gateways.
void main() {
  test('index.html links only icons that exist', () {
    final html = File('web/index.html').readAsStringSync();
    final links = RegExp(r'<link\s[^>]*rel="([^"]*icon[^"]*)"[^>]*>')
        .allMatches(html)
        .map(
            (m) => RegExp(r'href="([^"]+)"').firstMatch(m.group(0)!)!.group(1)!)
        .toList();

    expect(links, contains('icons/icon-192x192.png'));
    for (final href in links) {
      expect(File('web/$href').existsSync(), isTrue, reason: href);
    }
  });

  test('manifest.json lists only icons that exist', () {
    final manifest = jsonDecode(File('web/manifest.json').readAsStringSync())
        as Map<String, dynamic>;
    final icons = (manifest['icons'] as List).cast<Map<String, dynamic>>();

    expect(icons, isNotEmpty);
    for (final icon in icons) {
      expect(File('web/${icon['src']}').existsSync(), isTrue,
          reason: '${icon['src']}');
    }
  });
}
