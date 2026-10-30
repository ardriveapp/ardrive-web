import 'dart:async';
import 'dart:ui' as ui;

import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog_cubit.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/drive_state/data/drive_state_discovery.dart';
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_entity.dart';
import 'package:ardrive/drive_state/domain/drive_state_publish_cost.dart';
import 'package:ardrive/drive_state/domain/drive_state_sync_skip_status.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/domain/publication_publisher.dart';
import 'package:ardrive/publication/presentation/publish/publish_cubit.dart';
import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:ardrive/services/license/license.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive_utils/ardrive_utils.dart' show DrivePrivacyTag;
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_utils/fake_user.dart';
import '../../test_utils/utils.dart';
import '../publication_test_files.dart';

const _drive = 'c863be1f-a725-4554-9a9e-18268ed8a035';
const _root = '41520b33-28c1-4892-886b-b845a5709085';
const _folder = 'aaaaaaaa-0000-4000-8000-000000000001';
const _hiddenFolder = '99999999-0000-4000-8000-000000000007';
const _release = 'RELEASE_MANIFEST_00000000000000000000000000';

class _Repository extends Mock implements PublicationRepository {}

class _Publisher extends Mock implements PublicationPublisher {}

class _Names extends Mock implements ArNSFlowNameCubit {}

class _Creation extends Mock implements DriveStateCreationService {}

class _Estimator extends Mock implements DriveStatePublishCostEstimator {}

class _Skip implements DriveStateSyncSkipSource {
  DriveStateSyncSkipStatus status = const DriveStateSyncSkipStatus.clean();

  @override
  DriveStateSyncSkipStatus statusFor(String driveId) => status;
}

class _Discovery implements DriveStateDiscovery {
  List<DriveStateArtifactCandidate> candidates = [];

  @override
  Future<DriveStateDiscoveryResult> findCandidates({
    required String driveId,
    required String ownerAddress,
    int? minBlockHeight,
  }) async =>
      DriveStateDiscoveryResult(candidates: candidates);
}

DriveStatePublishCost _cost() => DriveStatePublishCost(
      costEstimateAr: UploadCostEstimate.zero(),
      costEstimateTurbo: UploadCostEstimate.zero(),
      isTurboUploadPossible: true,
      hasNoTurboBalance: false,
      arBalance: '1',
      turboCredits: '1',
      sufficientArBalance: true,
      sufficientTurboBalance: true,
      freeStatus: FreeUploadStatus.notEligible,
    );

