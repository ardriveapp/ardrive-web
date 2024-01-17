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
  final bool canUpload;

  const UploadPaymentMethodLoaded({
    required this.params,
    required this.paymentMethodInfo,
    required this.canUpload,
  });

  @override
  List<Object> get props => [params, paymentMethodInfo];

  UploadPaymentMethodLoaded copyWith({
    UploadParams? params,
    UploadPaymentMethodInfo? paymentMethodInfo,
    bool? canUpload,
  }) {
    return UploadPaymentMethodLoaded(
      params: params ?? this.params,
      paymentMethodInfo: paymentMethodInfo ?? this.paymentMethodInfo,
      canUpload: canUpload ?? this.canUpload,
    );
  }
}

final class UploadPaymentMethodError extends UploadPaymentMethodState {
  @override
  List<Object> get props => [];
}

final class UploadPaymentMethodWalletMismatch extends UploadPaymentMethodState {
  @override
  List<Object> get props => [];
}
