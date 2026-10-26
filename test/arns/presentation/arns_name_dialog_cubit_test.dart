import 'dart:async';

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
import 'package:ardrive/arns/presentation/name_dialog/arns_name_dialog_cubit.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:bloc_test/bloc_test.dart';
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

const _sol = '6eV7bK3bQJdd7Q44doWqAbnBCWNQRhB1HwCDGWf8Qe3V';
const _antId = 'EH9PsyfwJBk9KLMpZ2C5nUjWQfXsNTHaUzTqFa4BpbQj';
const _itemTx = 'FWswWiH1FMFnuzLFzpqzdgxOBlMS8L7DiP5MxUnWODE';
const _otherTx = 'OtherTxOtherTxOtherTxOtherTxOtherTxOtherTx1';
const _placeholder = 'PlaceholderPlaceholderPlaceholderPlacehold1';

final _price = BigInt.from(120000000000); // 0.12 credits
final _metadata = BigInt.from(1000000000); // 0.001 credits

const _item = ArNSNameableItem(
  fileId: 'file-1',
  driveId: 'drive-1',
  name: 'Site',
  dataTxId: _itemTx,
  isManifest: true,
);

ArNSManagedName _name({
  ArNSRole role = ArNSRole.owner,
  List<ArNSNameRecord>? records,
  DateTime? end,
}) =>
    ArNSManagedName(
      name: 'acme',
      processId: _antId,
      role: role,
      type: end == null ? ArNSNameType.permabuy : ArNSNameType.lease,
      endTimestamp: end,
      undernameLimit: 10,
      records: records ??
          const [
            ArNSNameRecord(
              name: 'acme',
              undername: '@',
              transactionId: _otherTx,
              ttlSeconds: 3600,
            ),
            ArNSNameRecord(
              name: 'acme',
              undername: 'blog',
              transactionId: _otherTx,
              ttlSeconds: 300,
              target: ArNSFileItem(
                fileId: 'old',
                driveId: 'drive-1',
                name: "Last year's site",
                parentFolderId: 'root',
                isManifest: true,
                isHidden: false,
                isLatestVersion: true,
              ),
            ),
          ],
    );

ArNSWalletState _wallet({
  bool linked = true,
  bool connected = true,
}) =>
    ArNSWalletState(
      enabled: true,
      profileAddress: 'profile',
      linked: linked ? const LinkedArNSWallet(address: _sol) : null,
      connectedAddress: connected ? _sol : null,
    );

