@Tags(['measurement'])
library;

// Screenshots of the names screens with fake data, for review. Not an
// assertion: run with
// flutter test test/arns/arns_screens_test.dart --run-skipped --tags=measurement
// and find the PNGs in build/arns-shots.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ardrive/arns/data/arns_change_executor.dart';
import 'package:ardrive/arns/data/arns_file_metadata_writer.dart';
import 'package:ardrive/arns/data/arns_names_repository.dart';
import 'package:ardrive/arns/data/arns_wallet_store.dart';
import 'package:ardrive/arns/data/turbo_arns_action_client.dart';
import 'package:ardrive/arns/domain/arns_action.dart';
import 'package:ardrive/arns/domain/arns_cache_time.dart';
import 'package:ardrive/arns/domain/arns_nameable_item.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_profile_row.dart';
import 'package:ardrive/arns/presentation/item/arns_item_names.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog_cubit.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/arns/presentation/names_page/names_page.dart';
import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/drives_list/presentation/drive_scope_rail.dart';
import 'package:ardrive/pages/app_router_delegate.dart';
import 'package:ardrive/services/config/config.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';

class _MockRepository extends Mock implements ArNSNamesRepository {}

class _MockWalletCubit extends MockCubit<ArNSWalletState>
    implements ArNSWalletCubit {}

class _MockNamesCubit extends MockCubit<ArNSNamesState>
    implements ArNSNamesCubit {}

class _MockClient extends Mock implements TurboArNSActionClient {}

class _MockExecutor extends Mock implements ArNSChangeExecutor {}

class _MockArioSDK extends Mock implements ArioSDK {}

class _MockMetadataWriter extends Mock implements ArNSFileMetadataWriter {}

class _MockPaymentSource extends Mock implements ArNSPaymentSource {}

class _MockOwner extends Mock implements ArNSOwnerSigner {}

class _MockPayer extends Mock implements ArNSPayerSigner {}

class _MockConfigService extends Mock implements ConfigService {}

const _sol = '7xKpH3nV9qR2bT5mW8cY4dF6gJ1kL3sA9eZ2uQ7q2Fd';
const _siteTx = 'nS7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWeQ';
const _blogTx = 'S1QzT9YbPo8iU7yT6rE5wQ4aS3dF2gH1jK0lZxCvBnM';
const _elseTx = 'Zvp8dEkO3nQ2wX9yV8uT7sR6qP5oN4mL3kJ2iH1gF0c';
const _placeholder = 'PlcHoLdErPlcHoLdErPlcHoLdErPlcHoLdErPlcHo1';

String _svg(String bg, String fg) => Uri.dataFromString(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 28 28">'
      '<rect width="28" height="28" rx="7" fill="$bg"/>'
      '<circle cx="14" cy="14" r="6" fill="$fg"/></svg>',
      mimeType: 'image/svg+xml',
    ).toString();

final _wallets = [
  SolanaWalletInfo(name: 'Phantom', icon: _svg('#AB9FF2', '#FFFFFF')),
  SolanaWalletInfo(name: 'Solflare', icon: _svg('#FFEF46', '#02050A')),
  SolanaWalletInfo(name: 'Backpack', icon: _svg('#E33E3F', '#FFFFFF')),
];

const _site = ArNSFileItem(
  fileId: 'f1',
  driveId: 'd1',
  name: 'Portfolio site',
  parentFolderId: 'root',
  isManifest: true,
  isHidden: false,
  isLatestVersion: true,
);

final _now = DateTime.now();

