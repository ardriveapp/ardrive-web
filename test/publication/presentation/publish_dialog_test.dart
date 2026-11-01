import 'package:ardrive/arns/data/arns_change_executor.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog_cubit.dart';
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

    expect(find.text('Review and publish'), findsOneWidget);
    expect(find.text('Link'), findsOneWidget, reason: 'the rest stays');
    expect(find.text('Snapshot'), findsNothing);
    expect(find.textContaining('snapshot'), findsNothing);
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

    expect(find.text('Review and publish'), findsOneWidget);
    expect(find.textContaining('permanent'), findsNothing);
  });

  testWidgets('the first step says what comes next', (tester) async {
    await open(
      tester,
      const PublishState(stage: PublishStage.included, summary: _summary),
    );

    expect(
      find.text('Next: a title. Images, a description and a name are '
          'optional, and you can add them later.'),
      findsOneWidget,
    );
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

  testWidgets('what is included counts files and folders, not their size',
      (tester) async {
    // The files are stored already: a size here read as uploading them
    // again.
    await open(
      tester,
      const PublishState(stage: PublishStage.included, summary: _summary),
    );

    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Folders'), findsOneWidget);
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

    testWidgets('says when the ArNS wallet is waiting for approval',
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

      expect(
          find.text('Approve the change in your ArNS wallet.'), findsOneWidget);
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
}
