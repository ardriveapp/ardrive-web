import 'package:ardrive/entities/entities.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  final fakeFileJson = {
    // Reserved JSON Metadata
    'name': 'El archivo',
    'size': 123,
    'lastModifiedDate': 12345,
    'dataTxId': 'txId',
    'dataContentType': 'text/plain',

    // Custom JSON Metadata
    'customKey': ['customValue'],
    'anotherOne': {'papá': 'papa'},
    'foo': 'bar',
  };
  final fakeFolderJson = {
    // Reserved JSON Metadata
    'name': 'La carpeta',

    // Custom JSON Metadata
    'customKey': ['customValue'],
    'anotherOne': {'papá': 'papa'},
    'foo': 'bar',
  };
  final fakeDriveJson = {
    // Reserved JSON Metadata
    'name': 'El disko',
    'rootFolderId': 'rootFolderId',

    // Custom JSON Metadata
    'customKey': ['customValue'],
    'anotherOne': {'papá': 'papa'},
    'foo': 'bar',
  };

  TestWidgetsFlutterBinding.ensureInitialized();

  group('Carry-over of Custom JSON Metadata', () {
    test('for FileEntity', () {
      final parsedEntity = FileEntity.fromJson(fakeFileJson);
      final customFields = parsedEntity.customJsonMetadata!;

      expect(customFields['customKey'], ['customValue']);
      expect(customFields['anotherOne'], {'papá': 'papa'});
      expect(customFields['foo'], 'bar');

      expect(customFields['name'], null);
      expect(customFields['size'], null);
      expect(customFields['lastModifiedDate'], null);
      expect(customFields['dataTxId'], null);
      expect(customFields['dataContentType'], null);

      final serializedEntity = parsedEntity.toJson();
      expect(serializedEntity['name'], 'El archivo');
      expect(serializedEntity['size'], 123);
      expect(serializedEntity['lastModifiedDate'], 12345);
      expect(serializedEntity['dataTxId'], 'txId');
      expect(serializedEntity['dataContentType'], 'text/plain');
      expect(serializedEntity['customKey'], ['customValue']);
      expect(serializedEntity['anotherOne'], {'papá': 'papa'});
      expect(serializedEntity['foo'], 'bar');
    });

    test('for FolderEntity', () {
      final parsedEntity = FolderEntity.fromJson(fakeFolderJson);
      final customFields = parsedEntity.customJsonMetadata!;

      expect(customFields['customKey'], ['customValue']);
      expect(customFields['anotherOne'], {'papá': 'papa'});
      expect(customFields['foo'], 'bar');

      expect(customFields['name'], null);

      final serializedEntity = parsedEntity.toJson();
      expect(serializedEntity['name'], 'La carpeta');
      expect(serializedEntity['customKey'], ['customValue']);
      expect(serializedEntity['anotherOne'], {'papá': 'papa'});
      expect(serializedEntity['foo'], 'bar');
    });

    test('for DriveEntity', () {
      final parsedEntity = DriveEntity.fromJson(fakeDriveJson);
      final customFields = parsedEntity.customJsonMetadata!;

      expect(customFields['customKey'], ['customValue']);
      expect(customFields['anotherOne'], {'papá': 'papa'});
      expect(customFields['foo'], 'bar');

      expect(customFields['name'], null);
      expect(customFields['rootFolderId'], null);

      final serializedEntity = parsedEntity.toJson();
      expect(serializedEntity['name'], 'El disko');
      expect(serializedEntity['rootFolderId'], 'rootFolderId');
      expect(serializedEntity['customKey'], ['customValue']);
      expect(serializedEntity['anotherOne'], {'papá': 'papa'});
      expect(serializedEntity['foo'], 'bar');
    });
  });

  group('Carry-over of Custom GQL Tags', () {
    late Transaction fileTransaction;
    late Transaction folderTransaction;
    late Transaction driveTransaction;

    late DataItem fileDataItem;
    late DataItem folderDataItem;
    late DataItem driveDataItem;

    // late Uint8List fileData;
    // late Uint8List folderData;
    // late Uint8List driveData;

    setUp(() async {
      PackageInfo.setMockInitialValues(
        appName: 'appName',
        packageName: 'packageName',
        version: '1.2.3',
        buildNumber: 'buildNumber',
        buildSignature: 'buildSignature',
      );

      final FileEntity fileEntity = FileEntity.fromJson(fakeFileJson);
      final FolderEntity folderEntity = FolderEntity.fromJson(fakeFolderJson);
      final DriveEntity driveEntity = DriveEntity.fromJson(fakeDriveJson);

      fileEntity.id = '';
      fileEntity.driveId = '';
      fileEntity.parentFolderId = '';
      folderEntity.id = '';
      folderEntity.driveId = '';
      folderEntity.parentFolderId = '';
      driveEntity.id = '';
      driveEntity.privacy = DrivePrivacyTag.public;

      fileTransaction = await fileEntity.asTransaction();
      folderTransaction = await folderEntity.asTransaction();
      driveTransaction = await driveEntity.asTransaction();

      fileTransaction.addTag('banana', 'manzana');
      folderTransaction.addTag('banana', 'manzana');
      driveTransaction.addTag('banana', 'manzana');

      fileDataItem = await fileEntity.asDataItem(null);
      folderDataItem = await folderEntity.asDataItem(null);
      driveDataItem = await driveEntity.asDataItem(null);

      fileDataItem.addTag('banana', 'manzana');
      folderDataItem.addTag('banana', 'manzana');
      driveDataItem.addTag('banana', 'manzana');

      // fileData = Uint8List.fromList(utf8.encode(jsonEncode(fakeFileJson)));
      // folderData = Uint8List.fromList(utf8.encode(jsonEncode(fakeFolderJson)));
      // driveData = Uint8List.fromList(utf8.encode(jsonEncode(fakeDriveJson)));
    });

    // test('for FileEntity', () async {
    //   final fileFromTransaction = await FileEntity.fromTransaction(
    //     /// FIXME: this hack doesn't work
    //     fileTransaction as TransactionCommonMixin,
    //     fileData,
    //     driveKey: null,
    //     fileKey: null,
    //     crypto: MockArDriveCrypto(),
    //   );

    //   expect(fileFromTransaction, isNotNull);
    // });
  });
}
