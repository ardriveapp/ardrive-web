import 'package:equatable/equatable.dart';

abstract class PaymentUserInformation extends Equatable {
  final String? email;
  final bool userAcceptedToReceiveEmails;
  final String name;
  final String country;

  const PaymentUserInformation({
    this.email,
    required this.name,
    required this.country,
    required this.userAcceptedToReceiveEmails,
  });

  factory PaymentUserInformation.create({
    String? email,
    required String name,
    required String country,
    required bool userAcceptedToReceiveEmails,
  }) {
    return _PaymentUserInformation(
      email: email,
      name: name,
      country: country,
      userAcceptedToReceiveEmails: userAcceptedToReceiveEmails,
    );
  }

  PaymentUserInformation copyWith({
    String? email,
    String? name,
    String? country,
    bool? userAcceptedToReceiveEmails,
  });
}

class _PaymentUserInformation extends PaymentUserInformation {
  const _PaymentUserInformation({
    String? email,
    required String country,
    required String name,
    required bool userAcceptedToReceiveEmails,
  }) : super(
          email: email,
          name: name,
          country: country,
          userAcceptedToReceiveEmails: userAcceptedToReceiveEmails,
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
    bool? userAcceptedToReceiveEmails,
  }) {
    return _PaymentUserInformation(
      email: email ?? this.email,
      name: name ?? this.name,
      country: country ?? this.country,
      userAcceptedToReceiveEmails:
          userAcceptedToReceiveEmails ?? this.userAcceptedToReceiveEmails,
    );
  }

  @override
  String toString() {
    return 'PaymentUserInformation(email: $email, name: $name, country: $country, userAcceptedToReceiveEmails: $userAcceptedToReceiveEmails)';
  }
}
