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

  Future<void> pump(WidgetTester tester, CreateFirstDrive create) async {
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
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a new account has My files made for it', (tester) async {
    when(() => firstDrive.claim('new-wallet')).thenAnswer((_) async => true);
    final making = Completer<bool>();
    var asked = 0;

    await pump(tester, (_) {
      asked++;
      return making.future;
    });

    expect(asked, 1);
    expect(find.text('Setting up My files'), findsOneWidget);
    expect(find.text('Getting started'), findsNothing);
    expect(find.byType(SyncLoadingIndicator), findsOneWidget);

    // Made: the explorer opens it, so this page waits to be replaced.
    making.complete(true);
    await tester.pump();
    expect(find.text('Getting started'), findsNothing);
  });

  testWidgets('falls back to Getting started when the drive is not made',
      (tester) async {
    when(() => firstDrive.claim('new-wallet')).thenAnswer((_) async => true);

    await pump(tester, (_) async => false);
    await tester.pump();

    expect(find.text('Getting started'), findsOneWidget);
    expect(find.text('Setting up My files'), findsNothing);
  });

  testWidgets('anyone else with no drives sees Getting started',
      (tester) async {
    when(() => firstDrive.claim('new-wallet')).thenAnswer((_) async => false);
    var asked = 0;

    await pump(tester, (_) async {
      asked++;
      return true;
    });

    expect(asked, 0);
    expect(find.text('Getting started'), findsOneWidget);
  });

  testWidgets('falls back to Getting started when making the drive throws',
      (tester) async {
    when(() => firstDrive.claim('new-wallet')).thenAnswer((_) async => true);

    await pump(tester, (_) async => throw StateError('no profile'));
    await tester.pump();

    expect(find.text('Getting started'), findsOneWidget);
  });
}
