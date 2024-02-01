import 'package:ardrive/gift/bloc/redeem_gift_bloc.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../blocs/turbo_balance_cubit_test.dart';
import '../../test_utils/fake_user.dart';
import '../../test_utils/utils.dart';

void main() {
  late MockPaymentService mockPaymentService;
  late MockArDriveAuth mockArDriveAuth;
  late RedeemGiftBloc redeemGiftBloc;

  setUp(() {
    mockPaymentService = MockPaymentService();
    mockArDriveAuth = MockArDriveAuth();
    redeemGiftBloc = RedeemGiftBloc(
      paymentService: mockPaymentService,
      auth: mockArDriveAuth,
    );
  });

  tearDown(() {
    redeemGiftBloc.close();
  });

  test('initial state is RedeemGiftInitial', () {
    expect(redeemGiftBloc.state, RedeemGiftInitial());
  });

  blocTest<RedeemGiftBloc, RedeemGiftState>(
    'emits [RedeemGiftLoading, RedeemGiftSuccess] when RedeemGiftLoad succeeds',
    build: () => redeemGiftBloc,
    act: (bloc) {
      when(() => mockArDriveAuth.currentUser).thenReturn(fakeUserJson);
      when(() => mockPaymentService.redeemGift(
            email: 'test@example.com',
            giftCode: '123456',
            destinationAddress: fakeUserJson.walletAddress,
          )).thenAnswer((_) async {
        return 100;
      });

      bloc.add(
          const RedeemGiftLoad(email: 'test@example.com', giftCode: '123456'));
    },
    expect: () => [RedeemGiftLoading(), RedeemGiftSuccess()],
  );

  blocTest<RedeemGiftBloc, RedeemGiftState>(
    'emits [RedeemGiftLoading, RedeemGiftFailure] when RedeemGiftLoad fails',
    build: () => redeemGiftBloc,
    act: (bloc) {
      when(() => mockArDriveAuth.currentUser).thenReturn(fakeUserJson);
      when(() => mockPaymentService.redeemGift(
            email: 'test@example.com',
            giftCode: '123456',
            destinationAddress: fakeUserJson.walletAddress,
          )).thenThrow(Exception('Failed'));

      bloc.add(
          const RedeemGiftLoad(email: 'test@example.com', giftCode: '123456'));
    },
    expect: () => [RedeemGiftLoading(), RedeemGiftFailure()],
  );

  blocTest<RedeemGiftBloc, RedeemGiftState>(
    'emits [RedeemGiftLoading, RedeemGiftAlreadyRedeemed] when RedeemGiftLoad fails with exception GiftAlreadyRedeemed',
    build: () => redeemGiftBloc,
    act: (bloc) {
      when(() => mockArDriveAuth.currentUser).thenReturn(fakeUserJson);
      when(() => mockPaymentService.redeemGift(
            email: 'test@example.com',
            giftCode: '123456',
            destinationAddress: fakeUserJson.walletAddress,
          )).thenThrow(GiftAlreadyRedeemed());

      bloc.add(
          const RedeemGiftLoad(email: 'test@example.com', giftCode: '123456'));
    },
    expect: () => [RedeemGiftLoading(), RedeemGiftAlreadyRedeemed()],
  );
}
