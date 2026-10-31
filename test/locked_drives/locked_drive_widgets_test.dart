import 'package:ardrive/components/drive_fingerprint.dart';
import 'package:ardrive/drives_list/domain/drive_list_item.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:ardrive/drives_list/presentation/drive_list_row.dart';
import 'package:ardrive/entities/drive_signature_type.dart';
import 'package:ardrive/locked_drives/data/sign_in_password_proof_store.dart';
import 'package:ardrive/locked_drives/domain/drive_unlock_session.dart';
import 'package:ardrive/locked_drives/domain/drive_unlocker.dart';
import 'package:ardrive/locked_drives/domain/locked_drive.dart';
import 'package:ardrive/locked_drives/presentation/locked_drive_view.dart';
import 'package:ardrive/locked_drives/presentation/unlock_drive_cubit.dart';
import 'package:ardrive/locked_drives/presentation/unlock_drive_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/locked_drive_fixtures.dart' show MemoryKeyValueStore;
import '../test_utils/utils.dart';

class _MockDriveUnlocker extends Mock implements DriveUnlocker {}

class _MockSyncCubit extends Mock implements SyncCubit {}

const _driveId = '6939b9e0-cc98-42cb-bae0-5888eca78885';
const _otherId = '2c1d4b5e-0f3a-4c8b-9d7e-6a5b4c3d2e1f';

const _widths = {'phone': 390.0, 'desktop': 1280.0};

Widget _app(Widget child, {required bool dark}) => ArDriveTheme(
      themeData: dark ? null : lightTheme(),
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en', '')],
        home: Scaffold(body: child),
      ),
    );

