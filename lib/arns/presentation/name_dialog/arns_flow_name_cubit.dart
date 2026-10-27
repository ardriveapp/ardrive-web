part of 'arns_name_dialog_cubit.dart';

/// What a flow's names came to once its item existed.
class ArNSFlowOutcome extends Equatable {
  const ArNSFlowOutcome({
    this.live = const [],
    this.failed = const [],
    this.liveWithinSeconds = 300,
  });

  /// Literal names that point at the new item now.
  final List<String> live;

  /// Literal names that couldn't be changed. Never tried again.
  final List<String> failed;

  /// When gateways show all the [live] names, in seconds: for each, the
  /// longer of its cache time before the change and after it.
  final int liveWithinSeconds;

  bool get isEmpty => live.isEmpty && failed.isEmpty;

  @override
  List<Object?> get props => [live, failed, liveWithinSeconds];
}

/// A transaction ID only for pricing, before the flow's item exists.
const _pricingTxId = 'PRICINGPRICINGPRICINGPRICINGPRICINGPRICING1';

/// The name step inside a flow: Publish, Create deployment and uploading a
/// single public file (docs/NAMES.md, "Name an item", "New versions").
///
/// Picks an optional name with the dialog's picker and cost line, carries
/// the names on the old version to the new one unless left there, and runs
/// the changes once the flow's transaction exists: [applyTo].
class ArNSFlowNameCubit extends ArNSNameDialogCubit {
  ArNSFlowNameCubit({
    required super.namesCubit,
    required super.walletCubit,
    required super.actionClient,
    required super.executor,
    required super.arioSDK,
    required super.metadataWriter,
    required super.paymentSource,
    super.following,
    super.clock,
    super.placeholderTxId,
    this.writesHint = true,
    Future<ArNSNameableItem?> Function(String dataTxId)? resolveItem,
  })  : _resolveItem = resolveItem,
        super(mode: ArNSNameDialogMode.nameItem);

  /// Whether the names go into the file's metadata afterwards; false for a
  /// publication, which writes them into publication.json itself.
  final bool writesHint;
  final Future<ArNSNameableItem?> Function(String dataTxId)? _resolveItem;

  /// Whether the flow will change any name.
  bool get hasWork => state.moving.isNotEmpty || _chosen != null;

  /// The literal names that will point at the new item, for
  /// `publication.json` and the confirm step.
  List<String> get plannedNames => [
        for (final record in state.moving) record.literalName,
        if (_chosenToAdd != null) _chosenToAdd!.literalName,
      ];

  /// The chosen name's record, while it points at something else and the
  /// repoint isn't confirmed yet (Q11). The flow waits until it is, so
  /// nothing is paid for before the question is answered.
  ArNSNameRecord? get repointing {
    final choice = _chosen;
    final record = state.selectedRecord;
    if (choice == null || record == null) return null;
    if (record.transactionId == state.placeholderTxId) return null;
    final moving = state.following.any(
      (r) => r.name == record.name && r.undername == record.undername,
    );
    if (moving || state.repointConfirmed == choice) return null;
    return record;
  }

  /// "Point it here instead?" answered yes.
  @override
  Future<void> confirmRepoint() async {
    if (repointing == null) return;
    emit(state.copyWith(repointConfirmed: () => state.choice));
  }

  /// Ready to go: nothing to change, or a priced change the wallet can
  /// approve now.
  bool get ready {
    if (!hasWork) return true;
    if (repointing != null) return false;
    final choice = state.choice;
    if (choice != null &&
        choice.isNew &&
        (state.newUndernameProblem != null || state.newUndernameTaken)) {
      return false;
    }
    return state.cost != null &&
        !state.pricing &&
        !state.insufficientCredits &&
        !state.insufficientSol &&
        !state.inGracePeriod &&
        _walletCubit.state.status == ArNSWalletStatus.connected;
  }

