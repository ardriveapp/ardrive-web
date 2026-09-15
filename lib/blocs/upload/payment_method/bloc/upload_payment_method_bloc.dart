import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/models/source_wallet_credits.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/turbo/services/credit_sharing_service.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'upload_payment_method_event.dart';
part 'upload_payment_method_state.dart';

class UploadPaymentMethodBloc
    extends Bloc<UploadPaymentMethodEvent, UploadPaymentMethodState> {
  final ArDriveUploadPreparationManager _arDriveUploadManager;
  final ArDriveAuth _auth;
  final ProfileCubit _profileCubit;
  final PaymentService _paymentService;

  /// Every upload sheet is given one, but only the web can sign a grant, and
  /// elsewhere it is a stub. See [canShareSourceWalletCredits].
  final CreditSharingService? _creditSharingService;

  late UploadPreparation uploadPreparation;

  /// What this sheet was prepared for, so it can be prepared again once a
  /// credit grant has changed the answer.
  UploadParams? _params;

  /// Which preparation is current. A credit lookup outlives the step that
  /// started it and events here run concurrently, so a late answer is only
  /// applied if no newer preparation has begun since.
  int _preparation = 0;

  UploadPaymentMethodBloc(
    this._profileCubit,
    this._arDriveUploadManager,
    this._auth,
    this._paymentService, [
    this._creditSharingService,
  ]) : super(UploadPaymentMethodInitial()) {
    on<UploadPaymentMethodEvent>(_onUploadPaymentMethodEvent);
  }

  /// Whether to offer the one-press share at all. It takes something to sign
  /// with, which only the web has, and a wallet that signs it: the web signs
  /// with a Solana wallet extension, so credits on an Ethereum sign-in wallet
  /// are left to Turbo. A button that can only fail is worse than none, and the
  /// notice still says how to share the credits by hand.
  bool get canShareSourceWalletCredits {
    final current = state;
    final credits = current is UploadPaymentMethodLoaded
        ? current.paymentMethodInfo.sourceWalletCredits
        : null;

    return credits?.walletType == WalletType.solana &&
        (_creditSharingService?.isSupported ?? false);
  }

  Future<void> _onUploadPaymentMethodEvent(UploadPaymentMethodEvent event,
      Emitter<UploadPaymentMethodState> emit) async {
    if (event is PrepareUploadPaymentMethod) {
      await _handlePrepareUploadPaymentMethod(event, emit);
    } else if (event is ChangeUploadPaymentMethod) {
      _handleChangeUploadPaymentMethod(event, emit);
    }
  }

  Future<void> _handlePrepareUploadPaymentMethod(
      PrepareUploadPaymentMethod event,
      Emitter<UploadPaymentMethodState> emit) async {
    final preparation = ++_preparation;

    emit(UploadPaymentMethodLoading(
        isArConnect: await _profileCubit.isCurrentProfileArConnect()));

    if (await _profileCubit.checkIfWalletMismatch()) {
      emit(UploadPaymentMethodWalletMismatch());
      return;
    }

    _params = event.params;

    try {
      uploadPreparation =
          await _arDriveUploadManager.prepareUpload(params: event.params);
      final paymentInfo = uploadPreparation.uploadPaymentInfo;

      final literalTurboBalance = convertWinstonToLiteralString(
          uploadPreparation.uploadPaymentInfo.turboBalance.balance);
      final literalARBalance =
          convertWinstonToLiteralString(_auth.currentUser.walletBalance);

      bool isTurboZeroBalance =
          uploadPreparation.uploadPaymentInfo.turboBalance.balance ==
              BigInt.zero;

      logger.d('Balance ${paymentInfo.turboBalance}');
      emit(
        UploadPaymentMethodLoaded(
          canUpload: _canUploadWithMethod(paymentInfo.defaultPaymentMethod),
          params:
              event.params.copyWith(paidBy: paymentInfo.turboBalance.paidBy),
          paymentMethodInfo: UploadPaymentMethodInfo(
            totalSize: uploadPreparation.uploadPaymentInfo.totalSize,
            uploadPlanForAR:
                uploadPreparation.uploadPlansPreparation.uploadPlanForAr,
            uploadPlanForTurbo:
                uploadPreparation.uploadPlansPreparation.uploadPlanForTurbo,
            arBalance: literalARBalance,
            costEstimateAr: uploadPreparation.uploadPaymentInfo.arCostEstimate,
            costEstimateTurbo:
                uploadPreparation.uploadPaymentInfo.turboCostEstimate,
            hasNoTurboBalance: isTurboZeroBalance,
            freeStatus: uploadPreparation.uploadPaymentInfo.freeStatus,
            isTurboUploadPossible: paymentInfo.isUploadEligibleToTurbo,
            sufficentCreditsBalance: _canUploadWithMethod(UploadMethod.turbo),
            sufficientArBalance: _canUploadWithMethod(UploadMethod.ar),
            turboCredits: literalTurboBalance,
            uploadMethod: paymentInfo.defaultPaymentMethod,
            paidBy: paymentInfo.turboBalance.paidBy,
          ),
        ),
      );
    } catch (e) {
      logger.e('Upload preparation failed.', e);
      emit(UploadPaymentMethodError());
      return;
    }

    // Outside the try on purpose: nothing below is preparation, so nothing
    // below may be reported as preparation failing. It sat inside once, and a
    // reader who closed the sheet mid-refresh was logged at error level as
    // "Upload preparation failed".
    //
    // Asked only when this sheet is about to say no, and only for somebody who
    // signed in with another chain's wallet. Everyone else, which is most
    // people, pays for none of it.
    //
    // Awaited here rather than raised as a second event. The sheet has already
    // painted - the state was emitted above - so waiting costs it nothing, and
    // an emit after the bloc closes is a no-op. The second event was the bug:
    // bloc closes its event controller before the state controller that
    // `isClosed` reports on, so for part of `close()` an `isClosed` check passes
    // and `add` throws anyway.
    if (!_canUploadWithMethod(UploadMethod.turbo) &&
        walletTypeOfSourceAddress(_auth.currentUser.sourceWalletAddress) !=
            null) {
      await _handleLookUpSourceWalletCredits(emit, preparation);
    }
  }

  /// Grants the derived Arweave wallet the right to spend the credits found on
  /// the wallet this reader signed in with.
  ///
  /// Returns whether it worked, because the control that called it has to
  /// decide what to say next: nothing here emits an error state. A refused
  /// signature is not a broken sheet, and the sheet still holds the
  /// instructions for doing it by hand.
  ///
  /// On success the whole preparation is run again rather than the state being
  /// patched. The grant changes what Turbo will report - `effectiveBalance`
  /// picks it up, `receivedApprovals` names the payer - and re-asking is how
  /// this sheet learns both without a second way of computing them.
  Future<bool> shareSourceWalletCredits() async {
    final service = _creditSharingService;
    final current = state;

    if (service == null || current is! UploadPaymentMethodLoaded) {
      return false;
    }

    final credits = current.paymentMethodInfo.sourceWalletCredits;
    final params = _params;

    if (credits == null || params == null || !canShareSourceWalletCredits) {
      return false;
    }

    try {
      await service.shareCreditsFromSignInWallet(
        sourceAddress: credits.sourceAddress,
        approvedAddress: credits.arweaveAddress,
        approvedWinc: credits.balance,
      );
    } catch (e) {
      logger
          .i('Sharing credits from the sign-in wallet did not go through: $e');

      return false;
    }

    // The grant went through; that is the operation, and the answer. Preparing
    // the sheet again is only how it learns the new balance, so a sheet closed
    // while the wallet was answering changes nothing about what to report.
    //
    // Caught rather than checked: bloc closes its event controller before the
    // state controller `isClosed` reads, so for part of `close()` that check
    // passes and `add` throws regardless.
    try {
      add(PrepareUploadPaymentMethod(params: params));
    } on StateError {
      logger.d('Sheet closed before it could be prepared again after a grant');
    }

    return true;
  }

  /// Looks for the credits on the wallet the user signed in with.
  ///
  /// Nothing found here is spendable and nothing about the upload changes. It
  /// only lets the sheet say where the money is instead of offering to sell more
  /// of it - see [SourceWalletCredits].
  ///
  /// Silent on every failure, and on a zero balance. An unanswered question is
  /// not a fact about somebody's money, and guessing at one turns an ordinary
  /// out-of-credits message into a puzzle.
  Future<void> _handleLookUpSourceWalletCredits(
      Emitter<UploadPaymentMethodState> emit, int preparation) async {
    final user = _auth.currentUser;
    final sourceAddress = user.sourceWalletAddress;
    final walletType = walletTypeOfSourceAddress(sourceAddress);

    if (sourceAddress == null || walletType == null) {
      return;
    }

    final BigInt balance;

    try {
      balance = await _paymentService.getBalanceForAddress(
        address: sourceAddress,
        walletType: walletType,
      );
    } catch (e) {
      logger.d('Could not check the sign-in wallet for credits: $e');
      return;
    }

    if (balance <= BigInt.zero) {
      return;
    }

    // The sheet may have moved on while the gateway was answering - the reader
    // could have topped up, or switched to AR, or closed it, or the sheet may
    // have been prepared again. A late answer is only worth adding to the
    // preparation it was asked about.
    final current = state;

    if (preparation != _preparation || current is! UploadPaymentMethodLoaded) {
      return;
    }

    emit(
      current.copyWith(
        paymentMethodInfo: current.paymentMethodInfo.copyWith(
          sourceWalletCredits: SourceWalletCredits(
            balance: balance,
            sourceAddress: sourceAddress,
            walletType: walletType,
            arweaveAddress: user.walletAddress,
          ),
        ),
      ),
    );
  }

  void _handleChangeUploadPaymentMethod(
      ChangeUploadPaymentMethod event, Emitter<UploadPaymentMethodState> emit) {
    if (state is UploadPaymentMethodLoaded) {
      final currentState = state as UploadPaymentMethodLoaded;
      final canUpload = _canUploadWithMethod(event.paymentMethod);
      emit(currentState.copyWith(
        paymentMethodInfo: currentState.paymentMethodInfo
            .copyWith(uploadMethod: event.paymentMethod),
        canUpload: canUpload,
      ));
    }
  }

  bool _canUploadWithMethod(UploadMethod method) {
    final profile = _profileCubit.state as ProfileLoggedIn;

    final paymentInfo = uploadPreparation.uploadPaymentInfo;

    bool sufficientBalanceToPayWithAR =
        profile.user.walletBalance >= paymentInfo.arCostEstimate.totalCost;
    bool sufficientBalanceToPayWithTurbo =
        paymentInfo.turboCostEstimate.totalCost <=
            uploadPreparation.uploadPaymentInfo.turboBalance.balance;

    if (method == UploadMethod.ar && sufficientBalanceToPayWithAR) {
      logger.d('Enabling button for AR payment method');
      return true;
    } else if (method == UploadMethod.turbo &&
        paymentInfo.isUploadEligibleToTurbo &&
        sufficientBalanceToPayWithTurbo) {
      logger.d('Enabling button for Turbo payment method');
      return true;
    } else if (paymentInfo.isFreeUploadPossibleUsingTurbo) {
      logger.d('Enabling button for free upload using Turbo');
      return true;
    } else {
      logger.d('Disabling button');
      return false;
    }
  }
}