void _size(WidgetTester tester, double width) {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  for (final MapEntry(key: name, value: width) in _widths.entries) {
    for (final dark in [false, true]) {
      final where = '$name, ${dark ? 'dark' : 'light'}';

      testWidgets('a locked row says what it is and offers Unlock ($where)',
          (tester) async {
        _size(tester, width);
        var opened = 0;

        await tester.pumpWidget(_app(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: DriveListRow(
                drive: DriveListItem.locked(
                    id: _driveId, dateCreated: DateTime(2026)),
                onOpen: () => opened++,
                showsColumns: driveListShowsColumns(width),
                selected: false,
              ),
            ),
          ),
          dark: dark,
        ));

        expect(tester.takeException(), isNull);
        expect(find.text('Private drive'), findsOneWidget);
        expect(find.text('Locked'), findsOneWidget);
        expect(
            find.bySemanticsLabel(
                RegExp('Drive emoji: milky way, shield, evergreen tree')),
            findsOneWidget);
        // A locked drive takes no tick.
        expect(find.byType(ArDriveCheckBox), findsNothing);

        await tester.tap(find.byKey(const ValueKey('unlock-$_driveId')));
        expect(opened, 1);
      });

      testWidgets(
          'a locked row is exactly as tall as the rows beside it ($where)',
          (tester) async {
        _size(tester, width);
        final columns = driveListShowsColumns(width);

        DriveListItem normal({required bool walked}) => DriveListItem(
              id: walked ? 'synced' : 'never',
              name: 'E2E Locked Login',
              isPrivate: true,
              isSharedWithMe: false,
              isHidden: false,
              dateCreated: DateTime(2026, 10, 29),
              hasBeenWalked: walked,
              fileCount: walked ? 3 : null,
              totalSize: walked ? 350 : null,
              lastSyncedAt: walked ? DateTime.now() : null,
              isSyncing: false,
              lastSyncFailed: false,
            );

        await tester.pumpWidget(_app(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: Column(
                children: [
                  for (final item in [
                    normal(walked: false),
                    normal(walked: true),
                    DriveListItem.locked(
                        id: _driveId, dateCreated: DateTime(2026)),
                  ])
                    DriveListRow(
                      drive: item,
                      onOpen: () {},
                      showsColumns: columns,
                      selected: false,
                    ),
                ],
              ),
            ),
          ),
          dark: dark,
        ));

        expect(tester.takeException(), isNull);
        final heights = [
          for (var i = 0; i < 3; i++)
            tester.getSize(find.byType(DriveListRow).at(i)).height,
        ];
        expect(heights[2], heights[0], reason: 'locked vs never synced');
        // On a phone a synced card's figures can wrap onto a second line in
        // the test font, so its height is its own; a table row's is fixed.
        if (columns) {
          expect(heights[2], heights[1], reason: 'locked vs synced');
        }
      });

      testWidgets('a locked drive\'s page offers Unlock ($where)',
          (tester) async {
        _size(tester, width);
        var unlocks = 0;

        await tester.pumpWidget(_app(
          LockedDrivePanel(driveId: _driveId, onUnlock: () => unlocks++),
          dark: dark,
        ));

        expect(tester.takeException(), isNull);
        expect(find.text('This drive is locked'), findsOneWidget);
        await tester.tap(find.text('Unlock'));
        expect(unlocks, 1);
      });

      testWidgets('the unlock dialog lays out ($where)', (tester) async {
        _size(tester, width);
        final unlocker = _MockDriveUnlocker();
        when(() => unlocker.session).thenReturn(DriveUnlockSession()
          ..setLockedDrives('owner', [
            for (final id in [_driveId, _otherId])
              LockedDrive(
                driveId: id,
                ownerAddress: 'owner',
                signatureType: DriveSignatureType.v2,
                lastUpdated: DateTime(2026),
              ),
          ]));

        await tester.pumpWidget(_app(
          BlocProvider(
            create: (_) => UnlockDriveCubit(
              driveId: _driveId,
              unlocker: unlocker,
              wallet: getTestWallet(),
              profileKey: null,
              syncDrives: (_) async {},
            ),
            child: const Center(child: UnlockDriveDialog()),
          ),
          dark: dark,
        ));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text('Unlock drive'), findsOneWidget);
        expect(find.text('Drive password'), findsOneWidget);
        expect(find.text('Try on my other locked drives'), findsOneWidget);
        expect(
            find.bySemanticsLabel(
                RegExp('Drive emoji: milky way, shield, evergreen tree')),
            findsOneWidget);
      });
    }
  }

  group('the unlock dialog', () {
    late _MockDriveUnlocker unlocker;
    late DriveUnlockSession session;
    late List<List<String>> synced;
    late List<List<String>> announced;

    setUpAll(() => registerFallbackValue(getTestWallet()));

    setUp(() {
      unlocker = _MockDriveUnlocker();
      session = DriveUnlockSession();
      when(() => unlocker.session).thenReturn(session);
      synced = [];
      announced = [];
    });

    void answers(DriveUnlockResult result) {
      when(() => unlocker.unlock(
            wallet: any(named: 'wallet'),
            profileKey: any(named: 'profileKey'),
            driveId: any(named: 'driveId'),
            password: any(named: 'password'),
            tryOthers: any(named: 'tryOthers'),
            remember: any(named: 'remember'),
          )).thenAnswer((_) async => result);
    }

    /// The dialog in a route of its own, as the app shows it, so closing it
    /// can be seen.
    Future<void> open(
      WidgetTester tester, {
      bool othersLocked = true,
      String? walletAddress,
    }) async {
      session.setLockedDrives('owner', [
        for (final id in [_driveId, if (othersLocked) _otherId])
          LockedDrive(
            driveId: id,
            ownerAddress: 'owner',
            signatureType: DriveSignatureType.v2,
            lastUpdated: DateTime(2026),
          ),
      ]);

      await tester.pumpWidget(_app(
        Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => BlocProvider(
                create: (_) => UnlockDriveCubit(
                  driveId: _driveId,
                  unlocker: unlocker,
                  wallet: getTestWallet(),
                  profileKey: null,
                  syncDrives: (ids) async => synced.add(ids),
                ),
                child: Dialog(
                  child: UnlockDriveDialog(
                    onUnlocked: announced.add,
                    walletAddress: walletAddress,
                  ),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
        dark: false,
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    Future<void> typeAndPressEnter(WidgetTester tester, String text) async {
      await tester.enterText(
          find.byKey(const Key('unlockDrivePassword')).first, text);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    EditableText field(WidgetTester tester) =>
        tester.widget<EditableText>(find.byType(EditableText));

    testWidgets(
        'Enter unlocks, trying the other locked drives by default; the '
        'dialog closes and the drives sync', (tester) async {
      answers(const DriveUnlockResult.opened([_driveId, _otherId]));
      await open(tester);

      await typeAndPressEnter(tester, 'secret');

      verify(() => unlocker.unlock(
            wallet: any(named: 'wallet'),
            profileKey: any(named: 'profileKey'),
            driveId: _driveId,
            password: 'secret',
            tryOthers: true,
            remember: true,
          )).called(1);
      expect(find.text('Unlock drive'), findsNothing);
      expect(synced, [
        [_driveId, _otherId]
      ]);
      expect(announced, [
        [_driveId, _otherId]
      ]);
    });

    testWidgets('unticking the box tries only this drive', (tester) async {
      answers(const DriveUnlockResult.opened([_driveId]));
      await open(tester);

      await tester.tap(find.text('Try on my other locked drives'));
      await tester.pump();
      await typeAndPressEnter(tester, 'secret');

      verify(() => unlocker.unlock(
            wallet: any(named: 'wallet'),
            profileKey: any(named: 'profileKey'),
            driveId: _driveId,
            password: 'secret',
            tryOthers: false,
            remember: true,
          )).called(1);
    });

    testWidgets(
        '"Remember on this device" is on by default; unticked, the drive is '
        'kept for this session only', (tester) async {
      answers(const DriveUnlockResult.opened([_driveId]));
      await open(tester);

      final box = find.byKey(const Key('unlockDriveRemember'));
      expect(box, findsOneWidget);
      expect(find.text('Remember on this device'), findsOneWidget);

      await tester.tap(find.text('Remember on this device'));
      await tester.pump();
      await typeAndPressEnter(tester, 'secret');

      verify(() => unlocker.unlock(
            wallet: any(named: 'wallet'),
            profileKey: any(named: 'profileKey'),
            driveId: _driveId,
            password: 'secret',
            tryOthers: true,
            remember: false,
          )).called(1);
    });

    testWidgets('the box is there with no other locked drive too',
        (tester) async {
      await open(tester, othersLocked: false);

      expect(find.text('Remember on this device'), findsOneWidget);
    });

    testWidgets(
        'the password field asks the browser for the saved drive password, '
        'beside the account\'s address', (tester) async {
      await open(tester, walletAddress: 'the-wallet-address');

      // The TextField is the autofill client; EditableText only draws.
      final password = tester.widget<TextField>(find.descendant(
          of: find.byKey(const Key('unlockDrivePassword')),
          matching: find.byType(TextField)));
      expect(password.autofillHints, [AutofillHints.password]);
      final username = tester.widget<TextField>(find
          .byKey(const Key('passwordAutofillUsername'), skipOffstage: false));
      expect(username.controller!.text, 'the-wallet-address');
      expect(username.autofillHints, [AutofillHints.username]);
      // One group: the browser sees the address and the password together.
      final passwordElement = tester.element(find.descendant(
          of: find.byKey(const Key('unlockDrivePassword')),
          matching: find.byType(TextField)));
      final usernameElement = tester.element(find.byKey(
          const Key('passwordAutofillUsername'),
          skipOffstage: false));
      expect(AutofillGroup.of(passwordElement),
          same(AutofillGroup.of(usernameElement)));
    });

    testWidgets('with no other locked drive, there is no box to tick',
        (tester) async {
      await open(tester, othersLocked: false);

      expect(find.text('Try on my other locked drives'), findsNothing);
    });

    testWidgets(
        'a wrong password says "Wrong password", and the field is focused '
        'with its text selected', (tester) async {
      answers(const DriveUnlockResult.failed(DriveUnlockFailure.wrongPassword));
      await open(tester);

      await typeAndPressEnter(tester, 'typo');

      expect(find.text('Wrong password'), findsOneWidget);
      expect(find.text("Couldn't reach the network. Try again."), findsNothing);
      expect(field(tester).focusNode.hasFocus, isTrue);
      expect(field(tester).controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 4));
      expect(synced, isEmpty);
    });

    testWidgets(
        'anything else says the network couldn\'t be reached, never "Wrong '
        'password"', (tester) async {
      answers(const DriveUnlockResult.failed(DriveUnlockFailure.unavailable));
      await open(tester);

      await typeAndPressEnter(tester, 'secret');

      expect(
          find.text("Couldn't reach the network. Try again."), findsOneWidget);
      expect(find.text('Wrong password'), findsNothing);
      expect(field(tester).focusNode.hasFocus, isTrue);
    });

    testWidgets('a cancelled wallet prompt returns quietly to the dialog',
        (tester) async {
      answers(
          const DriveUnlockResult.failed(DriveUnlockFailure.walletDeclined));
      await open(tester);

      await typeAndPressEnter(tester, 'secret');

      expect(find.text('Unlock drive'), findsOneWidget);
      expect(find.text('Wrong password'), findsNothing);
      expect(find.text("Couldn't reach the network. Try again."), findsNothing);
      expect(field(tester).focusNode.hasFocus, isTrue);
    });

    testWidgets(
        'a wallet that couldn\'t sign, not cancelled, says so and keeps the '
        'dialog', (tester) async {
      answers(const DriveUnlockResult.failed(DriveUnlockFailure.walletFailed));
      await open(tester);

      await typeAndPressEnter(tester, 'secret');

      expect(
          find.text("Your wallet couldn't sign. Try again."), findsOneWidget);
      expect(find.text('Wrong password'), findsNothing);
      expect(field(tester).focusNode.hasFocus, isTrue);
    });

    testWidgets('typing again clears the error', (tester) async {
      answers(const DriveUnlockResult.failed(DriveUnlockFailure.wrongPassword));
      await open(tester);
      await typeAndPressEnter(tester, 'typo');

      await tester.enterText(
          find.byKey(const Key('unlockDrivePassword')).first, 'typo2');
      await tester.pump();

      expect(find.text('Wrong password'), findsNothing);
    });

    testWidgets('an empty field does not submit', (tester) async {
      answers(const DriveUnlockResult.opened([_driveId]));
      await open(tester);

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      verifyNever(() => unlocker.unlock(
            wallet: any(named: 'wallet'),
            profileKey: any(named: 'profileKey'),
            driveId: any(named: 'driveId'),
            password: any(named: 'password'),
            tryOthers: any(named: 'tryOthers'),
            remember: any(named: 'remember'),
          ));
    });
  });

  testWidgets(
      'a not-found drive that isn\'t locked - a visitor\'s link with no key '
      '- gets no locked page and no shell', (tester) async {
    final session = DriveUnlockSession();
    var framed = 0;

    Widget view() => _app(
          RepositoryProvider.value(
            value: session,
            child: LockedDriveView(
              driveId: _driveId,
              otherwise: const SizedBox(key: Key('nothing')),
              frame: (panel) {
                framed++;
                return panel;
              },
            ),
          ),
          dark: false,
        );

    await tester.pumpWidget(view());
    expect(find.byKey(const Key('nothing')), findsOneWidget);
    expect(find.text('This drive is locked'), findsNothing);
    expect(framed, 0);

    session.setLockedDrives('owner', [
      LockedDrive(
        driveId: _driveId,
        ownerAddress: 'owner',
        signatureType: DriveSignatureType.v2,
        lastUpdated: DateTime(2026),
      ),
    ]);
    await tester.pump();
    expect(find.text('This drive is locked'), findsOneWidget);
    expect(framed, greaterThan(0));
  });

  test('the sync after an unlock never asks the wallet again for others',
      () async {
    final syncCubit = _MockSyncCubit();
    when(() => syncCubit.isClosed).thenReturn(false);
    when(() => syncCubit.syncDrives(any(),
            askWalletAgain: any(named: 'askWalletAgain'),
            skipTabVisibilityCheck: any(named: 'skipTabVisibilityCheck')))
        .thenAnswer((_) async => true);

    await syncUnlockedDrives(syncCubit, [_driveId]);

    verify(() => syncCubit.syncDrives([_driveId],
        askWalletAgain: false, skipTabVisibilityCheck: true)).called(1);
  });

  test(
      'the sync after an unlock that stays refused gives up after a few '
      'tries, waiting between them', () async {
    final syncCubit = _MockSyncCubit();
    when(() => syncCubit.isClosed).thenReturn(false);
    when(() => syncCubit.waitUntilSyncCanStart()).thenAnswer((_) async {});
    when(() => syncCubit.lastStartWasRefused).thenReturn(true);
    when(() => syncCubit.syncDrives(any(),
            askWalletAgain: any(named: 'askWalletAgain'),
            skipTabVisibilityCheck: any(named: 'skipTabVisibilityCheck')))
        .thenAnswer((_) async => false);

    await syncUnlockedDrives(syncCubit, [_driveId]);

    verify(() => syncCubit.syncDrives([_driveId],
        askWalletAgain: false, skipTabVisibilityCheck: true)).called(3);
    verify(() => syncCubit.waitUntilSyncCanStart()).called(2);
  });

  test('the sync after an unlock that ran and was stopped is not retried',
      () async {
    final syncCubit = _MockSyncCubit();
    when(() => syncCubit.isClosed).thenReturn(false);
    when(() => syncCubit.lastStartWasRefused).thenReturn(false);
    when(() => syncCubit.syncDrives(any(),
            askWalletAgain: any(named: 'askWalletAgain'),
            skipTabVisibilityCheck: any(named: 'skipTabVisibilityCheck')))
        .thenAnswer((_) async => false);

    await syncUnlockedDrives(syncCubit, [_driveId]);

    verify(() => syncCubit.syncDrives([_driveId],
        askWalletAgain: false, skipTabVisibilityCheck: true)).called(1);
    verifyNever(() => syncCubit.waitUntilSyncCanStart());
  });

  testWidgets('the fingerprint is drawn in its own colour emoji face',
      (tester) async {
    await tester.pumpWidget(
        _app(const DriveFingerprint(driveId: _driveId), dark: false));

    final text = tester.widget<Text>(find.byType(Text).first);
    expect(text.style?.fontFamily, FingerprintEmojiFont.family);
  });

  group('which face draws the fingerprint', () {
    test('CanvasKit, any browser: the bundled colour face', () {
      for (final webKit in [true, false]) {
        expect(
            usesBundledEmojiFont(
                isWeb: true,
                webKit: webKit,
                canvasKit: true,
                platform: TargetPlatform.macOS),
            isTrue);
      }
    });

    test(
        'the HTML renderer in Safari or any iOS browser: the system\'s Apple '
        'Color Emoji, which WebKit can draw', () {
      expect(
          usesBundledEmojiFont(
              isWeb: true,
              webKit: true,
              canvasKit: false,
              platform: TargetPlatform.iOS),
          isFalse);
    });

    test('the HTML renderer in Chrome on Android: the bundled face', () {
      expect(
          usesBundledEmojiFont(
              isWeb: true,
              webKit: false,
              canvasKit: false,
              platform: TargetPlatform.android),
          isTrue);
    });

    test('the iOS app: the system face; Android: the bundled one', () {
      expect(
          usesBundledEmojiFont(
              isWeb: false,
              webKit: false,
              canvasKit: false,
              platform: TargetPlatform.iOS),
          isFalse);
      expect(
          usesBundledEmojiFont(
              isWeb: false,
              webKit: false,
              canvasKit: false,
              platform: TargetPlatform.android),
          isTrue);
    });
  });

  group('a password that unlocks a drive', () {
    late _MockDriveUnlocker unlocker;
    late DriveUnlockSession session;
    late MemoryKeyValueStore deviceStore;
    late SignInPasswordProofStore proofStore;
    late String owner;

    setUpAll(() => registerFallbackValue(getTestWallet()));

    setUp(() async {
      owner = await getTestWallet().getAddress();
      unlocker = _MockDriveUnlocker();
      session = DriveUnlockSession()..setSignInPasswordProven(owner, false);
      deviceStore = MemoryKeyValueStore();
      proofStore = SignInPasswordProofStore(store: () async => deviceStore);
      when(() => unlocker.session).thenReturn(session);
      when(() => unlocker.unlock(
                wallet: any(named: 'wallet'),
                profileKey: any(named: 'profileKey'),
                driveId: any(named: 'driveId'),
                password: any(named: 'password'),
                tryOthers: any(named: 'tryOthers'),
                remember: any(named: 'remember'),
              ))
          .thenAnswer((_) async => const DriveUnlockResult.opened([_driveId]));
    });

    UnlockDriveCubit cubit() => UnlockDriveCubit(
          driveId: _driveId,
          unlocker: unlocker,
          wallet: getTestWallet(),
          profileKey: null,
          syncDrives: (_) async {},
          signInPassword: 'sign-in password',
          proofStore: proofStore,
        );

    test(
        'proves the sign-in password when it is that one: in the session and '
        'on this device', () async {
      await proofStore.markUnproven(owner);

      await cubit().submit(password: 'sign-in password', tryOthers: false);

      expect(session.signInPasswordProven(owner), isTrue);
      expect(await proofStore.isUnproven(owner), isFalse);
    });

    test(
        'another password, while the sign-in one is unproven, is one '
        'discovery may try, never the one new drives use, and proves nothing '
        'about the sign-in one', () async {
      await proofStore.markUnproven(owner);

      await cubit().submit(
          password: 'old cli password', tryOthers: true, remember: false);

      expect(session.provenDrivePassword(owner), 'old cli password');
      expect(session.provenDrivePasswordKeepsKeys(owner), isFalse);
      expect(session.newDrivePassword(owner), isNull);
      expect(session.signInPasswordProven(owner), isFalse);
      expect(await proofStore.isUnproven(owner), isTrue);
    });

    test(
        'with "Try on my other locked drives" unticked, discovery is not '
        'given it: the person asked for this drive alone', () async {
      await proofStore.markUnproven(owner);

      await cubit().submit(password: 'old cli password', tryOthers: false);

      expect(session.provenDrivePassword(owner), isNull);
      expect(session.signInPasswordProven(owner), isFalse);
    });
  });
}
