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

final class PrepareUploadPaymentMethodWithDataItem
    extends UploadPaymentMethodEvent {
  final DataItem dataItem;

  const PrepareUploadPaymentMethodWithDataItem({
    required this.dataItem,
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

/// Asks whether the credits somebody is looking for are on the wallet they
/// signed in with.
///
/// Raised by [PrepareUploadPaymentMethod] itself, and only when that has already
/// refused: a second event rather than an await, because the first handler must
/// return before the payment sheet can paint. The answer arrives late and adds
/// an explanation to a sheet that is already on screen.
final class LookUpSourceWalletCredits extends UploadPaymentMethodEvent {
  const LookUpSourceWalletCredits();
}
