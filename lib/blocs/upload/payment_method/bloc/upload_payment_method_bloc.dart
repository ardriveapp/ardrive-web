import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/upload/models/payment_method_info.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/turbo/utils/utils.dart';
import 'package:ardrive/utils/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'upload_payment_method_event.dart';
part 'upload_payment_method_state.dart';

class UploadPaymentMethodBloc
    extends Bloc<UploadPaymentMethodEvent, UploadPaymentMethodState> {
  final ArDriveUploadPreparationManager _arDriveUploadManager;
  final ArDriveAuth _auth;
  final ProfileCubit _profileCubit;
  UploadPaymentMethodBloc(
    this._profileCubit,
    this._arDriveUploadManager,
    this._auth,
  ) : super(UploadPaymentMethodInitial()) {
    on<UploadPaymentMethodEvent>((event, emit) async {
      if (event is PrepareUploadPaymentMethod) {
        emit(
          UploadPaymentMethodLoading(
            isArConnect: await _profileCubit.isCurrentProfileArConnect(),
          ),
        );

        final profile = _profileCubit.state as ProfileLoggedIn;

        // TODO: refactor to a new component that verifies it
        if (await _profileCubit.checkIfWalletMismatch()) {
          emit(UploadWalletMismatch());
          return;
        }

        logger.d('Upload preparation started.');

        try {
          final uploadPreparation = await _arDriveUploadManager.prepareUpload(
            params: event.params,
          );

          final paymentInfo = uploadPreparation.uploadPaymentInfo;

          if (await _profileCubit.checkIfWalletMismatch()) {
            emit(UploadWalletMismatch());
            return;
          }
          bool isTurboZeroBalance =
              uploadPreparation.uploadPaymentInfo.turboBalance == BigInt.zero;

          logger.d(
            'Upload preparation finished\n'
            'UploadMethod: ${uploadPreparation.uploadPaymentInfo.defaultPaymentMethod}\n'
            'UploadPlan For AR: ${uploadPreparation.uploadPaymentInfo.arCostEstimate.toString()}\n'
            'UploadPlan For Turbo: ${uploadPreparation.uploadPlansPreparation.uploadPlanForTurbo.toString()}\n'
            'Turbo Balance: ${uploadPreparation.uploadPaymentInfo.turboBalance}\n'
            'AR Balance: ${_auth.currentUser.walletBalance}\n'
            'Is Turbo Upload Possible: ${paymentInfo.isUploadEligibleToTurbo}\n'
            'Is Zero Balance: $isTurboZeroBalance\n',
          );

          final literalTurboBalance = convertWinstonToLiteralString(
              uploadPreparation.uploadPaymentInfo.turboBalance);
          final literalARBalance =
              convertWinstonToLiteralString(_auth.currentUser.walletBalance);

          bool sufficientBalanceToPayWithAR =
              profile.walletBalance >= paymentInfo.arCostEstimate.totalCost;
          bool sufficientBalanceToPayWithTurbo =
              paymentInfo.turboCostEstimate.totalCost <=
                  uploadPreparation.uploadPaymentInfo.turboBalance;

          emit(
            UploadPaymentMethodLoaded(
              params: event.params,
              paymentMethodInfo: UploadPaymentMethodInfo(
                totalSize: uploadPreparation.uploadPaymentInfo.totalSize,
                uploadPlanForAR:
                    uploadPreparation.uploadPlansPreparation.uploadPlanForAr,
                uploadPlanForTurbo:
                    uploadPreparation.uploadPlansPreparation.uploadPlanForTurbo,
                arBalance: literalARBalance,
                costEstimateAr:
                    uploadPreparation.uploadPaymentInfo.arCostEstimate,
                costEstimateTurbo:
                    uploadPreparation.uploadPaymentInfo.turboCostEstimate,
                hasNoTurboBalance: isTurboZeroBalance,
                isFreeThanksToTurbo: uploadPreparation
                    .uploadPaymentInfo.isFreeUploadPossibleUsingTurbo,
                isTurboUploadPossible: paymentInfo.isUploadEligibleToTurbo,
                sufficentCreditsBalance: sufficientBalanceToPayWithTurbo,
                sufficientArBalance: sufficientBalanceToPayWithAR,
                turboCredits: literalTurboBalance,
                uploadMethod: paymentInfo.defaultPaymentMethod,
              ),
            ),
          );
        } catch (e) {
          logger.e('Upload preparation failed.', e);
        }
      } else if (event is ChangeUploadPaymentMethod) {
        final paymentMethodLoaded = (state as UploadPaymentMethodLoaded);

        emit(
          paymentMethodLoaded.copyWith(
            paymentMethodInfo: paymentMethodLoaded.paymentMethodInfo.copyWith(
              uploadMethod: event.paymentMethod,
            ),
          ),
        );
      }
    });
  }
}
