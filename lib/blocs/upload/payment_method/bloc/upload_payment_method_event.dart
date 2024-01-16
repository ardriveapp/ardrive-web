part of 'upload_payment_method_bloc.dart';

sealed class UploadPaymentMethodEvent extends Equatable {
  const UploadPaymentMethodEvent();

  @override
  List<Object> get props => [];
}

final class PrepareUploadPaymentMethod extends UploadPaymentMethodEvent {
  final UploadParams params;

  const PrepareUploadPaymentMethod({
    required this.params,
  });

  @override
  List<Object> get props => [];
}

final class ChangeUploadPaymentMethod extends UploadPaymentMethodEvent {
  final UploadMethod paymentMethod;

  const ChangeUploadPaymentMethod({
    required this.paymentMethod,
  });

  @override
  List<Object> get props => [];
}
