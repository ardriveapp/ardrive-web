import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/app_platform.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/fake_data.dart';

const gatewayUrl = 'https://arweave.net';
void main() {
  group('Arweave Service Tests', () {
    //TODO Create and inject mock artemis client
    AppPlatform.setMockPlatform(platform: SystemPlatform.unknown);

    final arweave = ArweaveService(
      Arweave(gatewayUrl: Uri.parse(gatewayUrl)),
    );
    test('AllFileEntitiesWithId returns all the file entities for a known Id',
        () async {
      const knownFileId = '0f029ecf-6593-4942-ad07-a57401e3861c';
      const knownRevisionCount = 10;
      final fileEntities = await arweave.getAllFileEntitiesWithId(knownFileId);
      expect(fileEntities?.length, equals(knownRevisionCount));
    });
    test('AllFileEntitiesWithId returns null for invalid Id', () async {
      final invalidFileId = testEntityId;

      final fileEntities = await arweave.getAllFileEntitiesWithId(
        invalidFileId,
      );
      expect(fileEntities, equals(null));
    });
  });
}
