import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/drive_create/first_drive.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/pages/no_drives/first_drive_page.dart';
import 'package:ardrive/sync/presentation/sync_loading_indicator.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

class _MockFirstDrive extends Mock implements FirstDrive {}

void main() {
  late MockProfileCubit profileCubit;
  late _MockFirstDrive firstDrive;

  setUp(() {
    profileCubit = MockProfileCubit();
    firstDrive = _MockFirstDrive();
    whenListen(
      profileCubit,
      const Stream<ProfileState>.empty(),
      initialState: ProfileLoggedIn(
        user: User(
          password: 'password',
          wallet: getTestWallet(),
          walletAddress: 'new-wallet',
          walletBalance: BigInt.zero,
          cipherKey: SecretKey([]),
          profileType: ProfileType.json,
          errorFetchingIOTokens: false,
        ),
        useTurbo: true,
      ),
    );
  });

  Future<void> pump(WidgetTester tester, CreateFirstDrive create,
      {List<Duration> retryDelays = const []}) async {
    await tester.pumpWidget(
      ArDriveApp(
        builder: (context) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: BlocProvider<ProfileCubit>.value(
            value: profileCubit,
            child: Scaffold(
              body: FirstDrivePage(
                noDrives: (_) => const Text('Getting started'),
                firstDrive: firstDrive,
                createFirstDrive: create,
                retryDelays: retryDelays,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  setUp(() {
    when(() => firstDrive.done()).thenAnswer((_) async {});
    when(() => firstDrive.release(any())).thenAnswer((_) async {});
  });

  testWidgets('a new account has My files made for it', (tester) async {
    when(() => firstDrive.claim('new-wallet')).thenAnswer((_) async => true);
    final making = Completer<FirstDriveOutcome>();
    var asked = 0;

    await pump(tester, (_) {
      asked++;
      return making.future;
    });

    expect(asked, 1);
    expect(find.text('Setting up My files'), findsOneWidget);
    expect(find.byType(SyncLoadingIndicator), findsOneWidget);
    expect(find.text('Getting started'), findsNothing);

    // Made: selecting it opens it, so this page waits to be replaced.
    making.complete(FirstDriveOutcome.made);
    await tester.pump();
    expect(find.text('Getting started'), findsNothing);
    verify(() => firstDrive.done()).called(1);
  });

  testWidgets('tries again while Turbo is away, then makes it', (tester) async {
    when(() => firstDrive.claim('new-wallet')).thenAnswer((_) async => true);
    final outcomes = [
      FirstDriveOutcome.failed,
      FirstDriveOutcome.failed,
      FirstDriveOutcome.made,
    ];
    var asked = 0;

    await pump(tester, (_) async => outcomes[asked++],
        retryDelays: const [Duration(seconds: 3), Duration(seconds: 10)]);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 10));

    expect(asked, 3);
    expect(find.text('Getting started'), findsNothing);
    verify(() => firstDrive.done()).called(1);
    verifyNever(() => firstDrive.release(any()));
  });

  testWidgets('keeps the request for later when Turbo stays away',
      (tester) async {
    when(() => firstDrive.claim('new-wallet')).thenAnswer((_) async => true);
    var asked = 0;

    await pump(tester, (_) async {
      asked++;
      return FirstDriveOutcome.failed;
    }, retryDelays: const [Duration(seconds: 3)]);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();

    expect(asked, 2);
    expect(find.text('Getting started'), findsOneWidget);
    verify(() => firstDrive.release('new-wallet')).called(1);
    verifyNever(() => firstDrive.done());
  });

  testWidgets('drops the request when it needs credits', (tester) async {
    when(() => firstDrive.claim('new-wallet')).thenAnswer((_) async => true);
    var asked = 0;

    await pump(tester, (_) async {
      asked++;
      return FirstDriveOutcome.needsCredits;
    }, retryDelays: const [Duration(seconds: 3)]);
    await tester.pump();

    expect(asked, 1, reason: 'trying again would not change the answer');
    expect(find.text('Getting started'), findsOneWidget);
    verify(() => firstDrive.done()).called(1);
  });

  testWidgets('treats a throw as worth trying again later', (tester) async {
    when(() => firstDrive.claim('new-wallet')).thenAnswer((_) async => true);

    await pump(tester, (_) async => throw StateError('no profile'));
    await tester.pump();

    expect(find.text('Getting started'), findsOneWidget);
    verify(() => firstDrive.release('new-wallet')).called(1);
  });

  testWidgets('anyone else with no drives sees Getting started',
      (tester) async {
    when(() => firstDrive.claim('new-wallet')).thenAnswer((_) async => false);
    var asked = 0;

    await pump(tester, (_) async {
      asked++;
      return FirstDriveOutcome.made;
    });

    expect(asked, 0);
    expect(find.text('Getting started'), findsOneWidget);
  });
}
