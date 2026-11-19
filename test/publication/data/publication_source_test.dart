import 'dart:convert';

import 'package:ardrive/publication/data/publication_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final page = Uri.parse('https://turbo-gateway.com/PageManifest/');

  PublicationSource serving(List<int> body) => PublicationSource(
        pageUri: page,
        // As gateways send it: no charset, which `http` reads as Latin-1.
        client: MockClient((_) async => http.Response.bytes(
              body,
              200,
              headers: {'content-type': 'application/json'},
            )),
      );

  test('reads publication.json as UTF-8, whatever charset it is served with',
      () async {
    const title = 'Phil’s Archive · café 日本語 🎉';

    final text = await serving(utf8.encode('{"title": "$title"}'))
        .readSettings('publication.json');

    expect(jsonDecode(text)['title'], title);
  });

  test('refuses a publication.json that is not UTF-8', () {
    expect(
      serving([0x7b, 0xff, 0x7d]).readSettings('publication.json'),
      throwsA(isA<PublicationSourceException>()),
    );
  });

  group('what the gateway says it served', () {
    PublicationSource naming(String? id, {List<int> body = const [1, 2, 3]}) =>
        PublicationSource(
          pageUri: page,
          client: MockClient((_) async => http.Response.bytes(body, 200,
              headers: {if (id != null) PublicationSource.dataIdHeader: id})),
        );

    test('is kept for each path read', () async {
      final source = naming('TX1');
      expect(source.dataIdOf('snapshot'), isNull);
      await source.readSnapshot('snapshot', maxBytes: 10);
      await source.readPart('sealed', maxBytes: 10);
      await source.readSettings('publication.json');
      expect(source.dataIdOf('snapshot'), 'TX1');
      expect(source.dataIdOf('sealed'), 'TX1');
      expect(source.dataIdOf('publication.json'), 'TX1');
    });

    test('is null when the gateway does not say', () async {
      final source = naming(null);
      await source.readSnapshot('snapshot', maxBytes: 10);
      expect(source.dataIdOf('snapshot'), isNull);
    });
  });

  test('a snapshot over its limit is refused', () {
    final source = PublicationSource(
      pageUri: page,
      client:
          MockClient((_) async => http.Response.bytes(List.filled(11, 0), 200)),
    );
    expect(source.readSnapshot('snapshot', maxBytes: 10),
        throwsA(isA<PublicationPartTooLarge>()));
  });
}
