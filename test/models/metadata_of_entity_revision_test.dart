import 'dart:convert';

import 'package:ardrive/models/daos/drive_dao/metadata_of_entity_revision.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('metadataOfEntityRevision method', () {
    final driveId = 'DRIVE_ID';

    test('re-constructs the metadata of a drive revision', () {
      final driveRevision = DriveRevision(
        driveId: driveId,
        action: '',
        dateCreated: DateTime(1234),
        metadataTxId: 'METADATA_TX_ID',
        name: 'Awesome drive',
        ownerAddress: '',
        privacy: '',
        rootFolderId: 'ROOT_FOLDER_ID',
        customJsonMetaData: '{"Foo": "Bar"}',
      );

      final response = metadataOfEntityRevision(driveRevision);
      expect(response, isNotNull);

      final metadata = response!.metadata;
      final Map<String, dynamic> metadataAsJson = jsonDecode(utf8.decode(
        metadata,
      ));

      expect(metadataAsJson.keys.length, 3);

      expect(metadataAsJson['name'], 'Awesome drive');
      expect(metadataAsJson['rootFolderId'], 'ROOT_FOLDER_ID');
      expect(metadataAsJson['Foo'], 'Bar');

      final metadataTxId = response.metadataTxId;
      expect(metadataTxId, 'METADATA_TX_ID');
    });

    test('re-constructs the metadata of a folder revision', () {
      final folderRevision = FolderRevision(
        driveId: driveId,
        action: '',
        dateCreated: DateTime(1234),
        metadataTxId: 'METADATA_TX_ID',
        name: 'Awesome folder',
        folderId: 'FOLDER_ID',
        customJsonMetaData: '{"Foo": "Bar"}',
      );

      final response = metadataOfEntityRevision(folderRevision);
      expect(response, isNotNull);

      final metadata = response!.metadata;
      final Map<String, dynamic> metadataAsJson = jsonDecode(utf8.decode(
        metadata,
      ));

      expect(metadataAsJson.keys.length, 2);

      expect(metadataAsJson['name'], 'Awesome folder');
      expect(metadataAsJson['Foo'], 'Bar');

      final metadataTxId = response.metadataTxId;
      expect(metadataTxId, 'METADATA_TX_ID');
    });

    test('re-constructs the metadata of a file revision', () async {
      final fileRevision = FileRevision(
        driveId: driveId,
        fileId: 'FILE_ID',
        action: '',
        dateCreated: DateTime(1234),
        metadataTxId: 'METADATA_TX_ID',
        name: 'Awesome file',
        customJsonMetaData: '{"Foo": "Bar"}',
        dataTxId: 'DATA_TX_ID',
        lastModifiedDate: DateTime.fromMillisecondsSinceEpoch(1234),
        parentFolderId: 'PARENT_FOLDER_ID',
        size: 1234,
        dataContentType: 'application/octet-stream',
      );

      final response = metadataOfEntityRevision(fileRevision);
      expect(response, isNotNull);

      final metadata = response!.metadata;
      final Map<String, dynamic> metadataAsJson = jsonDecode(utf8.decode(
        metadata,
      ));

      expect(metadataAsJson.keys.length, 6);

      expect(metadataAsJson['name'], 'Awesome file');
      expect(metadataAsJson['size'], 1234);
      expect(metadataAsJson['Foo'], 'Bar');
      expect(metadataAsJson['lastModifiedDate'], 1234);
      expect(metadataAsJson['dataTxId'], 'DATA_TX_ID');
      expect(metadataAsJson['dataContentType'], 'application/octet-stream');

      final metadataTxId = response.metadataTxId;
      expect(metadataTxId, 'METADATA_TX_ID');
    });

    test('returns null if the revision has no customMetaData', () async {
      final fileRevision = FileRevision(
        driveId: driveId,
        fileId: 'FILE_ID',
        action: '',
        dateCreated: DateTime(1234),
        metadataTxId: 'METADATA_TX_ID',
        name: 'Awesome file',
        customJsonMetaData: null,
        dataTxId: 'DATA_TX_ID',
        lastModifiedDate: DateTime(1234),
        parentFolderId: 'PARENT_FOLDER_ID',
        size: 1234,
      );

      final response = metadataOfEntityRevision(fileRevision);
      expect(response, isNull);
    });
  });
}
