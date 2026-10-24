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
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' show decodeBase64ToString;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
  int failOnTurboPost = -1;

  @override
  Future<void> postToTurbo(DataItem item, Wallet wallet) async {
    if (turbo.length == failOnTurboPost) {
      failOnTurboPost = -1;
      throw Exception('connection reset');
    }
    turbo.add(item);
  }

  @override
  Future<String> postBundle(
    List<DataItem> items,
    Wallet wallet, {
    void Function(String txId)? onPosted,
  }) async {
    bundles.add(items);
    onPosted?.call('BUNDLE');
    return 'BUNDLE';
  }
}

class _SnapshotUploader implements DriveStateUploader {
  int calls = 0;

  @override
  Future<DriveStateUploadResult> publish(
    PreparedDriveStateArtifact artifact, {
    required UploadMethod method,
  }) async {
    calls++;
    return const DriveStateUploadResult.published(_snapshotId, tags: {
      'Entity-Type': 'drive-state',
      'Drive-Id': _drive,
      'Unix-Time': '1792800000',
    });
  }
}

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
        folderId: null,
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
    expect(config.snapshot.txId, _snapshotId);
    expect(config.snapshot.tags['Unix-Time'], '1792800000');
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
}
