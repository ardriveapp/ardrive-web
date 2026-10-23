import 'dart:convert';

import 'package:ardrive/library/domain/library_config.dart';
import 'package:flutter_test/flutter_test.dart';

const _driveId = 'c863be1f-a725-4554-9a9e-18268ed8a035';
const _rootFolderId = '41520b33-28c1-4892-886b-b845a5709085';
const _folderId = 'e9b05236-0000-4000-8000-000000000001';
const _owner = 'iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA';
const _artifactTx = 'a8dfadXLDbkLLbd5jmi297xfvJvns9Trn7axRXgniow';
const _releaseManifest = 'kQJt49W-uYw_E7YSqQqkUARNZPg4H38hFnOMP4hf9MA';

Map<String, dynamic> _publicJson() => {
      'version': 1,
      'driveId': _driveId,
      'rootFolderId': _rootFolderId,
      'scope': {'type': 'drive'},
      'privacy': 'public',
      'owner': _owner,
      'snapshot': {
        'path': 'snapshot',
        'txId': _artifactTx,
        'tags': <String, dynamic>{
          'Drive-Id': _driveId,
          'Block-Start': '0',
          'Block-End': '1879136',
          'Entity-Count': '6',
          'State-Version': '1',
        },
      },
      'title': "Phil's Archive",
      'description': 'Photos, notes and the odd recording.',
      'images': {
        'icon': 'icon-512.png',
        'social': 'social.jpg',
        'cover': 'cover.jpg',
      },
      'publishedAt': '2026-10-21T18:02:11Z',
      'viewer': {'release': '2.91.0', 'manifest': _releaseManifest},
    };

Map<String, dynamic> _privateJson() => _publicJson()
  ..['privacy'] = 'private'
  ..['snapshot'] = {
    'path': 'snapshot',
    'txId': _artifactTx,
    'tags': <String, dynamic>{
      'Drive-Id': _driveId,
      'Cipher': 'AES256-GCM',
      'Cipher-IV': 'aXZpdml2aXZpdml2',
    },
  };

Matcher _throwsConfig(LibraryConfigError error) => throwsA(
      isA<LibraryConfigException>().having((e) => e.error, 'error', error),
    );

