import 'package:ardrive/arns/data/arns_change_executor.dart';
import 'package:ardrive/arns/data/arns_file_metadata_writer.dart';
import 'package:ardrive/arns/data/arns_names_repository.dart';
import 'package:ardrive/arns/data/arns_wallet_store.dart';
import 'package:ardrive/arns/data/turbo_arns_action_client.dart';
import 'package:ardrive/arns/domain/arns_action.dart';
import 'package:ardrive/arns/domain/arns_nameable_item.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog.dart';
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog_cubit.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/utils/truncate_string.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockRepository extends Mock implements ArNSNamesRepository {}

class _MockWalletCubit extends MockCubit<ArNSWalletState>
    implements ArNSWalletCubit {}

class _MockClient extends Mock implements TurboArNSActionClient {}

class _MockExecutor extends Mock implements ArNSChangeExecutor {}

class _MockArioSDK extends Mock implements ArioSDK {}

class _MockMetadataWriter extends Mock implements ArNSFileMetadataWriter {}

class _MockPaymentSource extends Mock implements ArNSPaymentSource {}

class _MockOwner extends Mock implements ArNSOwnerSigner {}

class _MockPayer extends Mock implements ArNSPayerSigner {}

const _sol = '7xKpH3nV9qR2bT5mW8cY4dF6gJ1kL3sA9eZ2uQ7q2Fd';
const _itemTx = 'NeWsItEnEwSiTeNeWsItEnEwSiTeNeWsItEnEwSiTe1';
const _elseTx = 'Zvp8dEkO3nQ2wX9yV8uT7sR6qP5oN4mL3kJ2iH1gF0c';
const _placeholder = 'PlcHoLdErPlcHoLdErPlcHoLdErPlcHoLdErPlcHo1';

const _item = ArNSNameableItem(
  fileId: 'f9',
  driveId: 'd1',
  name: 'Spring launch',
  dataTxId: _itemTx,
  isManifest: true,
);

ArNSManagedName _acme({String? blogTx}) => ArNSManagedName(
      name: 'acme',
      processId: 'ant-acme',
      role: ArNSRole.owner,
      type: ArNSNameType.permabuy,
      endTimestamp: null,
      undernameLimit: 10,
      records: [
        const ArNSNameRecord(
          name: 'acme',
          undername: '@',
          transactionId: _elseTx,
          ttlSeconds: 300,
        ),
        ArNSNameRecord(
          name: 'acme',
          undername: 'blog',
          transactionId: blogTx ?? _elseTx,
          ttlSeconds: 300,
        ),
      ],
    );

ArNSWalletState _connected() => const ArNSWalletState(
      enabled: true,
      profileAddress: 'profile',
      linked: LinkedArNSWallet(address: _sol, walletName: 'Phantom'),
      connectedAddress: _sol,
      installedWallets: [SolanaWalletInfo(name: 'Phantom', icon: '')],
    );

