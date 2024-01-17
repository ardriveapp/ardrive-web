part of 'redeem_gift_bloc.dart';

sealed class RedeemGiftState extends Equatable {
  const RedeemGiftState();

  @override
  List<Object> get props => [];
}

final class RedeemGiftInitial extends RedeemGiftState {}

final class RedeemGiftLoading extends RedeemGiftState {}

final class RedeemGiftSuccess extends RedeemGiftState {}

final class RedeemGiftFailure extends RedeemGiftState {}

final class RedeemGiftAlreadyRedeemed extends RedeemGiftState {}
