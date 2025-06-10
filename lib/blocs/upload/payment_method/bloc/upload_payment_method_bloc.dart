import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/core/upload/uploader.dart';
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

  late UploadPreparation uploadPreparation;

  UploadPaymentMethodBloc(
    this._profileCubit,
    this._arDriveUploadManager,
    this._auth,
  ) : super(UploadPaymentMethodInitial()) {
    on<UploadPaymentMethodEvent>(_onUploadPaymentMethodEvent);
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
          uploadPreparation.uploadPaymentInfo.turboBalance == BigInt.zero;

      emit(
        UploadPaymentMethodLoaded(
          canUpload: _canUploadWithMethod(paymentInfo.defaultPaymentMethod),
          params: event.params,
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
            isFreeThanksToTurbo: uploadPreparation
                .uploadPaymentInfo.isFreeUploadPossibleUsingTurbo,
            isTurboUploadPossible: paymentInfo.isUploadEligibleToTurbo,
            sufficentCreditsBalance: _canUploadWithMethod(UploadMethod.turbo),
            sufficientArBalance: _canUploadWithMethod(UploadMethod.ar),
            turboCredits: literalTurboBalance,
            uploadMethod: paymentInfo.defaultPaymentMethod,
          ),
        ),
      );
    } catch (e) {
      logger.e('Upload preparation failed.', e);
      emit(UploadPaymentMethodError());
    }
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