void main() {
  group('LibraryConfig.fromJson', () {
    test('reads every field of a public library', () {
      final config = LibraryConfig.fromJson(_publicJson());

      expect(config.version, 1);
      expect(config.driveId, _driveId);
      expect(config.rootFolderId, _rootFolderId);
      expect(config.scope, const LibraryDriveScope());
      expect(config.scopeRootFolderId, _rootFolderId);
      expect(config.privacy, 'public');
      expect(config.isPrivate, isFalse);
      expect(config.owner, _owner);
      expect(config.snapshot.path, 'snapshot');
      expect(config.snapshot.txId, _artifactTx);
      expect(config.snapshot.tags['Block-End'], '1879136');
      expect(config.title, "Phil's Archive");
      expect(config.description, 'Photos, notes and the odd recording.');
      expect(
        config.images,
        const LibraryImages(
          icon: 'icon-512.png',
          social: 'social.jpg',
          cover: 'cover.jpg',
        ),
      );
      expect(config.publishedAt, DateTime.utc(2026, 10, 21, 18, 2, 11));
      expect(
        config.viewer,
        const LibraryViewer(release: '2.91.0', manifest: _releaseManifest),
      );
    });

    test('a folder library opens at its folder', () {
      final config = LibraryConfig.fromJson(
        _publicJson()..['scope'] = {'type': 'folder', 'folderId': _folderId},
      );

      expect(config.scope, const LibraryFolderScope(_folderId));
      expect(config.scopeRootFolderId, _folderId);
    });

    test('reads a private library with its cipher tags', () {
      final config = LibraryConfig.fromJson(_privateJson());

      expect(config.isPrivate, isTrue);
      expect(config.snapshot.tags['Cipher'], 'AES256-GCM');
    });

    test('optional fields may be left out', () {
      final json = _publicJson()
        ..remove('description')
        ..remove('images')
        ..remove('publishedAt')
        ..remove('viewer');

      final config = LibraryConfig.fromJson(json);

      expect(config.description, '');
      expect(config.images, const LibraryImages());
      expect(config.publishedAt, isNull);
      expect(config.viewer, isNull);
    });

    test("reads the owner's chosen name, trimmed, and none when it is blank",
        () {
      expect(
        LibraryConfig.fromJson(_publicJson()..['ownerName'] = '  Phil  ')
            .ownerName,
        'Phil',
      );
      expect(
        LibraryConfig.fromJson(_publicJson()..['ownerName'] = '   ').ownerName,
        isNull,
      );
      expect(LibraryConfig.fromJson(_publicJson()).ownerName, isNull);
      expect(
        () => LibraryConfig.fromJson(_publicJson()..['ownerName'] = 7),
        throwsA(isA<LibraryConfigException>()),
      );
    });

    test('an image left null is not set', () {
      final config = LibraryConfig.fromJson(
        _publicJson()..['images'] = {'icon': 'icon-512.png', 'cover': null},
      );

      expect(config.images, const LibraryImages(icon: 'icon-512.png'));
    });

    test('keeps markup in the owner\'s text as text', () {
      const title = '<script>alert(1)</script> & "quotes"';
      const description = '<img src=x onerror=alert(1)>';
      final config = LibraryConfig.fromJson(
        _publicJson()
          ..['title'] = title
          ..['description'] = description,
      );

      expect(config.title, title);
      expect(config.description, description);
    });

    test('a newer version is reported as needing a newer viewer', () {
      expect(
        () => LibraryConfig.fromJson(const {'version': 2}),
        _throwsConfig(LibraryConfigError.unsupportedVersion),
      );
    });

    test('a newer version wins even when the rest would not parse here', () {
      expect(
        () => LibraryConfig.fromJson(
          _publicJson()
            ..['version'] = 7
            ..['scope'] = {'type': 'something-new'},
        ),
        _throwsConfig(LibraryConfigError.unsupportedVersion),
      );
    });

    for (final field in [
      'version',
      'driveId',
      'rootFolderId',
      'scope',
      'privacy',
      'owner',
      'snapshot',
      'title',
    ]) {
      test('refuses a library without $field', () {
        expect(
          () => LibraryConfig.fromJson(_publicJson()..remove(field)),
          _throwsConfig(LibraryConfigError.invalid),
        );
      });
    }

    test('refuses a private library without cipher tags', () {
      final json = _publicJson()..['privacy'] = 'private';

      expect(
        () => LibraryConfig.fromJson(json),
        _throwsConfig(LibraryConfigError.invalid),
      );
    });

    test('refuses a private library with only one cipher tag', () {
      final json = _privateJson();
      (json['snapshot']['tags'] as Map).remove('Cipher-IV');

      expect(
        () => LibraryConfig.fromJson(json),
        _throwsConfig(LibraryConfigError.invalid),
      );
    });

    test('refuses a public library whose snapshot carries a cipher tag', () {
      final json = _publicJson();
      (json['snapshot']['tags'] as Map)['Cipher'] = 'AES256-GCM';

      expect(
        () => LibraryConfig.fromJson(json),
        _throwsConfig(LibraryConfigError.invalid),
      );
    });

    final invalid = <String, void Function(Map<String, dynamic>)>{
      'an unknown privacy': (j) => j['privacy'] = 'secret',
      'a drive id that is not an ArFS id': (j) => j['driveId'] = 'drive-1',
      'an owner that is not an address': (j) => j['owner'] = 'phil',
      'an empty title': (j) => j['title'] = '   ',
      'a folder scope without a folder': (j) => j['scope'] = {'type': 'folder'},
      'an unknown scope type': (j) => j['scope'] = {'type': 'everything'},
      'a non-string tag value': (j) => j['snapshot']['tags']['Block-End'] = 5,
      'a snapshot path with a scheme': (j) =>
          j['snapshot']['path'] = 'https://evil.example/snapshot',
      'a snapshot path from the root': (j) => j['snapshot']['path'] = '/snap',
      'a snapshot path out of the page': (j) =>
          j['snapshot']['path'] = '../other/snapshot',
      'an image on another host': (j) =>
          j['images'] = {'cover': '//evil.example/cover.jpg'},
      'an image path with a query': (j) =>
          j['images'] = {'icon': 'icon.png?x=1'},
      'a date that is not a date': (j) => j['publishedAt'] = 'yesterday',
      'a version that is not a number': (j) => j['version'] = '1',
      'a version of zero': (j) => j['version'] = 0,
    };
    invalid.forEach((name, mutate) {
      test('refuses $name', () {
        final json = _publicJson();
        mutate(json);

        expect(
          () => LibraryConfig.fromJson(json),
          _throwsConfig(LibraryConfigError.invalid),
        );
      });
    });
  });

  group('LibraryConfig.parse', () {
    test('reads library.json\'s text', () {
      expect(
        LibraryConfig.parse(json.encode(_publicJson())),
        LibraryConfig.fromJson(_publicJson()),
      );
    });

    test('refuses text that is not JSON', () {
      expect(
        () => LibraryConfig.parse('<html>404</html>'),
        _throwsConfig(LibraryConfigError.invalid),
      );
    });

    test('refuses JSON that is not an object', () {
      expect(
        () => LibraryConfig.parse('[1, 2]'),
        _throwsConfig(LibraryConfigError.invalid),
      );
    });
  });
}
