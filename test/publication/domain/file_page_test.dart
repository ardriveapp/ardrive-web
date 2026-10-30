import 'dart:convert';
import 'dart:io';

import 'package:ardrive/models/models.dart';
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/publication/domain/file_page.dart';
import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/domain/publication_files.dart';
import 'package:ardrive/publication/presentation/publications_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

const _driveId = 'c863be1f-a725-4554-9a9e-18268ed8a035';
const _rootFolderId = '41520b33-28c1-4892-886b-b845a5709085';
const _fileId = 'f1e2d3c4-0000-4000-8000-000000000001';
const _owner = 'iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA';
const _dataTx = 'DATAtx0000000000000000000000000000000000000';
const _metadataTx = 'METAtx0000000000000000000000000000000000000';

FileRevision _revision({String name = 'Lake.jpg'}) => FileRevision(
      fileId: _fileId,
      driveId: _driveId,
      name: name,
      parentFolderId: _rootFolderId,
      size: 2048,
      lastModifiedDate: DateTime.utc(2026),
      dataContentType: 'image/jpeg',
      metadataTxId: _metadataTx,
      dataTxId: _dataTx,
      dateCreated: DateTime.utc(2026),
      action: 'create',
      isHidden: false,
    );

String _pageJson({
  required String privacy,
  required Map<String, Object> file,
}) =>
    buildPublicationJson(
      driveId: _driveId,
      rootFolderId: _rootFolderId,
      fileId: _fileId,
      file: file,
      privacy: privacy,
      owner: _owner,
      title: 'A lake',
      description: 'Taken at dawn.',
      publishedAt: '2026-10-29T12:00:00Z',
    );

Matcher _throwsConfig(PublicationConfigError error) => throwsA(
      isA<PublicationConfigException>().having((e) => e.error, 'error', error),
    );

