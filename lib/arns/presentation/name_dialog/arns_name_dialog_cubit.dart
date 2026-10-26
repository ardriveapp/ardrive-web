import 'dart:async';

import 'package:ardrive/arns/data/arns_change_executor.dart';
import 'package:ardrive/arns/data/arns_file_metadata_writer.dart';
import 'package:ardrive/arns/data/turbo_arns_action_client.dart';
import 'package:ardrive/arns/domain/arns_action.dart';
import 'package:ardrive/arns/domain/arns_cache_time.dart';
import 'package:ardrive/arns/domain/arns_nameable_item.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/domain/undername_validation.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'arns_name_dialog_state.dart';
part 'arns_flow_name_cubit.dart';

/// Searches the items a record can point at, for the Names page.
typedef ArNSNameableItemSearch = Future<List<ArNSNameableItem>> Function(
  String query,
);

/// The name dialog: Add name, Change name, Remove name, and the Names page's
/// changes (docs/NAMES.md, "Flows"). Says the cost before any prompt, asks
/// for the ArNS wallet at commit, and never retries a change that may have
/// been charged.
class ArNSNameDialogCubit extends Cubit<ArNSNameDialogState> {
  ArNSNameDialogCubit({
    required ArNSNameDialogMode mode,
    required ArNSNamesCubit namesCubit,
    required ArNSWalletCubit walletCubit,
    required TurboArNSActionClient actionClient,
    required ArNSChangeExecutor executor,
    required ArioSDK arioSDK,
    required ArNSFileMetadataWriter metadataWriter,
    required ArNSPaymentSource paymentSource,
    String? placeholderTxId,
    ArNSNameableItem? item,
    ArNSRecordChoice? choice,
    ArNSNameableItemSearch? searchItems,
    DateTime Function()? clock,
    List<ArNSNameRecord> following = const [],
  })  : _namesCubit = namesCubit,
        _walletCubit = walletCubit,
        _actionClient = actionClient,
        _executor = executor,
        _arioSDK = arioSDK,
        _metadataWriter = metadataWriter,
        _paymentSource = paymentSource,
        _searchItems = searchItems,
        _clock = clock ?? DateTime.now,
        super(ArNSNameDialogState(
          mode: mode,
          item: item,
          choice: choice,
          placeholderTxId: placeholderTxId,
          now: (clock ?? DateTime.now)(),
          following: following,
        ));

  final ArNSNamesCubit _namesCubit;
  final ArNSWalletCubit _walletCubit;
  final TurboArNSActionClient _actionClient;
  final ArNSChangeExecutor _executor;
  final ArioSDK _arioSDK;
  final ArNSFileMetadataWriter _metadataWriter;
  final ArNSPaymentSource _paymentSource;
  final ArNSNameableItemSearch? _searchItems;
  final DateTime Function() _clock;

  StreamSubscription<ArNSNamesState>? _namesSubscription;
  final _prices = <ArNSRecordAction, BigInt>{};
  BigInt? _metadataCost;
  List<String> _paidBy = const [];
  int _priceRequest = 0;
  bool _choiceSeeded = false;

  /// Starts on the cached names and reads ArNS again, so the picker shows
  /// what the chain says.
  Future<void> load() async {
    _onNames(_namesCubit.state);
    _namesSubscription = _namesCubit.stream.listen(_onNames);
    if (state.mode == ArNSNameDialogMode.pointRecord) {
      unawaited(searchItems(''));
    }
    await _namesCubit.refresh();
  }

  void _onNames(ArNSNamesState names) {
    if (isClosed) return;
    final now = _clock();
    final usable = [
      for (final name in names.names)
        if (!name.isExpired(now)) name,
    ];
    final settled = switch (state.stage) {
      ArNSDialogStage.loading ||
      ArNSDialogStage.needsWallet ||
      ArNSDialogStage.noNames ||
      ArNSDialogStage.loadFailed ||
      ArNSDialogStage.choose =>
        false,
      _ => true,
    };
    if (settled) {
      emit(state.copyWith(names: usable, now: now));
      return;
    }

    final stage = switch (names.status) {
      ArNSNamesStatus.none => ArNSDialogStage.needsWallet,
      ArNSNamesStatus.loading => ArNSDialogStage.loading,
      ArNSNamesStatus.failed => ArNSDialogStage.loadFailed,
      ArNSNamesStatus.loaded =>
        usable.isEmpty ? ArNSDialogStage.noNames : ArNSDialogStage.choose,
    };
    final wasChoosing = state.stage == ArNSDialogStage.choose;
    emit(state.copyWith(stage: stage, names: usable, now: now));
    if (stage == ArNSDialogStage.choose) {
      if (!_choiceSeeded) {
        _choiceSeeded = true;
        _seedChoice();
      }
      if (!wasChoosing) unawaited(_reprice());
    }
  }

