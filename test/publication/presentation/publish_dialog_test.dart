import 'package:ardrive/arns/data/arns_change_executor.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog_cubit.dart';
import 'dart:async';
import 'dart:ui' as ui;

import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/components/upload_review_dialog.dart'
    show UploadCostBlock;
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/drive_state/domain/drive_state_sync_skip_status.dart'
    show DriveStateSyncSkipStatus;
import 'package:ardrive/drive_state/domain/drive_state_publish_cost.dart';
import 'package:ardrive/publication/domain/publication_publisher.dart'
    show PublicationStep;
import 'package:ardrive/models/models.dart';
import 'package:ardrive/publication/domain/publication_scope.dart';
import 'package:ardrive/publication/presentation/publish/publish_cubit.dart';
import 'package:ardrive/publication/presentation/publish/publish_dialog.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../test_utils/mocks.dart' show MockDriveDao;
import 'package:mocktail/mocktail.dart';

class _MockPublishCubit extends MockCubit<PublishState>
    implements PublishCubit {}

class _MockWalletCubit extends MockCubit<ArNSWalletState>
    implements ArNSWalletCubit {}

class _MockNameCubit extends MockCubit<ArNSNameDialogState>
    implements ArNSFlowNameCubit {}

const _summary = PublicationSummary(
  fileCount: 3,
  folderCount: 1,
  totalSize: 1024,
  hiddenItems: 0,
  inHiddenFolders: 0,
  inGhostFolders: 0,
  pendingFiles: 0,
  failedFiles: 0,
);

final _freeCost = DriveStatePublishCost(
  costEstimateAr: UploadCostEstimate.zero(),
  costEstimateTurbo: UploadCostEstimate.zero(),
  isTurboUploadPossible: true,
  hasNoTurboBalance: false,
  arBalance: '0',
  turboCredits: '0',
  sufficientArBalance: true,
  sufficientTurboBalance: true,
  freeStatus: FreeUploadStatus.free,
);

