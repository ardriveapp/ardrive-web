import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The vendored PDF.js build carries a patch, and a patch on a minified
/// third-party file is exactly the kind of thing a future re-vendor drops
/// silently. This is the executable half of the note in `pdfjs_config.js`.
void main() {
  group('the vendored PDF.js build', () {
    final pdfJs = File('web/js/pdfjs/pdf.min.js');

    test('is present where index.html expects it', () {
      // A missing file would make every assertion below vacuous.
      expect(pdfJs.existsSync(), isTrue,
          reason: 'web/js/pdfjs/pdf.min.js is missing');
    });

    test('does not default isEvalSupported to true (CVE-2024-4367)', () {
      final source = pdfJs.readAsStringSync();

      // 2.12.313 compiles Type1 glyph paths with `new Function(...)` built from
      // a FontMatrix it never type-checks. The PDFs reaching it are chosen by
      // whoever made the link, and this origin holds a recipient's access key
      // in sessionStorage, so eval has to stay off.
      //
      // It is patched in the bundle rather than passed as an option because
      // pdfx merges its option map with `Map.addAll` over a raw JS object,
      // which throws under dart2js.
      expect(
        source,
        isNot(contains('isEvalSupported=!0')),
        reason: 'the CVE-2024-4367 patch is missing from the vendored build. '
            'Re-apply it (isEvalSupported must default to !1), or move to '
            'pdf.js >= 4.2.67, which fixes this upstream.',
      );

      expect(
        source,
        contains('isEvalSupported=!1'),
        reason: 'the vendored build no longer defaults isEvalSupported to '
            'false. If this is a new pdf.js version, confirm it is >= 4.2.67 '
            'and update this test rather than deleting it.',
      );
    });

    test('is not fetched from a CDN', () {
      // The whole reason this file is in the repository: the build is
      // permanent on Arweave and could never be patched, and a CDN script also
      // breaks under the strict CSP an AR.IO gateway serves.
      final indexHtml = File('web/index.html').readAsStringSync();

      expect(indexHtml, isNot(contains('cdn.jsdelivr.net/npm/pdfjs')));
      expect(indexHtml, isNot(contains('unpkg.com/pdfjs')));
    });
  });
}
