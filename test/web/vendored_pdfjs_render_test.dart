// ignore_for_file: avoid_web_libraries_in_flutter
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

/// Renders PDFs through the vendored pdf.js build exactly as `pdfx` 2.6.0 does
/// on the web: one page into an opaque 2D canvas, then the pixels.
///
/// Run with `tool/browser_tests.sh`, which CI runs too. It serves `web/` on
/// 127.0.0.1:8099, which the script URL below expects.
void main() {
  const pdfJsBase = 'http://127.0.0.1:8099/js/pdfjs/';
  const hotpink = [255, 105, 180];
  const white = [255, 255, 255];
  const black = [0, 0, 0];

  late Object pdfjsLib;

  setUpAll(() async {
    final script = html.ScriptElement()..src = '${pdfJsBase}pdf.min.js';
    html.document.head!.append(script);
    await script.onLoad.first;

    pdfjsLib = js_util.getProperty<Object>(html.window, 'pdfjsLib');
    js_util.setProperty(
      js_util.getProperty<Object>(pdfjsLib, 'GlobalWorkerOptions'),
      'workerSrc',
      '${pdfJsBase}pdf.worker.min.js',
    );
  });

  /// The RGB of the pixel at ([x], [y]) once page 1 is rendered at 1:1, with
  /// the canvas options pdfx uses (`alpha: false`).
  Future<List<int>> renderAndSample(Uint8List pdf, int x, int y) async {
    final task = js_util.callMethod<Object>(pdfjsLib, 'getDocument', [
      js_util.jsify({'data': pdf}),
    ]);
    final document = await js_util.promiseToFuture<Object>(
      js_util.getProperty<Object>(task, 'promise'),
    );
    final page = await js_util.promiseToFuture<Object>(
      js_util.callMethod<Object>(document, 'getPage', [1]),
    );
    final viewport = js_util.callMethod<Object>(page, 'getViewport', [
      js_util.jsify({'scale': 1}),
    ]);

    final canvas = html.CanvasElement(width: 100, height: 100);
    final context = canvas.getContext('2d', {'alpha': false})
        as html.CanvasRenderingContext2D;

    final renderContext = js_util.newObject<Object>();
    js_util.setProperty(renderContext, 'canvasContext', context);
    js_util.setProperty(renderContext, 'viewport', viewport);
    final renderTask =
        js_util.callMethod<Object>(page, 'render', [renderContext]);
    await js_util.promiseToFuture<void>(
      js_util.getProperty<Object>(renderTask, 'promise'),
    );

    final data = context.getImageData(x, y, 1, 1).data;
    return [data[0], data[1], data[2]];
  }

  group('the vendored PDF.js build', () {
    // Chrome prints a CSS `repeating-linear-gradient` (ruled paper, stripes)
    // as a function-based shading (ShadingType 1), which pdf.js 2.12.313 does
    // not implement. Upstream it paints such a shading hotpink, so a whole page
    // background came out solid pink (#2369). The vendored build is patched to
    // skip it instead.
    final pdf = _pdfWithFunctionBasedShading();

    test('still renders what it supports beside the shading', () async {
      // The left half is a plain black fill: proof the page rendered at all,
      // so the assertion below cannot pass on a blank canvas.
      expect(await renderAndSample(pdf, 25, 50), black);
    });

    test('skips a function-based shading instead of painting it hotpink',
        () async {
      final pixel = await renderAndSample(pdf, 75, 50);

      expect(
        pixel,
        isNot(hotpink),
        reason: 'pdf.js painted an unsupported shading hotpink: the patch to '
            'DummyShadingPattern in web/js/pdfjs/pdf.min.js is missing',
      );
      expect(pixel, white, reason: 'the page background shows through');
    });
  });
}

/// A 100x100 pt page: the left half filled black, the right half painted by
/// a function-based shading (ShadingType 1) that a complete renderer draws
/// blue.
Uint8List _pdfWithFunctionBasedShading() {
  const content = 'q 50 0 50 100 re W n /Sh0 sh Q\n0 0 0 rg 0 0 50 100 re f\n';
  const function = '{pop pop 0 0 1}\n';

  final objects = [
    '<</Type /Catalog /Pages 2 0 R>>',
    '<</Type /Pages /Kids [3 0 R] /Count 1>>',
    '<</Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] '
        '/Resources <</Shading <</Sh0 5 0 R>>>> /Contents 4 0 R>>',
    '<</Length ${content.length}>>\nstream\n${content}endstream',
    '<</ShadingType 1 /ColorSpace /DeviceRGB /Domain [0 1 0 1] '
        '/Matrix [100 0 0 100 0 0] /Function 6 0 R>>',
    '<</FunctionType 4 /Domain [0 1 0 1] /Range [0 1 0 1 0 1] '
        '/Length ${function.length}>>\nstream\n${function}endstream',
  ];

  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }

  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final offset in offsets) {
    out.write('${offset.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write('trailer\n<</Size ${objects.length + 1} /Root 1 0 R>>\n'
      'startxref\n$xref\n%%EOF\n');

  return Uint8List.fromList(ascii.encode(out.toString()));
}
