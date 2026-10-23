import 'dart:convert';

import 'package:ardrive/library/data/library_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final page = Uri.parse('https://turbo-gateway.com/PageManifest/');

  LibrarySource serving(List<int> body) => LibrarySource(
        pageUri: page,
        // As gateways send it: no charset, which `http` reads as Latin-1.
        client: MockClient((_) async => http.Response.bytes(
              body,
              200,
              headers: {'content-type': 'application/json'},
            )),
      );

  test('reads library.json as UTF-8, whatever charset it is served with',
      () async {
    const title = 'Phil’s Archive · café 日本語 🎉';

    final text = await serving(utf8.encode('{"title": "$title"}'))
        .readSettings('library.json');

    expect(jsonDecode(text)['title'], title);
  });

  test('refuses a library.json that is not UTF-8', () {
    expect(
      serving([0x7b, 0xff, 0x7d]).readSettings('library.json'),
      throwsA(isA<LibrarySourceException>()),
    );
  });
}
