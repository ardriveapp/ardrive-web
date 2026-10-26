part of 'arns_name_dialog_cubit.dart';

/// What the dialog is for (docs/NAMES.md, "Flows").
enum ArNSNameDialogMode {
  /// Add name or Change name, from an item: pick a name.
  nameItem,

  /// From the Names page: point a record at an ArDrive item.
  pointRecord,

  /// From the Names page: change a record's cache time.
  cacheTime,

  /// Remove name: an undername is deleted, a main name points at "Nothing
  /// published here".
  remove,
}

enum ArNSDialogStage {
  /// Reading the names, with none to show yet.
  loading,

  /// No ArNS wallet linked, so there are no names to list yet.
  needsWallet,

  /// The linked wallet owns and manages no names.
  noNames,

  /// The names could not be read.
  loadFailed,

  /// Picking, with the cost line.
  choose,

  /// "blog_acme.ar.io points to Last year's site. Point it here instead?"
  confirmRepoint,

  /// Through the wallet prompts.
  committing,

  done,
  failed,
}

/// A record picked in the dialog: a name's own record (`@`), an undername
/// that exists, or one to create.
class ArNSRecordChoice extends Equatable {
  const ArNSRecordChoice({
    required this.name,
    required this.undername,
    this.isNew = false,
  });

  final String name;
  final String undername;
  final bool isNew;

  String get literalName => literalArNSName(undername, name);

  @override
  List<Object?> get props => [name, undername, isNew];
}

/// What a change costs, said before any prompt.
class ArNSCost extends Equatable {
  const ArNSCost({
    required this.credits,
    required this.metadataWrites,
    this.solLamports,
  });

  /// In winc: the name change through Turbo plus the metadata update, or
  /// the metadata update alone for a name managed for its owner.
  final BigInt credits;

  /// How many metadata revisions [credits] includes.
  final int metadataWrites;

  /// What a name managed for its owner costs the ArNS wallet on Solana.
  final int? solLamports;

  bool get paidInSol => solLamports != null;

  @override
  List<Object?> get props => [credits, metadataWrites, solLamports];
}

class ArNSNameDialogState extends Equatable {
  const ArNSNameDialogState({
    required this.mode,
    this.stage = ArNSDialogStage.loading,
    this.item,
    this.names = const [],
    this.choice,
    this.newUndername = '',
    this.newUndernameFor,
    this.cacheTime = ArNSCacheTime.standard,
    this.cost,
    this.pricing = false,
    this.costFailed = false,
    this.creditBalance,
    this.solBalance,
    this.step,
    this.failure,
    this.metadataFailed = false,
    this.items = const [],
    this.itemQuery = '',
    this.now,
    this.placeholderTxId,
    this.previousRecord,
    this.removePrevious = true,
    this.previousRemovalFailed = false,
    this.following = const [],
    this.leaveOnOld = false,
  });

  final ArNSNameDialogMode mode;
  final ArNSDialogStage stage;

  /// What the name points to: the item named, or the item picked on the
  /// Names page. For a removal, the file whose metadata loses the name.
  final ArNSNameableItem? item;

  /// Names the wallet can still change: expired leases are left out.
  final List<ArNSManagedName> names;
  final ArNSRecordChoice? choice;

  /// The undername being typed, and the name it goes under.
  final String newUndername;
  final String? newUndernameFor;

  final ArNSCacheTime cacheTime;
  final ArNSCost? cost;
  final bool pricing;
  final bool costFailed;

  /// Credits the ArDrive wallet can spend, in winc; null until read.
  final BigInt? creditBalance;

  /// Lamports the ArNS wallet holds, read for a name managed for its owner.
  final int? solBalance;

  final ArNSCommitStep? step;
  final ArNSChangeFailure? failure;

  /// The name changed but the item's metadata couldn't be updated.
  final bool metadataFailed;

  /// Items to point a record at, for [ArNSNameDialogMode.pointRecord].
  final List<ArNSNameableItem> items;
  final String itemQuery;

  /// The clock, for lease ends.
  final DateTime? now;

  /// The "Nothing published here" page a removed main name points at: not
  /// "somewhere else" worth confirming.
  final String? placeholderTxId;

  /// Change name: the item's name when the dialog opened. Choosing another
  /// moves the name, removing this one too unless [removePrevious] is off.
  final ArNSNameRecord? previousRecord;
  final bool removePrevious;

  /// The new name is live but the old one couldn't be removed.
  final bool previousRemovalFailed;

  /// In a flow: the names on the old version, which move to the new one
  /// unless [leaveOnOld] (Q12, Q29).
  final List<ArNSNameRecord> following;
  final bool leaveOnOld;

  /// The names that move with a new version.
  List<ArNSNameRecord> get moving => leaveOnOld ? const [] : following;

  /// The name a Change moves away from, when it can be removed: an
  /// undername, or a main name once the "Nothing published here" page is
  /// configured.
  ArNSNameRecord? get movesFrom {
    final previous = previousRecord;
    final choice = this.choice;
    if (mode != ArNSNameDialogMode.nameItem ||
        previous == null ||
        choice == null) {
      return null;
    }
    if (!choice.isNew &&
        choice.name == previous.name &&
        choice.undername == previous.undername) {
      return null;
    }
    if (previous.isApex && placeholderTxId == null) return null;
    return previous;
  }

  /// The old name is removed in the same flow.
  bool get removesPrevious => movesFrom != null && removePrevious;

  /// Change name rather than Add name: the item had a name when the dialog
  /// opened. Not read from [names], which point at the item once the change
  /// is made, so the title would turn to Change name half way through.
  bool get changesName =>
      mode == ArNSNameDialogMode.nameItem && previousRecord != null;

