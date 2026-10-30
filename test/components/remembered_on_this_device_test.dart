import 'dart:async';

import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/components/remembered_on_this_device.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/utils.dart';

/// Drive details, "On this device": whether the key is remembered here, and
/// Forget on this device, at the details panel's width.
void main() {
  const driveId = 'b3c8cb1b-4c3b-5d2c-9b3f-7e2b1c4d5e6f';
  late MockDriveDao driveDao;
  late MockArDriveAuth auth;
  late StreamController<bool> remembered;
  final deviceKey = SecretKey(List.filled(32, 7));

  setUp(() {
    driveDao = MockDriveDao();
    auth = MockArDriveAuth();
    remembered = StreamController<bool>.broadcast();
    when(() => driveDao.watchDriveKeyRemembered(driveId))
        .thenAnswer((_) => remembered.stream);
    when(() => driveDao.forgetDriveKey(driveId, deviceKey))
        .thenAnswer((_) async {
      remembered.add(false);
      return true;
    });
    when(() => auth.currentUser).thenReturn(User(
      password: 'pw',
      wallet: getTestWallet(),
      walletAddress: 'owner',
      walletBalance: BigInt.zero,
      cipherKey: deviceKey,
      profileType: ProfileType.json,
      errorFetchingIOTokens: false,
    ));
  });
  tearDown(() => remembered.close());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ArDriveTheme(
      themeData: lightTheme(),
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: const [Locale('en', '')],
        home: Scaffold(
          body: MultiRepositoryProvider(
            providers: [
              RepositoryProvider<DriveDao>.value(value: driveDao),
              RepositoryProvider<ArDriveAuth>.value(value: auth),
            ],
            // About the details panel's content width. Tests draw text in
            // Ahem, a square per letter, much wider than the app's font, so
            // this is a little wider than the panel.
            child: const Center(
              child: SizedBox(
                width: 400,
                child: RememberedOnThisDevice(driveId: driveId),
              ),
            ),
          ),
        ),
      ),
    ));
    remembered.add(true);
    await tester.pumpAndSettle();
  }

  testWidgets(
      'a remembered drive says so and offers Forget, in full at the panel\'s '
      'width; Forget turns it to Not remembered', (tester) async {
    await pump(tester);

    expect(find.text('Remembered'), findsOneWidget);
    final label = tester
        .renderObject<RenderParagraph>(find.text('Forget on this device'));
    expect(label.didExceedMaxLines, isFalse);
    expect(
      label.size.width,
      greaterThanOrEqualTo(label.getMaxIntrinsicWidth(double.infinity) - 1),
      reason: 'the label is not cut short',
    );

    await tester.tap(find.text('Forget on this device'));
    await tester.pumpAndSettle();

    verify(() => driveDao.forgetDriveKey(driveId, deviceKey)).called(1);
    expect(find.text('Not remembered'), findsOneWidget);
    expect(find.text('Forget on this device'), findsNothing);
  });
}
