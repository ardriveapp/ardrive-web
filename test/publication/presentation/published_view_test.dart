import 'dart:typed_data';

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/core/crypto/crypto.dart' show DriveKey;
import 'package:ardrive/models/models.dart';
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/publication/presentation/publish/published_view.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../../test_utils/fake_user.dart';
import '../../test_utils/mocks.dart';

class _MockPublicationRepository extends Mock
    implements PublicationRepository {}

void main() {
  late _MockPublicationRepository repository;
  late MockDriveDao driveDao;
  late MockProfileCubit profile;
  late MockConfigService config;

  final drive = Drive(
    id: 'd1d1d1d1-0000-4000-8000-000000000001',
    rootFolderId: 'a0a0a0a0-0000-4000-8000-000000000001',
    ownerAddress: fakeUserJson.walletAddress,
    name: 'Private',
    privacy: 'private',
    isHidden: false,
    dateCreated: DateTime.utc(2026),
    lastUpdated: DateTime.utc(2026),
  );
  final publication = Publication([
    PublishedVersion(
      txId: 'LATEST',
      publicationId: 'pub-1',
      driveId: drive.id,
      scope: const PublicationDriveScope(),
      publishedAt: DateTime.utc(2026, 11, 19),
    ),
  ]);

  setUp(() {
    repository = _MockPublicationRepository();
    driveDao = MockDriveDao();
    profile = MockProfileCubit();
    config = MockConfigService();
    when(() => profile.state)
        .thenReturn(ProfileLoggedIn(user: fakeUserJson, useTurbo: true));
    when(() => driveDao.getDriveKey(any(), any()))
        .thenAnswer((_) async => DriveKey(SecretKey(Uint8List(32)), true));
    when(() => config.config).thenAnswer((_) => AppConfig(
          stripePublishableKey: '',
          allowedDataItemSizeForTurbo: 100,
        ));
  });

  setUpAll(() {
    registerFallbackValue(SecretKey(Uint8List(32)));
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<PublicationRepository>.value(value: repository),
          Provider<DriveDao>.value(value: driveDao),
          Provider<ConfigService>.value(value: config),
          BlocProvider<ProfileCubit>.value(value: profile),
        ],
        child: ArDriveTheme(
          themeData: lightTheme(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SingleChildScrollView(
                child: PublishedView(
                  drive: drive,
                  folder: null,
                  publication: publication,
                  onUpdate: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'a private page whose settings did not load offers a retry, '
      'never a link without its key', (tester) async {
    var reads = 0;
    when(() => repository.readContent(any())).thenAnswer((_) async {
      reads++;
      throw Exception('gateway');
    });
    await pump(tester);

    expect(find.text('Couldn’t read this page’s key.'), findsOneWidget);
    expect(find.textContaining('/LATEST/'), findsNothing);
    // Nor a way to open the page without its key.
    expect(find.text('Open page'), findsNothing);
    expect(reads, 1);

    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('Couldn’t read this page’s key.'), findsOneWidget);
  });
}
