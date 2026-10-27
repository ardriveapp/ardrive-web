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

  /// It failed: Turbo refunds the credits within about 15 minutes.
  refunding,

  /// It expired, or still waits for an approval nothing here can give:
  /// Turbo's status read never carries the transaction to sign, so it
  /// expires and its credits come back within about 15 minutes.
  expired,
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
    this.statusTimeout = const Duration(seconds: 20),
    this.signingWindow = const Duration(minutes: 2),
  })  : _store = store,
        _client = client,
        _namesCubit = namesCubit,
        _clock = clock ?? DateTime.now,
        super(const ArNSResumeState()) {
    _subscription = walletCubit.stream.listen(_onWallet);
    _onWallet(walletCubit.state);
  }

  final ArNSPendingActionStore _store;
  final TurboArNSActionClient _client;
  final ArNSNamesCubit _namesCubit;
  final DateTime Function() _clock;
  late final StreamSubscription<ArNSWalletState> _subscription;

  /// Profiles checked this session: once per load is enough.
  final _checked = <String>{};

  /// Past this, an action still unresolved is dropped: Turbo refunds an
  /// abandoned one within 15 minutes, so it has long been settled.
  static const staleAfter = Duration(days: 1);

  /// An action this young awaiting signature may be another tab's, whose
  /// prompt is still open: read again once the window has passed rather
  /// than called expired now, which it may not be.
  final Duration signingWindow;

  /// How long one status read may take. One that stalls is asked again on
  /// the next load, and the actions after it are still read.
  final Duration statusTimeout;

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

  Future<void> _resolve(
    String profile,
    ArNSPendingAction action, {
    bool readAgain = true,
  }) async {
    final ArNSActionResult result;
    try {
      result = await _client
          .status(
            action.nonce,
            paymentUrl: action.paymentUrl,
          )
          .timeout(statusTimeout);
    } on ArNSActionRequestException catch (e) {
      logger.w('Could not read ArNS action ${action.nonce}: $e');
      // Turbo doesn't know it: nothing was charged for it.
      if (e.statusCode == 404 || _isStale(action)) {
        await _forget(profile, action);
      }
      return;
    } catch (e) {
      // Offline or timed out, most likely: asked again on the next load.
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
        if (readAgain && _mayBeSigning(action)) {
          _readAgainLater(profile, action);
          return;
        }
        // Its prompt went with the page and nothing here can sign it: it
        // expires and is refunded, as below.
        await _forget(profile, action);
        _notify(ArNSResumeOutcome.expired, action);
      case ArNSActionInProgress(:final status):
        // Turbo's status read leaves out the transaction of an action
        // awaiting signature: it can only expire and be refunded.
        if (readAgain &&
            status == 'awaiting-signature' &&
            _mayBeSigning(action)) {
          _readAgainLater(profile, action);
          return;
        }
        if (status == 'awaiting-signature' || status.contains('expired')) {
          await _forget(profile, action);
          _notify(ArNSResumeOutcome.expired, action);
        } else if (_isStale(action)) {
          logger.w('Dropping ArNS action ${action.nonce}, still $status');
          await _forget(profile, action);
        }
    }
  }

  bool _mayBeSigning(ArNSPendingAction action) =>
      _clock().difference(action.createdAt) < signingWindow;

  /// Once the window has passed: signed by then, it reads as done; still
  /// unsigned, as expired.
  void _readAgainLater(String profile, ArNSPendingAction action) {
    final wait = signingWindow - _clock().difference(action.createdAt);
    unawaited(Future<void>.delayed(wait, () async {
      if (!isClosed) await _resolve(profile, action, readAgain: false);
    }));
  }

  bool _isStale(ArNSPendingAction action) =>
      _clock().difference(action.createdAt) > staleAfter;

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
