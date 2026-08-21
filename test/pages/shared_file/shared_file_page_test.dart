import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/shared_file/shared_file_key_session.dart';
import 'package:ardrive/pages/shared_file/shared_file_page.dart';
import 'package:ardrive/services/config/selected_gateway.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/pages/shared_file/shared_file_ready_view.dart';
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

import '../../test_utils/mocks.dart';

class MockSharedFileCubit extends MockCubit<SharedFileState>
    implements SharedFileCubit {}

/// A key store whose read is still in flight until [gate] is completed.
///
/// The real store answers out of `sessionStorage` in a microtask, which is
/// fast enough that the race below is hard to hit and impossible to write a
/// test for. It is still a race: `read` is a `Future`, the page is a state
/// machine that keeps moving while it is pending, and nothing about a
/// remembered key entitles it to land on whatever page it finds when it
/// arrives.
class GatedKeySession extends SharedFileKeySession {
  GatedKeySession(this.gate, this.rememberedKey)
      : super(store: SessionKeyValueStore.inMemory());

  final Completer<void> gate;
  final String rememberedKey;

  @override
  Future<String?> read(String fileId) async {
    await gate.future;

    return rememberedKey;
  }
}

/// Widget tests for the recipient landing page
/// (`docs/FILE_SHARING_REDESIGN_PLAN.md` §2).
///
/// The assertions here are about what a *recipient* can see and do: the file
/// they are being given, one obvious download, a key gate that never lies to
/// them, and no transaction id in their face.
/// Only ever handed to `any()`, never read.
final fileRevisionFallback = FileRevision(
  fileId: 'fallback',
  driveId: 'fallback',
  name: 'fallback',
  parentFolderId: 'fallback',
  size: 0,
  lastModifiedDate: DateTime.utc(2024),
  metadataTxId: 'fallback',
  dataTxId: 'fallback',
  dateCreated: DateTime.utc(2024),
  action: RevisionAction.create,
  isHidden: false,
);

