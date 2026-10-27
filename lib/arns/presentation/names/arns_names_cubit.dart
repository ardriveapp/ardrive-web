import 'dart:async';

import 'package:ardrive/arns/data/arns_names_repository.dart';
import 'package:ardrive/arns/domain/arns_action.dart';
import 'package:ardrive/arns/domain/arns_nameable_item.dart';
import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum ArNSNamesStatus {
  /// Names are off, or no ArNS wallet is linked.
  none,

  /// Reading, with nothing cached to show yet.
  loading,

  /// What ArNS (or the cache of it) says.
  loaded,

  /// The read failed, with nothing cached to show.
  failed,
}

class ArNSNamesState extends Equatable {
  const ArNSNamesState({
    this.status = ArNSNamesStatus.none,
    this.address,
    this.names = const [],
    this.refreshing = false,
    this.refreshFailed = false,
  });

  final ArNSNamesStatus status;

  /// The ArNS wallet the names were read for.
  final String? address;
  final List<ArNSManagedName> names;

  /// Reading ArNS again while [names] shows what was cached.
  final bool refreshing;

  /// The last read failed; [names] may be from the cache.
  final bool refreshFailed;

  /// The records pointing at [dataTxId], for a row's chip and the details
  /// panel's Name section.
  List<ArNSNameRecord> recordsFor(String dataTxId) =>
      recordsPointingAt(names, dataTxId);

  ArNSManagedName? nameOf(String name) {
    for (final n in names) {
      if (n.name == name) return n;
    }
    return null;
  }

  ArNSNamesState copyWith({
    ArNSNamesStatus? status,
    String? Function()? address,
    List<ArNSManagedName>? names,
    bool? refreshing,
    bool? refreshFailed,
  }) =>
      ArNSNamesState(
        status: status ?? this.status,
        address: address != null ? address() : this.address,
        names: names ?? this.names,
        refreshing: refreshing ?? this.refreshing,
        refreshFailed: refreshFailed ?? this.refreshFailed,
      );

  @override
  List<Object?> get props =>
      [status, address, names, refreshing, refreshFailed];
}

/// The names the linked ArNS wallet owns or manages, for every screen that
/// shows them: rows, the details panel, the name dialog and the Names page.
///
/// Shows the cache at once and reads ArNS when asked: when the Names page or
/// the name dialog opens, and after every change (docs/NAMES.md, "Where
/// names are recorded").
class ArNSNamesCubit extends Cubit<ArNSNamesState> {
  ArNSNamesCubit({
    required ArNSNamesRepository repository,
    required ArNSWalletCubit walletCubit,
  })  : _repository = repository,
        super(const ArNSNamesState()) {
    _onWallet(walletCubit.state);
    _subscription = walletCubit.stream.listen(_onWallet);
  }

  final ArNSNamesRepository _repository;
  late final StreamSubscription<ArNSWalletState> _subscription;
  Future<void>? _refreshing;
  String? _refreshingFor;

  void _onWallet(ArNSWalletState wallet) {
    final address = wallet.enabled ? wallet.linked?.address : null;
    if (address == state.address) return;
    if (address == null) {
      emit(const ArNSNamesState());
      return;
    }
    emit(ArNSNamesState(status: ArNSNamesStatus.loading, address: address));
    unawaited(_loadCached(address));
  }

  Future<void> _loadCached(String address) async {
    try {
      final cached = await _repository.cached(address);
      if (isClosed || state.address != address) return;
      // An empty cache is not "no names": nothing was read yet.
      if (cached.isNotEmpty) {
        emit(state.copyWith(status: ArNSNamesStatus.loaded, names: cached));
        return;
      }
    } catch (e) {
      logger.w('Could not read the cached names: $e');
      if (isClosed || state.address != address) return;
    }
    await refresh();
  }

  /// Reads the names from ArNS again. Calls while one is running for the
  /// same address share it; a refresh for another wallet starts its own.
  Future<void> refresh() {
    final address = state.address;
    if (address == null) return Future.value();
    final running = _refreshing;
    if (running != null && _refreshingFor == address) return running;
    late final Future<void> started;
    started = _refresh(address).whenComplete(() {
      // An older refresh finishing leaves a newer one in place.
      if (identical(_refreshing, started)) {
        _refreshing = null;
        _refreshingFor = null;
      }
    });
    _refreshingFor = address;
    return _refreshing = started;
  }

  Future<void> _refresh(String address) async {
    emit(state.copyWith(refreshing: true, refreshFailed: false));
    try {
      final names = await _repository.refresh(address);
      if (isClosed || state.address != address) return;
      emit(state.copyWith(
        status: ArNSNamesStatus.loaded,
        names: names,
        refreshing: false,
      ));
    } catch (e) {
      logger.w('Could not read the names from ArNS: $e');
      if (isClosed || state.address != address) return;
      emit(state.copyWith(
        status: state.names.isEmpty && state.status != ArNSNamesStatus.loaded
            ? ArNSNamesStatus.failed
            : state.status,
        refreshing: false,
        refreshFailed: true,
      ));
    }
  }

  /// A publication version just published, known before GraphQL has it.
  void rememberPublication(String txId, ArNSPublicationItem publication) =>
      _repository.rememberPublication(txId, publication);

  /// One name read again after [made], the changes just made to it.
  Future<ArNSManagedName?> refreshName(
    String name, {
    List<ArNSRecordChange> made = const [],
  }) async {
    final current = state.nameOf(name);
    if (current == null) return null;
    try {
      final updated = await _repository.refreshRecords(current, made: made);
      if (isClosed) return updated;
      emit(state.copyWith(names: [
        for (final n in state.names) n.name == name ? updated : n,
      ]));
      return updated;
    } catch (e) {
      logger.w('Could not read $name again: $e');
      return null;
    }
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