void main() {
  late _MockRepository repository;
  late _MockWalletCubit wallet;
  late _MockClient client;
  late _MockExecutor executor;
  late _MockArioSDK sdk;
  late _MockMetadataWriter metadata;
  late _MockPaymentSource payments;
  late ArNSNamesCubit names;
  late List<ArNSManagedName> chain;
  final now = DateTime(2026, 10, 26);

  setUpAll(() {
    registerFallbackValue(ArNSRecordAction.setRecord);
    registerFallbackValue(
      const ArNSRemoveRecord(antId: '', undername: ''),
    );
    registerFallbackValue(_name());
    registerFallbackValue(_MockOwner());
    registerFallbackValue(_MockPayer());
    registerFallbackValue(ControllerWrite.editRecord);
    registerFallbackValue((ArNSCommitStep _) {});
    registerFallbackValue(const <String>[]);
  });

  void setUpWallet(ArNSWalletState state) {
    whenListen(wallet, const Stream<ArNSWalletState>.empty(),
        initialState: state);
    when(() => wallet.ownerSigner).thenReturn(
        state.status == ArNSWalletStatus.connected ? _MockOwner() : null);
  }

  setUp(() {
    repository = _MockRepository();
    wallet = _MockWalletCubit();
    client = _MockClient();
    executor = _MockExecutor();
    sdk = _MockArioSDK();
    metadata = _MockMetadataWriter();
    payments = _MockPaymentSource();
    chain = [_name()];

    setUpWallet(_wallet());
    when(() => repository.cached(any())).thenAnswer((_) async => chain);
    when(() => repository.refresh(any())).thenAnswer((_) async => chain);
    when(() => repository.refreshRecords(any(), made: any(named: 'made')))
        .thenAnswer((i) async => chain.first);
    when(() => client.price(ArNSRecordAction.setRecord))
        .thenAnswer((_) async => _price);
    when(() => client.price(ArNSRecordAction.removeRecord))
        .thenAnswer((_) async => BigInt.from(1000000000));
    when(() => metadata.estimateCost()).thenAnswer((_) async => _metadata);
    when(() => metadata.writeAssignedNames(
          driveId: any(named: 'driveId'),
          fileId: any(named: 'fileId'),
          names: any(named: 'names'),
        )).thenAnswer((_) async => true);
    when(() => payments.balance()).thenAnswer(
      (_) async => (balance: BigInt.from(10).pow(13), paidBy: ['payer-2']),
    );
    when(() => payments.payer()).thenReturn(_MockPayer());
    when(() => executor.execute(
          name: any(named: 'name'),
          change: any(named: 'change'),
          owner: any(named: 'owner'),
          payer: any(named: 'payer'),
          paidBy: any(named: 'paidBy'),
          onStep: any(named: 'onStep'),
          onNonce: any(named: 'onNonce'),
        )).thenAnswer((_) async {});
  });

  Future<ArNSNameDialogCubit> open({
    ArNSNameDialogMode mode = ArNSNameDialogMode.nameItem,
    ArNSNameableItem? item = _item,
    ArNSRecordChoice? choice,
    String? placeholder = _placeholder,
  }) async {
    names = ArNSNamesCubit(repository: repository, walletCubit: wallet);
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
      placeholderTxId: placeholder,
      clock: () => now,
    );
    await cubit.load();
    await pumpEventQueue();
    return cubit;
  }

  ArNSRecordChange? executedChange() {
    final call = verify(() => executor.execute(
          name: any(named: 'name'),
          change: captureAny(named: 'change'),
          owner: any(named: 'owner'),
          payer: any(named: 'payer'),
          paidBy: any(named: 'paidBy'),
          onStep: any(named: 'onStep'),
          onNonce: any(named: 'onNonce'),
        ));
    return call.captured.single as ArNSRecordChange;
  }

  group('opening', () {
    test('lists the names and waits for a choice', () async {
      final cubit = await open();

      expect(cubit.state.stage, ArNSDialogStage.choose);
      expect(cubit.state.names.single.name, 'acme');
      expect(cubit.state.choice, isNull);
      expect(cubit.state.canCommit, isFalse);
    });

    test('asks for a wallet when none is linked', () async {
      setUpWallet(_wallet(linked: false, connected: false));

      final cubit = await open();

      expect(cubit.state.stage, ArNSDialogStage.needsWallet);
      verifyNever(() => repository.refresh(any()));
    });

    test('says so when the wallet has no names', () async {
      chain = [];

      final cubit = await open();

      expect(cubit.state.stage, ArNSDialogStage.noNames);
    });

    test('Change name opens on the current name and its cache time', () async {
      chain = [
        _name(records: const [
          ArNSNameRecord(
            name: 'acme',
            undername: 'www',
            transactionId: _itemTx,
            ttlSeconds: 900,
          ),
        ]),
      ];

      final cubit = await open();

      expect(cubit.state.choice,
          const ArNSRecordChoice(name: 'acme', undername: 'www'));
      expect(cubit.state.cacheTime, ArNSCacheTime.fifteenMinutes);
      expect(cubit.state.unchanged, isTrue, reason: 'nothing to change yet');
    });

    test('leaves out names past their grace period', () async {
      chain = [_name(end: now.subtract(const Duration(days: 20)))];

      final cubit = await open();

      expect(cubit.state.stage, ArNSDialogStage.noNames);
    });
  });

  group('cost', () {
    test('is the Turbo price plus the metadata update, in credits', () async {
      final cubit = await open();
      cubit.startNewUndername('acme');
      cubit.editNewUndername('docs');
      await pumpEventQueue();

      expect(cubit.state.cost?.credits, _price + _metadata);
      expect(cubit.state.cost?.paidInSol, isFalse);
      expect(cubit.state.canCommit, isTrue);
    });

    test('blocks the change when the credits do not cover it', () async {
      when(() => payments.balance())
          .thenAnswer((_) async => (balance: BigInt.one, paidBy: <String>[]));
      final cubit = await open();
      cubit.choose('acme', '@');
      await pumpEventQueue();

      expect(cubit.state.insufficientCredits, isTrue);
      expect(cubit.state.canCommit, isFalse);
    });

    test('a managed name costs SOL and is checked against the balance',
        () async {
      chain = [_name(role: ArNSRole.controller)];
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
      when(() => sdk.getSolBalanceLamports(_sol))
          .thenAnswer((_) async => BigInt.from(4000));

      final cubit = await open();
      cubit.choose('acme', '@');
      await pumpEventQueue();

      expect(cubit.state.cost?.solLamports, 5000);
      expect(cubit.state.cost?.credits, _metadata,
          reason: 'only the metadata update is in credits');
      expect(cubit.state.insufficientSol, isTrue);
      expect(cubit.state.canCommit, isFalse);
      verifyNever(() => client.price(any()));
    });

    test('a name in its grace period cannot be changed', () async {
      chain = [_name(end: now.subtract(const Duration(days: 2)))];
      final cubit = await open();
      cubit.choose('acme', '@');
      await pumpEventQueue();

      expect(cubit.state.inGracePeriod, isTrue);
      expect(cubit.state.canCommit, isFalse);
    });
  });

  group('undernames', () {
    test('an invalid undername cannot be created', () async {
      final cubit = await open();
      cubit.startNewUndername('acme');
      cubit.editNewUndername('-bad');
      await pumpEventQueue();

      expect(cubit.state.newUndernameProblem, isNotNull);
      expect(cubit.state.canCommit, isFalse);
    });

    test('an existing undername is not created again', () async {
      final cubit = await open();
      cubit.startNewUndername('acme');
      cubit.editNewUndername('Blog');
      await pumpEventQueue();

      expect(cubit.state.newUndernameTaken, isTrue);
      expect(cubit.state.canCommit, isFalse);
    });

    test('a new undername is set to point here', () async {
      final cubit = await open();
      cubit.startNewUndername('acme');
      cubit.editNewUndername('docs');
      cubit.setCacheTime(ArNSCacheTime.oneHour);
      await pumpEventQueue();
      await cubit.commit();

      expect(
        executedChange(),
        const ArNSSetRecord(
          antId: _antId,
          undername: 'docs',
          transactionId: _itemTx,
          ttlSeconds: 3600,
        ),
      );
      expect(cubit.state.stage, ArNSDialogStage.done);
      verify(() => metadata.writeAssignedNames(
            driveId: 'drive-1',
            fileId: 'file-1',
            names: ['docs_acme'],
          )).called(1);
    });
  });

  group('Add name or Change name', () {
    test('an unnamed item is Add name all the way through', () async {
      when(() => executor.execute(
            name: any(named: 'name'),
            change: any(named: 'change'),
            owner: any(named: 'owner'),
            payer: any(named: 'payer'),
            paidBy: any(named: 'paidBy'),
            onStep: any(named: 'onStep'),
            onNonce: any(named: 'onNonce'),
          )).thenAnswer((_) async {
        // Read again after the change: the new name points at the item.
        chain = [
          _name(records: const [
            ArNSNameRecord(
              name: 'acme',
              undername: 'docs',
              transactionId: _itemTx,
              ttlSeconds: 300,
            ),
          ]),
        ];
      });
      final cubit = await open();
      cubit.startNewUndername('acme');
      cubit.editNewUndername('docs');
      await pumpEventQueue();

      final states = <ArNSNameDialogState>[cubit.state];
      final sub = cubit.stream.listen(states.add);
      await cubit.commit();
      await pumpEventQueue();
      await sub.cancel();

      expect(states.last.stage, ArNSDialogStage.done);
      expect(states.map((s) => s.changesName), everyElement(isFalse),
          reason: 'the progress title said Change name once the new name '
              'pointed at the item');
    });

    test('an item that has a name is Change name', () async {
      chain = [
        _name(records: const [
          ArNSNameRecord(
            name: 'acme',
            undername: 'www',
            transactionId: _itemTx,
            ttlSeconds: 300,
          ),
        ]),
      ];

      final cubit = await open();

      expect(cubit.state.changesName, isTrue);
    });
  });

  group('committing', () {
    test('a name pointing elsewhere is confirmed before it moves', () async {
      final cubit = await open();
      cubit.choose('acme', 'blog');
      await pumpEventQueue();
      await cubit.commit();

      expect(cubit.state.stage, ArNSDialogStage.confirmRepoint);
      verifyNever(() => executor.execute(
            name: any(named: 'name'),
            change: any(named: 'change'),
            owner: any(named: 'owner'),
            payer: any(named: 'payer'),
            paidBy: any(named: 'paidBy'),
            onStep: any(named: 'onStep'),
            onNonce: any(named: 'onNonce'),
          ));

      await cubit.confirmRepoint();

      expect(cubit.state.stage, ArNSDialogStage.done);
      expect((executedChange() as ArNSSetRecord).undername, 'blog');
    });

    test('passes the credit sharers and reports each step', () async {
      when(() => executor.execute(
            name: any(named: 'name'),
            change: any(named: 'change'),
            owner: any(named: 'owner'),
            payer: any(named: 'payer'),
            paidBy: any(named: 'paidBy'),
            onStep: any(named: 'onStep'),
            onNonce: any(named: 'onNonce'),
          )).thenAnswer((i) async {
        final onStep =
            i.namedArguments[#onStep] as void Function(ArNSCommitStep);
        onStep(ArNSCommitStep.approve);
        onStep(ArNSCommitStep.approveTransaction);
      });
      final cubit = await open();
      cubit.choose('acme', '@');
      await pumpEventQueue();

      final steps = <ArNSCommitStep?>[];
      final sub = cubit.stream.listen((s) => steps.add(s.step));
      await cubit.confirmRepoint(); // not asked: no-op
      await cubit.commit();
      await cubit.confirmRepoint();
      await pumpEventQueue();
      await sub.cancel();

      expect(
        steps,
        containsAllInOrder([
          ArNSCommitStep.approve,
          ArNSCommitStep.approveTransaction,
          ArNSCommitStep.updatingDetails,
        ]),
      );
      final paidBy = verify(() => executor.execute(
            name: any(named: 'name'),
            change: any(named: 'change'),
            owner: any(named: 'owner'),
            payer: any(named: 'payer'),
            paidBy: captureAny(named: 'paidBy'),
            onStep: any(named: 'onStep'),
            onNonce: any(named: 'onNonce'),
          )).captured.single;
      expect(paidBy, ['payer-2']);
    });

    test('does nothing until the ArNS wallet is connected', () async {
      setUpWallet(_wallet(connected: false));
      final cubit = await open();
      cubit.startNewUndername('acme');
      cubit.editNewUndername('docs');
      await pumpEventQueue();
      await cubit.commit();

      expect(cubit.state.stage, ArNSDialogStage.choose);
    });

    for (final kind in [
      ArNSFailureKind.rejected,
      ArNSFailureKind.failed,
      ArNSFailureKind.insufficientCredits,
      ArNSFailureKind.wrongAccount,
    ]) {
      test('$kind charged nothing, so it can be tried again', () async {
        when(() => executor.execute(
              name: any(named: 'name'),
              change: any(named: 'change'),
              owner: any(named: 'owner'),
              payer: any(named: 'payer'),
              paidBy: any(named: 'paidBy'),
              onStep: any(named: 'onStep'),
              onNonce: any(named: 'onNonce'),
            )).thenThrow(ArNSChangeFailure(kind));
        final cubit = await open();
        cubit.startNewUndername('acme');
        cubit.editNewUndername('docs');
        await pumpEventQueue();
        await cubit.commit();

        expect(cubit.state.stage, ArNSDialogStage.failed);
        expect(cubit.state.failure?.kind, kind);
        expect(cubit.canTryAgain, isTrue);
        cubit.backToChoose();
        expect(cubit.state.stage, ArNSDialogStage.choose);
        verifyNever(() => metadata.writeAssignedNames(
              driveId: any(named: 'driveId'),
              fileId: any(named: 'fileId'),
              names: any(named: 'names'),
            ));
      });
    }

    test('a lost response is never retried: the names are read again',
        () async {
      when(() => executor.execute(
                name: any(named: 'name'),
                change: any(named: 'change'),
                owner: any(named: 'owner'),
                payer: any(named: 'payer'),
                paidBy: any(named: 'paidBy'),
                onStep: any(named: 'onStep'),
                onNonce: any(named: 'onNonce'),
              ))
          .thenThrow(const ArNSChangeFailure(ArNSFailureKind.lostAfterCreate));
      final cubit = await open();
      cubit.startNewUndername('acme');
      cubit.editNewUndername('docs');
      await pumpEventQueue();
      clearInteractions(repository);

      await cubit.commit();
      await pumpEventQueue();

      expect(cubit.state.stage, ArNSDialogStage.failed);
      expect(cubit.canTryAgain, isFalse);
      cubit.backToChoose();
      await cubit.commit();
      expect(cubit.state.stage, ArNSDialogStage.failed);
      verify(() => repository.refresh(_sol)).called(1);
      verify(() => executor.execute(
            name: any(named: 'name'),
            change: any(named: 'change'),
            owner: any(named: 'owner'),
            payer: any(named: 'payer'),
            paidBy: any(named: 'paidBy'),
            onStep: any(named: 'onStep'),
            onNonce: any(named: 'onNonce'),
          )).called(1);
    });

    test('an expired action says the credits come back', () async {
      when(() => executor.execute(
            name: any(named: 'name'),
            change: any(named: 'change'),
            owner: any(named: 'owner'),
            payer: any(named: 'payer'),
            paidBy: any(named: 'paidBy'),
            onStep: any(named: 'onStep'),
            onNonce: any(named: 'onNonce'),
          )).thenThrow(const ArNSChangeFailure(
        ArNSFailureKind.expired,
        refunded: true,
      ));
      final cubit = await open();
      cubit.startNewUndername('acme');
      cubit.editNewUndername('docs');
      await pumpEventQueue();
      await cubit.commit();

      expect(cubit.state.failure?.refunded, isTrue);
      expect(cubit.canTryAgain, isFalse);
    });

    test('a failed metadata update still reports the name as changed',
        () async {
      when(() => metadata.writeAssignedNames(
            driveId: any(named: 'driveId'),
            fileId: any(named: 'fileId'),
            names: any(named: 'names'),
          )).thenThrow(Exception('402'));
      final cubit = await open();
      cubit.startNewUndername('acme');
      cubit.editNewUndername('docs');
      await pumpEventQueue();
      await cubit.commit();

      expect(cubit.state.stage, ArNSDialogStage.done);
      expect(cubit.state.metadataFailed, isTrue);
    });
  });

  group('removing', () {
    test('an undername is deleted and leaves the metadata', () async {
      chain = [
        _name(records: const [
          ArNSNameRecord(
            name: 'acme',
            undername: 'www',
            transactionId: _itemTx,
            ttlSeconds: 300,
          ),
        ]),
      ];
      final cubit = await open(
        mode: ArNSNameDialogMode.remove,
        choice: const ArNSRecordChoice(name: 'acme', undername: 'www'),
      );

      expect(cubit.state.cost?.credits, BigInt.from(1000000000) + _metadata);
      await cubit.commit();

      expect(
        executedChange(),
        const ArNSRemoveRecord(antId: _antId, undername: 'www'),
      );
      verify(() => metadata.writeAssignedNames(
            driveId: 'drive-1',
            fileId: 'file-1',
            names: [],
          )).called(1);
    });

    test('a main name points at the placeholder page', () async {
      final cubit = await open(
        mode: ArNSNameDialogMode.remove,
        item: null,
        choice: const ArNSRecordChoice(name: 'acme', undername: '@'),
      );
      await cubit.commit();

      expect(
        executedChange(),
        const ArNSSetRecord(
          antId: _antId,
          undername: '@',
          transactionId: _placeholder,
          ttlSeconds: 3600,
        ),
      );
    });

    test('a main name cannot be removed without a placeholder page', () async {
      final cubit = await open(
        mode: ArNSNameDialogMode.remove,
        item: null,
        placeholder: null,
        choice: const ArNSRecordChoice(name: 'acme', undername: '@'),
      );

      expect(cubit.canRemoveMainName, isFalse);
      expect(cubit.change, isNull);
      expect(cubit.state.canCommit, isFalse);
    });
  });

  test('the cache time alone can change, at no metadata cost', () async {
    final cubit = await open(
      mode: ArNSNameDialogMode.cacheTime,
      item: null,
      choice: const ArNSRecordChoice(name: 'acme', undername: '@'),
    );

    expect(cubit.state.cacheTime, ArNSCacheTime.oneHour);
    expect(cubit.state.canCommit, isFalse, reason: 'unchanged');
    cubit.setCacheTime(ArNSCacheTime.fiveMinutes);
    expect(cubit.state.cost?.metadataWrites, 0);
    expect(cubit.state.canCommit, isTrue);
    await cubit.commit();

    expect(
      executedChange(),
      const ArNSSetRecord(
        antId: _antId,
        undername: '@',
        transactionId: _otherTx,
        ttlSeconds: 300,
      ),
    );
  });

  test('the Names page points a record at a picked item', () async {
    final cubit = await open(
      mode: ArNSNameDialogMode.pointRecord,
      item: null,
      choice: const ArNSRecordChoice(name: 'acme', undername: '@'),
    );
    expect(cubit.state.canCommit, isFalse, reason: 'no item yet');

    cubit.pickItem(_item);
    await pumpEventQueue();
    await cubit.commit();
    expect(cubit.state.stage, ArNSDialogStage.confirmRepoint);
    await cubit.confirmRepoint();

    expect((executedChange() as ArNSSetRecord).transactionId, _itemTx);
  });

  group('Change name moves the name', () {
    setUp(() {
      chain = [
        _name(records: const [
          ArNSNameRecord(
            name: 'acme',
            undername: 'www',
            transactionId: _itemTx,
            ttlSeconds: 300,
          ),
          ArNSNameRecord(
            name: 'acme',
            undername: 'blog',
            transactionId: _otherTx,
            ttlSeconds: 300,
          ),
        ]),
      ];
    });

    test('offers to remove the old name, on by default, priced in', () async {
      final cubit = await open();
      expect(cubit.state.previousRecord?.undername, 'www');
      expect(cubit.state.movesFrom, isNull, reason: 'nothing chosen yet');

      cubit.startNewUndername('acme');
      cubit.editNewUndername('docs');
      await pumpEventQueue();

      expect(cubit.state.movesFrom?.undername, 'www');
      expect(cubit.state.removesPrevious, isTrue);
      expect(
        cubit.previousRemoval,
        const ArNSRemoveRecord(antId: _antId, undername: 'www'),
      );
      expect(cubit.state.cost?.credits,
          _price + BigInt.from(1000000000) + _metadata);

      cubit.setRemovePrevious(false);
      await pumpEventQueue();
      expect(cubit.previousRemoval, isNull);
      expect(cubit.state.cost?.credits, _price + _metadata);
    });

    test('runs two changes and drops the old name from the hint', () async {
      final cubit = await open();
      cubit.startNewUndername('acme');
      cubit.editNewUndername('docs');
      await pumpEventQueue();
      await cubit.commit();

      final changes = verify(() => executor.execute(
            name: any(named: 'name'),
            change: captureAny(named: 'change'),
            owner: any(named: 'owner'),
            payer: any(named: 'payer'),
            paidBy: any(named: 'paidBy'),
            onStep: any(named: 'onStep'),
            onNonce: any(named: 'onNonce'),
          )).captured;
      expect(changes, [
        const ArNSSetRecord(
          antId: _antId,
          undername: 'docs',
          transactionId: _itemTx,
          ttlSeconds: 300,
        ),
        const ArNSRemoveRecord(antId: _antId, undername: 'www'),
      ]);
      expect(cubit.state.stage, ArNSDialogStage.done);
      verify(() => metadata.writeAssignedNames(
            driveId: 'drive-1',
            fileId: 'file-1',
            names: ['docs_acme'],
          )).called(1);
    });

    test('a failed removal leaves the new name live and is not retried',
        () async {
      var calls = 0;
      when(() => executor.execute(
            name: any(named: 'name'),
            change: any(named: 'change'),
            owner: any(named: 'owner'),
            payer: any(named: 'payer'),
            paidBy: any(named: 'paidBy'),
            onStep: any(named: 'onStep'),
            onNonce: any(named: 'onNonce'),
          )).thenAnswer((_) async {
        if (++calls == 2) {
          throw const ArNSChangeFailure(ArNSFailureKind.rejected);
        }
      });
      final cubit = await open();
      cubit.startNewUndername('acme');
      cubit.editNewUndername('docs');
      await pumpEventQueue();
      await cubit.commit();

      expect(calls, 2);
      expect(cubit.state.stage, ArNSDialogStage.done);
      expect(cubit.state.previousRemovalFailed, isTrue);
      verify(() => metadata.writeAssignedNames(
            driveId: 'drive-1',
            fileId: 'file-1',
            names: ['www_acme', 'docs_acme'],
          )).called(1);
    });

    test('an old main name stays when no placeholder page is set', () async {
      chain = [
        _name(records: const [
          ArNSNameRecord(
            name: 'acme',
            undername: '@',
            transactionId: _itemTx,
            ttlSeconds: 300,
          ),
        ]),
      ];
      final cubit = await open(placeholder: null);
      cubit.startNewUndername('acme');
      cubit.editNewUndername('docs');
      await pumpEventQueue();

      expect(cubit.state.movesFrom, isNull);
      expect(cubit.previousRemoval, isNull);
    });
  });

  group('the name step in a flow', () {
    ArNSFlowNameCubit flow({List<ArNSNameRecord> following = const []}) {
      names = ArNSNamesCubit(repository: repository, walletCubit: wallet);
      return ArNSFlowNameCubit(
        namesCubit: names,
        walletCubit: wallet,
        actionClient: client,
        executor: executor,
        arioSDK: sdk,
        metadataWriter: metadata,
        paymentSource: payments,
        following: following,
        clock: () => now,
        resolveItem: (tx) async => tx == _itemTx ? _item : null,
      );
    }

    const blog = ArNSNameRecord(
      name: 'acme',
      undername: 'blog',
      transactionId: _otherTx,
      ttlSeconds: 900,
    );

    test('has no work and is ready with nothing chosen', () async {
      final cubit = flow()..load();
      await pumpEventQueue();

      expect(cubit.hasWork, isFalse);
      expect(cubit.ready, isTrue);
      expect(await cubit.applyTo(_itemTx), const ArNSFlowOutcome());
    });

    test('names on the old version move, priced, unless left', () async {
      final cubit = flow(following: [blog])..load();
      await pumpEventQueue();

      expect(cubit.plannedNames, ['blog_acme']);
      expect(cubit.state.cost?.credits, _price + _metadata);
      expect(cubit.ready, isTrue);

      cubit.setLeaveOnOld(true);
      await pumpEventQueue();
      expect(cubit.hasWork, isFalse);
      expect(cubit.plannedNames, isEmpty);
    });

    test('points the moving names and the new one at the new item', () async {
      final cubit = flow(following: [blog])..load();
      await pumpEventQueue();
      cubit.startNewUndername('acme');
      cubit.editNewUndername('docs');
      await pumpEventQueue();
      expect(cubit.plannedNames, ['blog_acme', 'docs_acme']);

      final outcome = await cubit.applyTo(_itemTx);

      expect(outcome.live, ['blog_acme', 'docs_acme']);
      final changes = verify(() => executor.execute(
            name: any(named: 'name'),
            change: captureAny(named: 'change'),
            owner: any(named: 'owner'),
            payer: any(named: 'payer'),
            paidBy: any(named: 'paidBy'),
            onStep: any(named: 'onStep'),
            onNonce: any(named: 'onNonce'),
          )).captured;
      expect(changes, [
        const ArNSSetRecord(
          antId: _antId,
          undername: 'blog',
          transactionId: _itemTx,
          ttlSeconds: 900,
        ),
        const ArNSSetRecord(
          antId: _antId,
          undername: 'docs',
          transactionId: _itemTx,
          ttlSeconds: 300,
        ),
      ]);
      verify(() => metadata.writeAssignedNames(
            driveId: 'drive-1',
            fileId: 'file-1',
            names: any(named: 'names'),
          )).called(1);
    });

    test('a failure after the upload is reported, not retried', () async {
      when(() => executor.execute(
                name: any(named: 'name'),
                change: any(named: 'change'),
                owner: any(named: 'owner'),
                payer: any(named: 'payer'),
                paidBy: any(named: 'paidBy'),
                onStep: any(named: 'onStep'),
                onNonce: any(named: 'onNonce'),
              ))
          .thenThrow(const ArNSChangeFailure(ArNSFailureKind.lostAfterCreate));
      final cubit = flow(following: [blog])..load();
      await pumpEventQueue();

      final outcome = await cubit.applyTo(_itemTx);

      expect(outcome.failed, ['blog_acme']);
      expect(outcome.live, isEmpty);
      verifyNever(() => metadata.writeAssignedNames(
            driveId: any(named: 'driveId'),
            fileId: any(named: 'fileId'),
            names: any(named: 'names'),
          ));
    });

    test('waits for the ArNS wallet before the flow can start', () async {
      setUpWallet(_wallet(connected: false));
      final cubit = flow(following: [blog])..load();
      await pumpEventQueue();

      expect(cubit.hasWork, isTrue);
      expect(cubit.ready, isFalse);
    });

    test('a publication writes no file metadata', () async {
      names = ArNSNamesCubit(repository: repository, walletCubit: wallet);
      final cubit = ArNSFlowNameCubit(
        namesCubit: names,
        walletCubit: wallet,
        actionClient: client,
        executor: executor,
        arioSDK: sdk,
        metadataWriter: metadata,
        paymentSource: payments,
        following: const [blog],
        writesHint: false,
        clock: () => now,
      )..load();
      await pumpEventQueue();

      expect(cubit.state.cost?.credits, _price);
      await cubit.applyTo(_itemTx);
      verifyNever(() => metadata.writeAssignedNames(
            driveId: any(named: 'driveId'),
            fileId: any(named: 'fileId'),
            names: any(named: 'names'),
          ));
    });
  });
}