void main() {
  group('a public file page', () {
    late PublicationConfig config;

    setUp(() {
      config = PublicationConfig.parse(_pageJson(
        privacy: 'public',
        file: buildFilePageBlock(revision: _revision()),
      ));
    });

    test('is version 2, scoped to its file, with no snapshot', () {
      expect(config.version, 2);
      expect(config.scope, const PublicationFileScope(_fileId));
      expect(config.snapshot, isNull);
      expect(config.fileCount, isNull);
      expect(config.file!.name, 'Lake.jpg');
      expect(config.file!.size, 2048);
      expect(config.file!.contentType, 'image/jpeg');
      expect(config.file!.cipher, isNull);
    });

    test('tells the share page the pinned version it was published with', () {
      final payload = filePagePayload(config);
      expect(payload.dataTxId, _dataTx);
      expect(payload.metadataTxId, _metadataTx);
      expect(payload.ownerAddress, _owner);
      expect(payload.name, 'Lake.jpg');
      expect(payload.isPinned, isTrue);
    });
  });

  group('a private file page', () {
    final block = buildFilePageBlock(
      revision: _revision(name: 'Secret plans.pdf'),
      cipher: (cipher: 'AES256-GCM', cipherIv: 'aXZpdml2aXZpdml2'),
    );
    final page = _pageJson(privacy: 'private', file: block);

    test('names nothing about its file but its transactions and cipher', () {
      expect(page, isNot(contains('Secret plans')));
      expect(page, isNot(contains('2048')));
      expect(page, isNot(contains('image/jpeg')));
      final config = PublicationConfig.parse(page);
      expect(config.isPrivate, isTrue);
      expect(config.file!.cipher, 'AES256-GCM');
      expect(config.file!.name, isNull);
      // The share page reads the rest by decrypting the metadata.
      expect(filePagePayload(config).name, isNull);
    });

    test('is refused when it carries the name', () {
      final json = jsonDecode(page) as Map<String, dynamic>;
      (json['file'] as Map)['name'] = 'Secret plans.pdf';
      expect(() => PublicationConfig.fromJson(json),
          _throwsConfig(PublicationConfigError.invalid));
    });

    test('is refused without its cipher', () {
      final json = jsonDecode(page) as Map<String, dynamic>;
      (json['file'] as Map).remove('cipherIv');
      expect(() => PublicationConfig.fromJson(json),
          _throwsConfig(PublicationConfigError.invalid));
    });
  });

  test('a public file page with cipher fields is refused', () {
    final json = jsonDecode(_pageJson(
      privacy: 'public',
      file: buildFilePageBlock(revision: _revision()),
    )) as Map<String, dynamic>;
    (json['file'] as Map)['cipher'] = 'AES256-GCM';
    expect(() => PublicationConfig.fromJson(json),
        _throwsConfig(PublicationConfigError.invalid));
  });

  test('a file page claiming version 1, or carrying a snapshot, is refused',
      () {
    Map<String, dynamic> json() => jsonDecode(_pageJson(
          privacy: 'public',
          file: buildFilePageBlock(revision: _revision()),
        )) as Map<String, dynamic>;
    expect(() => PublicationConfig.fromJson(json()..['version'] = 1),
        _throwsConfig(PublicationConfigError.invalid));
    expect(
      () => PublicationConfig.fromJson(json()
        ..['snapshot'] = {'path': 'snapshot', 'txId': _dataTx, 'tags': {}}),
      _throwsConfig(PublicationConfigError.invalid),
    );
  });

  group('versions by scope', () {
    String version(List<PublicationTag> tags) =>
        tags.firstWhere((t) => t.name == 'Publication-Version').value;
    String scope(List<PublicationTag> tags) =>
        tags.firstWhere((t) => t.name == 'Publication-Scope').value;

    test('drive and folder pages stay version 1, which released apps open', () {
      final drive =
          publicationEntityTags(driveId: _driveId, publicationId: 'p');
      final folder = publicationEntityTags(
          driveId: _driveId, publicationId: 'p', folderId: 'folder');
      expect(version(drive), '1');
      expect(scope(drive), 'drive');
      expect(version(folder), '1');
      expect(scope(folder), 'folder');
      final json = jsonDecode(buildPublicationJson(
        driveId: _driveId,
        rootFolderId: _rootFolderId,
        privacy: 'public',
        owner: _owner,
        snapshotTxId: _dataTx,
        snapshotTags: const {},
        title: 't',
        description: '',
        publishedAt: '2026-10-29T12:00:00Z',
      ));
      expect(json['version'], 1);
    });

    test('a file page is version 2 and names its file', () {
      final tags = publicationEntityTags(
          driveId: _driveId, publicationId: 'p', fileId: _fileId);
      expect(version(tags), '2');
      expect(scope(tags), 'file');
      expect(tags.firstWhere((t) => t.name == 'Publication-File-Id').value,
          _fileId);
      expect(tags.map((t) => t.name), isNot(contains('File-Id')));
    });

    test('the viewer reads every version a page is written at', () {
      expect(PublicationConfig.supportedVersion,
          PublicationConfig.fileScopeVersion);
    });
  });

  test('the release says it opens file pages, in step with the viewer', () {
    final marker =
        jsonDecode(File('web/$publicationCapabilitiesPath').readAsStringSync())
            as Map<String, dynamic>;
    expect(marker['publicationVersion'], PublicationConfig.supportedVersion);
  });

  group('a drive\'s publications', () {
    Publication publication(String id, PublicationScope scope) => Publication([
          PublishedVersion(
            txId: '$id-tx',
            publicationId: id,
            driveId: _driveId,
            scope: scope,
            publishedAt: DateTime.utc(2026),
          ),
        ]);

    test('a file page is never the drive\'s page, nor a folder\'s', () {
      final only = DrivePublications(publications: [
        publication('page', const PublicationFileScope(_fileId)),
      ]);
      expect(only.of(null), isNull);
      expect(only.of(_fileId), isNull);
      expect(only.ofFile(_fileId)?.id, 'page');
    });

    test('and the drive\'s page is not a file\'s', () {
      final both = DrivePublications(publications: [
        publication('drive', const PublicationDriveScope()),
        publication('page', const PublicationFileScope(_fileId)),
      ]);
      expect(both.of(null)?.id, 'drive');
      expect(both.ofFile('another')?.id, isNull);
    });
  });

  test('linkHasKey tells a key-bearing link', () {
    expect(linkHasKey(withFileKey('https://ardrive.net/P/', 'KEY')), isTrue);
    expect(linkHasKey('https://ardrive.net/P/'), isFalse);
  });

  group('the owner\'s link to a private file page', () {
    test('carries the key in the hash route', () {
      expect(withFileKey('https://ardrive.net/PAGE/', 'KEY'),
          'https://ardrive.net/PAGE/#/?k=KEY');
      expect(withFileKey('https://lake.ar.io', 'KEY'),
          'https://lake.ar.io/#/?k=KEY');
    });

    test('is the page itself without a key', () {
      expect(withFileKey('https://ardrive.net/PAGE/', null),
          'https://ardrive.net/PAGE/');
    });
  });
}