  ArNSRecordChoice? get _chosen {
    final choice = state.choice;
    if (choice == null || choice.undername.isEmpty) return null;
    return choice;
  }

  /// The chosen name, unless it is already one of the names moving to the
  /// new version: that one is changed once, as it moves.
  ArNSRecordChoice? get _chosenToAdd {
    final choice = _chosen;
    if (choice == null) return null;
    final moving = state.moving.any(
      (r) => r.name == choice.name && r.undername == choice.undername,
    );
    return moving ? null : choice;
  }

  /// No new name after all.
  void clearChoice() {
    emit(state.copyWith(
      choice: () => null,
      newUndernameFor: () => null,
      newUndername: '',
    ));
    unawaited(_reprice());
  }

  /// The names on the version being replaced, once known.
  void setFollowing(List<ArNSNameRecord> following) {
    emit(state.copyWith(following: following));
    unawaited(_reprice());
  }

  /// "Leave the name on the old version".
  void setLeaveOnOld(bool leave) {
    emit(state.copyWith(leaveOnOld: leave));
    unawaited(_reprice());
  }

  @override
  ArNSRecordChange? get change {
    final name = state.selectedName;
    final choice = _chosen;
    if (name == null || choice == null) return null;
    return ArNSSetRecord(
      antId: name.processId,
      undername: choice.undername,
      transactionId: state.item?.dataTxId ?? _pricingTxId,
      ttlSeconds: state.cacheTime.seconds,
    );
  }

  @override
  int get _metadataWrites => writesHint && hasWork ? 1 : 0;

  @override
  void _onNames(ArNSNamesState names) {
    super._onNames(names);
    // The flow prices what moves even before a name is picked.
    if (state.cost == null && !state.pricing && hasWork) {
      unawaited(_reprice());
    }
  }

  @override
  Future<void> _reprice() async {
    final request = ++_priceRequest;
    if (!hasWork) {
      emit(state.copyWith(cost: () => null, pricing: false));
      return;
    }
    emit(state.copyWith(pricing: true, costFailed: false));
    try {
      var credits = BigInt.zero;
      int? lamports;
      Future<void> add(ArNSManagedName of, ArNSRecordChange c,
          {required bool exists}) async {
        if (of.role == ArNSRole.owner) {
          credits += await _price(c.action);
        } else {
          final estimate = await _arioSDK.estimateControllerFee(
            processId: of.processId,
            write: ArNSNameDialogCubit._controllerWrite(c, exists: exists),
            undername: c.undername,
          );
          lamports = (lamports ?? 0) + estimate.totalLamports;
        }
      }

      for (final record in state.moving) {
        final of = _nameOf(record.name);
        if (of == null) continue;
        await add(of, _moveChange(of, record, _pricingTxId), exists: true);
      }
      final chosen = _chosenToAdd == null ? null : change;
      final name = state.selectedName;
      if (chosen != null && name != null) {
        await add(name, chosen, exists: state.selectedRecord != null);
      }
      if (_metadataWrites > 0) credits += await _metadataPrice();

      int? solBalance;
      final address = _walletCubit.state.linked?.address;
      if (lamports != null && address != null) {
        solBalance = (await _arioSDK.getSolBalanceLamports(address)).toInt();
      }
      var balance = state.creditBalance;
      if (balance == null && credits > BigInt.zero) {
        final read = await _paymentSource.balance();
        balance = read.balance;
        _paidBy = read.paidBy;
      }
      if (isClosed || request != _priceRequest) return;
      emit(state.copyWith(
        cost: () => ArNSCost(
          credits: credits,
          metadataWrites: _metadataWrites,
          solLamports: lamports,
        ),
        pricing: false,
        creditBalance: () => balance,
        solBalance: () => solBalance ?? state.solBalance,
      ));
    } catch (e) {
      logger.w('Could not price the flow\'s names: $e');
      if (isClosed || request != _priceRequest) return;
      emit(state.copyWith(cost: () => null, pricing: false, costFailed: true));
    }
  }

