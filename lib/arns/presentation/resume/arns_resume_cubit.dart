import 'dart:async';

import 'package:ardrive/arns/data/arns_pending_action_store.dart';
import 'package:ardrive/arns/data/turbo_arns_action_client.dart';
import 'package:ardrive/arns/domain/arns_action.dart';
import 'package:ardrive/arns/presentation/arns_wallet/arns_wallet_cubit.dart';
import 'package:ardrive/arns/presentation/names/arns_names_cubit.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// What the app says about a change left unfinished by a reload.
enum ArNSResumeOutcome {
  /// It went through: "Name saved".
  saved,

  /// It expired or failed, or can't be finished from here: Turbo refunds the
  /// credits within about 15 minutes.
  refunding,

  /// Turbo still waits for the ArNS wallet's approval of its transaction,
  /// which can be given now: "Finish".
  canFinish,
}

class ArNSResumeNotice extends Equatable {
  const ArNSResumeNotice({
    required this.outcome,
    required this.name,
    required this.nonce,
  });

  final ArNSResumeOutcome outcome;

  /// The literal name the change was for.
  final String name;
  final String nonce;

  @override
  List<Object?> get props => [outcome, name, nonce];
}

class ArNSResumeState extends Equatable {
  const ArNSResumeState({this.notice, this.serial = 0});

  /// The latest thing to tell the user, or null before there is any.
  final ArNSResumeNotice? notice;

  /// Counts notices, so the same one twice is still news.
  final int serial;

  @override
  List<Object?> get props => [notice, serial];
}

/// After a reload, reads what became of each Turbo ArNS action the signed-in
/// profile left unfinished, and says so once (docs/NAMES.md, "Writes", step
/// 6). Never creates an action: that would charge again.
class ArNSResumeCubit extends Cubit<ArNSResumeState> {
  ArNSResumeCubit({
    required ArNSPendingActionStore store,
    required TurboArNSActionClient client,
    required ArNSWalletCubit walletCubit,
    required ArNSNamesCubit namesCubit,
    DateTime Function()? clock,
  })  : _store = store,
        _client = client,
        _walletCubit = walletCubit,
        _namesCubit = namesCubit,
        _clock = clock ?? DateTime.now,
        super(const ArNSResumeState()) {
    _subscription = walletCubit.stream.listen(_onWallet);
    _onWallet(walletCubit.state);
  }

  final ArNSPendingActionStore _store;
  final TurboArNSActionClient _client;
  final ArNSWalletCubit _walletCubit;
  final ArNSNamesCubit _namesCubit;
  final DateTime Function() _clock;
  late final StreamSubscription<ArNSWalletState> _subscription;

  /// Profiles checked this session: once per load is enough.
  final _checked = <String>{};

  /// Actions that can be finished now, by nonce.
  final _awaiting =
      <String, (ArNSPendingAction, ArNSActionAwaitingSignature)>{};

  /// Past this, an action still unresolved is dropped: Turbo refunds an
  /// abandoned one within 15 minutes, so it has long been settled.
  static const staleAfter = Duration(days: 1);

  void _onWallet(ArNSWalletState wallet) {
    final profile = wallet.profileAddress;
    if (!wallet.enabled || profile == null || !_checked.add(profile)) return;
    unawaited(check(profile));
  }

  /// Reads each of [profile]'s unfinished actions once and reports it.
  Future<void> check(String profile) async {
    final List<ArNSPendingAction> pending;
    try {
      pending = await _store.pending(profile);
    } catch (e) {
      logger.w('Could not read the pending ArNS actions: $e');
      return;
    }
    for (final action in pending) {
      if (isClosed) return;
      await _resolve(profile, action);
    }
  }

