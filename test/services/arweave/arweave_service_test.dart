import 'dart:math';

import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';

const gatewayUrl = 'https://arweave.net';
void main(List<String> args) {
  group('Arweave Service Tests', () {
    final arweave = ArweaveService(
      Arweave(
        gatewayUrl: Uri.parse(gatewayUrl),
      ),
    );
    test('AllFileEntitiesWithId returns all the file entities for a known Id',
        () async {
      const knownFileId = '0f029ecf-6593-4942-ad07-a57401e3861c';
      const knownRevisionCount = 9;
      final fileEntities = await arweave.getAllFileEntitiesWithId(knownFileId);
      expect(fileEntities?.length, equals(knownRevisionCount));
    });
    test('AllFileEntitiesWithId returns null for invalid Id', () async {
      final invalidFileId = Random().nextInt(1000).toString();

      final fileEntities = await arweave.getAllFileEntitiesWithId(
        invalidFileId,
      );
      expect(fileEntities, equals(null));
    });
  });
}
