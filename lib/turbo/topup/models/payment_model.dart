import 'package:json_annotation/json_annotation.dart';

part 'payment_model.g.dart';

@JsonSerializable()
class PaymentModel {
  // payment session
  final PaymentSession paymentSession;

  // top up quote
  final TopUpQuote topUpQuote;

  PaymentModel({
    required this.paymentSession,
    required this.topUpQuote,
  });

  factory PaymentModel.fromJson(Map<String, dynamic> json) =>
      _$PaymentModelFromJson(json);
}

@JsonSerializable()
class PaymentSession {
  final String id;
  @JsonKey(name: 'client_secret')
  final String clientSecret;
  // final String url;

  PaymentSession({
    required this.id,
    required this.clientSecret,
    // required this.url,
  });

  factory PaymentSession.fromJson(Map<String, dynamic> json) =>
      _$PaymentSessionFromJson(json);
  Map<String, dynamic> toJson() => _$PaymentSessionToJson(this);
}

@JsonSerializable()
class TopUpQuote {
  @JsonKey(name: 'topUpQuoteId')
  final String quoteId;
  final String destinationAddress;
  final String destinationAddressType;
  final int paymentAmount;
  final String currencyType;
  final String winstonCreditAmount;
  final String quoteExpirationDate;
  final String paymentProvider;

  TopUpQuote({
    required this.quoteId,
    required this.destinationAddress,
    required this.destinationAddressType,
    required this.paymentAmount,
    required this.currencyType,
    required this.winstonCreditAmount,
    required this.quoteExpirationDate,
    required this.paymentProvider,
  });

  factory TopUpQuote.fromJson(Map<String, dynamic> json) =>
      _$TopUpQuoteFromJson(json);
  Map<String, dynamic> toJson() => _$TopUpQuoteToJson(this);
}
