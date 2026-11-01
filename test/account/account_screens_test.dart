@Tags(['measurement'])
library;

// Screenshots of Account and security for each way of signing in, with fake
// data, for review. Not an assertion: run with
// flutter test test/account/account_screens_test.dart --run-skipped --tags=measurement
// and find the PNGs in build/account-shots.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:ardrive/account/presentation/account_page.dart';
import 'package:ardrive/arns/data/arns_wallet_store.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/components/list_page/list_page_layout.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

import '../test_utils/utils.dart';

class _MockWalletCubit extends MockCubit<ArNSWalletState>
    implements ArNSWalletCubit {}

final _outDir = Directory('build/account-shots');

// Made-up addresses, not real wallets.
const _arweave = 'Hm3rXq7LkP2sVt9aBcDeFgHiJkLmNoPqRsTuVwtW8c';
const _solana = '7xKpQd2aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567Qd2a';
const _ethereum = '0x4f2a6c0d9e8b7a6f5e4d3c2b1a0f9e8d7c6b91bc';

User _user({ProfileType type = ProfileType.json, String? source}) => User(
      password: 'password',
      wallet: getTestWallet(),
      walletAddress: _arweave,
      walletBalance: BigInt.zero,
      cipherKey: SecretKey([1, 2, 3]),
      profileType: type,
      errorFetchingIOTokens: false,
      sourceWalletAddress: source,
    );

Future<ByteData> _read(String path) async =>
    ByteData.view(Uint8List.fromList(File(path).readAsBytesSync()).buffer);

/// The app's faces, as test/arns/arns_screens_test.dart loads them.
Future<void> _loadFonts() async {
  const dir = 'packages/ardrive_ui/assets/fonts';
  final wavehaus = FontLoader('packages/ardrive_ui/Wavehaus');
  for (final f in [
    'Wavehaus-42Light.otf',
    'Wavehaus-66Book.otf',
    'Wavehaus-95SemiBold.otf',
    'Wavehaus-128Bold.otf',
  ]) {
    wavehaus.addFont(_read('$dir/$f'));
  }
  await wavehaus.load();
  await (FontLoader('packages/ardrive_ui/ArDriveIcons')
        ..addFont(_read('$dir/ArDriveIcons.ttf')))
      .load();
  ArDriveMonospace.readFont = () => _read('$dir/mono/RobotoMono-Regular.ttf');
  await ArDriveMonospace.ensureLoaded();
}

void main() {
  setUpAll(_loadFonts);

  final kinds = <String, (User, String?, int)>{
    'keyfile': (_user(), null, 2),
    'wander': (_user(type: ProfileType.arConnect), null, 0),
    'phantom': (_user(source: _solana), 'phantom', 1),
    'metamask': (_user(source: _ethereum), null, 3),
  };

  Future<void> capture(
    WidgetTester tester,
    String name, {
    required User user,
    required String? solanaProvider,
    required int remembered,
    required bool phone,
    required bool dark,
  }) async {
    final size = phone ? const Size(390, 844) : const Size(1000, 700);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = size * 2;
    addTearDown(tester.view.reset);

    final auth = MockArDriveAuth();
    when(() => auth.currentUser).thenReturn(user);
    final profile = MockProfileCubit();
    whenListen(profile, const Stream<ProfileState>.empty(),
        initialState: ProfileLoggedIn(user: user, useTurbo: false));
    final dao = MockDriveDao();
    when(() => dao.watchRememberedDriveKeyCount(
          ownerAddress: any(named: 'ownerAddress'),
        )).thenAnswer((_) => Stream.value(remembered));
    final config = MockConfigService();
    when(() => config.config).thenReturn(AppConfig(
      allowedDataItemSizeForTurbo: 0,
      stripePublishableKey: '',
      enableArNS: true,
    ));
    final wallet = _MockWalletCubit();
    whenListen(wallet, const Stream<ArNSWalletState>.empty(),
        initialState: ArNSWalletState(
          enabled: true,
          profileAddress: _arweave,
          linked: solanaProvider != null
              ? const LinkedArNSWallet(address: _solana)
              : null,
        ));

    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MultiRepositoryProvider(
          providers: [
            RepositoryProvider<ArDriveAuth>.value(value: auth),
            RepositoryProvider<DriveDao>.value(value: dao),
            RepositoryProvider<ConfigService>.value(value: config),
          ],
          child: MultiBlocProvider(
            providers: [
              BlocProvider<ProfileCubit>.value(value: profile),
              BlocProvider<ArNSWalletCubit>.value(value: wallet),
              ListenableProvider<AppRouterDelegate>.value(
                value: AppRouterDelegate(),
              ),
            ],
            child: ArDriveApp(
              themeData: dark ? null : lightTheme(),
              builder: (context) => MaterialApp(
                debugShowCheckedModeBanner: false,
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: ArDriveTheme.of(context).themeData.materialThemeData,
                home: Builder(
                  builder: (context) => phone
                      ? AccountPage(solanaProvider: solanaProvider)
                      // The desktop page's main area, without the top bar.
                      : Scaffold(
                          backgroundColor: ArDriveTheme.of(context)
                              .themeData
                              .colorTokens
                              .containerL0,
                          body: SingleChildScrollView(
                            padding: const EdgeInsets.only(top: 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ListPageTitleRow(
                                  title: ListPageTitleRow.text(
                                      context, 'Account and security'),
                                ),
                                const SizedBox(height: listPageBlockGap),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: listPagePadding),
                                  child: PageContentColumn(
                                    child: AccountSections(
                                      solanaProvider: solanaProvider,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(
          '${_outDir.path}/$name-${phone ? '390' : 'desktop'}-${dark ? 'dark' : 'light'}.png');
      file.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  for (final entry in kinds.entries) {
    testWidgets('account: ${entry.key}', (tester) async {
      final (user, provider, remembered) = entry.value;
      for (final phone in [true, false]) {
        for (final dark in [false, true]) {
          await capture(
            tester,
            entry.key,
            user: user,
            solanaProvider: provider,
            remembered: remembered,
            phone: phone,
            dark: dark,
          );
        }
      }
    });
  }
}