  /// Change name opens on the item's current name, with its cache time.
  void _seedChoice() {
    var choice = state.choice;
    final item = state.item;
    if (choice == null &&
        item != null &&
        state.mode == ArNSNameDialogMode.nameItem) {
      final current = recordsPointingAt(state.names, item.dataTxId);
      if (current.isNotEmpty) {
        choice = ArNSRecordChoice(
          name: current.first.name,
          undername: current.first.undername,
        );
        emit(state.copyWith(previousRecord: () => current.first));
      }
    }
    if (choice == null) return;
    emit(state.copyWith(choice: () => choice));
    final record = state.selectedRecord;
    if (record != null) {
      emit(state.copyWith(
        cacheTime:
            ArNSCacheTime.fromSeconds(record.ttlSeconds) ?? state.cacheTime,
      ));
    }
  }

  /// Picks a name's own record (`@`) or an existing undername.
  void choose(String name, String undername) {
    emit(state.copyWith(
      choice: () => ArNSRecordChoice(name: name, undername: undername),
      newUndernameFor: () => null,
      newUndername: '',
    ));
    final record = state.selectedRecord;
    if (record != null && state.mode != ArNSNameDialogMode.nameItem) {
      emit(state.copyWith(
        cacheTime:
            ArNSCacheTime.fromSeconds(record.ttlSeconds) ?? state.cacheTime,
      ));
    }
    unawaited(_reprice());
  }

  /// Opens the field for a new undername under [name].
  void startNewUndername(String name) {
    emit(state.copyWith(
      newUndernameFor: () => name,
      newUndername: '',
      choice: () => ArNSRecordChoice(name: name, undername: '', isNew: true),
    ));
    unawaited(_reprice());
  }

  void editNewUndername(String text) {
    final name = state.newUndernameFor;
    if (name == null) return;
    final repriceNeeded = state.choice?.isNew != true;
    emit(state.copyWith(
      newUndername: text,
      choice: () =>
          ArNSRecordChoice(name: name, undername: text.trim(), isNew: true),
    ));
    if (repriceNeeded || state.cost == null) unawaited(_reprice());
  }

  /// Change name: whether the old name is removed too (on by default).
  void setRemovePrevious(bool remove) {
    emit(state.copyWith(removePrevious: remove));
    unawaited(_reprice());
  }

  /// The old name's removal, when a Change moves the name: an undername is
  /// deleted, a main name points at "Nothing published here".
  ArNSRecordChange? get previousRemoval {
    if (!state.removesPrevious) return null;
    final previous = state.movesFrom!;
    final name = _nameOf(previous.name);
    if (name == null) return null;
    if (!previous.isApex) {
      return ArNSRemoveRecord(
          antId: name.processId, undername: previous.undername);
    }
    return ArNSSetRecord(
      antId: name.processId,
      undername: arnsApex,
      transactionId: state.placeholderTxId!,
      ttlSeconds: previous.ttlSeconds,
    );
  }

  ArNSManagedName? _nameOf(String name) {
    for (final n in state.names) {
      if (n.name == name) return n;
    }
    return null;
  }

  void setCacheTime(ArNSCacheTime cacheTime) {
    emit(state.copyWith(cacheTime: cacheTime));
  }

  /// For the Names page: the item a record will point at.
  void pickItem(ArNSNameableItem item) {
    emit(state.copyWith(item: () => item));
    unawaited(_reprice());
  }

  Future<void> searchItems(String query) async {
    final search = _searchItems;
    if (search == null) return;
    emit(state.copyWith(itemQuery: query));
    try {
      final items = await search(query);
      if (isClosed || state.itemQuery != query) return;
      emit(state.copyWith(items: items));
    } catch (e) {
      logger.w('Could not search items to name: $e');
    }
  }

  /// The change the choice makes, or null while there is nothing to make.
  ArNSRecordChange? get change {
    final name = state.selectedName;
    final choice = state.choice;
    if (name == null || choice == null || choice.undername.isEmpty) {
      return null;
    }
    switch (state.mode) {
      case ArNSNameDialogMode.remove:
        final record = state.selectedRecord;
        if (record == null) return null;
        if (!record.isApex) {
          return ArNSRemoveRecord(
            antId: name.processId,
            undername: record.undername,
          );
        }
        final placeholder = state.placeholderTxId;
        if (placeholder == null) return null;
        return ArNSSetRecord(
          antId: name.processId,
          undername: arnsApex,
          transactionId: placeholder,
          ttlSeconds: record.ttlSeconds,
        );
      case ArNSNameDialogMode.cacheTime:
        final record = state.selectedRecord;
        if (record == null) return null;
        return ArNSSetRecord(
          antId: name.processId,
          undername: record.undername,
          transactionId: record.transactionId,
          ttlSeconds: state.cacheTime.seconds,
        );
      case ArNSNameDialogMode.nameItem:
      case ArNSNameDialogMode.pointRecord:
        final item = state.item;
        if (item == null) return null;
        return ArNSSetRecord(
          antId: name.processId,
          undername: choice.undername,
          transactionId: item.dataTxId,
          ttlSeconds: state.cacheTime.seconds,
        );
    }
  }

