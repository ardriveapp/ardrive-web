import 'package:equatable/equatable.dart';
import 'package:json_annotation/json_annotation.dart';

part 'payment_model.g.dart';

@JsonSerializable()
class PaymentModel {
  // payment session
  final PaymentSession paymentSession;

  // top up quote
  final TopUpQuote topUpQuote;

  final List<Adjustment> adjustments;

  PaymentModel({
    required this.paymentSession,
    required this.topUpQuote,
    required this.adjustments,
  });

  factory PaymentModel.fromJson(Map<String, dynamic> json) =>
      _$PaymentModelFromJson(json);
}

@JsonSerializable()
class PaymentSession {
  final String id;
  @JsonKey(name: 'client_secret')
  final String clientSecret;

  PaymentSession({
    required this.id,
    required this.clientSecret,
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
  final int? quotedPaymentAmount;
  final String currencyType;
  final String winstonCreditAmount;
  final String quoteExpirationDate;
  final String paymentProvider;

  TopUpQuote({
    required this.quoteId,
    required this.destinationAddress,
    required this.destinationAddressType,
    required this.paymentAmount,
    required this.quotedPaymentAmount,
    required this.currencyType,
    required this.winstonCreditAmount,
    required this.quoteExpirationDate,
    required this.paymentProvider,
  });

  factory TopUpQuote.fromJson(Map<String, dynamic> json) =>
      _$TopUpQuoteFromJson(json);
  Map<String, dynamic> toJson() => _$TopUpQuoteToJson(this);
}

@JsonSerializable()
class Adjustment extends Equatable {
  final String name;
  final String description;
  final double operatorMagnitude;
  final String operator;
  final int adjustmentAmount;

  const Adjustment({
    required this.name,
    required this.description,
    required this.operatorMagnitude,
    required this.operator,
    required this.adjustmentAmount,
  });

  String get humanReadableDiscountPercentage {
    return discountPercentage.toStringAsFixed(0);
  }

  double get promoDiscountFactor {
    final factor = discountPercentage / 100;
    return factor;
  }

  double get discountPercentage {
    final discountPercentage = 100 - (operatorMagnitude * 100);
    return discountPercentage;
  }

  factory Adjustment.fromJson(Map<String, dynamic> json) =>
      _$AdjustmentFromJson(json);
  Map<String, dynamic> toJson() => _$AdjustmentToJson(this);

  @override
  String toString() {
    return 'Adjustment{name: $name, description: $description, operatorMagnitude: $operatorMagnitude, operator: $operator, adjustmentAmount: $adjustmentAmount}';
  }

  @override
  List<Object> get props => [
        name,
        description,
        operatorMagnitude,
        operator,
        adjustmentAmount,
      ];
}