  Future<void> _resolve(String profile, ArNSPendingAction action) async {
    final ArNSActionResult result;
    try {
      result = await _client.status(
        action.nonce,
        paymentUrl: action.paymentUrl,
      );
    } on ArNSActionRequestException catch (e) {
      logger.w('Could not read ArNS action ${action.nonce}: $e');
      // Turbo doesn't know it: nothing was charged for it.
      if (e.statusCode == 404 || _isStale(action)) {
        await _forget(profile, action);
      }
      return;
    } catch (e) {
      // Offline, most likely: asked again on the next load.
      logger.w('Could not read ArNS action ${action.nonce}: $e');
      if (_isStale(action)) await _forget(profile, action);
      return;
    }

    switch (result) {
      case ArNSActionCompleted():
        await _forget(profile, action);
        unawaited(_namesCubit.refresh());
        _notify(ArNSResumeOutcome.saved, action);
      case ArNSActionFailed():
        await _forget(profile, action);
        _notify(ArNSResumeOutcome.refunding, action);
      case ArNSActionAwaitingSignature():
        if (_isPast(result.expiresAt)) {
          await _forget(profile, action);
          _notify(ArNSResumeOutcome.refunding, action);
          return;
        }
        // Kept until it ends, so the next load says how.
        _awaiting[action.nonce] = (action, result);
        _notify(ArNSResumeOutcome.canFinish, action);
      case ArNSActionInProgress(:final status):
        if (status == 'awaiting-signature' || status.contains('expired')) {
          // Nothing here can sign it: it expires and is refunded.
          await _forget(profile, action);
          _notify(ArNSResumeOutcome.refunding, action);
        } else if (_isStale(action)) {
          logger.w('Dropping ArNS action ${action.nonce}, still $status');
          await _forget(profile, action);
        }
    }
  }

  /// Signs the transaction Turbo is waiting on with the ArNS wallet and
  /// submits it, through the same path as the name dialog. Re-posting the
  /// same signed bytes is safe; nothing is created.
  Future<void> finish(String nonce) async {
    final awaiting = _awaiting.remove(nonce);
    final profile = _walletCubit.state.profileAddress;
    if (awaiting == null || profile == null) return;
    final (action, result) = awaiting;

    var owner = _walletCubit.ownerSigner;
    if (owner == null) {
      try {
        await _walletCubit.reconnect();
      } catch (e) {
        logger.w('Could not reconnect the ArNS wallet: $e');
      }
      owner = _walletCubit.ownerSigner;
    }
    if (owner == null) {
      // Not approved: it expires unsigned and its credits come back. Kept,
      // so the next load says how it ended.
      _notify(ArNSResumeOutcome.refunding, action);
      return;
    }

    try {
      final signed = await owner.signTransaction(result.transaction);
      await _client.submitSigned(
        nonce,
        signed,
        paymentUrl: action.paymentUrl,
      );
      await _forget(profile, action);
      unawaited(_namesCubit.refresh());
      _notify(ArNSResumeOutcome.saved, action);
    } on ArNSActionExpiredException {
      await _forget(profile, action);
      _notify(ArNSResumeOutcome.refunding, action);
    } catch (e) {
      // Rejected, or the answer was lost: the next load reads the status.
      logger.w('Could not finish ArNS action $nonce: $e');
      _notify(ArNSResumeOutcome.refunding, action);
    }
  }

  bool _isStale(ArNSPendingAction action) =>
      _clock().difference(action.createdAt) > staleAfter;

  bool _isPast(String? timestamp) {
    final at = timestamp == null ? null : DateTime.tryParse(timestamp);
    return at != null && !_clock().isBefore(at);
  }

  Future<void> _forget(String profile, ArNSPendingAction action) async {
    try {
      await _store.remove(profile, action.nonce);
    } catch (e) {
      logger.w('Could not forget ArNS action ${action.nonce}: $e');
    }
  }

  void _notify(ArNSResumeOutcome outcome, ArNSPendingAction action) {
    if (isClosed) return;
    emit(ArNSResumeState(
      notice: ArNSResumeNotice(
        outcome: outcome,
        name: action.name,
        nonce: action.nonce,
      ),
      serial: state.serial + 1,
    ));
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