void main() {
  late _MockPublishCubit cubit;

  setUp(() {
    cubit = _MockPublishCubit();
    when(() => cubit.scopeName).thenReturn('Archive');
    when(() => cubit.folder).thenReturn(null);
    when(() => cubit.isFile).thenReturn(false);
    when(() => cubit.uploadSize).thenReturn(2048);
    when(() => cubit.isPrivateFile).thenReturn(false);
    when(() => cubit.canSyncDrive).thenReturn(false);
    when(() => cubit.names).thenReturn(null);
  });

  Widget app(Widget home) => ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: home),
        ),
      );

  Future<void> open(WidgetTester tester, PublishState state) async {
    when(() => cubit.state).thenReturn(state);
    await tester.pumpWidget(app(Builder(
      builder: (context) => TextButton(
        onPressed: () => showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => BlocProvider<PublishCubit>.value(
            value: cubit,
            // The link field is a TextField, which needs a Material.
            child: const Material(
              type: MaterialType.transparency,
              child: PublishDialog(),
            ),
          ),
        ),
        child: const Text('Publish to web'),
      ),
    )));
    await tester.tap(find.text('Publish to web'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('the review leaves the snapshot to the total', (tester) async {
    await open(
      tester,
      PublishState(
        stage: PublishStage.review,
        summary: _summary,
        title: 'Archive',
        cost: _freeCost,
      ),
    );

    expect(find.byType(UploadCostBlock), findsOneWidget);
    expect(find.text('Link'), findsOneWidget, reason: 'the rest stays');
    expect(find.text('Snapshot'), findsNothing);
    expect(find.textContaining('snapshot'), findsNothing);
  });

  testWidgets('the review is the upload review: its cost, Back and Publish',
      (tester) async {
    await open(
      tester,
      PublishState(
        stage: PublishStage.review,
        summary: _summary,
        title: 'Archive',
        cost: _freeCost,
      ),
    );

    expect(find.byType(UploadCostBlock), findsOneWidget);
    expect(find.text('Free'), findsOneWidget);
    expect(find.text('Covered by your free upload allowance'), findsOneWidget);
    expect(find.text('Payment method'), findsNothing,
        reason: 'the old payment block is gone');
    expect(find.text('Back'), findsOneWidget);
    expect(find.text('Publish'), findsWidgets);
    expect(find.text('2 KiB'), findsOneWidget,
        reason: 'what publishing uploads, not the files');
  });

  // Priced short on both, so the cubit's method is the wallet; then credits
  // arrive. The review shows Turbo Credits, covered: Publish is offered.
  testWidgets('credits that cover it offer Publish whatever the priced method',
      (tester) async {
    await open(
      tester,
      PublishState(
        stage: PublishStage.review,
        summary: _summary,
        title: 'Archive',
        method: UploadMethod.ar,
        cost: DriveStatePublishCost(
          costEstimateAr: UploadCostEstimate(
            pstFee: BigInt.zero,
            totalCost: BigInt.from(4000000000),
            totalSize: 1024,
            usdUploadCost: 0.4,
          ),
          costEstimateTurbo: UploadCostEstimate(
            pstFee: BigInt.zero,
            totalCost: BigInt.from(3000000000),
            totalSize: 1024,
            usdUploadCost: 0.3,
          ),
          isTurboUploadPossible: true,
          hasNoTurboBalance: false,
          arBalance: '0',
          turboCredits: '5',
          sufficientArBalance: false,
          sufficientTurboBalance: true,
          turboBalanceWinc: BigInt.from(5000000000),
          freeStatus: FreeUploadStatus.notEligible,
        ),
      ),
    );

    final publish = tester.widget<ArDriveButtonNew>(
        find.widgetWithText(ArDriveButtonNew, 'Publish'));
    expect(publish.isDisabled, isFalse);
  });

  testWidgets('the review no longer warns that publishing is permanent',
      (tester) async {
    await open(
      tester,
      PublishState(
        stage: PublishStage.review,
        summary: _summary,
        title: 'Archive',
        cost: _freeCost,
      ),
    );

    expect(find.byType(UploadCostBlock), findsOneWidget);
    expect(find.textContaining('permanent'), findsNothing);
  });

  testWidgets('a folder has no read-only included step: the review carries it',
      (tester) async {
    await open(
      tester,
      PublishState(
        stage: PublishStage.review,
        summary: const PublicationSummary(
          fileCount: 3,
          folderCount: 1,
          totalSize: 1024,
          hiddenItems: 2,
          inHiddenFolders: 0,
          inGhostFolders: 0,
          pendingFiles: 0,
          failedFiles: 0,
        ),
        title: 'Archive',
        cost: _freeCost,
      ),
    );

    expect(find.text("What's included"), findsNothing);
    expect(find.text('Left out'), findsOneWidget);
    expect(find.text('Hidden items in a public drive can still be found.'),
        findsOneWidget);
    expect(
      find.text('Anyone can find this page, and search engines can list its '
          'files.'),
      findsOneWidget,
    );
  });

  testWidgets('a failure and an unaffordable cost are error notices',
      (tester) async {
    await open(
      tester,
      const PublishState(stage: PublishStage.failed, failure: 'It broke.'),
    );
    expect(find.byType(ArDriveNotice), findsOneWidget);
    expect(find.text('It broke.'), findsOneWidget);
  });

  testWidgets('choosing an image replaces the look, with Back to return',
      (tester) async {
    when(() => cubit.drive).thenReturn(Drive(
      id: 'drive',
      rootFolderId: 'root',
      ownerAddress: 'addr',
      name: 'Drive',
      privacy: 'public',
      isHidden: false,
      dateCreated: DateTime.utc(2026),
      lastUpdated: DateTime.utc(2026),
    ));
    // The look stays mounted under the chooser.
    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder);
    final mark =
        await tester.runAsync(() => recorder.endRecording().toImage(4, 4));
    when(() => cubit.mark()).thenAnswer((_) async => mark!);
    when(() => cubit.state).thenReturn(const PublishState(
      stage: PublishStage.look,
      title: 'A',
      choosingSlot: PublicationImageSlot.cover,
    ));
    await tester.pumpWidget(app(RepositoryProvider<DriveDao>.value(
      // Reading the images fails: the chooser's title and Back are the test.
      value: MockDriveDao(),
      child: BlocProvider<PublishCubit>.value(
        value: cubit,
        child: const Material(
          type: MaterialType.transparency,
          child: SingleChildScrollView(child: PublishDialog()),
        ),
      ),
    )));
    await tester.pump();

    expect(find.text('Choose an image'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    expect(find.text('How it looks'), findsNothing);
  });

  group('the review of an update', () {
    ArNSNameRecord record(String name) => ArNSNameRecord(
          name: name,
          undername: '@',
          transactionId: 'tx',
          ttlSeconds: 900,
        );

    Future<void> review(WidgetTester tester, List<ArNSNameRecord> following,
        {bool isUpdate = true}) async {
      final names = _MockNameCubit();
      whenListen(
        names,
        const Stream<ArNSNameDialogState>.empty(),
        initialState: ArNSNameDialogState(
          mode: ArNSNameDialogMode.nameItem,
          stage: ArNSDialogStage.noNames,
          following: following,
        ),
      );
      when(() => names.ready).thenReturn(true);
      when(() => names.hasWork).thenReturn(following.isNotEmpty);
      when(() => names.repointing).thenReturn(null);
      when(() => cubit.names).thenReturn(names);
      final wallet = _MockWalletCubit();
      whenListen(wallet, const Stream<ArNSWalletState>.empty(),
          initialState: const ArNSWalletState());
      when(() => cubit.state).thenReturn(PublishState(
        stage: PublishStage.review,
        summary: _summary,
        title: 'Archive',
        cost: _freeCost,
        isUpdate: isUpdate,
      ));
      await tester.pumpWidget(app(BlocProvider<ArNSWalletCubit>.value(
        value: wallet,
        child: BlocProvider<PublishCubit>.value(
          value: cubit,
          child: const Material(
            type: MaterialType.transparency,
            child: SingleChildScrollView(child: PublishDialog()),
          ),
        ),
      )));
      await tester.pump();
    }

    testWidgets('without names, keeps the plain note', (tester) async {
      await review(tester, const []);

      expect(find.text('A new link. The current one keeps working.'),
          findsOneWidget);
    });

    testWidgets('with one name, says it moves', (tester) async {
      await review(tester, [record('maya')]);

      expect(
        find.text(
            'A new link. maya.ar.io moves to it; the current link keeps working.'),
        findsOneWidget,
      );
    });

    testWidgets('with several names, says how many move', (tester) async {
      await review(tester, [record('maya'), record('lake')]);

      expect(
        find.text(
            'A new link. 2 names move to it; the current link keeps working.'),
        findsOneWidget,
      );
    });

    testWidgets('the name row asks for a name like yours.ar.io',
        (tester) async {
      await review(tester, const [], isUpdate: false);

      expect(find.text('Give it a name like yours.ar.io'), findsOneWidget);
      expect(find.text('Add name'), findsNothing);
    });
  });

  testWidgets('the review counts files and folders, not their size',
      (tester) async {
    // The files are stored already: a size here read as uploading them
    // again.
    await open(
      tester,
      PublishState(
        stage: PublishStage.review,
        summary: _summary,
        title: 'Archive',
        cost: _freeCost,
      ),
    );

    expect(find.text('Folders'), findsOneWidget);
    expect(find.textContaining('3 files'), findsOneWidget);
    expect(find.text('Size'), findsNothing);
    expect(find.text('1 KB'), findsNothing);
  });

  group('blocked by sync', () {
    final blocked = PublishState(
      stage: PublishStage.blocked,
      blocked: PublishBlock.sync,
      blockedReason: const DriveStateSyncSkipStatus.unknown(
              'No sync has finished yet. Sync this drive, then try again.')
          .reason,
    );

    testWidgets('offers Sync drive, which syncs', (tester) async {
      when(() => cubit.canSyncDrive).thenReturn(true);
      when(() => cubit.syncDrive()).thenAnswer((_) async {});
      await open(tester, blocked);

      expect(find.text('Close'), findsOneWidget);
      await tester.tap(find.text('Sync drive'));
      await tester.pump();
      verify(() => cubit.syncDrive()).called(1);
    });

    testWidgets('only Close when the dialog cannot sync', (tester) async {
      await open(tester, blocked);

      expect(find.text('Sync drive'), findsNothing);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('says it is syncing while it does', (tester) async {
      await open(tester, const PublishState(stage: PublishStage.syncing));

      expect(find.text('Syncing this drive...'), findsOneWidget);
    });

    testWidgets('centres the wait across the dialog', (tester) async {
      await open(tester, const PublishState(stage: PublishStage.syncing));

      final title = tester.getRect(find.text('Syncing this drive...'));
      final spinner = tester.getCenter(find.byType(ArDriveSpinner));
      final dialog = tester.getRect(find.byType(ArDriveStandardModalNew));
      expect(spinner.dx, moreOrLessEquals(dialog.center.dx, epsilon: 1));
      expect(title.center.dx, moreOrLessEquals(dialog.center.dx, epsilon: 1));
    });
  });

  // It said "a few minutes" and named nothing, while the wait after an upload
  // was nearer an hour (issue #2366).
  testWidgets('blocked by changes says how many and that it takes an hour',
      (tester) async {
    await open(
      tester,
      const PublishState(
        stage: PublishStage.blocked,
        blocked: PublishBlock.pendingUploads,
        pendingChanges: 3,
      ),
    );

    expect(
        find.text("3 recent changes to this drive aren't confirmed on "
            'Arweave yet. You can publish once they are, usually within an '
            'hour.'),
        findsOneWidget);
    expect(find.textContaining('a few minutes'), findsNothing);
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('blocked by one change says it is one', (tester) async {
    await open(
      tester,
      const PublishState(
        stage: PublishStage.blocked,
        blocked: PublishBlock.pendingUploads,
        pendingChanges: 1,
      ),
    );

    expect(
        find.text("1 recent change to this drive isn't confirmed on Arweave "
            'yet. You can publish once it is, usually within an hour.'),
        findsOneWidget);
  });

  group('while publishing', () {
    final publishing = PublishState(
      stage: PublishStage.publishing,
      summary: _summary,
      title: 'Archive',
      cost: _freeCost,
    );

    testWidgets('Close hides the dialog; back does not', (tester) async {
      await open(tester, publishing);
      expect(find.byType(PublishDialog), findsOneWidget);
      expect(find.text('Keep this tab open until it\'s done.'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(PublishDialog), findsOneWidget,
          reason: 'back never hides a publish in progress');

      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump();
      expect(find.byType(PublishDialog), findsNothing);
    });
  });

  group('a publish with a name', () {
    final base = PublishState(
      stage: PublishStage.publishing,
      summary: _summary,
      title: 'Archive',
      cost: _freeCost,
      step: PublicationStep.warmUp,
      naming: const ['published_playdead'],
    );

    testWidgets('lists the name as the last step', (tester) async {
      await open(tester, base);

      expect(find.text('Getting the page ready'), findsOneWidget);
      expect(find.text('Updating published_playdead'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('says when the Solana wallet is waiting for approval',
        (tester) async {
      final names = _MockNameCubit();
      whenListen(
        names,
        const Stream<ArNSNameDialogState>.empty(),
        initialState: const ArNSNameDialogState(
          mode: ArNSNameDialogMode.nameItem,
          step: ArNSCommitStep.approve,
        ),
      );
      when(() => cubit.names).thenReturn(names);
      await open(tester, base.copyWith(namingStarted: true));

      expect(find.text('Approve the change in your Solana wallet.'),
          findsOneWidget);
    });

    testWidgets('says nothing about the wallet while Turbo works',
        (tester) async {
      final names = _MockNameCubit();
      whenListen(
        names,
        const Stream<ArNSNameDialogState>.empty(),
        initialState: const ArNSNameDialogState(
          mode: ArNSNameDialogMode.nameItem,
          step: ArNSCommitStep.working,
        ),
      );
      when(() => cubit.names).thenReturn(names);
      await open(tester, base.copyWith(namingStarted: true));

      expect(find.textContaining('wallet'), findsNothing);
    });

    testWidgets('names several by count', (tester) async {
      await open(tester, base.copyWith(naming: const ['a', 'b_a']));

      expect(find.text('Updating 2 names'), findsOneWidget);
    });
  });

  group('the notice after a closed publish settles', () {
    Future<(ScaffoldMessengerState, AppLocalizations)> host(
        WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(app(Builder(builder: (c) {
        context = c;
        return const SizedBox.shrink();
      })));
      return (
        ScaffoldMessenger.of(context),
        AppLocalizations.of(context)!,
      );
    }

    testWidgets('says the page is published, with Open', (tester) async {
      final (messenger, strings) = await host(tester);
      showPublishSettledNotice(
          messenger, strings, 'https://ardrive.net/MANIFEST/');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));

      expect(find.text('Your page is published'), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Open'), findsOneWidget);
    });

    testWidgets('says how to try again when it stopped', (tester) async {
      final (messenger, strings) = await host(tester);
      showPublishSettledNotice(messenger, strings, null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));

      expect(
        find.text('Publishing stopped. Open Publish to web to try again.'),
        findsOneWidget,
      );
      expect(find.byType(SnackBarAction), findsNothing);
    });
  });

  group('a file', () {
    setUpAll(() => registerFallbackValue(FilePublishHow.page));

    setUp(() {
      when(() => cubit.isFile).thenReturn(true);
      when(() => cubit.scopeName).thenReturn('Lake.jpg');
    });

    testWidgets('How offers its page and the file itself', (tester) async {
      await open(
        tester,
        const PublishState(
          stage: PublishStage.how,
          filePages: FilePageAvailability.available,
        ),
      );

      expect(find.text('How to publish'), findsOneWidget);
      expect(find.text('File page'), findsOneWidget);
      expect(find.text('The file itself'), findsOneWidget);
      await tester.tap(find.text('The file itself'));
      verify(() => cubit.setHow(FilePublishHow.itself)).called(1);
    });

    testWidgets('a release that cannot open file pages says so',
        (tester) async {
      await open(
        tester,
        const PublishState(
          stage: PublishStage.how,
          filePages: FilePageAvailability.needsRelease,
        ),
      );

      expect(find.text('Available after the next ArDrive release.'),
          findsOneWidget);
    });

    testWidgets('a private file\'s page is the only choice', (tester) async {
      when(() => cubit.isPrivateFile).thenReturn(true);
      await open(
        tester,
        const PublishState(
          stage: PublishStage.how,
          filePages: FilePageAvailability.available,
        ),
      );

      expect(find.text('Only for files in public drives.'), findsOneWidget);
      await tester.tap(find.text('The file itself'));
      verifyNever(() => cubit.setHow(any()));
    });

    testWidgets('the file itself shows its link', (tester) async {
      when(() => cubit.fileLink).thenReturn('https://ardrive.net/DATA');
      when(() => cubit.file).thenReturn(FileEntry(
        id: 'lake',
        driveId: 'drive',
        name: 'Lake.jpg',
        parentFolderId: 'root',
        path: '',
        size: 1,
        lastModifiedDate: DateTime.utc(2026),
        dataTxId: 'DATA',
        isHidden: false,
        dateCreated: DateTime.utc(2026),
        lastUpdated: DateTime.utc(2026),
      ));
      await open(tester, const PublishState(stage: PublishStage.itself));

      expect(find.text('The file itself'), findsOneWidget);
      expect(
          find.byWidgetPredicate((w) =>
              w is TextField &&
              w.controller?.text == 'https://ardrive.net/DATA'),
          findsOneWidget);
      expect(find.text('This link always opens this version of the file.'),
          findsOneWidget);
    });

    testWidgets('a private page\'s link holds the key, and says so',
        (tester) async {
      when(() => cubit.isPrivateFile).thenReturn(true);
      await open(
        tester,
        PublishState(
          stage: PublishStage.done,
          link: 'https://ardrive.net/PAGE/#/?k=${'A' * 43}',
        ),
      );

      expect(find.textContaining("This link holds the file's key."),
          findsOneWidget);
      // Behind the reveal control, as a share link's key is.
      expect(find.byWidgetPredicate((w) => w is TextField && w.obscureText),
          findsOneWidget);
    });

    testWidgets('a progress has no snapshot step', (tester) async {
      await open(tester, const PublishState(stage: PublishStage.publishing));

      expect(find.text('Saving a snapshot of the drive'), findsNothing);
      expect(find.text("Signing the page's files"), findsOneWidget);
    });
  });

  group('the look', () {
    Drive aDrive() => Drive(
          id: 'drive',
          rootFolderId: 'root',
          ownerAddress: 'iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA',
          name: 'Drive',
          privacy: 'public',
          isHidden: false,
          dateCreated: DateTime.utc(2026),
          lastUpdated: DateTime.utc(2026),
        );

    Future<void> stubLook(WidgetTester tester) async {
      when(() => cubit.drive).thenReturn(aDrive());
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder);
      final mark =
          await tester.runAsync(() => recorder.endRecording().toImage(4, 4));
      when(() => cubit.mark()).thenAnswer((_) async => mark!);
    }

    testWidgets('the first step of a folder has Cancel, not a dead Back',
        (tester) async {
      await stubLook(tester);
      await open(
        tester,
        const PublishState(stage: PublishStage.look, title: 'A'),
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Back'), findsNothing);
    });

    testWidgets('a file keeps Back on its look', (tester) async {
      await stubLook(tester);
      when(() => cubit.isFile).thenReturn(true);
      await open(
        tester,
        const PublishState(stage: PublishStage.look, title: 'A'),
      );
      expect(find.text('Back'), findsOneWidget);
    });

    testWidgets('a keyword being typed survives choosing an image',
        (tester) async {
      await stubLook(tester);
      const look = PublishState(stage: PublishStage.look, title: 'A');
      const choosing = PublishState(
        stage: PublishStage.look,
        title: 'A',
        choosingSlot: PublicationImageSlot.cover,
      );
      final states = StreamController<PublishState>.broadcast();
      addTearDown(states.close);
      whenListen(cubit, states.stream, initialState: look);
      when(() => cubit.state).thenReturn(look);
      await tester.binding.setSurfaceSize(const Size(1200, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(app(RepositoryProvider<DriveDao>.value(
        value: MockDriveDao(),
        child: BlocProvider<PublishCubit>.value(
          value: cubit,
          child: const Material(
            type: MaterialType.transparency,
            child: SingleChildScrollView(child: PublishDialog()),
          ),
        ),
      )));
      await tester.pump();

      await tester.tap(find.text('More options'));
      await tester.pump();
      await tester.enterText(find.byType(EditableText).last, 'draft');
      await tester.pump();

      when(() => cubit.state).thenReturn(choosing);
      states.add(choosing);
      await tester.pump();
      expect(find.text('Choose an image'), findsOneWidget);

      when(() => cubit.state).thenReturn(look);
      states.add(look);
      await tester.pump();

      expect(find.text('Choose an image'), findsNothing);
      expect(find.text('draft'), findsOneWidget);
    });
  });
}