  static ArNSSetRecord _moveChange(
    ArNSManagedName name,
    ArNSNameRecord record,
    String dataTxId,
  ) =>
      ArNSSetRecord(
        antId: name.processId,
        undername: record.undername,
        transactionId: dataTxId,
        ttlSeconds: record.ttlSeconds,
      );

  /// Points the names at [dataTxId], the flow's new item: the names moving
  /// from the old version first, then the new one. Each is its own change
  /// with its own nonce; a failure is reported, never retried, and the
  /// flow's upload stands.
  ///
  /// [publication] is the publication version [dataTxId] is, from Publish:
  /// remembered first, so the names read as pointing to it at once.
  Future<ArNSFlowOutcome> applyTo(
    String dataTxId, {
    ArNSPublicationItem? publication,
  }) async {
    if (publication != null) {
      _namesCubit.rememberPublication(dataTxId, publication);
    }
    if (!hasWork) return const ArNSFlowOutcome();
    final owner = _walletCubit.ownerSigner;
    // Each with its record's cache time before the change, if it had one.
    final planned = <(ArNSManagedName, ArNSSetRecord, String, int?)>[];
    for (final record in state.moving) {
      final of = _nameOf(record.name);
      if (of == null) continue;
      planned.add((
        of,
        _moveChange(of, record, dataTxId),
        record.literalName,
        record.ttlSeconds,
      ));
    }
    final chosen = _chosenToAdd;
    final name = state.selectedName;
    if (chosen != null && name != null) {
      planned.add((
        name,
        ArNSSetRecord(
          antId: name.processId,
          undername: chosen.undername,
          transactionId: dataTxId,
          ttlSeconds: state.cacheTime.seconds,
        ),
        chosen.literalName,
        state.selectedRecord?.ttlSeconds,
      ));
    }

    if (owner == null) {
      return ArNSFlowOutcome(failed: [for (final p in planned) p.$3]);
    }

    final live = <String>[];
    final failed = <String>[];
    int? liveWithinSeconds;
    for (final (of, setRecord, literal, previousTtl) in planned) {
      try {
        await _executor.execute(
          name: of,
          change: setRecord,
          owner: owner,
          payer: _paymentSource.payer(),
          paidBy: _paidBy,
          onStep: (step) {
            if (!isClosed) emit(state.copyWith(step: () => step));
          },
        );
        _namesCubit.rememberChange(setRecord);
        live.add(literal);
        final within = arnsLiveWithinSeconds(
          ttlSeconds: setRecord.ttlSeconds,
          previousTtlSeconds: previousTtl,
        );
        if (liveWithinSeconds == null || within > liveWithinSeconds) {
          liveWithinSeconds = within;
        }
      } on ArNSChangeFailure catch (failure) {
        logger.w('The flow could not point $literal: ${failure.kind}');
        failed.add(literal);
      }
    }
    await _namesCubit.refresh();

    final resolve = _resolveItem;
    if (writesHint && live.isNotEmpty && resolve != null) {
      if (!isClosed) {
        emit(state.copyWith(step: () => ArNSCommitStep.updatingDetails));
      }
      try {
        final item = await resolve(dataTxId);
        if (item != null && !item.isPublication) {
          final names = {
            for (final r in _namesCubit.state.recordsFor(dataTxId))
              r.literalName,
            ...live,
          }.toList();
          await _metadataWriter.writeAssignedNames(
            driveId: item.driveId,
            fileId: item.fileId,
            names: names,
          );
        }
      } catch (e) {
        logger.w('The names changed, but the metadata update failed: $e');
      }
    }
    if (!isClosed) emit(state.copyWith(step: () => null));
    return ArNSFlowOutcome(
      live: live,
      failed: failed,
      liveWithinSeconds: liveWithinSeconds ?? ArNSCacheTime.standard.seconds,
    );
  }
}
