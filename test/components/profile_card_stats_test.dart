import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/profile_card.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/permanence/permanence_cache.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/user/name/presentation/bloc/profile_name_bloc.dart';
import 'package:ardrive/user/repositories/user_preferences_repository.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../test_utils/utils.dart';

class _MockPaymentService extends Mock implements PaymentService {}

class _MockProfileNameBloc extends MockBloc<ProfileNameEvent, ProfileNameState>
    implements ProfileNameBloc {}

class _MockUserPreferencesRepository extends Mock
    implements UserPreferencesRepository {}

/// The account line on the profile card: "5 drives • 46 files • 4.8 MiB".
///
/// Right after a first sync every file's data is still pending, so nothing
/// counts as stored yet. The card read "0 files · 0.0 KiB" then, and kept
/// reading it until it was closed and opened again.
void main() {
  // Full length: the card truncates it, and a short one throws.
  const walletAddress = 'Aa1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8S9t0Uv';
  final user = User(
    password: 'password',
    wallet: getTestWallet(),
    walletAddress: walletAddress,
    walletBalance: BigInt.zero,
    cipherKey: SecretKey([1, 2, 3]),
    profileType: ProfileType.json,
    errorFetchingIOTokens: false,
  );

  late Database db;
  late MockProfileCubit profileCubit;
  late MockArDriveAuth auth;

  setUpAll(() {
    registerFallbackValue(getTestWallet());
  });

  setUp(() {
    db = getTestDb();

    profileCubit = MockProfileCubit();
    whenListen(
      profileCubit,
      const Stream<ProfileState>.empty(),
      initialState: ProfileLoggedIn(user: user, useTurbo: false),
    );

    auth = MockArDriveAuth();
    when(() => auth.currentUser).thenReturn(user);
  });

  tearDown(() => db.close());

  Future<void> addDrive(String id) => db.into(db.drives).insert(
        DrivesCompanion.insert(
          id: id,
          rootFolderId: '$id-root',
          ownerAddress: walletAddress,
          name: id,
          privacy: DrivePrivacyTag.public,
        ),
      );

  /// A file as a first sync writes it: its data marked pending.
  Future<void> addSyncedFile(String fileId, {required String driveId}) async {
    await db.into(db.fileRevisions).insert(
          FileRevisionsCompanion.insert(
            fileId: fileId,
            driveId: driveId,
            parentFolderId: '$driveId-root',
            name: fileId,
            metadataTxId: '$fileId-meta',
            dataTxId: '$fileId-data',
            size: 2048,
            lastModifiedDate: DateTime(2024),
            dateCreated: Value(DateTime(2024)),
            action: RevisionAction.create,
          ),
        );
    await db.into(db.networkTransactions).insert(
          NetworkTransactionsCompanion.insert(
            id: '$fileId-data',
            status: const Value(TransactionStatus.pending),
          ),
        );
  }

  /// What the gateway answering does to the rows above.
  Future<void> confirmAll() => db.update(db.networkTransactions).write(
        const NetworkTransactionsCompanion(
          status: Value(TransactionStatus.confirmed),
        ),
      );

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final config = MockConfigService();
    when(() => config.config).thenReturn(
      AppConfig(allowedDataItemSizeForTurbo: 0, stripePublishableKey: ''),
    );

    final payments = _MockPaymentService();
    when(() => payments.getBalance(wallet: any(named: 'wallet')))
        .thenAnswer((_) async => BigInt.zero);
    when(() => auth.onAuthStateChanged())
        .thenAnswer((_) => const Stream.empty());
    when(() => auth.refreshBalance()).thenAnswer((_) async {});

    final names = _MockProfileNameBloc();
    whenListen(
      names,
      const Stream<ProfileNameState>.empty(),
      initialState: const ProfileNameInitial(walletAddress),
    );

    final preferences = _MockUserPreferencesRepository();
    when(() => preferences.watch()).thenAnswer((_) => const Stream.empty());
    when(() => preferences.currentPreferences).thenReturn(null);

    await tester.pumpWidget(
      MultiRepositoryProvider(
        providers: [
          RepositoryProvider<DriveDao>.value(value: db.driveDao),
          RepositoryProvider<ArDriveAuth>.value(value: auth),
          RepositoryProvider<ConfigService>.value(value: config),
          RepositoryProvider<PaymentService>.value(value: payments),
          RepositoryProvider<ArweaveService>.value(
            value: MockArweaveService(),
          ),
          RepositoryProvider<UserPreferencesRepository>.value(
            value: preferences,
          ),
          RepositoryProvider<PermanenceCache>.value(value: PermanenceCache()),
        ],
        child: MultiBlocProvider(
          providers: [
            BlocProvider<ProfileCubit>.value(value: profileCubit),
            BlocProvider<ProfileNameBloc>.value(value: names),
            ListenableProvider<AppRouterDelegate>.value(
              value: AppRouterDelegate(),
            ),
          ],
          child: ArDriveApp(
            builder: (context) => const MaterialApp(
              localizationsDelegates: [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: [Locale('en', '')],
              home: Scaffold(
                body: Align(
                  alignment: Alignment.topRight,
                  child: ProfileCard(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Pumps on the real clock until [finder] finds something, for work the
  /// database does off the test's fake one.
  Future<void> waitFor(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 50 && finder.evaluate().isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await tester.pump();
    }
  }

  /// Unmounts on the real clock, so the card's database watch is cancelled
  /// there: cancelled on the fake one, it leaves a timer behind that holds up
  /// closing the database.
  Future<void> takeDown(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }

  Future<void> openCard(WidgetTester tester) async {
    await tester.tap(find.byType(ProfileCardHeader));
    await tester.pump();
  }

  testWidgets(
      'says nothing about files while every one is still waiting to land, '
      'and counts them once they do, without being reopened', (tester) async {
    await tester.runAsync(() async {
      await addDrive('a');
      await addDrive('b');
      await addSyncedFile('one', driveId: 'a');
      await addSyncedFile('two', driveId: 'b');

      await pumpCard(tester);
      await openCard(tester);
      await waitFor(tester, find.text('2 drives'));

      expect(find.text('2 drives'), findsOneWidget);
      expect(find.textContaining('0 files'), findsNothing);
      expect(find.textContaining('0.0 KiB'), findsNothing);
      expect(find.text('Your permanence'), findsNothing);

      // The card stays open while the gateway confirms what sync wrote.
      await confirmAll();
      await waitFor(tester, find.textContaining('2 files'));

      expect(find.textContaining('2 drives  •  2 files'), findsOneWidget);
      expect(find.text('Your permanence'), findsOneWidget);

      await takeDown(tester);
    });
  });

  testWidgets('still says "0 files" for drives that really have none',
      (tester) async {
    await tester.runAsync(() async {
      await addDrive('empty');

      await pumpCard(tester);
      await openCard(tester);
      await waitFor(tester, find.textContaining('1 drive'));

      expect(find.textContaining('1 drive  •  0 files'), findsOneWidget);

      await takeDown(tester);
    });
  });
}
