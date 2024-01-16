part of 'upload_payment_method_bloc.dart';

sealed class UploadPaymentMethodState extends Equatable {
  const UploadPaymentMethodState();

  @override
  List<Object> get props => [];
}

final class UploadPaymentMethodInitial extends UploadPaymentMethodState {}

final class UploadPaymentMethodLoading extends UploadPaymentMethodState {
  final bool isArConnect;

  const UploadPaymentMethodLoading({
    this.isArConnect = false,
  });
}

final class UploadPaymentMethodLoaded extends UploadPaymentMethodState {
  final UploadParams params;
  final UploadPaymentMethodInfo paymentMethodInfo;

  const UploadPaymentMethodLoaded({
    required this.params,
    required this.paymentMethodInfo,
  });

  @override
  List<Object> get props => [params, paymentMethodInfo];

  UploadPaymentMethodLoaded copyWith({
    UploadParams? params,
    UploadPaymentMethodInfo? paymentMethodInfo,
  }) {
    return UploadPaymentMethodLoaded(
      params: params ?? this.params,
      paymentMethodInfo: paymentMethodInfo ?? this.paymentMethodInfo,
    );
  }
}

final class UploadWalletMismatch extends UploadPaymentMethodState {}
