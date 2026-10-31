import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/billing/data/billing_session_cache.dart';
import 'package:ardrive/billing/data/purchase.dart';
import 'package:ardrive/blocs/upload/models/source_wallet_credits.dart';
import 'package:ardrive/turbo/models/turbo_free_allowance.dart';
import 'package:ardrive/turbo/services/credit_sharing_service.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:ardrive_http/ardrive_http.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum LoadStatus { loading, ready, error }

/// Why the purchases did not load.
enum PurchasesFailure {
  /// The wallet's approval was refused (or could not be given).
  refused,
  failed,
}

/// Turbo Credits and what is shared, as the balance read gave them.
class BalanceView {
  const BalanceView({
    this.status = LoadStatus.loading,
    BigInt? own,
    BigInt? effective,
    this.given = const [],
    this.received = const [],
  })  : _own = own,
        _effective = effective;

  final LoadStatus status;
  final BigInt? _own;
  final BigInt? _effective;

  /// The account's own credits.
  BigInt get own => _own ?? BigInt.zero;

  /// Own plus what is left of credits shared with it.
  BigInt get effective => _effective ?? BigInt.zero;
  final List<TurboCreditApproval> given;
  final List<TurboCreditApproval> received;

  /// What others shared with the account that is left to spend.
  BigInt get shared {
    final extra = effective - own;
    return extra > BigInt.zero ? extra : BigInt.zero;
  }
}

/// The account's AR, read from the gateway. Unknown is not 0.
class ArView {
  const ArView({this.status = LoadStatus.loading, this.balance});

  final LoadStatus status;
  final BigInt? balance;
}

class PurchasesView {
  const PurchasesView({
    this.started = false,
    this.loading = false,
    this.loadingMore = false,
    this.rows = const [],
    this.hasMore = false,
    this.failure,
    this.savingCsv = false,
  });

  /// False until the purchases were asked for: a Wander account asks with a
  /// button, because the wallet shows an approval first.
  final bool started;
  final bool loading;
  final bool loadingMore;
  final List<Purchase> rows;
  final bool hasMore;
  final PurchasesFailure? failure;
  final bool savingCsv;

  PurchasesView copyWith({
    bool? started,
    bool? loading,
    bool? loadingMore,
    List<Purchase>? rows,
    bool? hasMore,
    PurchasesFailure? failure,
    bool clearFailure = false,
    bool? savingCsv,
  }) =>
      PurchasesView(
        started: started ?? this.started,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        rows: rows ?? this.rows,
        hasMore: hasMore ?? this.hasMore,
        failure: clearFailure ? null : failure ?? this.failure,
        savingCsv: savingCsv ?? this.savingCsv,
      );
}

class BillingState {
  const BillingState({
    this.balance = const BalanceView(),
    this.storageGiB,
    this.freeAllowance,
    this.ar = const ArView(),
    this.sourceCredits,
    this.sharing = false,
    this.shareFailed = false,
    this.purchases = const PurchasesView(),
    this.csvFailed = false,
    this.csvPartialRows,
  });

  final BalanceView balance;

  /// What the credits buy, in GiB; null when the price couldn't be read.
  final double? storageGiB;
  final TurboFreeAllowance? freeAllowance;
  final ArView ar;

  /// Credits on the Phantom, Solflare or MetaMask wallet that signed in.
  final SourceWalletCredits? sourceCredits;
  final bool sharing;
  final bool shareFailed;
  final PurchasesView purchases;
  final bool csvFailed;

  /// A CSV that saved this many purchases and left the older ones out.
  final int? csvPartialRows;

  BillingState copyWith({
    BalanceView? balance,
    double? storageGiB,
    bool clearStorage = false,
    TurboFreeAllowance? freeAllowance,
    ArView? ar,
    SourceWalletCredits? sourceCredits,
    bool clearSourceCredits = false,
    bool? sharing,
    bool? shareFailed,
    PurchasesView? purchases,
    bool? csvFailed,
    int? csvPartialRows,
    bool clearCsvPartial = false,
  }) =>
      BillingState(
        balance: balance ?? this.balance,
        storageGiB: clearStorage ? null : storageGiB ?? this.storageGiB,
        freeAllowance: freeAllowance ?? this.freeAllowance,
        ar: ar ?? this.ar,
        sourceCredits:
            clearSourceCredits ? null : sourceCredits ?? this.sourceCredits,
        sharing: sharing ?? this.sharing,
        shareFailed: shareFailed ?? this.shareFailed,
        purchases: purchases ?? this.purchases,
        csvFailed: csvFailed ?? this.csvFailed,
        csvPartialRows:
            clearCsvPartial ? null : csvPartialRows ?? this.csvPartialRows,
      );
}

/// Saves the CSV; the app's file saver on the page, a recorder in tests.
typedef SaveCsv = Future<void> Function(String name, Uint8List bytes);

/// The Billing page's reads and actions for [user].
class BillingCubit extends Cubit<BillingState> {
  BillingCubit({
    required this.user,
    required this.paymentService,
    required this.cache,
    required this.saveCsv,
    required this.readArBalance,
    this.creditSharing,
    this.asksBeforePurchases = false,
  }) : super(const BillingState());

