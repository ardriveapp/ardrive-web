import 'package:equatable/equatable.dart';

abstract class PaymentUserInformation extends Equatable {
  final String name;
  final String cardNumber;
  final String expirationDate;
  final String cvv;
  final String country;
  final String postalCode;
  final String? email;

  const PaymentUserInformation({
    required this.name,
    required this.cardNumber,
    required this.expirationDate,
    required this.cvv,
    required this.country,
    required this.postalCode,
    this.email,
  });

  @override
  List<Object> get props => [
        name,
        cardNumber,
        expirationDate,
        cvv,
        country,
        postalCode,
      ];
}

class PaymentUserInformationFromUSA extends PaymentUserInformation {
  final String state;
  final String addressLine1;
  final String addressLine2;

  const PaymentUserInformationFromUSA({
    required this.addressLine1,
    required this.addressLine2,
    required this.state,
    required String name,
    required String cardNumber,
    required String expirationDate,
    required String cvv,
    required String postalCode,
  }) : super(
          name: name,
          cardNumber: cardNumber,
          expirationDate: expirationDate,
          cvv: cvv,
          postalCode: postalCode,
          country: 'US',
        );

  @override
  List<Object> get props => [
        ...super.props,
        state,
        addressLine1,
        addressLine2,
      ];
}