  ArNSManagedName? get selectedName {
    final choice = this.choice;
    if (choice == null) return null;
    for (final name in names) {
      if (name.name == choice.name) return name;
    }
    return null;
  }

  /// The record the choice changes, when it exists already.
  ArNSNameRecord? get selectedRecord {
    final choice = this.choice;
    final name = selectedName;
    if (choice == null || name == null || choice.isNew) return null;
    for (final record in name.records) {
      if (record.undername == choice.undername) return record;
    }
    return null;
  }

  /// The record points somewhere else now: confirm before repointing.
  bool get repoints {
    if (mode != ArNSNameDialogMode.nameItem &&
        mode != ArNSNameDialogMode.pointRecord) {
      return false;
    }
    final record = selectedRecord;
    final item = this.item;
    return record != null &&
        item != null &&
        record.transactionId != item.dataTxId &&
        record.transactionId != placeholderTxId;
  }

  UndernameProblem? get newUndernameProblem {
    final name = newUndernameFor;
    if (name == null) return null;
    return validateUndername(newUndername.trim(), name: name);
  }

  /// The undername typed exists already under that name.
  bool get newUndernameTaken {
    final name = newUndernameFor;
    if (name == null) return false;
    final undername = newUndername.trim().toLowerCase();
    for (final n in names) {
      if (n.name != name) continue;
      return n.records.any((r) => r.undername.toLowerCase() == undername);
    }
    return false;
  }

  bool get inGracePeriod {
    final name = selectedName;
    return name != null && name.isInGracePeriod(now ?? DateTime.now());
  }

  bool get insufficientCredits {
    final cost = this.cost;
    final balance = creditBalance;
    return cost != null && balance != null && balance < cost.credits;
  }

  bool get insufficientSol {
    final lamports = cost?.solLamports;
    final balance = solBalance;
    return lamports != null && balance != null && balance < lamports;
  }

  /// Nothing would change: the record points here with this cache time.
  bool get unchanged {
    final record = selectedRecord;
    if (record == null) return false;
    return switch (mode) {
      ArNSNameDialogMode.nameItem ||
      ArNSNameDialogMode.pointRecord =>
        record.transactionId == item?.dataTxId &&
            record.ttlSeconds == cacheTime.seconds,
      ArNSNameDialogMode.cacheTime => record.ttlSeconds == cacheTime.seconds,
      ArNSNameDialogMode.remove => false,
    };
  }

  bool get canCommit {
    final choice = this.choice;
    if (stage != ArNSDialogStage.choose || choice == null) return false;
    if (choice.isNew && (newUndernameProblem != null || newUndernameTaken)) {
      return false;
    }
    if (mode != ArNSNameDialogMode.remove &&
        mode != ArNSNameDialogMode.cacheTime &&
        item == null) {
      return false;
    }
    return cost != null &&
        !pricing &&
        !insufficientCredits &&
        !insufficientSol &&
        !inGracePeriod &&
        !unchanged;
  }

  ArNSNameDialogState copyWith({
    ArNSDialogStage? stage,
    ArNSNameableItem? Function()? item,
    List<ArNSManagedName>? names,
    ArNSRecordChoice? Function()? choice,
    String? newUndername,
    String? Function()? newUndernameFor,
    ArNSCacheTime? cacheTime,
    ArNSCost? Function()? cost,
    bool? pricing,
    bool? costFailed,
    BigInt? Function()? creditBalance,
    int? Function()? solBalance,
    ArNSCommitStep? Function()? step,
    ArNSChangeFailure? Function()? failure,
    bool? metadataFailed,
    List<ArNSNameableItem>? items,
    String? itemQuery,
    DateTime? now,
    bool? removePrevious,
    bool? previousRemovalFailed,
    ArNSNameRecord? Function()? previousRecord,
    bool? leaveOnOld,
    List<ArNSNameRecord>? following,
  }) =>
      ArNSNameDialogState(
        mode: mode,
        stage: stage ?? this.stage,
        item: item != null ? item() : this.item,
        names: names ?? this.names,
        choice: choice != null ? choice() : this.choice,
        newUndername: newUndername ?? this.newUndername,
        newUndernameFor:
            newUndernameFor != null ? newUndernameFor() : this.newUndernameFor,
        cacheTime: cacheTime ?? this.cacheTime,
        cost: cost != null ? cost() : this.cost,
        pricing: pricing ?? this.pricing,
        costFailed: costFailed ?? this.costFailed,
        creditBalance:
            creditBalance != null ? creditBalance() : this.creditBalance,
        solBalance: solBalance != null ? solBalance() : this.solBalance,
        step: step != null ? step() : this.step,
        failure: failure != null ? failure() : this.failure,
        metadataFailed: metadataFailed ?? this.metadataFailed,
        items: items ?? this.items,
        itemQuery: itemQuery ?? this.itemQuery,
        now: now ?? this.now,
        placeholderTxId: placeholderTxId,
        previousRecord:
            previousRecord != null ? previousRecord() : this.previousRecord,
        removePrevious: removePrevious ?? this.removePrevious,
        previousRemovalFailed:
            previousRemovalFailed ?? this.previousRemovalFailed,
        following: following ?? this.following,
        leaveOnOld: leaveOnOld ?? this.leaveOnOld,
      );

  @override
  List<Object?> get props => [
        mode,
        stage,
        item,
        names,
        choice,
        newUndername,
        newUndernameFor,
        cacheTime,
        cost,
        pricing,
        costFailed,
        creditBalance,
        solBalance,
        step,
        failure,
        metadataFailed,
        items,
        itemQuery,
        now,
        previousRecord,
        removePrevious,
        previousRemovalFailed,
        following,
        leaveOnOld,
      ];
}