  final User user;
  final PaymentService paymentService;
  final BillingSessionCache cache;
  final SaveCsv saveCsv;

  /// The AR balance of an address, from the gateway.
  final Future<BigInt> Function(String address) readArBalance;
  final CreditSharingService? creditSharing;

  /// Wander asks the person to approve a signature, so its purchases wait for
  /// a button. Everyone else's load by themselves.
  final bool asksBeforePurchases;

  static const _gib = 1024 * 1024 * 1024;

  /// A CSV reads at most this many pages (of 50) beyond what is loaded.
  static const maxCsvPages = 40;

  String get _address => user.walletAddress;

  Future<void> load() async {
    await Future.wait([
      loadBalance(),
      loadAr(),
      loadSourceCredits(),
      _restoreOrStartPurchases(),
    ]);
  }

  Future<void> _restoreOrStartPurchases() async {
    if (cache.hasPurchasesFor(_address)) {
      _safeEmit(state.copyWith(
        purchases: PurchasesView(
          started: true,
          rows: cache.purchasesFor(_address),
          hasMore: cache.hasMoreFor(_address),
        ),
      ));
      return;
    }
    if (!asksBeforePurchases) await loadPurchases();
  }

  void _safeEmit(BillingState next) {
    if (!isClosed) emit(next);
  }

  Future<void> loadBalance() async {
    _safeEmit(state.copyWith(
      balance: BalanceView(
        status: LoadStatus.loading,
        own: state.balance.own,
        effective: state.balance.effective,
        given: state.balance.given,
        received: state.balance.received,
      ),
    ));

    BalanceView view;
    try {
      final details = await paymentService.getBalanceDetails(
        wallet: user.wallet,
      );
      view = BalanceView(
        status: LoadStatus.ready,
        own: details.controlled,
        effective: details.effective,
        given: details.given,
        received: details.received,
      );
    } on TurboUserNotFound {
      // An account Turbo has never seen holds nothing: a fact, not a failure.
      view = const BalanceView(status: LoadStatus.ready);
    } catch (e) {
      logger.e('Billing: could not read the balance', e);
      _safeEmit(state.copyWith(
        balance: const BalanceView(status: LoadStatus.error),
      ));
      return;
    }
    _safeEmit(state.copyWith(balance: view));

    await Future.wait([_loadStorage(view.effective), _loadFreeAllowance()]);
  }

  Future<void> _loadStorage(BigInt credits) async {
    if (credits <= BigInt.zero) {
      _safeEmit(state.copyWith(clearStorage: true));
      return;
    }
    try {
      final perGiB = await paymentService.getPriceForBytes(byteSize: _gib);
      if (perGiB <= BigInt.zero) return;
      // Credits and the price are both in winston: scaled so BigInt keeps the
      // fraction of a GiB.
      final gib = (credits * BigInt.from(1000000) ~/ perGiB).toInt() / 1000000;
      _safeEmit(state.copyWith(storageGiB: gib));
    } catch (e) {
      logger.d('Billing: no storage estimate: $e');
      _safeEmit(state.copyWith(clearStorage: true));
    }
  }

  Future<void> _loadFreeAllowance() async {
    try {
      final allowance = await paymentService.getFreeAllowance(
        wallet: user.wallet,
      );
      _safeEmit(state.copyWith(freeAllowance: allowance));
    } catch (e) {
      logger.d('Billing: no free allowance: $e');
    }
  }

  Future<void> loadAr() async {
    try {
      final ar = await readArBalance(_address);
      _safeEmit(state.copyWith(
        ar: ArView(status: LoadStatus.ready, balance: ar),
      ));
    } catch (e) {
      logger.d('Billing: could not read the AR balance: $e');
      _safeEmit(state.copyWith(ar: const ArView(status: LoadStatus.error)));
    }
  }

  Future<void> loadSourceCredits() async {
    final source = user.sourceWalletAddress;
    final type = walletTypeOfSourceAddress(source);
    if (source == null || type == null) return;
    try {
      final balance = await paymentService.getBalanceForAddress(
        address: source,
        walletType: type,
      );
      _safeEmit(
        balance > BigInt.zero
            ? state.copyWith(
                sourceCredits: SourceWalletCredits(
                  balance: balance,
                  sourceAddress: source,
                  walletType: type,
                  arweaveAddress: _address,
                ),
              )
            : state.copyWith(clearSourceCredits: true),
      );
    } catch (e) {
      // An unanswered question is not a fact about somebody's money.
      logger.d('Billing: could not check the sign-in wallet: $e');
    }
  }

  /// Whether the one-press share is offered: Solana on the web only.
  bool get canShareSourceCredits =>
      state.sourceCredits?.walletType == WalletType.solana &&
      (creditSharing?.isSupported ?? false);

