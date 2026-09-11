import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/blocs/upload/models/source_wallet_credits.dart';
import 'package:ardrive/core/upload/uploader.dart';
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

  late UploadPreparation uploadPreparation;

  UploadPaymentMethodBloc(
    this._profileCubit,
    this._arDriveUploadManager,
    this._auth,
    this._paymentService,
  ) : super(UploadPaymentMethodInitial()) {
    on<UploadPaymentMethodEvent>(_onUploadPaymentMethodEvent);
  }

  Future<void> _onUploadPaymentMethodEvent(UploadPaymentMethodEvent event,
      Emitter<UploadPaymentMethodState> emit) async {
    if (event is PrepareUploadPaymentMethod) {
      await _handlePrepareUploadPaymentMethod(event, emit);
    } else if (event is ChangeUploadPaymentMethod) {
      _handleChangeUploadPaymentMethod(event, emit);
    } else if (event is LookUpSourceWalletCredits) {
      await _handleLookUpSourceWalletCredits(emit);
    }
  }

  Future<void> _handlePrepareUploadPaymentMethod(
      PrepareUploadPaymentMethod event,
      Emitter<UploadPaymentMethodState> emit) async {
    emit(UploadPaymentMethodLoading(
        isArConnect: await _profileCubit.isCurrentProfileArConnect()));

    if (await _profileCubit.checkIfWalletMismatch()) {
      emit(UploadPaymentMethodWalletMismatch());
      return;
    }

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

      // Asked only when this sheet is about to say no, and only for somebody
      // who signed in with another chain's wallet. Everyone else, which is most
      // people, pays for none of it.
      if (!_canUploadWithMethod(UploadMethod.turbo) &&
          walletTypeOfSourceAddress(_auth.currentUser.sourceWalletAddress) !=
              null) {
        add(const LookUpSourceWalletCredits());
      }
    } catch (e) {
      logger.e('Upload preparation failed.', e);
      emit(UploadPaymentMethodError());
    }
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
      Emitter<UploadPaymentMethodState> emit) async {
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
    // could have topped up, or switched to AR, or closed it. A late answer is
    // only worth adding to the state it was asked about.
    final current = state;

    if (current is! UploadPaymentMethodLoaded) {
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
