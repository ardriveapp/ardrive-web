import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_entity.dart';
import 'package:ardrive/drive_state/domain/drive_state_uploader.dart';
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/publication/data/publication_uploader.dart';
import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/domain/publication_publisher.dart';
import 'package:ardrive/turbo/services/upload_service.dart'
    show TurboPaymentRequiredException;
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' show decodeBase64ToString;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../test_utils/utils.dart';

const _gateway = 'https://turbo-gateway.com';
const _drive = 'c863be1f-a725-4554-9a9e-18268ed8a035';
const _root = '41520b33-28c1-4892-886b-b845a5709085';
const _owner = 'iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA';
const _snapshotId = 'SNAPSHOT_TX_ID_0000000000000000000000000000';
const _existingIcon = 'EXISTING_ICON_00000000000000000000000000000';

/// Records what would reach the network; signs for real, so IDs are real.
class _RecordingUploader extends PublicationUploader {
  _RecordingUploader()
      : super(
          arweave: MockArweaveService(),
          turboUploadService: MockTurboUploadService(),
        );

  final turbo = <DataItem>[];
  final bundles = <List<DataItem>>[];
  final uploads = <String>[];
  int failOnTurboPost = -1;

  /// What the failing Turbo post or bundle upload throws.
  Object turboError = Exception('connection reset');
  Object bundleError = Exception('chunk 3 rejected');

  /// Fails the next bundle upload after its header is accepted.
  bool failBundleAfterHeader = false;

  @override
  Future<void> postToTurbo(DataItem item, Wallet wallet) async {
    if (turbo.length == failOnTurboPost) {
      failOnTurboPost = -1;
      throw turboError;
    }
    turbo.add(item);
  }

  @override
  Future<Transaction> prepareBundle(List<DataItem> items, Wallet wallet) async {
    bundles.add(items);
    final tx = _MockTransaction();
    when(() => tx.id).thenReturn('BUNDLE${bundles.length}');
    return tx;
  }

  @override
  Future<void> uploadBundle(Transaction bundle,
      {void Function()? onPosted}) async {
    uploads.add(bundle.id);
    onPosted?.call();
    if (failBundleAfterHeader) {
      failBundleAfterHeader = false;
      throw bundleError;
    }
  }
}

class _MockTransaction extends Mock implements Transaction {}

class _SnapshotUploader implements DriveStateUploader {
  int calls = 0;
  int resumes = 0;

  /// The first publish ends uncertain: header accepted, chunks failed.
  bool uncertainFirst = false;

  @override
  Future<DriveStateUploadResult> publish(
    PreparedDriveStateArtifact artifact, {
    required UploadMethod method,
  }) async {
    calls++;
    if (uncertainFirst) {
      uncertainFirst = false;
      return DriveStateUploadResult.uncertain(
        txId: _snapshotId,
        reason: 'chunks failed',
        tags: _snapshotTags,
        resume: () async {
          resumes++;
          return const DriveStateUploadResult.published(_snapshotId,
              tags: _snapshotTags);
        },
      );
    }
    return const DriveStateUploadResult.published(_snapshotId,
        tags: _snapshotTags);
  }
}

const _snapshotTags = {
  'Entity-Type': 'drive-state',
  'Drive-Id': _drive,
  'Unix-Time': '1792800000',
};

const _fileId = 'f1e2d3c4-0000-4000-8000-000000000001';
const _fileData = 'FILEdata00000000000000000000000000000000000';
const _fileMeta = 'FILEmeta00000000000000000000000000000000000';

Map<String, String> _tags(DataItem item) => {
      for (final t in item.tags)
        decodeBase64ToString(t.name): decodeBase64ToString(t.value),
    };

String _text(DataItem item) => utf8.decode(item.data);