  Future<void> shareSourceCredits() async {
    final credits = state.sourceCredits;
    final service = creditSharing;
    if (credits == null || service == null || state.sharing) return;
    if (!canShareSourceCredits) return;

    _safeEmit(state.copyWith(sharing: true, shareFailed: false));
    try {
      await service.shareCreditsFromSignInWallet(
        sourceAddress: credits.sourceAddress,
        approvedAddress: credits.arweaveAddress,
        approvedWinc: credits.balance,
      );
    } catch (e) {
      logger.i('Billing: sharing from the sign-in wallet failed: $e');
      _safeEmit(state.copyWith(sharing: false, shareFailed: true));
      return;
    }
    _safeEmit(state.copyWith(sharing: false, clearSourceCredits: true));
    await Future.wait([loadBalance(), loadSourceCredits()]);
  }

  /// The first page, or the first page again after a failure or a top-up.
  Future<void> loadPurchases({bool refresh = false}) async {
    if (state.purchases.loading) return;
    if (refresh) cache.clear();

    _safeEmit(state.copyWith(
      csvFailed: false,
      purchases: state.purchases.copyWith(
        started: true,
        loading: true,
        clearFailure: true,
      ),
    ));

    try {
      final page = await paymentService.getPaymentHistoryPage(
        wallet: user.wallet,
      );
      final rows = page.payments.map(Purchase.fromJson).toList();
      cache.storePurchases(
        _address,
        purchases: rows,
        cursor: page.cursor,
        hasMore: page.hasMore,
      );
      _safeEmit(state.copyWith(
        purchases: PurchasesView(
          started: true,
          rows: rows,
          hasMore: page.hasMore,
        ),
      ));
    } catch (e) {
      if (e is ArDriveHTTPException && e.statusCode == 404) {
        // No account at Turbo yet: nothing bought, not a failure.
        cache.storePurchases(
          _address,
          purchases: const [],
          cursor: null,
          hasMore: false,
        );
        _safeEmit(
            state.copyWith(purchases: const PurchasesView(started: true)));
        return;
      }
      logger.w('Billing: could not load purchases: $e');
      _safeEmit(state.copyWith(
        purchases: PurchasesView(
          started: true,
          failure: _failureOf(e),
        ),
      ));
    }
  }

  PurchasesFailure _failureOf(Object e) =>
      e is TurboSignatureException && asksBeforePurchases
          ? PurchasesFailure.refused
          : PurchasesFailure.failed;

  Future<void> loadMore() async {
    final view = state.purchases;
    if (view.loading || view.loadingMore || !view.hasMore) return;

    _safeEmit(state.copyWith(
      purchases: view.copyWith(loadingMore: true, clearFailure: true),
    ));
    try {
      await _readNextPage();
      _safeEmit(state.copyWith(
        purchases: PurchasesView(
          started: true,
          rows: cache.purchasesFor(_address),
          hasMore: cache.hasMoreFor(_address),
        ),
      ));
    } catch (e) {
      logger.w('Billing: could not load more purchases: $e');
      _safeEmit(state.copyWith(
        purchases: view.copyWith(
          loadingMore: false,
          failure: PurchasesFailure.failed,
        ),
      ));
    }
  }

  Future<void> _readNextPage() async {
    final page = await paymentService.getPaymentHistoryPage(
      wallet: user.wallet,
      cursor: cache.cursorFor(_address),
    );
    cache.storePurchases(
      _address,
      purchases: [
        ...cache.purchasesFor(_address),
        ...page.payments.map(Purchase.fromJson),
      ],
      cursor: page.cursor,
      hasMore: page.hasMore,
    );
  }

  /// Saves every purchase as a CSV. A CSV that stopped at the last page
  /// loaded would read as the whole history, so the rest is read first.
  Future<void> downloadCsv() async {
    final view = state.purchases;
    if (view.savingCsv || view.rows.isEmpty) return;

    _safeEmit(state.copyWith(
      csvFailed: false,
      clearCsvPartial: true,
      purchases: view.copyWith(savingCsv: true),
    ));
    try {
      var pages = 0;
      while (cache.hasMoreFor(_address) && pages++ < maxCsvPages) {
        await _readNextPage();
      }
      final rows = cache.purchasesFor(_address);
      await saveCsv(
        'turbo-purchases.csv',
        Uint8List.fromList(utf8.encode(purchasesCsv(rows))),
      );
      // The loop is bounded: a history longer than that is saved as far as it
      // was read, and says so rather than passing for the whole of it.
      final partial = cache.hasMoreFor(_address);
      _safeEmit(state.copyWith(
        csvPartialRows: partial ? rows.length : null,
        purchases: PurchasesView(
          started: true,
          rows: rows,
          hasMore: partial,
        ),
      ));
    } catch (e) {
      logger.w('Billing: could not save the CSV: $e');
      _safeEmit(state.copyWith(
        csvFailed: true,
        purchases: state.purchases.copyWith(savingCsv: false),
      ));
    }
  }

  /// After a top-up: the balance, and the purchases when they were showing.
  Future<void> refreshAfterTopUp() async {
    final wasShowing = state.purchases.started;
    await Future.wait([
      loadBalance(),
      loadAr(),
      if (wasShowing) loadPurchases(refresh: true),
    ]);
  }
}