List<ArNSManagedName> _names() => [
      const ArNSManagedName(
        name: 'acme',
        processId: 'ant-acme',
        role: ArNSRole.owner,
        type: ArNSNameType.permabuy,
        endTimestamp: null,
        undernameLimit: 10,
        records: [
          ArNSNameRecord(
            name: 'acme',
            undername: '@',
            transactionId: _siteTx,
            ttlSeconds: 300,
            target: _site,
          ),
          ArNSNameRecord(
            name: 'acme',
            undername: 'blog',
            transactionId: _blogTx,
            ttlSeconds: 3600,
            target: ArNSFileItem(
              fileId: 'f2',
              driveId: 'd1',
              name: "Last year's site",
              parentFolderId: 'root',
              isManifest: true,
              isHidden: false,
              isLatestVersion: false,
            ),
          ),
          ArNSNameRecord(
            name: 'acme',
            undername: 'docs',
            transactionId: _elseTx,
            ttlSeconds: 900,
          ),
        ],
      ),
      ArNSManagedName(
        name: 'ardrive-demo',
        processId: 'ant-demo',
        role: ArNSRole.owner,
        type: ArNSNameType.lease,
        endTimestamp: _now.add(const Duration(days: 12, hours: 3)),
        undernameLimit: 10,
        records: const [
          ArNSNameRecord(
            name: 'ardrive-demo',
            undername: '@',
            transactionId: _placeholder,
            ttlSeconds: 300,
          ),
        ],
      ),
      ArNSManagedName(
        name: 'friends-shop',
        processId: 'ant-shop',
        role: ArNSRole.controller,
        type: ArNSNameType.lease,
        endTimestamp: _now.add(const Duration(days: 240)),
        undernameLimit: 10,
        records: const [
          ArNSNameRecord(
            name: 'friends-shop',
            undername: '@',
            transactionId: _elseTx,
            ttlSeconds: 3600,
          ),
        ],
      ),
      ArNSManagedName(
        name: 'oldproject',
        processId: 'ant-old',
        role: ArNSRole.owner,
        type: ArNSNameType.lease,
        endTimestamp: _now.subtract(const Duration(days: 3)),
        undernameLimit: 10,
        records: const [
          ArNSNameRecord(
            name: 'oldproject',
            undername: '@',
            transactionId: _elseTx,
            ttlSeconds: 300,
          ),
        ],
      ),
    ];

const _item = ArNSNameableItem(
  fileId: 'f9',
  driveId: 'd1',
  name: 'Spring launch',
  dataTxId: 'NeWsItEnEwSiTeNeWsItEnEwSiTeNeWsItEnEwSiTe1',
  isManifest: true,
);

ArNSWalletState _wallet(ArNSWalletStatus status, {bool installed = true}) =>
    ArNSWalletState(
      enabled: true,
      profileAddress: 'profile',
      linked: status == ArNSWalletStatus.notLinked
          ? null
          : const LinkedArNSWallet(address: _sol, walletName: 'Phantom'),
      connectedAddress: switch (status) {
        ArNSWalletStatus.connected => _sol,
        ArNSWalletStatus.wrongAccount =>
          'CBsEKdomKa9nwF4fMiV5iFerfQPT73Et2ZKWpdCLHHsv',
        _ => null,
      },
      installedWallets: installed ? _wallets : const [],
    );

final _outDir = Directory('build/arns-shots');

Future<ByteData> _read(String path) async =>
    ByteData.view(Uint8List.fromList(File(path).readAsBytesSync()).buffer);

Future<void> _loadFonts() async {
  const dir = 'packages/ardrive_ui/assets/fonts';
  final wavehaus = FontLoader('packages/ardrive_ui/Wavehaus');
  for (final f in [
    'Wavehaus-42Light.otf',
    'Wavehaus-66Book.otf',
    'Wavehaus-95SemiBold.otf',
    'Wavehaus-128Bold.otf',
    'Wavehaus-158ExtraBold.otf',
  ]) {
    wavehaus.addFont(_read('$dir/$f'));
  }
  await wavehaus.load();
  await (FontLoader('packages/ardrive_ui/ArDriveIcons')
        ..addFont(_read('$dir/ArDriveIcons.ttf')))
      .load();
  final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
  await (FontLoader('MaterialIcons')
        ..addFont(_read(
            '$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf')))
      .load();
  ArDriveMonospace.readFont = () => _read('$dir/mono/RobotoMono-Regular.ttf');
  await ArDriveMonospace.ensureLoaded();
}