void main() {
  const fileId = 'file-id';

  // 43 base64url characters whose last character carries no stray bits - the
  // shape `SharedFileLinkKey.isWellFormed` accepts.
  const wellFormedKey = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopQ';

  late MockSharedFileCubit cubit;
  late MockDriveDao driveDao;
  late MockArweaveService arweave;
  late MockConfigService configService;
  late MockProfileCubit profileCubit;
  late StreamController<SharedFileState> states;

  /// The value rendered beside [label] in the details drawer, scoped to that
  /// label's own row.
  Finder detailRowValue(String label, String value) => find.descendant(
        of: find
            .ancestor(of: find.text(label), matching: find.byType(Row))
            .first,
        matching: find.text(value),
      );

  FileRevision fileRevision({
    String name = 'Q3 Report.pdf',
    String dataTxId = 'data-tx-newest',
    int size = 4821133,
    String? dataContentType = 'application/pdf',
    DateTime? lastModifiedDate,
    DateTime? dateCreated,
  }) {
    return FileRevision(
      fileId: fileId,
      driveId: 'drive-id',
      name: name,
      parentFolderId: 'parent-folder-id',
      size: size,
      lastModifiedDate: lastModifiedDate ?? DateTime.utc(2023, 11, 9),
      dataContentType: dataContentType,
      metadataTxId: 'metadata-tx',
      dataTxId: dataTxId,
      dateCreated: dateCreated ?? DateTime.utc(2024, 3, 3),
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

  /// The page's own dependencies, plus the four the preview reaches for.
  ///
  /// [FsEntryPreviewCubit] resolves `DriveDao`, `ProfileCubit`,
  /// `ArweaveService` and `ConfigService` out of the tree when it is built.
  /// Nothing here opened a preview while it was opt-in, so the harness never
  /// carried them; now that the preview opens on arrival, every test builds one
  /// and they are all required.
  ///
  /// They are inert: the preview is not what these tests are about, and a
  /// preview that reaches the network from a widget test would be worse than
  /// one that does nothing.
  Widget wrap(Widget child) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider<DriveDao>.value(value: driveDao),
        RepositoryProvider<ArweaveService>.value(value: arweave),
        RepositoryProvider<ConfigService>.value(value: configService),
      ],
      child: BlocProvider<ProfileCubit>.value(
        value: profileCubit,
        child: ArDriveTheme(
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
        ),
      ),
    );
  }

  Future<void> pumpPage(
    WidgetTester tester,
    SharedFileState initialState, {
    SharedFileKeySession? keySession,
    // Tall enough that the whole card is laid out and tappable, and narrower
    // than the 950px the desktop fork needs, so every test that is not about
    // the layout gets the phone column.
    Size surface = const Size(800, 1600),
  }) async {
    tester.view.physicalSize = surface;
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

  setUpAll(() => registerFallbackValue(fileRevisionFallback));

  setUp(() {
    cubit = MockSharedFileCubit();
    driveDao = MockDriveDao();
    arweave = MockArweaveService();
    configService = MockConfigService();
    profileCubit = MockProfileCubit();

    when(() => profileCubit.state).thenReturn(ProfilePromptAdd());
    // The preview reads the config the moment it is built, and reaches the
    // gateway url out of it. A real AppConfig is simpler than stubbing the
    // fields one refusal at a time.
    when(() => configService.config).thenReturn(
      AppConfig(
        allowedDataItemSizeForTurbo: 1,
        stripePublishableKey: 'stripePublishableKey',
        arweaveGatewayForDataRequest: const SelectedGateway(
          label: 'Gateway',
          url: 'https://example.com',
        ),
      ),
    );
    states = StreamController<SharedFileState>.broadcast();

    when(() => cubit.fileId).thenReturn(fileId);
    when(() => cubit.submit(any())).thenAnswer((_) async {});
    when(() => cubit.retry()).thenAnswer((_) async {});
    when(() => cubit.loadActivity()).thenAnswer((_) async {});
    when(() => cubit.showLatestRevision()).thenAnswer((_) async {});
    when(() => cubit.showSharedRevision()).thenAnswer((_) async {});
    when(() => cubit.showRevision(any())).thenAnswer((_) async {});
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

    testWidgets('a recipient who changes their mind while the key is being '
        'checked is not overruled when it works', (tester) async {
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

      // Pasting a whole key submits it, so from here the page is holding the
      // key it will write *if* it works.
      await tester.enterText(find.byType(ArDriveTextField), wellFormedKey);
      await tester.pump();

      // Second thoughts, while the unlock is still in flight. Un-ticking
      // clears what is stored; the key of the attempt that is running has to
      // go with it, or it lands in session storage the moment the unlock
      // succeeds - after the recipient said not to keep it.
      await tester.tap(find.byType(ArDriveCheckBox));
      await tester.pump();

      states.add(success());
      await tester.pump();

      expect(storage, isEmpty);
    });

    testWidgets('a remembered key that arrives late never overrides what the '
        'recipient typed', (tester) async {
      // Both well formed, and deliberately different: the assertion is about
      // *which* one is submitted.
      const typedKey = 'ZYXWVUTSRQPONMLKJIHGFEDCBAzyxwvutsrqponmlkQ';
      final gate = Completer<void>();

      await pumpPage(
        tester,
        locked(),
        keySession: GatedKeySession(gate, wellFormedKey),
      );

      await tester.enterText(find.byType(ArDriveTextField), typedKey);
      await tester.pump();

      verify(() => cubit.submit(typedKey)).called(1);

      gate.complete();
      await tester.pump();

      verifyNever(() => cubit.submit(wellFormedKey));

      final field = tester.widget<ArDriveTextField>(
        find.byType(ArDriveTextField),
      );

      expect(field.controller?.text, typedKey);
    });

    testWidgets('a remembered key that arrives after the file is open does '
        'not throw the page back to the gate', (tester) async {
      final gate = Completer<void>();

      await pumpPage(
        tester,
        locked(),
        keySession: GatedKeySession(gate, wellFormedKey),
      );

      // Unlocked by some other route - the key was in the link, or the file
      // turned out not to need one.
      states.add(success());
      await tester.pump();

      gate.complete();
      await tester.pump();

      verifyNever(() => cubit.submit(any()));
      expect(find.text('Download'), findsOneWidget);
    });
  });

  group('READY', () {
    testWidgets('leads with Download and keeps transaction ids in the drawer',
        (tester) async {
      await pumpPage(tester, success());

      // The preview opens on arrival and names the file too, so the name is
      // legitimately on screen more than once.
      expect(find.text('Q3 Report.pdf'), findsWidgets);
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

    testWidgets(
        'the details drawer states the type and when the file was uploaded',
        (tester) async {
      // A recipient sent a link by a stranger has almost nothing to judge the
      // file by, and the upload date is the strongest signal available. It
      // used to appear nowhere on this page: the drawer listed only ids, and
      // the sole date on the page sat inside the version history, which is
      // collapsed and not fetched until opened.
      await pumpPage(tester, success());

      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();

      // Each value is scoped to the row its label is in, so two rows cannot
      // satisfy each other's assertion - a swap between created and modified
      // would otherwise still pass. The expected strings are literal rather
      // than run through `formatDateToUtcString`, which would let a formatter
      // change rewrite the production output and the expectation together.
      expect(detailRowValue('File type', 'application/pdf'), findsOneWidget);
      expect(
        detailRowValue('Date created', '2024-03-03 00:00:00 GMT+0'),
        findsOneWidget,
      );
      expect(
        detailRowValue('Last updated', '2023-11-09 00:00:00 GMT+0'),
        findsOneWidget,
      );
    });

    testWidgets('asks for the version history only when it is opened',
        (tester) async {
      await pumpPage(tester, success());

      verifyNever(() => cubit.loadActivity());

      await tester.tap(find.byType(ExpansionTile).last);
      await tester.pump();

      verify(() => cubit.loadActivity()).called(1);
      // No spinner: the version the link named is already in hand, so the list
      // says what it is still looking for rather than showing nothing.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Looking for other versions'), findsOneWidget);

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

      expect(find.textContaining('Looking for other versions'), findsNothing);
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

    testWidgets('shows no dates until the file\'s own record has them',
        (tester) async {
      // A v2 link carries no timestamps, so the revision it paints from holds
      // the epoch placeholder until the metadata resolves. Rendering that puts
      // "1970-01-01" in front of a recipient as though it were the upload
      // date - worse than showing nothing, and worse than the placeholder was
      // ever meant to be.
      await pumpPage(
        tester,
        SharedFileLoadSuccess(
          fileRevisions: [
            fileRevision(
              lastModifiedDate: DateTime.fromMillisecondsSinceEpoch(0),
              dateCreated: DateTime.fromMillisecondsSinceEpoch(0),
            ),
          ],
          verification: LinkVerification.pending,
          detailsAreResolved: false,
        ),
      );

      await tester.tap(find.byType(ExpansionTile).first);
      await tester.pumpAndSettle();

      expect(find.text('Date created'), findsNothing);
      expect(find.text('Last updated'), findsNothing);
      expect(find.textContaining('1970'), findsNothing);

      // The type still shows: the link really did carry it.
      expect(find.text('File type'), findsOneWidget);
    });

    testWidgets('a failed history keeps the version the recipient was sent',
        (tester) async {
      // The state a rate limited connection lands in. It costs the list, never
      // the file - so the row stays, and it stays selected.
      await pumpPage(
        tester,
        success(
          activityRevisions: [fileRevision()],
          activityStatus: SharedFileActivityStatus.failed,
        ),
      );

      await tester.tap(find.byType(ExpansionTile).last);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Couldn\u2019t check for other versions'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      // The version itself is still listed, and Download is untouched.
      expect(find.text('Download'), findsOneWidget);
    });

    testWidgets('choosing a version asks the resolver for it', (tester) async {
      await pumpPage(
        tester,
        success(
          activityRevisions: [
            fileRevision(dataTxId: 'data-tx-newer'),
            fileRevision(),
          ],
          activityStatus: SharedFileActivityStatus.loaded,
        ),
      );

      await tester.tap(find.byType(ExpansionTile).last);
      await tester.pumpAndSettle();

      expect(find.text('Latest'), findsOneWidget);
      expect(find.text('Shared'), findsOneWidget);

      await tester.tap(find.text('Latest'));
      await tester.pumpAndSettle();

      verify(() => cubit.showRevision(any())).called(1);
    });

    testWidgets('a version with no date is never dated 1970', (tester) async {
      // The list seeds itself with the version the link named so that opening
      // it costs nothing - but a link carries no timestamps, so that row has
      // the epoch placeholder. Rendered, it read as 1 Jan 1970 and then
      // silently corrected itself when the history arrived.
      await pumpPage(
        tester,
        success(
          revision: fileRevision(
            dateCreated: SharedFileCubit.unknownDate,
            lastModifiedDate: SharedFileCubit.unknownDate,
          ),
          activityRevisions: [
            fileRevision(
              dateCreated: SharedFileCubit.unknownDate,
              lastModifiedDate: SharedFileCubit.unknownDate,
            ),
          ],
          activityStatus: SharedFileActivityStatus.loading,
        ),
      );

      await tester.tap(find.byType(ExpansionTile).last);
      await tester.pumpAndSettle();

      expect(find.textContaining('1970'), findsNothing);
      // Named by what it is instead, so the row still says something true.
      expect(find.text('Shared'), findsOneWidget);
    });

    testWidgets('a pinned link names its version pinned, and still lets go',
        (tester) async {
      // Pinning is the sharer saying which version they mean, not a limit on
      // the recipient - who can reach every other version on chain anyway, and
      // whom the freshness banner already offers "View latest". So the chip
      // changes and nothing else does.
      await pumpPage(
        tester,
        success(
          isPinned: true,
          activityRevisions: [
            fileRevision(dataTxId: 'data-tx-newer'),
            fileRevision(),
          ],
          activityStatus: SharedFileActivityStatus.loaded,
        ),
      );

      await tester.tap(find.byType(ExpansionTile).last);
      await tester.pumpAndSettle();

      expect(find.text('Pinned'), findsOneWidget);
      expect(find.text('Shared'), findsNothing);

      // And the newer one is still selectable.
      await tester.tap(find.text('Latest'));
      await tester.pumpAndSettle();

      verify(() => cubit.showRevision(any())).called(1);
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
      // The copy uses a typographic apostrophe (U+2019). An ASCII `'` here
      // matches no widget on any state, which makes the assertion an
      // expensive way of writing nothing.
      expect(find.textContaining('don’t match'), findsNothing);
      expect(find.text('Not checked'), findsOneWidget);
    });

    testWidgets('says so, once, when the link disagrees with the file',
        (tester) async {
      await pumpPage(tester, success(verification: LinkVerification.mismatch));

      expect(find.textContaining('don’t match'), findsOneWidget);
      expect(find.text('Verified'), findsNothing);

      // A mismatch is a warning about the *link*, not a refusal: the file is
      // still there and the recipient can still take it.
      expect(
        find.byKey(const ValueKey('sharedFileDownload_data-tx-newest')),
        findsOneWidget,
      );
      expect(
        tester
            .widget<ArDriveButton>(
              find.byKey(const ValueKey('sharedFileDownload_data-tx-newest')),
            )
            .isDisabled,
        isFalse,
      );
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

  group('layout', () {
    // A phone in portrait, and a laptop. 950 is where `responsive_builder`
    // calls a screen a desktop, so 1440 is comfortably one and 390 is
    // comfortably not.
    const phone = Size(390, 844);
    const laptop = Size(1440, 1000);

    const downloadButton = ValueKey('sharedFileDownload_data-tx-newest');

    /// The width of the one card the page is built around.
    double cardWidth(WidgetTester tester) =>
        tester.getSize(find.byType(ArDriveCard).first).width;

    testWidgets('gives the recipient one narrow column on a phone',
        (tester) async {
      await pumpPage(tester, success(), surface: phone);

      // A single column: no pane to put a preview in, and the card is the
      // reading width it has always been.
      expect(find.byKey(sharedFilePreviewPaneKey), findsNothing);
      expect(cardWidth(tester), lessThanOrEqualTo(400));

      await tester.ensureVisible(find.byKey(downloadButton));
      await tester.pump();

      final download = tester.getRect(find.byKey(downloadButton));

      expect(download.left, greaterThanOrEqualTo(0));
      expect(download.right, lessThanOrEqualTo(phone.width));
      expect(download.top, greaterThanOrEqualTo(0));
      expect(download.bottom, lessThanOrEqualTo(phone.height));
      // The primary action, full width of the column and comfortably over the
      // 44px a control on a touch screen needs.
      expect(download.width, greaterThan(300));
      expect(download.height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens out into two panes on a desktop screen', (tester) async {
      await pumpPage(tester, success(), surface: laptop);

      // The regression this fixes: the ready card used to be capped at the
      // phone's 400px on a monitor, so the preview had 400px to live in.
      expect(cardWidth(tester), greaterThan(400));

      await tester.ensureVisible(find.byKey(downloadButton));
      await tester.pump();

      // Measured after any scrolling, so that the two rectangles are in the
      // same coordinates.
      final pane = tester.getRect(find.byKey(sharedFilePreviewPaneKey));
      final download = tester.getRect(find.byKey(downloadButton));

      // The pane is reserved whether or not the preview is open, so that
      // opening it moves nothing, and it is wide enough to be worth opening.
      expect(pane.height, 420);
      expect(pane.width, greaterThan(400));

      expect(download.left, greaterThanOrEqualTo(0));
      expect(download.right, lessThanOrEqualTo(laptop.width));
      expect(download.top, greaterThanOrEqualTo(0));
      expect(download.bottom, lessThanOrEqualTo(laptop.height));
      expect(download.height, greaterThanOrEqualTo(44));

      // Download stays a button, not a 1000px banner, and it stays on the
      // reading side of the card - to the left of the preview, and above it,
      // so it is the first thing found by eye, pointer and Tab key alike.
      expect(download.width, lessThanOrEqualTo(368));
      expect(download.right, lessThanOrEqualTo(pane.left));
      expect(download.top, lessThan(pane.bottom));
      expect(tester.takeException(), isNull);
    });

    // An overflow is an exception in a widget test, so what these two assert is
    // that the fullest card there is - a name nobody would type by hand, a
    // version notice above it, both drawers open - lays out at all. A card that
    // ran off the side of the screen would take the exception with it.
    SharedFileLoadSuccess crowded() => success(
          newerVersionAvailable: true,
          revision: fileRevision(
            name: 'A file with a name nobody would ever choose to type out by '
                'hand, but which the sender chose anyway.pdf',
          ),
          activityRevisions: [fileRevision()],
          activityStatus: SharedFileActivityStatus.loaded,
        );

    Future<void> openBothDrawers(WidgetTester tester) async {
      // An open drawer can push the card past the bottom of a phone, so each
      // header is scrolled to before it is pressed.
      for (final drawer in [
        find.byType(ExpansionTile).first,
        find.byType(ExpansionTile).last,
      ]) {
        await tester.ensureVisible(drawer);
        await tester.pumpAndSettle();
        await tester.tap(drawer);
        await tester.pumpAndSettle();
      }
    }

    testWidgets('never overflows a phone', (tester) async {
      await pumpPage(tester, crowded(), surface: phone);
      await openBothDrawers(tester);

      expect(tester.takeException(), isNull);
    });

    testWidgets('never overflows a desktop screen', (tester) async {
      await pumpPage(tester, crowded(), surface: laptop);
      await openBothDrawers(tester);

      expect(tester.takeException(), isNull);
      // Still two panes with the card at its fullest.
      expect(find.byKey(sharedFilePreviewPaneKey), findsOneWidget);
    });

    testWidgets('leaves the key gate narrow on a desktop screen',
        (tester) async {
      // Deliberate, and the opposite of the ready card: a key field stretched
      // across a monitor is worse than one that is 400px wide, so only the
      // state that hosts the preview is allowed the extra room.
      await pumpPage(tester, locked(), surface: laptop);

      expect(cardWidth(tester), lessThanOrEqualTo(400));
      expect(find.byKey(sharedFilePreviewPaneKey), findsNothing);
      expect(tester.takeException(), isNull);
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
