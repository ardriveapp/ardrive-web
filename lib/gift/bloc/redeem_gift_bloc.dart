import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/utils/logger/logger.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'redeem_gift_event.dart';
part 'redeem_gift_state.dart';

class RedeemGiftBloc extends Bloc<RedeemGiftEvent, RedeemGiftState> {
  final PaymentService _paymentService;
  final ArDriveAuth _auth;

  RedeemGiftBloc({
    required PaymentService paymentService,
    required ArDriveAuth auth,
  })  : _auth = auth,
        _paymentService = paymentService,
        super(RedeemGiftInitial()) {
    on<RedeemGiftEvent>((event, emit) async {
      if (event is RedeemGiftLoad) {
        await _handleRedeemGiftLoad(emit, event);
      }
    });
  }

  Future<void> _handleRedeemGiftLoad(
      Emitter<RedeemGiftState> emit, RedeemGiftLoad event) async {
    try {
      logger.d('RedeemGiftLoad');

      emit(RedeemGiftLoading());

      await _paymentService.redeemGift(
        email: event.email,
        giftCode: event.giftCode,
        destinationAddress: _auth.currentUser.walletAddress,
      );

      logger.d('RedeemGiftSuccess');

      emit(RedeemGiftSuccess());
    } catch (e) {
      if (e is GiftAlreadyRedeemed) {
        logger.e('RedeemGiftAlreadyRedeemed', e);
        emit(RedeemGiftAlreadyRedeemed());
        return;
      }
      logger.e('RedeemGiftFailure', e);
      emit(RedeemGiftFailure());
    }
  }
}
