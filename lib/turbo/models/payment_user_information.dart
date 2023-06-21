import 'package:equatable/equatable.dart';

abstract class PaymentUserInformation extends Equatable {
  final String? email;

  const PaymentUserInformation({
    this.email,
  });

  @override
  List<Object?> get props => [
        email,
      ];
}

class PaymentUserInformationFromUSA extends PaymentUserInformation {
  const PaymentUserInformationFromUSA({
    String? email,
  }) : super(
          email: email,
        );

  @override
  List<Object?> get props => [
        ...super.props,
      ];
}