void main() {
  late _RecordingUploader uploader;
  late _SnapshotUploader snapshots;
  late PublicationPublisher publisher;
  final wallet = getTestWallet();

  const release = PublicationRelease(
    manifestId: 'RELEASE_MANIFEST_00000000000000000000000000',
    manifest: {
      'manifest': 'arweave/paths',
      'version': '0.2.0',
      'index': {'path': 'index.html'},
      'paths': {
        'index.html': {'id': 'RELEASE_INDEX'},
        'main.dart.js': {'id': 'MAIN'},
      },
    },
    indexHtml:
        '<!DOCTYPE html>\n<html>\n  <head>\n    <meta charset="UTF-8" />\n'
        '    <title>ArDrive</title>\n  </head>\n  <body>\n  </body>\n</html>\n',
    version: '2.91.0',
  );

  PublicationJob job({
    UploadMethod method = UploadMethod.turbo,
    PublicationSnapshotPlan? snapshot,
    PublicationImage? icon,
  }) =>
      PublicationJob(
        publicationId: '5f0c8b5e-7f53-4c31-9a3e-2f1d4c8b6a90',
        driveId: _drive,
        rootFolderId: _root,
        scope: const PublicationDriveScope(),
        owner: _owner,
        ownerName: 'Phil',
        title: 'Phil’s <Archive>',
        description: 'Photos and notes.',
        keywords: const ['photos', 'notes'],
        license: const {
          'name': 'Attribution',
          'shortName': 'CC-BY',
          'definitionTxId': 'mSOFUrl5mUQvG7VBP36DD39kzJASv9FDe3NX5hB3sYk',
        },
        icon: icon ??
            NewPublicationImage({
              'icon-32.png': Uint8List.fromList([1]),
              'icon-180.png': Uint8List.fromList([2]),
              'icon-512.png': Uint8List.fromList([3]),
            }),
        cover: null,
        social: NewPublicationImage({
          'social.jpg': Uint8List.fromList([4])
        }),
        snapshot: snapshot ??
            NewSnapshot(PreparedDriveStateArtifact(
              entity: DriveStateEntity(
                id: 'artifact-id',
                driveId: _drive,
                blockEnd: 1,
                dataStart: 0,
                dataEnd: 1,
                entityCount: 3,
              ),
              driveId: _drive,
              driveName: 'Drive',
              entityCount: 3,
              sizeInBytes: 5000,
            )),
        release: release,
        files: const [
          (path: ['a.txt'], id: 'A_DATA'),
        ],
        fileCount: 1,
        labels: const PublicationLabels(
          filesPage: 'All files',
          openPage: 'Open the page',
          moreFiles: 'And {count} more files.',
        ),
        method: method,
      );

  setUpAll(() {
    PackageInfo.setMockInitialValues(
      appName: 'ArDrive',
      packageName: 'ardrive',
      version: '2.91.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  setUp(() {
    uploader = _RecordingUploader();
    snapshots = _SnapshotUploader();
    publisher = PublicationPublisher(
      uploader: uploader,
      driveStateUploader: snapshots,
      repository: PublicationRepository(
        graphQLRetry: MockGraphQLRetry(),
        gatewayUrl: () => _gateway,
      ),
      gatewayUrl: () => _gateway,
      client: MockClient((_) async => http.Response('', 200)),
      now: () => DateTime.utc(2026, 10, 24, 12),
    );
  });

  test('Turbo: the snapshot, then images, pages and the manifest last',
      () async {
    final steps = <PublicationStep>[];
    final version = await publisher.publish(job(), wallet, onStep: steps.add);

    expect(snapshots.calls, 1);
    expect(steps, [
      PublicationStep.snapshot,
      PublicationStep.files,
      PublicationStep.publication,
      PublicationStep.warmUp,
    ]);
    final posted = {for (final item in uploader.turbo) item.id: item};
    final order = [for (final item in uploader.turbo) _tags(item)];
    expect(order.map((t) => t['Content-Type']), [
      'image/png',
      'image/png',
      'image/png',
      'image/jpeg',
      'application/json',
      'text/html',
      'text/html',
      'application/xml',
      'application/x.arweave-manifest+json',
    ]);

    final manifest = uploader.turbo.last;
    expect(version.txId, manifest.id);
    final paths = (json.decode(_text(manifest))['paths'] as Map)
        .map((k, v) => MapEntry(k as String, (v as Map)['id'] as String));
    expect(paths['snapshot'], _snapshotId);
    expect(paths['main.dart.js'], 'MAIN');
    for (final path in [
      'icon-32.png',
      'social.jpg',
      'publication.json',
      'index.html',
      'files.html',
      'sitemap.xml',
    ]) {
      expect(posted.containsKey(paths[path]), isTrue, reason: path);
    }
    expect(
        json.decode(_text(manifest))['fallback'], {'id': paths['index.html']});

    final index = _text(posted[paths['index.html']]!);
    expect(
        index,
        contains(
            '<meta property="og:image" content="$_gateway/${paths['social.jpg']}">'));
    expect(index, contains('<title>Phil’s &lt;Archive&gt;</title>'));
    expect(index,
        contains('<noscript><a href="files.html">All files</a></noscript>'));

    final config =
        PublicationConfig.parse(_text(posted[paths['publication.json']]!));
    expect(config.snapshot!.txId, _snapshotId);
    expect(config.snapshot!.tags['Unix-Time'], '1792800000');
    expect(config.ownerName, 'Phil');
    expect(config.fileCount, 1);
    expect(config.license?.shortName, 'CC-BY');
    expect(config.viewer?.manifest, release.manifestId);
    expect(config.publishedAt, DateTime.utc(2026, 10, 24, 12));

    final tags = _tags(manifest);
    expect(tags['Entity-Type'], 'publication');
    expect(tags['Publication-Id'], '5f0c8b5e-7f53-4c31-9a3e-2f1d4c8b6a90');
    expect(tags['Publication-Scope'], 'drive');
    expect(tags['ArFS'], '0.15');
    expect(tags['App-Name'], 'ArDrive-App');
    expect(
      manifest.tags
          .where((t) => decodeBase64ToString(t.name) == 'Keyword')
          .map((t) => decodeBase64ToString(t.value)),
      ['photos', 'notes'],
    );
    for (final item in uploader.turbo.take(8)) {
      expect(_tags(item)['Publication-Id'],
          '5f0c8b5e-7f53-4c31-9a3e-2f1d4c8b6a90');
      expect(_tags(item).containsKey('Entity-Type'), isFalse);
    }
  });

  PublicationJob fileJob(
          {Map<String, Object>? file, String privacy = 'public'}) =>
      PublicationJob(
        publicationId: '7a1c8b5e-7f53-4c31-9a3e-2f1d4c8b6a91',
        driveId: _drive,
        rootFolderId: _root,
        scope: const PublicationFileScope(_fileId),
        privacy: privacy,
        file: file ??
            {
              'dataTxId': _fileData,
              'metadataTxId': _fileMeta,
              'name': 'Lake.jpg',
              'size': 2048,
              'contentType': 'image/jpeg',
            },
        owner: _owner,
        ownerName: null,
        license: null,
        title: 'A lake',
        description: 'Taken at dawn.',
        keywords: const [],
        icon: null,
        cover: null,
        social: NewPublicationImage({
          'social.jpg': Uint8List.fromList([4])
        }),
        snapshot: const NoSnapshot(),
        release: release,
        files: const [],
        fileCount: 0,
        labels: const PublicationLabels(
          filesPage: 'All files',
          openPage: 'Open the page',
          moreFiles: 'And {count} more files.',
        ),
        method: UploadMethod.turbo,
      );

  test('a file page: no snapshot, no file list, tagged with its file',
      () async {
    final steps = <PublicationStep>[];
    final version =
        await publisher.publish(fileJob(), wallet, onStep: steps.add);

    expect(snapshots.calls, 0);
    expect(steps, isNot(contains(PublicationStep.snapshot)));
    expect(version.scope, const PublicationFileScope(_fileId));
    final manifest = uploader.turbo.last;
    final paths = (json.decode(_text(manifest))['paths'] as Map)
        .map((k, v) => MapEntry(k as String, (v as Map)['id'] as String));
    expect(paths.keys, isNot(contains('snapshot')));
    expect(paths.keys, isNot(contains('files.html')));
    expect(paths.keys, isNot(contains('sitemap.xml')));
    final posted = {for (final item in uploader.turbo) item.id: item};
    final index = _text(posted[paths['index.html']]!);
    expect(index, isNot(contains('files.html')));

    final config =
        PublicationConfig.parse(_text(posted[paths['publication.json']]!));
    expect(config.scope, const PublicationFileScope(_fileId));
    expect(config.file!.dataTxId, _fileData);

    final tags = _tags(manifest);
    expect(tags['Publication-Scope'], 'file');
    expect(tags['Publication-File-Id'], _fileId);
    // File lookups match File-Id and the owner alone: the page would be
    // found in place of the file.
    expect(tags.containsKey('File-Id'), isFalse);
    expect(tags['Publication-Version'], '2');
  });

  test('a private file page uploads nothing that names its file', () async {
    await publisher.publish(
      fileJob(
        privacy: 'private',
        file: {
          'dataTxId': _fileData,
          'metadataTxId': _fileMeta,
          'cipher': 'AES256-GCM',
          'cipherIv': 'aXZpdml2aXZpdml2',
        },
      ),
      wallet,
    );
    for (final item in uploader.turbo) {
      expect(utf8.decode(item.data, allowMalformed: true),
          isNot(contains('Lake.jpg')));
      expect(_tags(item).values, isNot(contains('Lake.jpg')));
    }
    final manifest = uploader.turbo.last;
    final paths = (json.decode(_text(manifest))['paths'] as Map)
        .map((k, v) => MapEntry(k as String, (v as Map)['id'] as String));
    final posted = {for (final item in uploader.turbo) item.id: item};
    final config =
        PublicationConfig.parse(_text(posted[paths['publication.json']]!));
    expect(config.isPrivate, isTrue);
    expect(config.file!.cipher, 'AES256-GCM');
  });

  test('a retry posts only what did not go, and pays for nothing twice',
      () async {
    final theJob = job();
    uploader.failOnTurboPost = 5;
    await expectLater(
      publisher.publish(theJob, wallet),
      throwsA(isA<PublicationFailure>()
          .having((f) => f.step, 'step', PublicationStep.publication)),
    );
    expect(uploader.turbo, hasLength(5));
    final firstIds = [for (final item in uploader.turbo) item.id];

    final version = await publisher.publish(theJob, wallet);
    expect(snapshots.calls, 1, reason: 'the snapshot is not published again');
    expect(uploader.turbo, hasLength(9));
    expect([for (final item in uploader.turbo.take(5)) item.id], firstIds);
    expect(uploader.turbo.map((i) => i.id).toSet(), hasLength(9),
        reason: 'no repeats');
    expect(version.txId, uploader.turbo.last.id);
  });

  test('AR: every file in one bundle', () async {
    await publisher.publish(job(method: UploadMethod.ar), wallet);
    expect(uploader.turbo, isEmpty);
    expect(uploader.bundles, hasLength(1));
    expect(uploader.bundles.single, hasLength(9));
  });

  test('AR: a bundle whose chunks failed is finished, not paid for again',
      () async {
    final theJob = job(method: UploadMethod.ar);
    uploader.failBundleAfterHeader = true;
    await expectLater(
      publisher.publish(theJob, wallet),
      throwsA(isA<PublicationFailure>()
          .having((f) => f.paidTxId, 'paidTxId', 'BUNDLE1')),
    );
    final version = await publisher.publish(theJob, wallet);
    expect(uploader.bundles, hasLength(1), reason: 'signed and paid once');
    expect(uploader.uploads, ['BUNDLE1', 'BUNDLE1'],
        reason: 'the same transaction sent again');
    expect(version.txId, isNotEmpty);
  });

  test(
      'a snapshot that reached the network half-sent is resumed, not bought '
      'again', () async {
    snapshots.uncertainFirst = true;
    final theJob = job();
    await expectLater(
      publisher.publish(theJob, wallet),
      throwsA(isA<PublicationFailure>()
          .having((f) => f.step, 'step', PublicationStep.snapshot)
          .having((f) => f.paidTxId, 'paidTxId', _snapshotId)
          .having((f) => f.canRetry, 'canRetry', true)),
    );
    await publisher.publish(theJob, wallet);
    expect(snapshots.calls, 1);
    expect(snapshots.resumes, 1);
  });

  test('switching to AR after a Turbo failure keeps what was sent', () async {
    final theJob = job();
    uploader.failOnTurboPost = 5;
    await expectLater(
        publisher.publish(theJob, wallet), throwsA(isA<PublicationFailure>()));
    await publisher.publish(theJob.withMethod(UploadMethod.ar), wallet);
    expect(snapshots.calls, 1, reason: 'the snapshot is kept');
    expect(uploader.bundles.single, hasLength(4),
        reason: 'only what Turbo had not taken');
  });

  test('a reused snapshot and an earlier icon are not uploaded again',
      () async {
    await publisher.publish(
      job(
        snapshot: const ReusedSnapshot(txId: 'OLD_SNAPSHOT', tags: {'A': 'b'}),
        icon: const ExistingPublicationImage({
          'icon-32.png': _existingIcon,
          'icon-180.png': _existingIcon,
          'icon-512.png': _existingIcon,
        }),
      ),
      wallet,
    );
    expect(snapshots.calls, 0);
    expect(uploader.turbo, hasLength(6), reason: 'social, 4 pages, manifest');
    final paths = json.decode(_text(uploader.turbo.last))['paths'] as Map;
    expect(paths['snapshot'], {'id': 'OLD_SNAPSHOT'});
    expect(paths['icon-180.png'], {'id': _existingIcon});
  });

  test('the size counts a new snapshot and every file', () {
    final withNew = publisher.sizeOf(job());
    final withReused = publisher
        .sizeOf(job(snapshot: const ReusedSnapshot(txId: 'OLD', tags: {})));
    expect(withNew - withReused, greaterThanOrEqualTo(5000));
    expect(withReused, greaterThan(9 * 1100));
  });

  test('a job priced again keeps the snapshot an attempt already sent',
      () async {
    final first = job();
    uploader.failOnTurboPost = 2;
    await expectLater(
        publisher.publish(first, wallet), throwsA(isA<PublicationFailure>()));
    expect(snapshots.calls, 1);

    // The owner went back to the look and priced again: a new job.
    final again = job(snapshot: first.snapshot).carrySnapshotFrom(first);
    expect(
      publisher.sizeOf(again),
      publisher.sizeOf(job(
          snapshot:
              const ReusedSnapshot(txId: _snapshotId, tags: _snapshotTags))),
      reason: 'priced like a reused snapshot: the sent one is not paid again',
    );
    await publisher.publish(again, wallet);
    expect(snapshots.calls, 1, reason: 'the snapshot is not bought again');
  });

  test('a job priced again finishes a half-sent snapshot, not a new one',
      () async {
    snapshots.uncertainFirst = true;
    final first = job();
    await expectLater(
        publisher.publish(first, wallet), throwsA(isA<PublicationFailure>()));

    final again = job(snapshot: first.snapshot).carrySnapshotFrom(first);
    await publisher.publish(again, wallet);
    expect(snapshots.calls, 1);
    expect(snapshots.resumes, 1);
  });

  test('Turbo refusing payment is a declined payment', () async {
    uploader
      ..failOnTurboPost = 0
      ..turboError = TurboPaymentRequiredException();
    await expectLater(
      publisher.publish(job(), wallet),
      throwsA(isA<PublicationFailure>()
          .having((f) => f.paymentDeclined, 'paymentDeclined', isTrue)),
    );
  });

  test('an AR error that mentions 402 is not a declined Turbo payment',
      () async {
    uploader
      ..failBundleAfterHeader = true
      ..bundleError = Exception('HTTP 402 PaymentRequired from a node');
    await expectLater(
      publisher.publish(job(method: UploadMethod.ar), wallet),
      throwsA(isA<PublicationFailure>()
          .having((f) => f.paymentDeclined, 'paymentDeclined', isFalse)
          .having(
              (f) => f.message, 'message', isNot(contains('Turbo declined')))),
    );
  });

  test('each item is sized on its own, the new snapshot among them', () {
    final sizes = publisher.itemSizesOf(job());
    // Four images, four pages, the manifest and the snapshot.
    expect(sizes, hasLength(10));
    expect(sizes.last, 5000 + 1100);
    expect(sizes.reduce((a, b) => a + b), publisher.sizeOf(job()));
    final reused = publisher.itemSizesOf(
        job(snapshot: const ReusedSnapshot(txId: 'OLD', tags: {})));
    expect(reused, hasLength(9));
    expect(reused.every((size) => size < 100000), isTrue);
  });

  group('the gateway', () {
    PublicationPublisher on(MockClient client) => PublicationPublisher(
          uploader: uploader,
          driveStateUploader: snapshots,
          repository: PublicationRepository(
            graphQLRetry: MockGraphQLRetry(),
            gatewayUrl: () => 'https://ardrive.net',
          ),
          gatewayUrl: () => 'https://ardrive.net',
          client: client,
          now: () => DateTime.utc(2026, 10, 24, 12),
        );

    test('a snapshot serves when the gateway hands it over', () async {
      final asked = <String>[];
      final serving = on(MockClient((request) async {
        asked.add('${request.method} ${request.url}');
        return switch (request.url.path) {
          '/raw/GOOD' => http.Response('', 200, headers: {
              'content-length': '17714',
            }),
          '/raw/EMPTY' => http.Response('', 200, headers: {
              'content-length': '0',
            }),
          _ => http.Response('', 404),
        };
      }));
      expect(await serving.snapshotServes('GOOD'), isTrue);
      expect(await serving.snapshotServes('MISSING'), isFalse);
      expect(await serving.snapshotServes('EMPTY'), isFalse);
      expect(asked.first, 'HEAD https://ardrive.net/raw/GOOD');
      expect(
          await on(MockClient((_) async => throw Exception('offline')))
              .snapshotServes('GOOD'),
          isFalse);
    });

    test('every link written into the page, and the warm-up, use it', () async {
      final warmed = <String>[];
      final version = await on(MockClient((request) async {
        warmed.add(request.url.toString());
        return http.Response('', 200);
      })).publish(job(), wallet);
      final posted = {for (final item in uploader.turbo) item.id: item};
      final paths = (json.decode(_text(uploader.turbo.last))['paths'] as Map)
          .map((k, v) => MapEntry(k as String, (v as Map)['id'] as String));
      expect(_text(posted[paths['index.html']]!),
          contains('content="https://ardrive.net/${paths['social.jpg']}"'));
      expect(_text(posted[paths['files.html']]!),
          contains('href="https://ardrive.net/A_DATA"'));
      expect(_text(posted[paths['sitemap.xml']]!),
          contains('<loc>https://ardrive.net/A_DATA</loc>'));
      expect(
          warmed,
          unorderedEquals([
            'https://ardrive.net/${version.txId}/',
            'https://ardrive.net/${version.txId}/publication.json',
            'https://ardrive.net/${version.txId}/snapshot',
          ]));
    });
  });

  test('a Turbo post that hangs stops, and Try again finishes the job',
      () async {
    registerFallbackValue(DataItem.withBlobData(data: Uint8List(0)));
    registerFallbackValue(wallet);
    final turbo = MockTurboUploadService();
    var calls = 0;
    when(() => turbo.postDataItem(
          dataItem: any(named: 'dataItem'),
          wallet: any(named: 'wallet'),
        )).thenAnswer((_) {
      // The first post never answers.
      return calls++ == 0 ? Completer<void>().future : Future.value();
    });
    final hanging = PublicationPublisher(
      uploader: PublicationUploader(
        arweave: MockArweaveService(),
        turboUploadService: turbo,
        turboTimeout: const Duration(milliseconds: 50),
      ),
      driveStateUploader: snapshots,
      repository: PublicationRepository(
        graphQLRetry: MockGraphQLRetry(),
        gatewayUrl: () => _gateway,
      ),
      gatewayUrl: () => _gateway,
      client: MockClient((_) async => http.Response('', 200)),
    );
    final theJob = job(snapshot: const ReusedSnapshot(txId: 'S', tags: {}));
    await expectLater(
      hanging.publish(theJob, wallet),
      throwsA(isA<PublicationFailure>()
          .having((f) => f.canRetry, 'canRetry', isTrue)),
    );
    final version = await hanging.publish(theJob, wallet);
    expect(version.txId, theJob.manifestTxId);
  });
}
