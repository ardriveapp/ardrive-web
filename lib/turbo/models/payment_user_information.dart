import 'package:equatable/equatable.dart';

abstract class PaymentUserInformation extends Equatable {
  final String? email;
  final String name;
  final String country;

  const PaymentUserInformation({
    this.email,
    required this.name,
    required this.country,
  });

  @override
  List<Object?> get props => [
        email,
      ];
}

class PaymentUserInformationFromUSA extends PaymentUserInformation {
  const PaymentUserInformationFromUSA({
    String? email,
    required String name,
  }) : super(
          email: email,
          name: name,
          country: 'United States',
        );

  @override
  List<Object?> get props => [
        ...super.props,
      ];
}