  /// Main names can't be removed until the "Nothing published here" page
  /// is configured.
  bool get canRemoveMainName => state.placeholderTxId != null;

  int get _metadataWrites => switch (state.mode) {
        ArNSNameDialogMode.cacheTime => 0,
        // A publication's names go in publication.json on its next publish.
        _ => state.item == null || state.item!.isPublication ? 0 : 1,
      };

  Future<void> _reprice() async {
    final change = this.change;
    final name = state.selectedName;
    final request = ++_priceRequest;
    if (change == null || name == null) {
      emit(state.copyWith(cost: () => null, pricing: false));
      return;
    }
    emit(state.copyWith(pricing: true, costFailed: false));

    try {
      final writes = _metadataWrites;
      final metadata = writes == 0
          ? BigInt.zero
          : (await _metadataPrice()) * BigInt.from(writes);

      var credits = metadata;
      int? lamports;
      Future<void> add(ArNSManagedName of, ArNSRecordChange c,
          {required bool exists}) async {
        if (of.role == ArNSRole.owner) {
          credits += await _price(c.action);
        } else {
          final estimate = await _arioSDK.estimateControllerFee(
            processId: of.processId,
            write: _controllerWrite(c, exists: exists),
            undername: c.undername,
          );
          lamports = (lamports ?? 0) + estimate.totalLamports;
        }
      }

      await add(name, change, exists: state.selectedRecord != null);
      final removal = previousRemoval;
      final previousName =
          state.movesFrom == null ? null : _nameOf(state.movesFrom!.name);
      if (removal != null && previousName != null) {
        await add(previousName, removal, exists: true);
      }
      final cost = ArNSCost(
        credits: credits,
        metadataWrites: writes,
        solLamports: lamports,
      );
      int? solBalance;
      if (lamports != null) {
        final address = _walletCubit.state.linked?.address;
        if (address != null) {
          solBalance = await _arioSDK.getSolBalanceLamports(address).then(
                (b) => b.toInt(),
              );
        }
      }

      var balance = state.creditBalance;
      if (balance == null && cost.credits > BigInt.zero) {
        final read = await _paymentSource.balance();
        balance = read.balance;
        _paidBy = read.paidBy;
      }

      if (isClosed || request != _priceRequest) return;
      emit(state.copyWith(
        cost: () => cost,
        pricing: false,
        creditBalance: () => balance,
        solBalance: () => solBalance ?? state.solBalance,
      ));
    } catch (e) {
      logger.w('Could not price the name change: $e');
      if (isClosed || request != _priceRequest) return;
      emit(state.copyWith(cost: () => null, pricing: false, costFailed: true));
    }
  }

  /// Prices again after a failed read.
  void retryPrice() => unawaited(_reprice());

  static ControllerWrite _controllerWrite(
    ArNSRecordChange change, {
    required bool exists,
  }) {
    if (change is ArNSRemoveRecord) return ControllerWrite.removeRecord;
    return exists ? ControllerWrite.editRecord : ControllerWrite.createRecord;
  }

  Future<BigInt> _price(ArNSRecordAction action) async =>
      _prices[action] ??= await _actionClient.price(action);

  Future<BigInt> _metadataPrice() async =>
      _metadataCost ??= await _metadataWriter.estimateCost();

  /// Makes the change: confirms a repoint first, then the wallet prompts.
  Future<void> commit() async {
    if (!state.canCommit) return;
    if (state.repoints) {
      emit(state.copyWith(stage: ArNSDialogStage.confirmRepoint));
      return;
    }
    await _run();
  }

  /// "Point it here instead?" answered yes.
  Future<void> confirmRepoint() async {
    if (state.stage != ArNSDialogStage.confirmRepoint) return;
    emit(state.copyWith(stage: ArNSDialogStage.choose));
    await _run();
  }

  /// Back from the repoint question, or from a failure that charged nothing.
  void backToChoose() {
    final failure = state.failure;
    if (failure != null && !_canTryAgain(failure.kind)) return;
    emit(state.copyWith(
      stage: ArNSDialogStage.choose,
      failure: () => null,
      step: () => null,
    ));
    unawaited(_reprice());
  }

