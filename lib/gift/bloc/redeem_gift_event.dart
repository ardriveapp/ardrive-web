part of 'redeem_gift_bloc.dart';

sealed class RedeemGiftEvent extends Equatable {
  const RedeemGiftEvent();

  @override
  List<Object> get props => [];
}

class RedeemGiftLoad extends RedeemGiftEvent {
  const RedeemGiftLoad({
    required this.giftCode,
    required this.email,
  });

  final String giftCode;
  final String email;

  @override
  List<Object> get props => [giftCode];
}