void main() {
  late Database db;
  late Drive drive;
  late _Repository repository;
  late _Publisher publisher;
  late _Creation creation;
  late _Estimator estimator;
  late _Skip skip;
  late _Discovery discovery;
  late MockProfileCubit profile;
  final guard = <String>[];

  setUpAll(() {
    registerFallbackValue(getTestWallet());
    registerFallbackValue(BigInt.zero);
    registerFallbackValue(PublicationJob(
      publicationId: 'p',
      driveId: _drive,
      rootFolderId: _root,
      folderId: null,
      owner: 'o',
      ownerName: null,
      title: 't',
      description: '',
      keywords: const [],
      license: null,
      icon: null,
      cover: null,
      social: const ExistingPublicationImage({}),
      snapshot: const ReusedSnapshot(txId: 's', tags: {}),
      release: const PublicationRelease(
          manifestId: _release, manifest: {}, indexHtml: '', version: null),
      files: const [],
      fileCount: 0,
      labels: const PublicationLabels(
          filesPage: 'a', openPage: 'b', moreFiles: 'c'),
      method: UploadMethod.turbo,
    ));
  });

  Future<void> folder(String id, String? parent, {bool hidden = false}) =>
      db.into(db.folderEntries).insert(FolderEntriesCompanion.insert(
            id: id,
            driveId: _drive,
            name: id == _root ? 'My drive' : 'Projects',
            parentFolderId: Value(parent),
            isHidden: Value(hidden),
            path: '',
          ));

  setUp(() async {
    guard.clear();
    SharedPreferences.setMockInitialValues({});
    db = getTestDb();
    await db.into(db.drives).insert(DrivesCompanion.insert(
          id: _drive,
          rootFolderId: _root,
          ownerAddress: fakeUserJson.walletAddress,
          name: 'My drive',
          privacy: DrivePrivacyTag.public,
        ));
    drive = await db.driveDao.driveById(driveId: _drive).getSingle();
    await folder(_root, null);
    await folder(_folder, _root);
    await folder(_hiddenFolder, _root, hidden: true);
    await insertPublicationFile(db,
        driveId: _drive, id: 'a', name: 'a.txt', parentFolderId: _root);
    await insertPublicationFile(db,
        driveId: _drive, id: 'b', name: 'b.txt', parentFolderId: _folder);

    repository = _Repository();
    publisher = _Publisher();
    creation = _Creation();
    estimator = _Estimator();
    skip = _Skip();
    discovery = _Discovery();
    profile = MockProfileCubit();
    when(() => profile.state)
        .thenReturn(ProfileLoggedIn(user: fakeUserJson, useTurbo: true));
    when(() => profile.logoutIfWalletMismatch()).thenAnswer((_) async => false);
    when(() => repository.readRelease(any())).thenAnswer((_) async =>
        const PublicationRelease(
            manifestId: _release,
            manifest: {},
            indexHtml: '',
            version: '2.91.0'));
    when(() => publisher.sizeOf(any())).thenReturn(5000);
    when(() => publisher.itemSizesOf(any())).thenReturn([2000, 3000]);
    when(() => publisher.snapshotServes(any())).thenAnswer((_) async => true);
    when(() => publisher.gatewayUrl).thenReturn('https://turbo-gateway.com');
    when(() => estimator.estimate(
          sizeInBytes: any(named: 'sizeInBytes'),
          itemSizes: any(named: 'itemSizes'),
          wallet: any(named: 'wallet'),
          walletBalance: any(named: 'walletBalance'),
        )).thenAnswer((_) async => _cost());
  });

  tearDown(() => db.close());

  PublishCubit cubit({
    FolderEntry? folderEntry,
    Publication? previous,
    ArNSFlowNameCubit? names,
    void Function(String? link)? onSettledAfterClose,
    Future<bool> Function(
      String driveId, {
      required bool deep,
      required bool Function() isCancelled,
    })? syncDrive,
  }) =>
      PublishCubit(
        drive: drive,
        folder: folderEntry,
        previous: previous,
        names: names,
        onSettledAfterClose: onSettledAfterClose,
        holdGuard: (_) => guard.add('hold'),
        releaseGuard: (_) => guard.add('release'),
        dependencies: PublishDependencies(
          driveDao: db.driveDao,
          profileCubit: profile,
          syncSkipSource: skip,
          repository: repository,
          publisher: publisher,
          creationService: creation,
          discovery: discovery,
          costEstimator: estimator,
          viewer: 'ardrive',
          labels: const PublicationLabels(
              filesPage: 'All files', openPage: 'Open', moreFiles: '{count}'),
          cardMark: () async {
            final recorder = ui.PictureRecorder();
            ui.Canvas(recorder);
            return recorder.endRecording().toImage(4, 4);
          },
          fileCountLabel: (n) => '$n files',
          syncDrive: syncDrive,
        ),
      );

  DriveStateArtifactCandidate freshSnapshot() => DriveStateArtifactCandidate(
        txId: 'NEWEST',
        ownerAddress: fakeUserJson.walletAddress,
        minedAtHeight: 100,
        tags: {
          'Drive-Id': _drive,
          'Entity-Type': 'drive-state',
          'State-Version': '0.2',
          'Entity-Count': '3',
          'Unix-Time': '${DateTime.now().millisecondsSinceEpoch ~/ 1000 + 60}',
        },
      );

  PublishedVersion latest() => PublishedVersion(
        txId: 'LATEST',
        publicationId: 'pub-1',
        driveId: _drive,
        folderId: null,
        publishedAt: DateTime.utc(2026, 10, 20),
      );

  PublishedContent content({
    required bool generatedCard,
    String license = '',
  }) =>
      PublishedContent(
        config: PublicationConfig.parse('''
{"version":1,"driveId":"$_drive","rootFolderId":"$_root",
 "scope":{"type":"drive"},"privacy":"public",
 "owner":"iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA",
 "snapshot":{"path":"snapshot","txId":"SNAPSHOT_TX_ID_0000000000000000000000000000","tags":{}},
 "title":"Phil's Archive","description":"Old words."$license,
 "images":{"social":"social.jpg"},"publishedAt":"2026-10-20T00:00:00Z"}'''),
        paths: const {'social.jpg': 'OLD_CARD'},
        generatedCard: generatedCard,
      );

  test('a drive that is still syncing is not offered', () async {
    skip.status = const DriveStateSyncSkipStatus.unknown('Still syncing.');
    final c = cubit();
    await c.load();
    expect(c.state.stage, PublishStage.blocked);
    expect(c.state.blocked, PublishBlock.sync);
    expect(c.state.blockedReason, 'Still syncing.');
  });

  group('Sync drive, from a dialog blocked by sync', () {
    test('syncs the drive and checks it again', () async {
      skip.status = const DriveStateSyncSkipStatus.unknown('Never synced.');
      final synced = <(String, bool)>[];
      final c = cubit(
          syncDrive: (driveId, {required deep, required isCancelled}) async {
        synced.add((driveId, deep));
        skip.status = const DriveStateSyncSkipStatus.clean();
        return true;
      });
      await c.load();
      expect(c.canSyncDrive, isTrue);

      final stages = <PublishStage>[];
      final sub = c.stream.listen((s) => stages.add(s.stage));
      await c.syncDrive();
      await sub.cancel();

      expect(synced, [(_drive, false)]);
      expect(stages.first, PublishStage.syncing);
      expect(c.state.stage, PublishStage.included);
    });

    test('stays blocked, and can sync again, when the sync fails', () async {
      skip.status = const DriveStateSyncSkipStatus.unknown('Never synced.');
      final c = cubit(
          syncDrive: (_, {required deep, required isCancelled}) async =>
              throw Exception('offline'));
      await c.load();
      await c.syncDrive();

      expect(c.state.stage, PublishStage.blocked);
      expect(c.state.blocked, PublishBlock.sync);
      expect(c.canSyncDrive, isTrue);
    });

    test('re-reads the drive from its start when items were skipped', () async {
      // A plain sync starts where the last one stopped: it would clear the
      // record of the skipped items without reading them, and the page would
      // leave them out for good.
      skip.status = const DriveStateSyncSkipStatus.skipped(
          skippedEntityCount: 3, reason: 'Could not read 3 items.');
      bool? deepAsked;
      final c =
          cubit(syncDrive: (_, {required deep, required isCancelled}) async {
        deepAsked = deep;
        return true;
      });
      await c.load();
      await c.syncDrive();

      expect(deepAsked, isTrue);
    });

    test('says why when no sync could start', () async {
      skip.status = const DriveStateSyncSkipStatus.unknown('Never synced.');
      final c = cubit(
          syncDrive: (_, {required deep, required isCancelled}) async => false);
      await c.load();
      await c.syncDrive();

      expect(c.state.stage, PublishStage.blocked);
      expect(c.state.blockedReason, contains("couldn't start"));
      expect(c.canSyncDrive, isTrue);
    });

    test('tells the sync when the dialog has closed', () async {
      skip.status = const DriveStateSyncSkipStatus.unknown('Never synced.');
      final release = Completer<void>();
      bool Function()? cancelled;
      final c =
          cubit(syncDrive: (_, {required deep, required isCancelled}) async {
        cancelled = isCancelled;
        await release.future;
        return !isCancelled();
      });
      await c.load();
      final running = c.syncDrive();
      await Future<void>.delayed(Duration.zero);
      expect(cancelled!(), isFalse);
      await c.close();
      expect(cancelled!(), isTrue);
      release.complete();
      await running;
    });

    test('is not offered for other blocks, or without a way to sync', () async {
      skip.status = const DriveStateSyncSkipStatus.unknown('Never synced.');
      final c = cubit();
      await c.load();
      expect(c.canSyncDrive, isFalse, reason: 'no way to sync');

      skip.status = const DriveStateSyncSkipStatus.clean();
      final open = cubit(
          syncDrive: (_, {required deep, required isCancelled}) async => true);
      await open.load();
      expect(open.state.blocked, isNull);
      expect(open.canSyncDrive, isFalse);
    });
  });

  test('a hidden folder, unconfirmed uploads and an empty folder block',
      () async {
    final hidden =
        await db.driveDao.folderById(folderId: _hiddenFolder).getSingle();
    var c = cubit(folderEntry: hidden);
    await c.load();
    expect(c.state.blocked, PublishBlock.hiddenFolder);

    final empty = await db.driveDao.folderById(folderId: _folder).getSingle();
    await db.delete(db.fileEntries).go();
    c = cubit(folderEntry: empty);
    await c.load();
    expect(c.state.blocked, PublishBlock.empty);

    await insertPublicationFile(db,
        driveId: _drive,
        id: 'p',
        name: 'p.txt',
        parentFolderId: _root,
        status: TransactionStatus.pending);
    c = cubit();
    await c.load();
    expect(c.state.blocked, PublishBlock.pendingUploads);
  });

  // The dialog said "some uploads" and named nothing (issue #2366): it counts
  // what waits, each item once, the same items that block it.
  test('unconfirmed changes block, counted once per item', () async {
    Future<void> pendingTx(String id) => db
        .into(db.networkTransactions)
        .insertOnConflictUpdate(NetworkTransactionsCompanion.insert(
            id: id, status: const Value(TransactionStatus.pending)));

    // Two new uploads: metadata and data both pending, one item each.
    for (final id in ['p1', 'p2']) {
      await insertPublicationFile(db,
          driveId: _drive,
          id: id,
          name: '$id.txt',
          parentFolderId: _root,
          status: TransactionStatus.pending);
    }
    // A folder renamed, moved back and hidden: three pending changes, one
    // item.
    for (final (i, tx) in ['renameTx', 'moveTx', 'hideTx'].indexed) {
      await pendingTx(tx);
      await db.into(db.folderRevisions).insert(FolderRevisionsCompanion.insert(
            folderId: _folder,
            driveId: _drive,
            name: 'Projects',
            parentFolderId: const Value(_root),
            metadataTxId: tx,
            dateCreated: Value(DateTime.utc(2026, 10, 27, 18, i)),
            action: RevisionAction.rename,
          ));
    }
    // An upload into a hidden folder still blocks: a new snapshot would
    // refuse its metadata.
    await insertPublicationFile(db,
        driveId: _drive,
        id: 'h',
        name: 'h.txt',
        parentFolderId: _hiddenFolder,
        status: TransactionStatus.pending);
    // Data still on its way after its metadata was confirmed.
    await insertPublicationFile(db,
        driveId: _drive, id: 'd', name: 'd.txt', parentFolderId: _root);
    await pendingTx('dData');

    final c = cubit();
    await c.load();
    expect(c.state.blocked, PublishBlock.pendingUploads);
    expect(c.state.pendingChanges, 5,
        reason: 'p1, p2, the folder, h and d; not a or b');
  });

  test('nothing pending, nothing counted', () async {
    final c = cubit();
    await c.load();
    expect(c.state.blocked, isNull);
    expect(c.state.pendingChanges, 0);
  });

  test('the dialog opens on what is included, titled with the name', () async {
    final c = cubit();
    await c.load();
    expect(c.state.stage, PublishStage.included);
    expect(c.state.summary!.fileCount, 2);
    expect(c.state.title, 'My drive');
    c.next();
    expect(c.state.stage, PublishStage.look);
    c.setTitle('   ');
    c.next();
    expect(c.state.stage, PublishStage.look, reason: 'a title is required');
    c.setTitle('x' * 90);
    expect(c.state.title.length, publicationTitleMax);
  });

  test('keywords: five at most, no repeats', () async {
    final c = cubit();
    await c.load();
    for (final k in ['a', 'b', 'a', 'c', 'd', 'e', 'f']) {
      c.addKeyword(k);
    }
    expect(c.state.keywords, ['a', 'b', 'c', 'd', 'e']);
    c.removeKeyword('b');
    expect(c.state.keywords, ['a', 'c', 'd', 'e']);
  });

  // GraphQL lags a new version: the name just pointed at it read "Points
  // elsewhere" until it caught up.
  test('the name step is told the new version is a publication', () async {
    discovery.candidates = [freshSnapshot()];
    when(() => publisher.publish(any(), any(), onStep: any(named: 'onStep')))
        .thenAnswer((_) async => PublishedVersion(
              txId: 'MANIFEST',
              publicationId: 'p',
              driveId: _drive,
              folderId: 'folder-1',
              publishedAt: DateTime.utc(2026),
            ));
    final names = _Names();
    when(() => names.plannedNames).thenReturn(['news_acme']);
    when(() => names.hasWork).thenReturn(true);
    late PublishCubit c;
    // The name is the last step shown, and has begun once the page is up.
    final namingWhenApplied = <(List<String>, bool)>[];
    when(() => names.applyTo(any(), publication: any(named: 'publication')))
        .thenAnswer((_) async {
      namingWhenApplied.add((c.state.naming, c.state.namingStarted));
      return const ArNSFlowOutcome(live: ['news_acme']);
    });
    when(() => names.close()).thenAnswer((_) async {});

    c = cubit(names: names);
    await c.load();
    await c.review();
    final publishing = <PublishState>[];
    final sub = c.stream.listen(publishing.add);
    await c.publish();
    await sub.cancel();

    expect(c.state.stage, PublishStage.done);
    expect(publishing.first.naming, ['news_acme']);
    expect(publishing.first.namingStarted, isFalse);
    expect(namingWhenApplied, hasLength(1));
    expect(namingWhenApplied.single.$1, ['news_acme']);
    expect(namingWhenApplied.single.$2, isTrue);
    verify(() => names.applyTo(
          'MANIFEST',
          publication: const ArNSPublicationItem(
            publicationId: 'p',
            driveId: _drive,
            folderId: 'folder-1',
            isLatestVersion: true,
          ),
        )).called(1);
  });

  test('an unchanged drive reuses its newest snapshot', () async {
    // Revisions in the fixture are dated now; a snapshot made later covers
    // them.
    discovery.candidates = [freshSnapshot()];
    final c = cubit();
    await c.load();
    await c.review();
    expect(c.state.stage, PublishStage.review);
    expect(c.state.reusesSnapshot, isTrue);
    verifyNever(() => creation.prepare(
          driveId: any(named: 'driveId'),
          driveKey: any(named: 'driveKey'),
          wallet: any(named: 'wallet'),
          isCancelled: any(named: 'isCancelled'),
        ));
  });

  test('a changed drive gets a new snapshot, and publishing gives a link',
      () async {
    discovery.candidates = [
      DriveStateArtifactCandidate(
        txId: 'OLD',
        ownerAddress: fakeUserJson.walletAddress,
        tags: const {
          'Drive-Id': _drive,
          'Entity-Type': 'drive-state',
          'State-Version': '0.2',
          'Unix-Time': '1000',
        },
      ),
    ];
    when(() => creation.prepare(
          driveId: any(named: 'driveId'),
          driveKey: any(named: 'driveKey'),
          wallet: any(named: 'wallet'),
          isCancelled: any(named: 'isCancelled'),
        )).thenAnswer((_) async => DriveStateCreationResult.prepared(
          PreparedDriveStateArtifact(
            entity: DriveStateEntity(
                id: 'x',
                driveId: _drive,
                blockEnd: 1,
                dataStart: 0,
                dataEnd: 1,
                entityCount: 4),
            driveId: _drive,
            driveName: 'My drive',
            entityCount: 4,
            sizeInBytes: 900,
          ),
        ));
    when(() => publisher.publish(any(), any(), onStep: any(named: 'onStep')))
        .thenAnswer((_) async => PublishedVersion(
              txId: 'MANIFEST',
              publicationId: 'p',
              driveId: _drive,
              folderId: null,
              publishedAt: DateTime.utc(2026),
            ));
    final c = cubit();
    await c.load();
    c.setOwnerName('Phil');
    await c.review();
    expect(c.state.reusesSnapshot, isFalse);
    expect(c.state.canPublish, isTrue);
    await c.publish();
    expect(c.state.stage, PublishStage.done);
    expect(c.state.link, 'https://turbo-gateway.com/MANIFEST/');
    final job = verify(() => publisher.publish(captureAny(), any(),
        onStep: any(named: 'onStep'))).captured.single as PublicationJob;
    expect(job.snapshot, isA<NewSnapshot>());
    expect(job.ownerName, 'Phil');
    expect(job.fileCount, 2);
    expect(job.social, isA<NewPublicationImage>(),
        reason: 'the generated card');

    // The display name is offered again next time.
    final next = cubit();
    await next.load();
    expect(next.state.ownerName, 'Phil');
  });

  group('the wallet check before publishing', () {
    test('on another wallet, publishes nothing', () async {
      discovery.candidates = [freshSnapshot()];
      when(() => profile.logoutIfWalletMismatch())
          .thenAnswer((_) async => true);
      final c = cubit();
      await c.load();
      await c.review();
      await c.publish();

      expect(c.state.stage, PublishStage.review);
      verifyNever(
          () => publisher.publish(any(), any(), onStep: any(named: 'onStep')));
    });

    test(
        'Wander unavailable, then Cancel: publishes nothing, the review '
        'stays', () async {
      discovery.candidates = [freshSnapshot()];
      when(() => profile.logoutIfWalletMismatch()).thenThrow(
        const ArConnectUnavailableException(
          ArConnectUnavailableReason.noAnswer,
        ),
      );
      final c = cubit();
      await c.load();
      await c.review();
      await c.publish();

      expect(c.state.stage, PublishStage.review);
      expect(c.state.canPublish, isTrue);
      verifyNever(
          () => publisher.publish(any(), any(), onStep: any(named: 'onStep')));
    });
  });

  test('a failed publish says why and can be tried again', () async {
    discovery.candidates = [freshSnapshot()];
    var attempts = 0;
    when(() => publisher.publish(any(), any(), onStep: any(named: 'onStep')))
        .thenAnswer((_) async {
      if (attempts++ == 0) {
        throw const PublicationFailure(PublicationStep.publication, 'Nope.');
      }
      return PublishedVersion(
        txId: 'MANIFEST',
        publicationId: 'p',
        driveId: _drive,
        folderId: null,
        publishedAt: DateTime.utc(2026),
      );
    });
    final c = cubit();
    await c.load();
    await c.review();
    await c.publish();
    expect(c.state.stage, PublishStage.failed);
    expect(c.state.failure, 'Nope.');
    await c.retry();
    expect(c.state.stage, PublishStage.done);
    final jobs = verify(() => publisher.publish(captureAny(), any(),
        onStep: any(named: 'onStep'))).captured;
    expect(identical(jobs[0], jobs[1]), isTrue,
        reason: 'the same job, so nothing is paid for twice');
  });

  group('priced again after a failure, back through the look', () {
    void failOnce() {
      var attempts = 0;
      when(() => publisher.publish(any(), any(), onStep: any(named: 'onStep')))
          .thenAnswer((_) async {
        if (attempts++ == 0) {
          throw const PublicationFailure(PublicationStep.publication, 'Nope.');
        }
        return PublishedVersion(
          txId: 'MANIFEST',
          publicationId: 'p',
          driveId: _drive,
          folderId: null,
          publishedAt: DateTime.utc(2026),
        );
      });
    }

    List<PublicationJob> jobs() =>
        verify(() => publisher.publish(captureAny(), any(),
            onStep: any(named: 'onStep'))).captured.cast<PublicationJob>();

    test('an unchanged look keeps the job, with all it sent', () async {
      discovery.candidates = [freshSnapshot()];
      failOnce();
      final c = cubit();
      await c.load();
      await c.review();
      await c.publish();
      c
        ..back() // to the review
        ..back(); // to the look
      expect(c.state.stage, PublishStage.look);
      await c.review();
      await c.publish();
      expect(c.state.stage, PublishStage.done);
      final run = jobs();
      expect(identical(run[0], run[1]), isTrue,
          reason: 'nothing signed or sent is redone');
    });

    test('a changed look is a new job for the same publication', () async {
      discovery.candidates = [freshSnapshot()];
      failOnce();
      final c = cubit();
      await c.load();
      await c.review();
      await c.publish();
      c
        ..back()
        ..back()
        ..setTitle('A new title');
      await c.review();
      await c.publish();
      final run = jobs();
      expect(identical(run[0], run[1]), isFalse);
      expect(run[1].title, 'A new title');
      expect(run[1].publicationId, run[0].publicationId,
          reason: 'never a second publication of the same thing');
    });
  });

  test(
      'an update is prefilled from the published version and opens on the '
      'look', () async {
    discovery.candidates = [freshSnapshot()];
    when(() => repository.readContent('LATEST'))
        .thenAnswer((_) async => PublishedContent(
              config: PublicationConfig.parse('''
{"version":1,"driveId":"$_drive","rootFolderId":"$_root",
 "scope":{"type":"drive"},"privacy":"public",
 "owner":"iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA","ownerName":"Phil",
 "snapshot":{"path":"snapshot","txId":"SNAPSHOT_TX_ID_0000000000000000000000000000","tags":{}},
 "title":"Phil's Archive","description":"Old words.",
 "images":{"social":"social.jpg"},"publishedAt":"2026-10-20T00:00:00Z"}'''),
              paths: const {},
              keywords: const ['photos'],
            ));
    final previous = Publication([
      PublishedVersion(
        txId: 'LATEST',
        publicationId: 'pub-1',
        driveId: _drive,
        folderId: null,
        publishedAt: DateTime.utc(2026, 10, 20),
      ),
    ]);
    final c = cubit(previous: previous);
    await c.load();
    expect(c.state.isUpdate, isTrue);
    expect(c.state.title, "Phil's Archive");
    expect(c.state.description, 'Old words.');
    expect(c.state.keywords, ['photos']);
    expect(c.state.stage, PublishStage.look, reason: 'an update opens on it');
  });

  test('a pricing failure after an edit never publishes the earlier job',
      () async {
    discovery.candidates = [freshSnapshot()];
    final c = cubit();
    await c.load();
    await c.review();
    expect(c.state.stage, PublishStage.review);
    c.back();
    c.setTitle('A new title');
    when(() => estimator.estimate(
          sizeInBytes: any(named: 'sizeInBytes'),
          itemSizes: any(named: 'itemSizes'),
          wallet: any(named: 'wallet'),
          walletBalance: any(named: 'walletBalance'),
        )).thenThrow(Exception('timeout'));
    await c.review();
    expect(c.state.stage, PublishStage.failed);
    when(() => estimator.estimate(
          sizeInBytes: any(named: 'sizeInBytes'),
          itemSizes: any(named: 'itemSizes'),
          wallet: any(named: 'wallet'),
          walletBalance: any(named: 'walletBalance'),
        )).thenAnswer((_) async => _cost());
    await c.retry();
    expect(c.state.stage, PublishStage.review, reason: 'priced again');
    verifyNever(
        () => publisher.publish(any(), any(), onStep: any(named: 'onStep')));
  });

  test('a folder inside a hidden folder is blocked like a hidden one',
      () async {
    const inside = 'abababab-0000-4000-8000-00000000000a';
    await folder(inside, _hiddenFolder);
    await insertPublicationFile(db,
        driveId: _drive, id: 'z', name: 'z.txt', parentFolderId: inside);
    final c = cubit(
        folderEntry:
            await db.driveDao.folderById(folderId: inside).getSingle());
    await c.load();
    expect(c.state.blocked, PublishBlock.hiddenFolder);
  });

  test("an update keeps the owner's own card and a UDL's terms", () async {
    discovery.candidates = [freshSnapshot()];
    when(() => repository.readContent('LATEST'))
        .thenAnswer((_) async => content(
              generatedCard: false,
              license: ',"license":{"name":"Universal Data License",'
                  '"shortName":"UDL","definitionTxId":'
                  '"${udlLicenseMetaV2.licenseDefinitionTxId}",'
                  '"params":{"License-Fee":"One-Time-0.1"}}',
            ));
    // The card cannot be read back; it is still kept as it was.
    when(() => repository.readData(any())).thenThrow(Exception('offline'));
    when(() => publisher.publish(any(), any(), onStep: any(named: 'onStep')))
        .thenAnswer((_) async => latest());
    final c = cubit(previous: Publication([latest()]));
    await c.load();
    expect(c.state.licence?.params, {'License-Fee': 'One-Time-0.1'});
    await c.review();
    await c.publish();
    final job = verify(() => publisher.publish(captureAny(), any(),
        onStep: any(named: 'onStep'))).captured.single as PublicationJob;
    expect(job.social, isA<ExistingPublicationImage>());
    expect((job.social as ExistingPublicationImage).files,
        {'social.jpg': 'OLD_CARD'});
    expect(job.generatedCard, isFalse);
    expect(job.license?['params'], {'License-Fee': 'One-Time-0.1'});
  });

  test('a generated card is kept while nothing it shows changes', () async {
    discovery.candidates = [freshSnapshot()];
    when(() => repository.readContent('LATEST'))
        .thenAnswer((_) async => content(generatedCard: true));
    when(() => publisher.publish(any(), any(), onStep: any(named: 'onStep')))
        .thenAnswer((_) async => latest());
    final c = cubit(previous: Publication([latest()]));
    await c.load();
    await c.review();
    await c.publish();
    var job = verify(() => publisher.publish(captureAny(), any(),
        onStep: any(named: 'onStep'))).captured.single as PublicationJob;
    expect(job.social, isA<ExistingPublicationImage>());
    expect(job.generatedCard, isTrue);

    final edited = cubit(
      previous: Publication([latest()]),
    );
    await edited.load();
    edited.setTitle('Something else');
    await edited.review();
    await edited.publish();
    job = verify(() => publisher.publish(captureAny(), any(),
        onStep: any(named: 'onStep'))).captured.single as PublicationJob;
    expect(job.social, isA<NewPublicationImage>(), reason: 'redrawn');
  });

  void publishes() =>
      when(() => publisher.publish(any(), any(), onStep: any(named: 'onStep')))
          .thenAnswer((_) async => latest());

  group('the leave-page guard', () {
    test('is held while publishing and released when done', () async {
      discovery.candidates = [freshSnapshot()];
      final during = <String>[];
      when(() => publisher.publish(any(), any(), onStep: any(named: 'onStep')))
          .thenAnswer((_) async {
        during.addAll(guard);
        return latest();
      });
      final c = cubit();
      await c.load();
      await c.review();
      expect(guard.where((g) => g == 'hold'), isEmpty,
          reason: 'nothing is at risk before Publish');
      await c.publish();
      expect(during.last, 'hold');
      expect(c.state.stage, PublishStage.done);
      expect(guard.last, 'release');
    });

    test('is released when publishing fails', () async {
      discovery.candidates = [freshSnapshot()];
      when(() => publisher.publish(any(), any(), onStep: any(named: 'onStep')))
          .thenThrow(
              const PublicationFailure(PublicationStep.publication, 'Nope.'));
      final c = cubit();
      await c.load();
      await c.review();
      await c.publish();
      expect(c.state.stage, PublishStage.failed);
      expect(guard, contains('hold'));
      expect(guard.last, 'release');
    });

    test('outlives a dialog closed mid-publish until the upload settles',
        () async {
      discovery.candidates = [freshSnapshot()];
      final gate = Completer<PublishedVersion>();
      when(() => publisher.publish(any(), any(), onStep: any(named: 'onStep')))
          .thenAnswer((_) => gate.future);
      final c = cubit();
      await c.load();
      await c.review();
      unawaited(c.publish());
      await pumpEventQueue();
      expect(guard.last, 'hold');
      await c.close();
      expect(guard.last, 'hold', reason: 'the upload is still running');
      gate.complete(latest());
      await pumpEventQueue();
      expect(guard.last, 'release');
    });

    test('is released when the dialog closes with nothing running', () async {
      discovery.candidates = [freshSnapshot()];
      final c = cubit();
      await c.load();
      await c.review();
      await c.close();
      expect(guard.where((g) => g == 'hold'), isEmpty);
      expect(guard.last, 'release');
    });
  });

  group('closed while publishing', () {
    late Completer<PublishedVersion> gate;
    late List<String?> told;

    Future<PublishCubit> closedMidPublish() async {
      discovery.candidates = [freshSnapshot()];
      gate = Completer<PublishedVersion>();
      told = [];
      when(() => publisher.publish(any(), any(), onStep: any(named: 'onStep')))
          .thenAnswer((_) => gate.future);
      final c = cubit(onSettledAfterClose: told.add);
      await c.load();
      await c.review();
      unawaited(c.publish());
      await pumpEventQueue();
      expect(c.state.stage, PublishStage.publishing);
      await c.close();
      expect(told, isEmpty, reason: 'nothing has settled yet');
      expect(guard.last, 'hold', reason: 'the upload is still running');
      return c;
    }

    test('says the page is published, with its link', () async {
      await closedMidPublish();
      gate.complete(PublishedVersion(
        txId: 'MANIFEST',
        publicationId: 'p',
        driveId: _drive,
        folderId: null,
        publishedAt: DateTime.utc(2026),
      ));
      await pumpEventQueue();
      expect(told, ['https://turbo-gateway.com/MANIFEST/']);
      expect(guard.last, 'release');
    });

    test('says it stopped when it fails', () async {
      await closedMidPublish();
      gate.completeError(
          const PublicationFailure(PublicationStep.publication, 'Nope.'));
      await pumpEventQueue();
      expect(told, [null]);
      expect(guard.last, 'release');
    });

    test('says it stopped when it fails unexpectedly', () async {
      await closedMidPublish();
      gate.completeError(StateError('boom'));
      await pumpEventQueue();
      expect(told, [null]);
      expect(guard.last, 'release');
    });

    test('says nothing when the dialog is still open', () async {
      discovery.candidates = [freshSnapshot()];
      publishes();
      final told = <String?>[];
      final c = cubit(onSettledAfterClose: told.add);
      await c.load();
      await c.review();
      await c.publish();
      expect(c.state.stage, PublishStage.done);
      expect(told, isEmpty, reason: 'the dialog shows it');
    });
  });

  test('a snapshot the gateway does not serve is not reused', () async {
    discovery.candidates = [freshSnapshot()];
    when(() => publisher.snapshotServes('NEWEST'))
        .thenAnswer((_) async => false);
    when(() => creation.prepare(
          driveId: any(named: 'driveId'),
          driveKey: any(named: 'driveKey'),
          wallet: any(named: 'wallet'),
          isCancelled: any(named: 'isCancelled'),
        )).thenAnswer((_) async => DriveStateCreationResult.prepared(
          PreparedDriveStateArtifact(
            entity: DriveStateEntity(
                id: 'x',
                driveId: _drive,
                blockEnd: 1,
                dataStart: 0,
                dataEnd: 1,
                entityCount: 3),
            driveId: _drive,
            driveName: 'My drive',
            entityCount: 3,
            sizeInBytes: 900,
          ),
        ));
    final c = cubit();
    await c.load();
    await c.review();
    expect(c.state.stage, PublishStage.review);
    expect(c.state.reusesSnapshot, isFalse);
    verify(() => publisher.snapshotServes('NEWEST')).called(1);
  });

  test('the cost is checked item by item', () async {
    discovery.candidates = [freshSnapshot()];
    final c = cubit();
    await c.load();
    await c.review();
    verify(() => estimator.estimate(
          sizeInBytes: 5000,
          itemSizes: [2000, 3000],
          wallet: any(named: 'wallet'),
          walletBalance: any(named: 'walletBalance'),
        )).called(1);
  });

  group('the display name', () {
    test('is free text, and a title may say ArDrive', () async {
      discovery.candidates = [freshSnapshot()];
      publishes();
      final c = cubit();
      await c.load();
      c.setTitle('ArDrive Photos Drive');
      c.setOwnerName('ArDrive Support');
      c.next();
      await c.review();
      expect(c.state.stage, PublishStage.review);
      await c.publish();
      expect(c.state.stage, PublishStage.done);
      final job = verify(() => publisher.publish(captureAny(), any(),
          onStep: any(named: 'onStep'))).captured.single as PublicationJob;
      expect(job.title, 'ArDrive Photos Drive');
      expect(job.ownerName, 'ArDrive Support');
    });
  });
}