  /// Whether a failure leaves nothing charged, so trying again is safe.
  static bool _canTryAgain(ArNSFailureKind kind) => switch (kind) {
        ArNSFailureKind.rejected ||
        ArNSFailureKind.failed ||
        ArNSFailureKind.wrongAccount ||
        ArNSFailureKind.insufficientCredits =>
          true,
        // Never: the action may exist, or its credits are on their way back.
        ArNSFailureKind.lostAfterCreate || ArNSFailureKind.expired => false,
      };

  bool get canTryAgain {
    final failure = state.failure;
    return failure != null && _canTryAgain(failure.kind);
  }

  Future<void> _run() async {
    final change = this.change;
    final name = state.selectedName;
    final choice = state.choice;
    final owner = _walletCubit.ownerSigner;
    if (change == null || name == null || choice == null || owner == null) {
      return;
    }
    final literal = choice.literalName;
    // Read before the change: afterwards the names hold the new record.
    final liveWithin = switch (change) {
      ArNSSetRecord(:final ttlSeconds) => arnsLiveWithinSeconds(
          ttlSeconds: ttlSeconds,
          previousTtlSeconds: state.selectedRecord?.ttlSeconds,
        ),
      ArNSRemoveRecord() => null,
    };

    emit(state.copyWith(
      stage: ArNSDialogStage.committing,
      step: () => ArNSCommitStep.approve,
      failure: () => null,
      liveWithinSeconds: () => liveWithin,
    ));

    try {
      await _executor.execute(
        name: name,
        change: change,
        owner: owner,
        payer: _paymentSource.payer(),
        paidBy: _paidBy,
        onStep: (step) {
          if (!isClosed) emit(state.copyWith(step: () => step));
        },
      );
    } on ArNSChangeFailure catch (failure) {
      if (failure.kind == ArNSFailureKind.lostAfterCreate) {
        // Never retried: what happened is read from ArNS instead.
        unawaited(_namesCubit.refresh());
      }
      if (!isClosed) {
        emit(state.copyWith(
          stage: ArNSDialogStage.failed,
          failure: () => failure,
          step: () => null,
        ));
      }
      return;
    }

    await _namesCubit.refreshName(name.name, made: [change]);

    // Change name moves the name: the old one goes in a change of its own,
    // with its own nonce. If it fails the new name stands, and nothing is
    // tried again.
    final removal = previousRemoval;
    final previous = state.movesFrom;
    var previousRemoved = false;
    var previousRemovalFailed = false;
    if (removal != null && previous != null) {
      final previousName = _nameOf(previous.name);
      if (previousName != null) {
        try {
          await _executor.execute(
            name: previousName,
            change: removal,
            owner: owner,
            payer: _paymentSource.payer(),
            paidBy: _paidBy,
            onStep: (step) {
              if (!isClosed) emit(state.copyWith(step: () => step));
            },
          );
          previousRemoved = true;
        } on ArNSChangeFailure catch (failure) {
          logger.w('The old name was not removed: ${failure.kind}');
          previousRemovalFailed = true;
          if (failure.kind == ArNSFailureKind.lostAfterCreate) {
            unawaited(_namesCubit.refresh());
          }
        }
        await _namesCubit.refreshName(
          previousName.name,
          made: [
            if (previousName.name == name.name) change,
            if (previousRemoved) removal,
          ],
        );
      }
    }

    var metadataFailed = false;
    final item = state.item;
    if (item != null && _metadataWrites > 0) {
      if (!isClosed) {
        emit(state.copyWith(step: () => ArNSCommitStep.updatingDetails));
      }
      try {
        final names = [
          for (final record in _namesCubit.state.recordsFor(item.dataTxId))
            record.literalName,
        ];
        // ArNS may not show the change yet: the hint says what was done.
        if (state.mode == ArNSNameDialogMode.remove) {
          names.remove(literal);
        } else if (!names.contains(literal)) {
          names.add(literal);
        }
        if (previousRemoved) names.remove(previous!.literalName);
        await _metadataWriter.writeAssignedNames(
          driveId: item.driveId,
          fileId: item.fileId,
          names: names,
        );
      } catch (e) {
        logger.w('The name changed, but the metadata update failed: $e');
        metadataFailed = true;
      }
    }

    if (!isClosed) {
      emit(state.copyWith(
        stage: ArNSDialogStage.done,
        step: () => null,
        metadataFailed: metadataFailed,
        previousRemovalFailed: previousRemovalFailed,
      ));
    }
  }

  @override
  Future<void> close() async {
    await _namesSubscription?.cancel();
    return super.close();
  }
}
