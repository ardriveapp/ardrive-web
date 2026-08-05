import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/shared_file/shared_file_key_session.dart';
import 'package:ardrive/pages/shared_file/shared_file_page.dart';
import 'package:ardrive/utils/filesize.dart';
import 'package:ardrive/utils/session_key_value_store.dart';
import 'package:ardrive/utils/shared_file_link.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSharedFileCubit extends MockCubit<SharedFileState>
    implements SharedFileCubit {}

/// Widget tests for the recipient landing page
/// (`docs/FILE_SHARING_REDESIGN_PLAN.md` §2).
///
/// The assertions here are about what a *recipient* can see and do: the file
/// they are being given, one obvious download, a key gate that never lies to
/// them, and no transaction id in their face.
void main() {
  const fileId = 'file-id';

  // 43 base64url characters whose last character carries no stray bits - the
  // shape `SharedFileLinkKey.isWellFormed` accepts.
  const wellFormedKey = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopQ';

  late MockSharedFileCubit cubit;
  late StreamController<SharedFileState> states;

  FileRevision fileRevision({
    String name = 'Q3 Report.pdf',
    String dataTxId = 'data-tx-newest',
    int size = 4821133,
    String? dataContentType = 'application/pdf',
  }) {
    return FileRevision(
      fileId: fileId,
      driveId: 'drive-id',
      name: name,
      parentFolderId: 'parent-folder-id',
      size: size,
      lastModifiedDate: DateTime.utc(2024, 3, 3),
      dataContentType: dataContentType,
      metadataTxId: 'metadata-tx',
      dataTxId: dataTxId,
      dateCreated: DateTime.utc(2024, 3, 3),
      action: RevisionAction.create,
      isHidden: false,
    );
  }

  SharedFileLoadSuccess success({
    bool newerVersionAvailable = false,
    bool isPinned = false,
    bool showsLatestRevision = false,
    LinkVerification verification = LinkVerification.verified,
    SharedFileLinkPayload? payload,
    FileRevision? revision,
    FileRevision? linkRevision,
    List<FileRevision> activityRevisions = const [],
    SharedFileActivityStatus activityStatus =
        SharedFileActivityStatus.notLoaded,
  }) {
    return SharedFileLoadSuccess(
      fileRevisions: [revision ?? fileRevision()],
      fileKey: null,
      latestLicense: null,
      ownerAddress: 'Zvp8dEkO3nQ2wX9yV8uT7sR6qP5oN4mL3kJ2iH1gF0e',
      payload: payload,
      verification: verification,
      newerVersionAvailable: newerVersionAvailable,
      isPinned: isPinned,
      activityRevisions: activityRevisions,
      activityStatus: activityStatus,
      linkRevision: linkRevision,
      showsLatestRevision: showsLatestRevision,
    );
  }

  // Every state is built through a helper that forwards *variables*: whether
  // the resolver's state classes end up with const constructors is its call,
  // not this file's, and a literal argument list would make that choice a lint
  // error here.
  SharedFileIsPrivate locked({SharedFileLinkPayload? payload}) =>
      SharedFileIsPrivate(payload: payload);

  SharedFileKeyInvalid keyInvalid({
    bool linkKeyIsDamaged = false,
    SharedFileLinkPayload? payload,
  }) =>
      SharedFileKeyInvalid(
        linkKeyIsDamaged: linkKeyIsDamaged,
        payload: payload,
      );

  SharedFileLoadInProgress resolving({SharedFileLinkPayload? payload}) =>
      SharedFileLoadInProgress(payload: payload);

  SharedFileNotFound notFound({
    required int retryAttempt,
    required bool mayStillBePropagating,
  }) =>
      SharedFileNotFound(
        retryAttempt: retryAttempt,
        mayStillBePropagating: mayStillBePropagating,
      );

  Widget wrap(Widget child) {
    return ArDriveTheme(
      themeData: lightTheme(),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', '')],
        home: child,
      ),
    );
  }

  Future<void> pumpPage(
    WidgetTester tester,
    SharedFileState initialState, {
    SharedFileKeySession? keySession,
  }) async {
    // Tall enough that the whole card is laid out and tappable; the page is a
    // single scrolling column, so nothing depends on this being a phone or a
    // monitor.
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    whenListen(cubit, states.stream, initialState: initialState);

    await tester.pumpWidget(
      wrap(
        BlocProvider<SharedFileCubit>.value(
          value: cubit,
          child: SharedFilePage(keySession: keySession),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() {
    cubit = MockSharedFileCubit();
    states = StreamController<SharedFileState>.broadcast();

    when(() => cubit.fileId).thenReturn(fileId);
    when(() => cubit.submit(any())).thenAnswer((_) async {});
    when(() => cubit.retry()).thenAnswer((_) async {});
    when(() => cubit.loadActivity()).thenAnswer((_) async {});
    when(() => cubit.showLatestRevision()).thenAnswer((_) async {});
    when(() => cubit.showSharedRevision()).thenAnswer((_) async {});
  });

  tearDown(() async {
    await states.close();
  });

  group('LOCKED', () {
    testWidgets('shows what the link says is behind the key', (tester) async {
      await pumpPage(
        tester,
        locked(
          payload: const SharedFileLinkPayload(
            name: 'Q3 Report.pdf',
            size: 4821133,
            contentType: 'application/pdf',
            cipher: 'AES256-GCM',
          ),
        ),
      );

      expect(find.text('Q3 Report.pdf'), findsOneWidget);
      expect(find.text(filesize(4821133)), findsOneWidget);
      expect(
        find.textContaining('protected with an access key'),
        findsOneWidget,
      );
      expect(
        find.textContaining('sent you the key separately'),
        findsOneWidget,
      );
    });

    testWidgets('says the sender hid the details instead of showing them',
        (tester) async {
      await pumpPage(
        tester,
        locked(
          payload: const SharedFileLinkPayload(
            name: 'Q3 Report.pdf',
            size: 4821133,
            detailsAreHidden: true,
            cipher: 'AES256-GCM',
          ),
        ),
      );

      expect(find.text('Q3 Report.pdf'), findsNothing);
      expect(find.text(filesize(4821133)), findsNothing);
      expect(find.textContaining('hide'), findsOneWidget);
    });

    testWidgets('rejects a malformed key without asking the network',
        (tester) async {
      await pumpPage(tester, locked());

      await tester.enterText(find.byType(ArDriveTextField), 'not-a-key');
      await tester.pump();
      await tester.tap(find.text('Unlock file'));
      await tester.pump();

      verifyNever(() => cubit.submit(any()));
      expect(find.textContaining('43 characters'), findsOneWidget);
    });

    testWidgets('unlocks on a pasted key, without a second tap',
        (tester) async {
      await pumpPage(tester, locked());

      await tester.enterText(find.byType(ArDriveTextField), wellFormedKey);
      await tester.pump();

      verify(() => cubit.submit(wellFormedKey)).called(1);
    });

    testWidgets('keeps the rejected key on screen with an inline error',
        (tester) async {
      await pumpPage(tester, locked());

      await tester.enterText(find.byType(ArDriveTextField), wellFormedKey);
      await tester.pump();

      states.add(keyInvalid());
      await tester.pump();

      final field = tester.widget<ArDriveTextField>(
        find.byType(ArDriveTextField),
      );

      expect(field.controller?.text, wellFormedKey);
      expect(
        find.textContaining('Check for missing characters'),
        findsOneWidget,
      );
      // A wrong key is never a missing file (F3/F5).
      expect(find.textContaining('does not exist'), findsNothing);
    });

    testWidgets('tells a damaged link apart from a rejected key',
        (tester) async {
      await pumpPage(
        tester,
        keyInvalid(linkKeyIsDamaged: true),
      );

      expect(find.textContaining('damaged'), findsOneWidget);
      expect(find.textContaining('Check for missing characters'), findsNothing);
      // The recovery path is the same gate either way.
      expect(find.byType(ArDriveTextField), findsOneWidget);
      expect(find.text('Unlock file'), findsOneWidget);
    });

    testWidgets('unlocks with the key remembered for this tab', (tester) async {
      final storage = <String, String>{
        SharedFileKeySession.storageKey(fileId): wellFormedKey,
      };

      await pumpPage(
        tester,
        locked(),
        keySession: SharedFileKeySession(
          store: SessionKeyValueStore.inMemory(storage),
        ),
      );
      await tester.pump();

      verify(() => cubit.submit(wellFormedKey)).called(1);
    });

    testWidgets('forgets a remembered key that stops working', (tester) async {
      final storage = <String, String>{
        SharedFileKeySession.storageKey(fileId): wellFormedKey,
      };

      await pumpPage(
        tester,
        locked(),
        keySession: SharedFileKeySession(
          store: SessionKeyValueStore.inMemory(storage),
        ),
      );
      await tester.pump();

      states.add(keyInvalid());
      await tester.pump();

      expect(storage, isEmpty);
    });

    testWidgets('remembers a working key only when asked to', (tester) async {
      final storage = <String, String>{};

      await pumpPage(
        tester,
        locked(),
        keySession: SharedFileKeySession(
          store: SessionKeyValueStore.inMemory(storage),
        ),
      );

      await tester.enterText(find.byType(ArDriveTextField), wellFormedKey);
      await tester.pump();

      states.add(success());
      await tester.pump();

      expect(storage, isEmpty);
    });

    testWidgets('remembers a working key for the tab when asked to',
        (tester) async {
      final storage = <String, String>{};

      await pumpPage(
        tester,
        locked(),
        keySession: SharedFileKeySession(
          store: SessionKeyValueStore.inMemory(storage),
        ),
      );

      await tester.tap(find.byType(ArDriveCheckBox));
      await tester.pump();

      await tester.enterText(find.byType(ArDriveTextField), wellFormedKey);
      await tester.pump();

      states.add(success());
      await tester.pump();

      expect(storage[SharedFileKeySession.storageKey(fileId)], wellFormedKey);
    });
  });

  group('READY', () {
    testWidgets('leads with Download and keeps transaction ids in the drawer',
        (tester) async {
      await pumpPage(tester, success());

      expect(find.text('Q3 Report.pdf'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('sharedFileDownload_data-tx-newest')),
        findsOneWidget,
      );

      // Nothing technical before the recipient asks for it.
      expect(find.text('data-tx-newest'), findsNothing);
      expect(find.text('metadata-tx'), findsNothing);

      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();

      expect(find.text('data-tx-newest'), findsOneWidget);
      expect(find.text('metadata-tx'), findsOneWidget);
    });

    testWidgets('asks for the version history only when it is opened',
        (tester) async {
      await pumpPage(tester, success());

      verifyNever(() => cubit.loadActivity());

      // Deliberately not `pumpAndSettle`: an unanswered history shows a
      // spinner, and a spinner never settles.
      await tester.tap(find.byType(ExpansionTile).last);
      await tester.pump();

      verify(() => cubit.loadActivity()).called(1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // The history lives on its own list. It is empty on a v2 link until the
      // resolver answers, and `fileRevisions` - the download target - is never
      // where it comes from.
      states.add(success(
        activityRevisions: [
          fileRevision(),
          fileRevision(dataTxId: 'data-tx-first', size: 12),
        ],
        activityStatus: SharedFileActivityStatus.loaded,
      ));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text(filesize(12)), findsOneWidget);
    });

    testWidgets('says so when the version history cannot be loaded, and never '
        'spins for ever', (tester) async {
      await pumpPage(tester, success());

      await tester.tap(find.byType(ExpansionTile).last);
      await tester.pump();

      states.add(success(activityStatus: SharedFileActivityStatus.failed));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      // No revision rows: only the header's own size is on screen.
      expect(find.text(filesize(4821133)), findsOneWidget);
    });

    testWidgets('never spins for ever on a history that came back empty',
        (tester) async {
      await pumpPage(tester, success());

      await tester.tap(find.byType(ExpansionTile).last);
      await tester.pump();

      states.add(success(activityStatus: SharedFileActivityStatus.loaded));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('never offers a download it cannot name', (tester) async {
      // The v2 fast path paints before the metadata resolves; a link that hid
      // the file's details leaves the revision a placeholder until then.
      await pumpPage(
        tester,
        SharedFileLoadSuccess(
          fileRevisions: [fileRevision(name: '', size: 0)],
          verification: LinkVerification.pending,
          detailsAreResolved: false,
        ),
      );

      final download = tester.widget<ArDriveButton>(
        find.byKey(const ValueKey('sharedFileDownload_data-tx-newest')),
      );

      expect(download.isDisabled, isTrue);
      // Nor a preview it cannot fetch.
      expect(find.text('Preview'), findsNothing);
    });

    testWidgets('shows the verification badge the link earned', (tester) async {
      await pumpPage(tester, success(verification: LinkVerification.verified));

      expect(find.text('Verified'), findsOneWidget);
    });

    testWidgets('warns, without alarming, when the link cannot be checked',
        (tester) async {
      await pumpPage(
        tester,
        success(verification: LinkVerification.unavailable),
      );

      expect(find.text('Verified'), findsNothing);
      expect(find.textContaining("don't match"), findsNothing);
    });

    testWidgets('offers a newer version without changing what Download fetches',
        (tester) async {
      await pumpPage(tester, success(newerVersionAvailable: true));

      expect(find.textContaining('newer version'), findsOneWidget);
      expect(find.text('Get latest'), findsOneWidget);

      // The offer never moves the download target.
      expect(
        find.byKey(const ValueKey('sharedFileDownload_data-tx-newest')),
        findsOneWidget,
      );

      await tester.tap(find.text('Get latest'));
      await tester.pump();

      // Taking the offer asks the resolver for the newest revision. The page
      // never swaps the target itself, and `retry()` - which re-resolves the
      // link and lands on the revision it already had - is not what this does.
      verify(() => cubit.showLatestRevision()).called(1);
      verifyNever(() => cubit.retry());
      expect(
        find.byKey(const ValueKey('sharedFileDownload_data-tx-newest')),
        findsOneWidget,
      );

      // Only the resolver's own answer moves it.
      states.add(success(
        revision: fileRevision(dataTxId: 'data-tx-newer'),
        linkRevision: fileRevision(),
        showsLatestRevision: true,
      ));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('sharedFileDownload_data-tx-newer')),
        findsOneWidget,
      );
      expect(find.textContaining('newer version'), findsNothing);
    });

    testWidgets('does not take the offer twice while it is being answered',
        (tester) async {
      final answer = Completer<void>();

      when(() => cubit.showLatestRevision()).thenAnswer((_) => answer.future);

      await pumpPage(tester, success(newerVersionAvailable: true));

      await tester.tap(find.text('Get latest'));
      await tester.pump();

      final action = tester.widget<ArDriveButton>(
        find.ancestor(
          of: find.text('Get latest'),
          matching: find.byType(ArDriveButton),
        ),
      );

      expect(action.isDisabled, isTrue);

      await tester.tap(find.text('Get latest'), warnIfMissed: false);
      await tester.pump();

      verify(() => cubit.showLatestRevision()).called(1);

      answer.complete();
      await tester.pump();
    });

    testWidgets('a pinned link says which version it is showing, and puts the '
        'shared one back', (tester) async {
      await pumpPage(
        tester,
        success(newerVersionAvailable: true, isPinned: true),
      );

      expect(find.text('View latest'), findsOneWidget);
      expect(find.text('Get latest'), findsNothing);

      await tester.tap(find.text('View latest'));
      await tester.pump();

      verify(() => cubit.showLatestRevision()).called(1);
      // Still the pinned bytes until the resolver answers.
      expect(
        find.byKey(const ValueKey('sharedFileDownload_data-tx-newest')),
        findsOneWidget,
      );

      states.add(success(
        revision: fileRevision(dataTxId: 'data-tx-newer'),
        linkRevision: fileRevision(),
        isPinned: true,
        showsLatestRevision: true,
      ));
      await tester.pump();

      // A pinned page never quietly stops being pinned: it says what it is
      // showing, and the version that was actually sent is one tap away.
      expect(find.textContaining('latest version'), findsOneWidget);
      expect(find.text('View shared version'), findsOneWidget);

      await tester.tap(find.text('View shared version'));
      await tester.pump();

      verify(() => cubit.showSharedRevision()).called(1);
    });
  });

  group('RESOLVING', () {
    testWidgets('fills the skeleton with what the link already knows',
        (tester) async {
      await pumpPage(
        tester,
        resolving(
          payload: const SharedFileLinkPayload(
            name: 'Q3 Report.pdf',
            size: 4821133,
            contentType: 'application/pdf',
          ),
        ),
      );

      expect(find.text('Q3 Report.pdf'), findsOneWidget);
      expect(find.text(filesize(4821133)), findsOneWidget);
      expect(find.textContaining('Loading file details'), findsOneWidget);
    });
  });

  group('NOT_FOUND', () {
    testWidgets('counts down while the file may still be propagating',
        (tester) async {
      await pumpPage(
        tester,
        notFound(retryAttempt: 1, mayStillBePropagating: true),
      );

      expect(find.textContaining('still be propagating'), findsOneWidget);
      // The resolver waits `3s * attempt`; this card counts the same wait.
      expect(find.textContaining('Retrying in 3'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('Retrying in 2'), findsOneWidget);
    });

    testWidgets('stops waiting after the automatic attempts', (tester) async {
      await pumpPage(
        tester,
        notFound(retryAttempt: 3, mayStillBePropagating: false),
      );

      expect(find.textContaining('Retrying in'), findsNothing);
      expect(
        find.textContaining('find this file on the network'),
        findsOneWidget,
      );

      await tester.tap(find.text('Retry'));
      await tester.pump();

      verify(() => cubit.retry()).called(1);
    });

    testWidgets('keeps the plain answer for a file that was never there',
        (tester) async {
      await pumpPage(
        tester,
        notFound(retryAttempt: 0, mayStillBePropagating: false),
      );

      expect(find.textContaining('does not exist'), findsOneWidget);
      expect(find.textContaining('Retrying in'), findsNothing);
    });
  });

  group('ERROR_NETWORK', () {
    testWidgets('says it is trying another route, then offers Retry',
        (tester) async {
      await pumpPage(tester, SharedFileLoadFailure());

      expect(
        find.textContaining('trouble reaching the network'),
        findsOneWidget,
      );

      await tester.tap(find.text('Retry'));
      await tester.pump();

      verify(() => cubit.retry()).called(1);
    });
  });

  group('ERROR_LINK', () {
    testWidgets('asks the sender for the link again, and offers nothing else',
        (tester) async {
      // `/file//view` - a link that names no file at all. The resolver answers
      // it without a request, and this is what the recipient sees.
      await pumpPage(tester, const SharedFileLinkDamaged());

      expect(find.textContaining('link looks incomplete'), findsOneWidget);
      // Nothing to retry and nothing to unlock: only the sender can fix it.
      expect(find.text('Retry'), findsNothing);
      expect(find.byType(ArDriveTextField), findsNothing);
    });
  });

  group('jargon', () {
    testWidgets('never says ArFS, data item, manifest, drive key or tx',
        (tester) async {
      await pumpPage(tester, success());

      for (final jargon in const [
        'ArFS',
        'data item',
        'manifest',
        'drive key',
        'file key',
        'Tx ID',
      ]) {
        expect(
          find.textContaining(jargon),
          findsNothing,
          reason: '"$jargon" reached the recipient',
        );
      }
    });

    testWidgets('the locked gate speaks of an access key', (tester) async {
      await pumpPage(tester, locked());

      expect(find.textContaining('access key'), findsWidgets);
      expect(find.textContaining('file key'), findsNothing);
      expect(find.textContaining('File Key'), findsNothing);
    });
  });
}
