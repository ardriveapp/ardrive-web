import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/utils.dart';

FileEntity _entity({Map<String, dynamic>? custom, String name = 'app.js'}) {
  final e = FileEntity(
    id: 'file-id',
    driveId: 'drive-id',
    parentFolderId: 'folder-id',
    name: name,
    size: 123,
    lastModifiedDate: DateTime(2026, 11, 16),
    dataTxId: 'data-tx',
    dataContentType: 'text/javascript',
  )..createdAt = DateTime(2026, 11, 16);
  if (custom != null) e.customJsonMetadata = custom;
  return e;
}

void main() {
  late Database db;
  late DriveDao driveDao;

  setUp(() {
    db = getTestDb();
    driveDao = db.driveDao;
  });

  tearDown(() => db.close());

  test('an uploaded file keeps dataContentEncoding for a rename before a sync',
      () async {
    await driveDao.writeFileEntity(
      _entity(custom: {FileEntity.dataContentEncodingKey: 'gzip'}),
    );

    final row = await driveDao.fileById(fileId: 'file-id').getSingle();
    final entity = row.asEntity();
    expect(entity.dataContentEncoding, 'gzip');

    // What a rename writes next.
    entity.name = 'renamed.js';
    final json = entity.toJson();
    expect(json['dataContentEncoding'], 'gzip');
    expect(json['size'], 123);
  });

  test('writing an entity without custom metadata leaves the row alone',
      () async {
    await driveDao.writeFileEntity(
      _entity(custom: {FileEntity.dataContentEncodingKey: 'gzip'}),
    );
    await driveDao.writeFileEntity(_entity(name: 'again.js'));

    final row = await driveDao.fileById(fileId: 'file-id').getSingle();
    expect(row.name, 'again.js');
    expect(row.asEntity().dataContentEncoding, 'gzip');
  });

  test('an uncompressed replacement upload drops the old field', () async {
    await driveDao.writeFileEntity(
      _entity(custom: {FileEntity.dataContentEncodingKey: 'gzip'}),
      replaceCustomMetadata: true,
    );
    final replacement = _entity(name: 'app.js')..dataTxId = 'new-data-tx';
    await driveDao.writeFileEntity(replacement, replaceCustomMetadata: true);

    final entity =
        (await driveDao.fileById(fileId: 'file-id').getSingle()).asEntity();
    expect(entity.dataTxId, 'new-data-tx');
    expect(entity.dataContentEncoding, isNull);
    entity.name = 'renamed.js';
    expect(entity.toJson().containsKey('dataContentEncoding'), isFalse);
  });

  test('a compressed replacement of an uncompressed file adds the field',
      () async {
    await driveDao.writeFileEntity(_entity(), replaceCustomMetadata: true);
    await driveDao.writeFileEntity(
      _entity(custom: {FileEntity.dataContentEncodingKey: 'gzip'})
        ..dataTxId = 'new-data-tx',
      replaceCustomMetadata: true,
    );

    final entity =
        (await driveDao.fileById(fileId: 'file-id').getSingle()).asEntity();
    expect(entity.dataContentEncoding, 'gzip');
  });
}
