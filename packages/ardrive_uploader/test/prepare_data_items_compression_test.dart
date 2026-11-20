@TestOn('vm')
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/data_bundler.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class MockAppInfoServices extends Mock implements AppInfoServices {}

const _contentEncoding = 'Content-Encoding';

Future<List<int>> _bytesOf(DataItemResult item) async {
  final out = <int>[];
  await for (final chunk in item.streamGenerator()) {
    out.addAll(chunk);
  }
  return out;
}

bool _endsWith(List<int> whole, List<int> tail) {
  if (tail.length > whole.length) return false;
  final offset = whole.length - tail.length;
  for (var i = 0; i < tail.length; i++) {
    if (whole[offset + i] != tail[i]) return false;
  }
  return true;
}

void main() {
  late Wallet wallet;
  late ARFSUploadMetadataGenerator generator;

  final script = Uint8List.fromList(
    utf8.encode('function hello() { return "hello hello hello"; }\n' * 400),
  );
  final noise = () {
    final random = Random(7);
    return Uint8List.fromList(List.generate(4096, (_) => random.nextInt(256)));
  }();

  setUpAll(() async {
    wallet = await Wallet.generate();
    final appInfoServices = MockAppInfoServices();
    when(() => appInfoServices.appInfo).thenReturn(AppInfo(
      version: '3.0.0',
      platform: 'FlutterTest',
      arfsVersion: '0.15',
      appName: 'ardrive',
    ));
    when(() => appInfoServices.loadAppInfo()).thenAnswer((_) async {});
    generator = ARFSUploadMetadataGenerator(
      tagsGenerator: ARFSTagsGenerator(appInfoServices: appInfoServices),
    );
  });

  Future<(ARFSFileUploadMetadata, UploadFilePreparation, IOFile)> prepare(
    String name,
    Uint8List bytes, {
    bool compress = true,
    bool isPrivate = false,
    SecretKey? driveKey,
    String? contentType,
  }) async {
    final file = await IOFile.fromData(
      bytes,
      name: name,
      lastModifiedDate: DateTime(2026, 11, 16),
      contentType: contentType,
    );
    final metadata = await generator.generateMetadata(
      file,
      arguments: ARFSUploadMetadataArgs(
        isPrivate: isPrivate,
        type: UploadType.turbo,
        driveId: 'drive-id',
        parentFolderId: 'folder-id',
        compressDeployment: compress,
      ),
    ) as ARFSFileUploadMetadata;
    final preparation = await prepareDataItems(
      file: file,
      metadata: metadata,
      wallet: wallet,
      driveKey: driveKey,
      addThumbnail: false,
    );
    return (metadata, preparation, file);
  }

  String? tag(ARFSFileUploadMetadata m, String name) {
    final values = [
      for (final t in m.getDataTags())
        if (t.name == name) t.value
    ];
    return values.isEmpty ? null : values.single;
  }

  // The ArFS file metadata JSON as signed: what readers on the network see.
  Future<Map<String, dynamic>> signedMetadata(
      UploadFilePreparation preparation) async {
    final bytes = await _bytesOf(preparation.metadataSignedDataItemResult!);
    final text = utf8.decode(bytes, allowMalformed: true);
    final start = text.indexOf('{"name"');
    return jsonDecode(text.substring(start, text.lastIndexOf('}') + 1))
        as Map<String, dynamic>;
  }

  group('prepareDataItems with a deployment flag', () {
    test('gzips a script, tags it, and keeps its type and ArFS size', () async {
      final (metadata, preparation, file) = await prepare('app.js', script);

      final signed = preparation.dataSignedDataItemResult!;
      expect(tag(metadata, _contentEncoding), 'gzip');
      expect(tag(metadata, 'Content-Type'), 'text/javascript');
      expect(signed.dataSize, lessThan(script.length));

      // The signed data item carries the gzip, which decodes to the file.
      final gz = CompressionPolicy.gzipDeterministic(script);
      expect(signed.dataSize, gz.length);
      final item = await _bytesOf(signed);
      expect(_endsWith(item, gz), isTrue);
      expect(GZipDecoder().decodeBytes(gz), script);

      // The file the bundle strategy (D2N) assembles carries the same.
      final dataItemFile = preparation.dataItemFiles.firstWhere(
        (f) => f.dataSize == gz.length,
      );
      expect(
        dataItemFile.tags
            .map((t) => decodeBase64ToString(t.name))
            .contains(_contentEncoding),
        isTrue,
      );

      // Only the data carries the encoding, never the ArFS metadata item.
      expect(
        metadata
            .getEntityMetadataTags()
            .where((t) => t.name == _contentEncoding),
        isEmpty,
      );

      // The ArFS entity still says how big the file is.
      expect(metadata.toJson()['size'], script.length);
      expect(metadata.toJson()['dataContentType'], file.contentType);

      // And the metadata says the stored data is gzip, in the item signed.
      expect(metadata.toJson()['dataContentEncoding'], 'gzip');
      final signedJson = await signedMetadata(preparation);
      expect(signedJson['dataContentEncoding'], 'gzip');
      expect(signedJson['size'], script.length);
    });

    test('a second preparation signs the same bytes', () async {
      final (_, first, _) = await prepare('app.js', script);
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final (_, second, _) = await prepare('app.js', script);

      expect(
        first.dataSignedDataItemResult!.dataSize,
        second.dataSignedDataItemResult!.dataSize,
      );
      final gz = CompressionPolicy.gzipDeterministic(script);
      expect(_endsWith(await _bytesOf(first.dataSignedDataItemResult!), gz),
          isTrue);
      expect(_endsWith(await _bytesOf(second.dataSignedDataItemResult!), gz),
          isTrue);
    });

    test('preparing the same metadata twice tags it once', () async {
      final (metadata, _, file) = await prepare('app.js', script);
      await prepareDataItems(
        file: file,
        metadata: metadata,
        wallet: wallet,
        addThumbnail: false,
      );
      expect(
        metadata.getDataTags().where((t) => t.name == _contentEncoding),
        hasLength(1),
      );
    });

    test('a retry that does not compress does not sign a stale tag', () async {
      final (metadata, first, _) = await prepare('app.js', script);
      expect(tag(metadata, _contentEncoding), 'gzip');
      expect(first.dataSignedDataItemResult!.dataSize, lessThan(script.length));

      // The same metadata is prepared again, now over bytes that do not
      // shrink: nothing is compressed, so nothing may be tagged.
      final raw = await IOFile.fromData(
        noise,
        name: 'app.js',
        lastModifiedDate: DateTime(2026, 11, 16),
      );
      final second = await prepareDataItems(
        file: raw,
        metadata: metadata,
        wallet: wallet,
        addThumbnail: false,
      );

      expect(tag(metadata, _contentEncoding), isNull);
      expect(metadata.toJson().containsKey('dataContentEncoding'), isFalse);
      expect(
        (await signedMetadata(second)).containsKey('dataContentEncoding'),
        isFalse,
      );
      expect(second.dataSignedDataItemResult!.dataSize, noise.length);
      final tagged = second.dataItemFiles.where((f) => f.tags
          .map((t) => decodeBase64ToString(t.name))
          .contains(_contentEncoding));
      expect(tagged, isEmpty);
    });

    test('leaves a png alone: no tag, same bytes', () async {
      final (metadata, preparation, _) = await prepare('logo.png', noise);

      expect(tag(metadata, _contentEncoding), isNull);
      expect(tag(metadata, 'Content-Type'), 'image/png');
      expect(metadata.toJson().containsKey('dataContentEncoding'), isFalse);
      final signed = preparation.dataSignedDataItemResult!;
      expect(signed.dataSize, noise.length);
      expect(_endsWith(await _bytesOf(signed), noise), isTrue);
    });

    test('leaves a script that does not shrink alone', () async {
      final (metadata, preparation, _) = await prepare('noise.js', noise);

      expect(tag(metadata, _contentEncoding), isNull);
      expect(metadata.toJson().containsKey('dataContentEncoding'), isFalse);
      final signed = preparation.dataSignedDataItemResult!;
      expect(signed.dataSize, noise.length);
      expect(_endsWith(await _bytesOf(signed), noise), isTrue);
    });

    test('a .gz is uploaded as it is', () async {
      final already = CompressionPolicy.gzipDeterministic(script);
      final (metadata, preparation, _) =
          await prepare('app.js.gz', Uint8List.fromList(already));

      expect(tag(metadata, _contentEncoding), isNull);
      expect(metadata.toJson().containsKey('dataContentEncoding'), isFalse);
      expect(preparation.dataSignedDataItemResult!.dataSize, already.length);
    });

    test('a manifest is never gzipped', () async {
      final manifest = Uint8List.fromList(
        utf8.encode(jsonEncode({
          'manifest': 'arweave/paths',
          'version': '0.2.0',
          'index': {'path': 'index.html'},
          'paths': {
            for (var i = 0; i < 50; i++) 'file$i.html': {'id': 'x' * 43},
          },
        })),
      );
      final (metadata, preparation, _) = await prepare(
        'manifest.json',
        manifest,
        contentType: 'application/x.arweave-manifest+json',
      );

      expect(tag(metadata, _contentEncoding), isNull);
      expect(metadata.toJson().containsKey('dataContentEncoding'), isFalse);
      expect(preparation.dataSignedDataItemResult!.dataSize, manifest.length);
    });
  });

  group('prepareDataItems without the flag', () {
    test('is what it was: no tag, the file as it is', () async {
      final (metadata, preparation, _) =
          await prepare('app.js', script, compress: false);

      expect(tag(metadata, _contentEncoding), isNull);
      expect(metadata.toJson().containsKey('dataContentEncoding'), isFalse);
      final signed = preparation.dataSignedDataItemResult!;
      expect(signed.dataSize, script.length);
      expect(_endsWith(await _bytesOf(signed), script), isTrue);
      expect(metadata.toJson()['size'], script.length);
    });

    test('the tags are the ones it always had', () async {
      final (on, _, _) = await prepare('app.js', script);
      final (off, _, _) = await prepare('app.js', script, compress: false);

      final onNames = [for (final t in on.getDataTags()) t.name];
      final offTags = {for (final t in off.getDataTags()) t.name: t.value};
      expect(onNames.where((n) => n == _contentEncoding), hasLength(1));
      expect(offTags.containsKey(_contentEncoding), isFalse);
      // Compressing adds one tag and changes none.
      for (final t
          in on.getDataTags().where((t) => t.name != _contentEncoding)) {
        if (t.name == 'Unix-Time') continue;
        expect(offTags[t.name], t.value, reason: t.name);
      }
    });
  });

  group('prepareDataItems with thumbnails', () {
    test(
        'when none can be made, the signed metadata names none, even ones '
        'an earlier try listed', () async {
      final file = await IOFile.fromData(
        noise,
        name: 'photo.jpg',
        lastModifiedDate: DateTime(2026, 11, 16),
        contentType: 'image/jpeg',
      );
      final metadata = await generator.generateMetadata(
        file,
        arguments: ARFSUploadMetadataArgs(
          isPrivate: false,
          type: UploadType.turbo,
          driveId: 'drive-id',
          parentFolderId: 'folder-id',
        ),
      ) as ARFSFileUploadMetadata;
      // What an earlier preparation of the same file left behind.
      metadata.updateThumbnailInfo([
        ThumbnailUploadMetadata(
          contentType: 'image/jpeg',
          height: 66,
          width: 100,
          size: 5000,
          relatesTo: 'old-data-tx',
          name: 'small',
          originalFileId: metadata.id,
        )..setTxId = 'never-uploaded',
      ]);

      // Noise is no image, so no thumbnail can be made from it.
      final preparation = await prepareDataItems(
        file: file,
        metadata: metadata,
        wallet: wallet,
        addThumbnail: true,
      );

      expect(preparation.thumbnails, isEmpty);
      expect(metadata.thumbnailInfo, isNull);
      expect((await signedMetadata(preparation)).containsKey('thumbnail'),
          isFalse);
    });
  });

  group('prepareDataItems on a private drive', () {
    test('never compresses, flag or not', () async {
      final driveKey = SecretKey(List<int>.generate(32, (i) => i));
      final (metadata, preparation, _) = await prepare(
        'app.js',
        script,
        isPrivate: true,
        driveKey: driveKey,
      );

      expect(tag(metadata, _contentEncoding), isNull);
      expect(metadata.toJson().containsKey('dataContentEncoding'), isFalse);
      expect(tag(metadata, 'Cipher'), isNotNull);
      expect(preparation.dataSignedDataItemResult!.dataSize,
          greaterThanOrEqualTo(script.length));
    });

    test('the flag alone, with no key, is not enough on a private file',
        () async {
      final (metadata, _, _) = await prepare('app.js', script, isPrivate: true);
      expect(tag(metadata, _contentEncoding), isNull);
      expect(metadata.toJson().containsKey('dataContentEncoding'), isFalse);
    });
  });

  group('ARFSUploadMetadataArgs', () {
    test('does not compress unless it is asked to', () {
      final args = ARFSUploadMetadataArgs(
        isPrivate: false,
        type: UploadType.turbo,
      );
      expect(args.compressDeployment, isFalse);
      expect(
        ARFSUploadMetadataArgs.file(
          driveId: 'd',
          parentFolderId: 'p',
          isPrivate: false,
          type: UploadType.d2n,
        ).compressDeployment,
        isFalse,
      );
    });
  });
}