void main() {
  late _MockRepository repository;
  late _MockClient client;
  late _MockExecutor executor;
  late _MockArioSDK sdk;
  late _MockMetadataWriter metadata;
  late _MockPaymentSource payments;
  late _MockConfigService config;

  setUpAll(() async {
    await _loadFonts();
    registerFallbackValue(ArNSRecordAction.setRecord);
    registerFallbackValue(const ArNSRemoveRecord(antId: '', undername: ''));
    registerFallbackValue(_names().first);
    registerFallbackValue(_MockOwner());
    registerFallbackValue(_MockPayer());
    registerFallbackValue(ControllerWrite.editRecord);
    registerFallbackValue((ArNSCommitStep _) {});
    registerFallbackValue(const <String>[]);
  });

  setUp(() {
    repository = _MockRepository();
    client = _MockClient();
    executor = _MockExecutor();
    sdk = _MockArioSDK();
    metadata = _MockMetadataWriter();
    payments = _MockPaymentSource();
    config = _MockConfigService();
    when(() => config.config).thenReturn(AppConfig(
      stripePublishableKey: '',
      allowedDataItemSizeForTurbo: 100,
      enableArNS: true,
      arnsPlaceholderTxId: _placeholder,
    ));
    when(() => repository.cached(any())).thenAnswer((_) async => _names());
    when(() => repository.refresh(any())).thenAnswer((_) async => _names());
    when(() => client.price(any()))
        .thenAnswer((_) async => BigInt.from(121000000000));
    when(() => metadata.estimateCost())
        .thenAnswer((_) async => BigInt.from(410000000));
    when(() => payments.balance()).thenAnswer(
      (_) async => (
        balance: BigInt.from(4) * BigInt.from(10).pow(12),
        paidBy: <String>[]
      ),
    );
    when(() => payments.payer()).thenReturn(_MockPayer());
    when(() => sdk.estimateControllerFee(
          processId: any(named: 'processId'),
          write: any(named: 'write'),
          undername: any(named: 'undername'),
        )).thenAnswer((_) async => const ControllerFeeEstimate(
          totalLamports: 5000,
          feeLamports: 5000,
          rentLamports: 0,
          rentReclaimedLamports: 0,
        ));
    when(() => sdk.getSolBalanceLamports(any()))
        .thenAnswer((_) async => BigInt.from(20000000));
  });

  _MockWalletCubit walletCubit(ArNSWalletState state) {
    final cubit = _MockWalletCubit();
    whenListen(cubit, const Stream<ArNSWalletState>.empty(),
        initialState: state);
    when(() => cubit.ownerSigner).thenReturn(
        state.status == ArNSWalletStatus.connected ? _MockOwner() : null);
    return cubit;
  }

  Future<void> capture(
    WidgetTester tester,
    String name,
    Widget Function(BuildContext context) build, {
    required bool phone,
    required bool dark,
    double? height,
  }) async {
    final size = phone ? Size(390, height ?? 844) : Size(1280, height ?? 800);
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = size * 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: ArDriveApp(
          themeData: dark ? null : lightTheme(),
          builder: (context) => MaterialApp(
            debugShowCheckedModeBanner: false,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: ArDriveTheme.of(context).themeData.materialThemeData,
            home: Builder(builder: build),
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

  /// A dialog over the page, or a sheet at the bottom of a phone.
  Widget overlay(BuildContext context, Widget child, {required bool phone}) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    return Scaffold(
      backgroundColor: colors.containerL0,
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(color: colors.primitives.transparent900_64),
          ),
          if (phone)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height - 40,
                ),
                decoration: BoxDecoration(
                  color: colors.containerL2,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(ArDriveRadius.lg),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: child,
              ),
            )
          else
            Center(child: child),
        ],
      ),
    );
  }

  Future<ArNSNameDialogCubit> dialogCubit(
    _MockWalletCubit wallet,
    ArNSNamesCubit names, {
    ArNSNameDialogMode mode = ArNSNameDialogMode.nameItem,
    ArNSNameableItem? item = _item,
    ArNSRecordChoice? choice,
  }) async {
    final cubit = ArNSNameDialogCubit(
      mode: mode,
      item: item,
      choice: choice,
      namesCubit: names,
      walletCubit: wallet,
      actionClient: client,
      executor: executor,
      arioSDK: sdk,
      metadataWriter: metadata,
      paymentSource: payments,
      placeholderTxId: _placeholder,
      searchItems: (_) async => const [
        _item,
        ArNSNameableItem(
          fileId: 'f1',
          driveId: 'd1',
          name: 'Portfolio site',
          dataTxId: _siteTx,
          isManifest: true,
        ),
        ArNSNameableItem(
          fileId: 'f3',
          driveId: 'd1',
          name: 'press-kit.pdf',
          dataTxId: _blogTx,
          isManifest: false,
        ),
      ],
    );
    return cubit;
  }

  Future<void> dialogShot(
    WidgetTester tester,
    String name, {
    required ArNSWalletStatus walletStatus,
    bool installed = true,
    ArNSNameDialogMode mode = ArNSNameDialogMode.nameItem,
    ArNSNameableItem? item = _item,
    ArNSRecordChoice? choice,
    Future<void> Function(ArNSNameDialogCubit cubit)? drive,
    Future<void> Function(WidgetTester tester)? interact,
    List<ArNSManagedName>? names,
  }) async {
    if (names != null) {
      when(() => repository.cached(any())).thenAnswer((_) async => names);
      when(() => repository.refresh(any())).thenAnswer((_) async => names);
    }
    for (final phone in [false, true]) {
      for (final dark in [true, false]) {
        final wallet = walletCubit(_wallet(walletStatus, installed: installed));
        final namesCubit = ArNSNamesCubit(
          repository: repository,
          walletCubit: wallet,
        );
        late ArNSNameDialogCubit cubit;
        await tester.runAsync(() async {
          cubit = await dialogCubit(
            wallet,
            namesCubit,
            mode: mode,
            item: item,
            choice: choice,
          );
          await cubit.load();
          await Future.delayed(const Duration(milliseconds: 50));
          if (drive != null) await drive(cubit);
          await Future.delayed(const Duration(milliseconds: 50));
        });
        await capture(
          tester,
          name,
          (context) => overlay(
            context,
            MultiBlocProvider(
              providers: [
                BlocProvider<ArNSNameDialogCubit>.value(value: cubit),
                BlocProvider<ArNSWalletCubit>.value(value: wallet),
                BlocProvider<ArNSNamesCubit>.value(value: namesCubit),
              ],
              child: ArNSNameDialog(inSheet: phone),
            ),
            phone: phone,
          ),
          phone: phone,
          dark: dark,
        );
        if (interact != null) {
          await interact(tester);
          await tester.pump(const Duration(milliseconds: 300));
          await capture(
            tester,
            '$name-open',
            (context) => overlay(
              context,
              MultiBlocProvider(
                providers: [
                  BlocProvider<ArNSNameDialogCubit>.value(value: cubit),
                  BlocProvider<ArNSWalletCubit>.value(value: wallet),
                  BlocProvider<ArNSNamesCubit>.value(value: namesCubit),
                ],
                child: ArNSNameDialog(inSheet: phone),
              ),
              phone: phone,
            ),
            phone: phone,
            dark: dark,
          );
        }
      }
    }
  }

  testWidgets('name dialog: pick a name', (tester) async {
    await dialogShot(
      tester,
      '01-add-name',
      walletStatus: ArNSWalletStatus.connected,
      names: _names().take(2).toList(),
      drive: (cubit) async {
        cubit.choose('acme', 'blog');
        await Future.delayed(const Duration(milliseconds: 50));
      },
    );
  });

  testWidgets('name dialog: new undername with advanced open', (tester) async {
    await dialogShot(
      tester,
      '02-new-undername',
      walletStatus: ArNSWalletStatus.connected,
      names: _names().take(1).toList(),
      drive: (cubit) async {
        cubit.startNewUndername('acme');
        cubit.editNewUndername('spring');
        await Future.delayed(const Duration(milliseconds: 50));
      },
    );
  });

  testWidgets('name dialog: invalid undername', (tester) async {
    await dialogShot(
      tester,
      '03-undername-invalid',
      walletStatus: ArNSWalletStatus.connected,
      names: _names().take(1).toList(),
      drive: (cubit) async {
        cubit.startNewUndername('acme');
        cubit.editNewUndername('-spring!');
      },
    );
  });

  testWidgets('name dialog: managed name pays SOL', (tester) async {
    await dialogShot(
      tester,
      '04-managed-sol',
      walletStatus: ArNSWalletStatus.connected,
      names: [_names()[2]],
      drive: (cubit) async {
        cubit.choose('friends-shop', '@');
        await Future.delayed(const Duration(milliseconds: 50));
      },
    );
  });

  testWidgets('name dialog: link a wallet', (tester) async {
    await dialogShot(
      tester,
      '05-link-wallet',
      walletStatus: ArNSWalletStatus.notLinked,
    );
  });

  testWidgets('name dialog: no wallet on this device', (tester) async {
    await dialogShot(
      tester,
      '06-no-wallet-found',
      walletStatus: ArNSWalletStatus.notLinked,
      installed: false,
    );
  });

  testWidgets('name dialog: reconnect and wrong account', (tester) async {
    await dialogShot(
      tester,
      '07-reconnect',
      walletStatus: ArNSWalletStatus.disconnected,
      names: _names().take(1).toList(),
      drive: (cubit) async {
        cubit.choose('acme', 'docs');
        await Future.delayed(const Duration(milliseconds: 50));
      },
    );
    await dialogShot(
      tester,
      '08-wrong-account',
      walletStatus: ArNSWalletStatus.wrongAccount,
      names: _names().take(1).toList(),
      drive: (cubit) async {
        cubit.choose('acme', 'docs');
        await Future.delayed(const Duration(milliseconds: 50));
      },
    );
  });

  testWidgets('name dialog: repoint confirm', (tester) async {
    await dialogShot(
      tester,
      '09-repoint',
      walletStatus: ArNSWalletStatus.connected,
      names: _names().take(1).toList(),
      drive: (cubit) async {
        cubit.choose('acme', 'blog');
        await Future.delayed(const Duration(milliseconds: 50));
        await cubit.commit();
      },
    );
  });

  testWidgets('name dialog: second prompt, done, failures', (tester) async {
    final hold = Completer<void>();
    when(() => executor.execute(
          name: any(named: 'name'),
          change: any(named: 'change'),
          owner: any(named: 'owner'),
          payer: any(named: 'payer'),
          paidBy: any(named: 'paidBy'),
          onStep: any(named: 'onStep'),
          onNonce: any(named: 'onNonce'),
        )).thenAnswer((i) {
      (i.namedArguments[#onStep] as void Function(
          ArNSCommitStep))(ArNSCommitStep.approveTransaction);
      return hold.future;
    });
    await dialogShot(
      tester,
      '10-second-prompt',
      walletStatus: ArNSWalletStatus.connected,
      names: _names().take(1).toList(),
      drive: (cubit) async {
        cubit.startNewUndername('acme');
        cubit.editNewUndername('spring');
        await Future.delayed(const Duration(milliseconds: 50));
        unawaited(cubit.commit());
      },
    );

    when(() => executor.execute(
          name: any(named: 'name'),
          change: any(named: 'change'),
          owner: any(named: 'owner'),
          payer: any(named: 'payer'),
          paidBy: any(named: 'paidBy'),
          onStep: any(named: 'onStep'),
          onNonce: any(named: 'onNonce'),
        )).thenAnswer((_) async {});
    when(() => repository.refreshRecords(any())).thenAnswer(
        (i) async => i.positionalArguments.first as ArNSManagedName);
    when(() => metadata.writeAssignedNames(
          driveId: any(named: 'driveId'),
          fileId: any(named: 'fileId'),
          names: any(named: 'names'),
        )).thenAnswer((_) async => true);
    await dialogShot(
      tester,
      '11-done',
      walletStatus: ArNSWalletStatus.connected,
      names: _names().take(1).toList(),
      drive: (cubit) async {
        cubit.startNewUndername('acme');
        cubit.editNewUndername('spring');
        await Future.delayed(const Duration(milliseconds: 50));
        await cubit.commit();
      },
    );

    for (final (name, failure) in [
      ('12-lost', const ArNSChangeFailure(ArNSFailureKind.lostAfterCreate)),
      (
        '13-expired',
        const ArNSChangeFailure(ArNSFailureKind.expired, refunded: false)
      ),
      ('14-rejected', const ArNSChangeFailure(ArNSFailureKind.rejected)),
      (
        '15-insufficient',
        const ArNSChangeFailure(ArNSFailureKind.insufficientCredits)
      ),
    ]) {
      when(() => executor.execute(
            name: any(named: 'name'),
            change: any(named: 'change'),
            owner: any(named: 'owner'),
            payer: any(named: 'payer'),
            paidBy: any(named: 'paidBy'),
            onStep: any(named: 'onStep'),
            onNonce: any(named: 'onNonce'),
          )).thenThrow(failure);
      await dialogShot(
        tester,
        name,
        walletStatus: ArNSWalletStatus.connected,
        names: _names().take(1).toList(),
        drive: (cubit) async {
          cubit.startNewUndername('acme');
          cubit.editNewUndername('spring');
          await Future.delayed(const Duration(milliseconds: 50));
          await cubit.commit();
        },
      );
    }
  });

  testWidgets('remove name and cache time dialogs', (tester) async {
    await dialogShot(
      tester,
      '16-remove-undername',
      walletStatus: ArNSWalletStatus.connected,
      mode: ArNSNameDialogMode.remove,
      choice: const ArNSRecordChoice(name: 'acme', undername: 'blog'),
      names: _names().take(1).toList(),
    );
    await dialogShot(
      tester,
      '17-remove-main-name',
      walletStatus: ArNSWalletStatus.connected,
      mode: ArNSNameDialogMode.remove,
      item: null,
      choice: const ArNSRecordChoice(name: 'acme', undername: '@'),
      names: _names().take(1).toList(),
    );
    await dialogShot(
      tester,
      '18-cache-time',
      walletStatus: ArNSWalletStatus.connected,
      mode: ArNSNameDialogMode.cacheTime,
      item: null,
      choice: const ArNSRecordChoice(name: 'acme', undername: 'docs'),
      names: _names().take(1).toList(),
      drive: (cubit) async => cubit.setCacheTime(ArNSCacheTime.fiveMinutes),
    );
    await dialogShot(
      tester,
      '19-point-record',
      walletStatus: ArNSWalletStatus.connected,
      mode: ArNSNameDialogMode.pointRecord,
      item: null,
      choice: const ArNSRecordChoice(name: 'acme', undername: 'docs'),
      names: _names().take(1).toList(),
      drive: (cubit) async {
        await Future.delayed(const Duration(milliseconds: 50));
        cubit.pickItem(_item);
        await Future.delayed(const Duration(milliseconds: 50));
      },
    );
  });

  /// The nav as the app draws it: Your drives, the drive sections, and On
  /// the web under them, so the match is visible.
  Widget fakeNav(BuildContext context) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    Widget section(IconData icon, String label, {required bool open}) =>
        DriveNavRow(
          icon: icon,
          label: label,
          onTap: () {},
          isExpanded: open,
          trailing: RotatedBox(
            quarterTurns: open ? 2 : 0,
            child: ArDriveIcons.chevronDown(size: 16, color: colors.textMid),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DriveNavRow(
          icon: Icons.home_outlined,
          label: 'Your drives',
          onTap: () {},
        ),
        const SizedBox(height: 6),
        Divider(height: 1, color: colors.strokeLow),
        const SizedBox(height: 6),
        section(Icons.public_outlined, 'Public', open: true),
        DriveNavRow(
            icon: null, dense: true, label: 'Acme website', onTap: () {}),
        DriveNavRow(icon: null, dense: true, label: 'Photos', onTap: () {}),
        section(Icons.lock_outline, 'Private', open: false),
        const OnTheWebNavGroup(showLabel: true),
      ],
    );
  }

  Widget namesPage(
    BuildContext context, {
    required bool phone,
    required ArNSWalletState walletState,
    required ArNSNamesState namesState,
  }) {
    final colors = ArDriveTheme.of(context).themeData.colorTokens;
    final names = _MockNamesCubit();
    whenListen(names, const Stream<ArNSNamesState>.empty(),
        initialState: namesState);
    when(() => names.refresh()).thenAnswer((_) async {});
    final delegate = AppRouterDelegate()..showingNames = true;
    final page = MultiProvider(
      providers: [
        RepositoryProvider<ConfigService>.value(value: config),
        ChangeNotifierProvider<AppRouterDelegate>.value(value: delegate),
        BlocProvider<ArNSWalletCubit>.value(value: walletCubit(walletState)),
        BlocProvider<ArNSNamesCubit>.value(value: names),
      ],
      child: Builder(
        builder: (context) => phone
            ? Scaffold(
                backgroundColor: colors.containerL0,
                appBar: AppBar(
                  backgroundColor: colors.containerL0,
                  elevation: 0,
                  leading: Icon(Icons.menu, color: colors.iconHigh),
                ),
                body: const ArNSNamesView(isPhone: true),
              )
            : Scaffold(
                backgroundColor: colors.containerL0,
                body: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 240,
                      padding: const EdgeInsets.fromLTRB(16, 120, 16, 0),
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(color: colors.strokeLow),
                        ),
                      ),
                      child: fakeNav(context),
                    ),
                    const Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(32, 48, 32, 0),
                        child: ArNSNamesView(isPhone: false),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
    return page;
  }

  testWidgets('names page', (tester) async {
    for (final phone in [false, true]) {
      for (final dark in [true, false]) {
        await capture(
          tester,
          '20-names-page',
          (context) => namesPage(
            context,
            phone: phone,
            walletState: _wallet(ArNSWalletStatus.connected),
            namesState: ArNSNamesState(
              status: ArNSNamesStatus.loaded,
              address: _sol,
              names: _names(),
            ),
          ),
          phone: phone,
          dark: dark,
          height: phone ? 1900 : 1180,
        );
        await capture(
          tester,
          '21-names-no-wallet',
          (context) => namesPage(
            context,
            phone: phone,
            walletState: _wallet(ArNSWalletStatus.notLinked),
            namesState: const ArNSNamesState(),
          ),
          phone: phone,
          dark: dark,
        );
        await capture(
          tester,
          '22-names-none',
          (context) => namesPage(
            context,
            phone: phone,
            walletState: _wallet(ArNSWalletStatus.connected),
            namesState: const ArNSNamesState(
              status: ArNSNamesStatus.loaded,
              address: _sol,
            ),
          ),
          phone: phone,
          dark: dark,
        );
      }
    }
  });

  testWidgets('item: details name section, row chip, profile row',
      (tester) async {
    for (final phone in [false, true]) {
      for (final dark in [true, false]) {
        final names = _MockNamesCubit();
        whenListen(names, const Stream<ArNSNamesState>.empty(),
            initialState: ArNSNamesState(
              status: ArNSNamesStatus.loaded,
              address: _sol,
              names: _names(),
            ));
        await capture(
          tester,
          '30-item-name',
          (context) {
            final colors = ArDriveTheme.of(context).themeData.colorTokens;
            final typography = ArDriveTypographyNew.of(context);
            return MultiProvider(
              providers: [
                RepositoryProvider<ConfigService>.value(value: config),
                BlocProvider<ArNSNamesCubit>.value(value: names),
                BlocProvider<ArNSWalletCubit>.value(
                    value: walletCubit(_wallet(ArNSWalletStatus.connected))),
              ],
              child: Scaffold(
                backgroundColor: colors.containerL0,
                body: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Row chip',
                          style:
                              typography.paragraphSmall(color: colors.textLow)),
                      const SizedBox(height: 8),
                      Container(
                        width: phone ? 342 : 620,
                        height: 48,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        color: colors.containerL1,
                        child: Row(
                          children: [
                            Icon(Icons.web_outlined,
                                size: 18, color: colors.iconMid),
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text('Portfolio site',
                                  overflow: TextOverflow.ellipsis,
                                  style: typography.paragraphNormal(
                                      fontWeight: ArFontWeight.semiBold)),
                            ),
                            const ArNSNameChip(dataTxId: _siteTx),
                            const Spacer(),
                            Text('2.1 MB',
                                style: typography.paragraphNormal(
                                    color: colors.textMid)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text('Details panel',
                          style:
                              typography.paragraphSmall(color: colors.textLow)),
                      const SizedBox(height: 8),
                      Container(
                        width: phone ? 342 : 380,
                        padding: const EdgeInsets.all(24),
                        color: colors.containerRaised,
                        child: const Column(
                          children: [
                            ArNSNameSection(
                              item: ArNSNameableItem(
                                fileId: 'f1',
                                driveId: 'd1',
                                name: 'Portfolio site',
                                dataTxId: _siteTx,
                                isManifest: true,
                              ),
                            ),
                            SizedBox(height: 16),
                            ArNSNameSection(item: _item),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text('Profile card',
                          style:
                              typography.paragraphSmall(color: colors.textLow)),
                      const SizedBox(height: 8),
                      for (final status in [
                        ArNSWalletStatus.connected,
                        ArNSWalletStatus.disconnected,
                        ArNSWalletStatus.notLinked,
                      ]) ...[
                        Container(
                          width: 281,
                          padding: const EdgeInsets.only(bottom: 12),
                          color: ArDriveTheme.of(context)
                              .themeData
                              .dropdownTheme
                              .backgroundColor,
                          child: BlocProvider<ArNSWalletCubit>.value(
                            value: walletCubit(_wallet(status)),
                            child: const ArNSWalletProfileRow(),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
          phone: phone,
          dark: dark,
          height: phone ? 1000 : 900,
        );
      }
    }
  });

  testWidgets('nav: On the web beside the drive sections', (tester) async {
    for (final phone in [false, true]) {
      for (final dark in [true, false]) {
        await capture(
          tester,
          '23-nav',
          (context) {
            final colors = ArDriveTheme.of(context).themeData.colorTokens;
            final delegate = AppRouterDelegate()..showingNames = true;
            return MultiProvider(
              providers: [
                RepositoryProvider<ConfigService>.value(value: config),
                ChangeNotifierProvider<AppRouterDelegate>.value(
                    value: delegate),
              ],
              child: Scaffold(
                backgroundColor: phone
                    ? colors.primitives.transparent900_64
                    : colors.containerL0,
                body: Align(
                  alignment: Alignment.topLeft,
                  child: Container(
                    width: phone ? 390 * 0.75 + 32 : 240,
                    height: double.infinity,
                    color: colors.containerL0,
                    padding: EdgeInsets.fromLTRB(16, phone ? 72 : 120, 16, 0),
                    child: Builder(builder: fakeNav),
                  ),
                ),
              ),
            );
          },
          phone: phone,
          dark: dark,
          height: phone ? 844 : 600,
        );
      }
    }
  });

  testWidgets('change name moves the name', (tester) async {
    await dialogShot(
      tester,
      '24-change-move',
      walletStatus: ArNSWalletStatus.connected,
      item: const ArNSNameableItem(
        fileId: 'f1',
        driveId: 'd1',
        name: 'Portfolio site',
        dataTxId: _blogTx,
        isManifest: true,
      ),
      names: _names().take(1).toList(),
      drive: (cubit) async {
        cubit.startNewUndername('acme');
        cubit.editNewUndername('portfolio');
        await Future.delayed(const Duration(milliseconds: 50));
      },
    );
  });

  Future<void> flowShot(
    WidgetTester tester,
    String name, {
    required String title,
    List<ArNSNameRecord> following = const [],
    bool open = false,
    ArNSWalletStatus walletStatus = ArNSWalletStatus.connected,
    Future<void> Function(ArNSFlowNameCubit cubit)? drive,
    ArNSFlowOutcome? result,
  }) async {
    when(() => repository.cached(any()))
        .thenAnswer((_) async => _names().take(2).toList());
    when(() => repository.refresh(any()))
        .thenAnswer((_) async => _names().take(2).toList());
    for (final phone in [false, true]) {
      for (final dark in [true, false]) {
        final wallet = walletCubit(_wallet(walletStatus));
        final namesCubit =
            ArNSNamesCubit(repository: repository, walletCubit: wallet);
        late ArNSFlowNameCubit cubit;
        await tester.runAsync(() async {
          cubit = ArNSFlowNameCubit(
            namesCubit: namesCubit,
            walletCubit: wallet,
            actionClient: client,
            executor: executor,
            arioSDK: sdk,
            metadataWriter: metadata,
            paymentSource: payments,
            following: following,
            placeholderTxId: _placeholder,
          );
          await cubit.load();
          await Future.delayed(const Duration(milliseconds: 50));
          if (drive != null) await drive(cubit);
          await Future.delayed(const Duration(milliseconds: 50));
        });
        await capture(
          tester,
          name,
          (context) {
            final typography = ArDriveTypographyNew.of(context);
            final colors = ArDriveTheme.of(context).themeData.colorTokens;
            final body = Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Spring launch',
                    style: typography.paragraphLarge(
                        fontWeight: ArFontWeight.bold)),
                Text('1.2 KB',
                    style: typography.paragraphNormal(color: colors.textLow)),
                const SizedBox(height: 24),
                if (result != null)
                  ArNSFlowNameResult(outcome: result)
                else
                  ArNSFlowNameSection(cubit: cubit, initiallyOpen: open),
              ],
            );
            final actions = [
              ModalAction.dismiss(title: 'Cancel', action: () {}),
              ModalAction(
                title: title,
                isEnable: cubit.ready,
                action: () {},
              ),
            ];
            return overlay(
              context,
              MultiBlocProvider(
                providers: [
                  BlocProvider<ArNSWalletCubit>.value(value: wallet),
                  BlocProvider<ArNSNamesCubit>.value(value: namesCubit),
                ],
                child: phone
                    ? ArDriveBottomSheet(
                        title: title, content: body, actions: actions)
                    : ArDriveStandardModalNew(
                        title: title,
                        width: 520,
                        scrollableContent: true,
                        content: body,
                        actions: actions,
                      ),
              ),
              phone: phone,
            );
          },
          phone: phone,
          dark: dark,
        );
      }
    }
  }

  testWidgets('flows: the name step', (tester) async {
    await flowShot(tester, '25-flow-step-folded', title: 'Create deployment');
    await flowShot(
      tester,
      '26-flow-step-open',
      title: 'Create deployment',
      open: true,
      drive: (cubit) async {
        cubit.choose('acme', 'docs');
        await Future.delayed(const Duration(milliseconds: 50));
      },
    );
    await flowShot(
      tester,
      '27-flow-new-version',
      title: 'Upload 1 file',
      following: [_names().first.records[1]],
    );
    await flowShot(
      tester,
      '28-flow-wallet',
      title: 'Publish',
      walletStatus: ArNSWalletStatus.disconnected,
      following: [_names().first.records[1]],
    );
    await flowShot(
      tester,
      '29-flow-result',
      title: 'Deployment created',
      result: const ArNSFlowOutcome(
        live: ['spring_acme'],
        failed: ['blog_acme'],
      ),
    );
  });
}