/// The name dialog's title and button for each mode, and the picker rows.
void main() {
  late _MockRepository repository;
  late _MockClient client;
  late _MockExecutor executor;
  late _MockArioSDK sdk;
  late _MockMetadataWriter metadata;
  late _MockPaymentSource payments;

  setUpAll(() {
    registerFallbackValue(ArNSRecordAction.setRecord);
  });

  setUp(() {
    repository = _MockRepository();
    client = _MockClient();
    executor = _MockExecutor();
    sdk = _MockArioSDK();
    metadata = _MockMetadataWriter();
    payments = _MockPaymentSource();
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
  });

  Future<void> openDialog(
    WidgetTester tester, {
    required ArNSNameDialogMode mode,
    ArNSNameableItem? item,
    ArNSRecordChoice? choice,
    required List<ArNSManagedName> names,
  }) async {
    when(() => repository.cached(any())).thenAnswer((_) async => names);
    when(() => repository.refresh(any())).thenAnswer((_) async => names);
    final wallet = _MockWalletCubit();
    whenListen(wallet, const Stream<ArNSWalletState>.empty(),
        initialState: _connected());
    when(() => wallet.ownerSigner).thenReturn(_MockOwner());
    final namesCubit =
        ArNSNamesCubit(repository: repository, walletCubit: wallet);
    final cubit = ArNSNameDialogCubit(
      mode: mode,
      item: item,
      choice: choice,
      namesCubit: namesCubit,
      walletCubit: wallet,
      actionClient: client,
      executor: executor,
      arioSDK: sdk,
      metadataWriter: metadata,
      paymentSource: payments,
      placeholderTxId: _placeholder,
    );
    await tester.runAsync(() async {
      await cubit.load();
      await Future.delayed(const Duration(milliseconds: 50));
    });
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ArDriveApp(
        themeData: lightTheme(),
        builder: (context) => MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MultiBlocProvider(
            providers: [
              BlocProvider<ArNSNameDialogCubit>.value(value: cubit),
              BlocProvider<ArNSWalletCubit>.value(value: wallet),
              BlocProvider<ArNSNamesCubit>.value(value: namesCubit),
            ],
            child: const Scaffold(body: ArNSNameDialog(inSheet: false)),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('title and button', () {
    testWidgets('an unnamed item: Add name, Save', (tester) async {
      await openDialog(
        tester,
        mode: ArNSNameDialogMode.nameItem,
        item: _item,
        names: [_acme()],
      );

      expect(find.text('Add name'), findsOneWidget, reason: 'the title');
      expect(find.text('Save'), findsOneWidget, reason: 'the button');
      expect(find.text('Name'), findsNothing);
    });

    testWidgets('an item with a name: Change name, Save', (tester) async {
      await openDialog(
        tester,
        mode: ArNSNameDialogMode.nameItem,
        item: _item,
        names: [_acme(blogTx: _itemTx)],
      );

      expect(find.text('Change name'), findsOneWidget, reason: 'the title');
      expect(find.text('Save'), findsOneWidget, reason: 'the button');
      expect(find.text('Add name'), findsNothing);
    });

    testWidgets('cache time: Change cache time, Save', (tester) async {
      await openDialog(
        tester,
        mode: ArNSNameDialogMode.cacheTime,
        choice: const ArNSRecordChoice(name: 'acme', undername: 'blog'),
        names: [_acme()],
      );

      expect(find.text('Change cache time'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('remove: Remove name, Remove', (tester) async {
      await openDialog(
        tester,
        mode: ArNSNameDialogMode.remove,
        choice: const ArNSRecordChoice(name: 'acme', undername: 'blog'),
        names: [_acme()],
      );

      expect(find.text('Remove name'), findsOneWidget, reason: 'the title');
      expect(find.text('Remove'), findsOneWidget, reason: 'the button');
    });

    testWidgets('point record: unchanged title, Save', (tester) async {
      await openDialog(
        tester,
        mode: ArNSNameDialogMode.pointRecord,
        item: _item,
        choice: const ArNSRecordChoice(name: 'acme', undername: 'blog'),
        names: [_acme()],
      );

      expect(find.text('Change what it points to'), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });
  });

  testWidgets('an elsewhere record shows Points elsewhere, and no ID',
      (tester) async {
    await openDialog(
      tester,
      mode: ArNSNameDialogMode.nameItem,
      item: _item,
      names: [_acme()],
    );

    expect(find.textContaining('Points elsewhere'), findsWidgets);
    expect(find.textContaining(shortenId(_elseTx)), findsNothing);
    expect(find.textContaining('Points to'), findsNothing);
  });

  testWidgets(
      'an unresolved record that points at the item names the item, '
      'not Points elsewhere', (tester) async {
    await openDialog(
      tester,
      mode: ArNSNameDialogMode.nameItem,
      item: _item,
      names: [_acme(blogTx: _itemTx)],
    );

    expect(find.textContaining('Points to Spring launch'), findsOneWidget);
    // The main name still points outside ArDrive.
    expect(find.textContaining('Points elsewhere'), findsOneWidget);
    expect(find.textContaining(shortenId(_itemTx)), findsNothing);
  });

  testWidgets('no names: the dialog keeps its own Get a name button',
      (tester) async {
    await openDialog(
      tester,
      mode: ArNSNameDialogMode.nameItem,
      item: _item,
      names: const [],
    );

    expect(find.text('No names yet'), findsOneWidget);
    expect(find.text('Get one in the ar.io Console.'), findsOneWidget);
    expect(find.text('Get a name'), findsOneWidget);
  });
}
