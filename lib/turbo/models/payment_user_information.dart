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

  factory PaymentUserInformation.create({
    String? email,
    required String name,
    required String country,
  }) {
    return _PaymentUserInformation(
      email: email,
      name: name,
      country: country,
    );
  }

  PaymentUserInformation copyWith({
    String? email,
    String? name,
    String? country,
  });
}

class _PaymentUserInformation extends PaymentUserInformation {
  const _PaymentUserInformation({
    String? email,
    required String country,
    required String name,
  }) : super(
          email: email,
          name: name,
          country: country,
        );

  @override
  List<Object?> get props => [
        email,
        name,
        country,
      ];

  @override
  _PaymentUserInformation copyWith({
    String? email,
    String? name,
    String? country,
  }) {
    return _PaymentUserInformation(
      email: email ?? this.email,
      name: name ?? this.name,
      country: country ?? this.country,
    );
  }
}
