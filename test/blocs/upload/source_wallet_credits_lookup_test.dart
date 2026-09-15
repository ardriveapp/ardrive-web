import 'dart:async';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/upload/models/upload_plan.dart';
import 'package:ardrive/blocs/upload/payment_method/bloc/upload_payment_method_bloc.dart';
import 'package:ardrive/core/upload/cost_calculator.dart';
import 'package:ardrive/core/upload/uploader.dart';
import 'package:ardrive/turbo/models/free_upload_status.dart';
import 'package:ardrive/turbo/services/credit_sharing_service.dart';
import 'package:ardrive/turbo/services/payment_service.dart';
import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:ardrive/user/user.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

class _MockUploadPreparationManager extends Mock
    implements ArDriveUploadPreparationManager {}

class _MockPaymentService extends Mock implements PaymentService {}

class _MockCreditSharingService extends Mock implements CreditSharingService {}

class _MockUser extends Mock implements User {}

class _FakeUploadParams extends Fake implements UploadParams {}

class _MockUploadParams extends Mock implements UploadParams {}

class _MockUploadPlan extends Mock implements UploadPlan {}

/// When the app asks whether somebody's credits are on their sign-in wallet.
///
/// The question costs a network round trip and answers nothing for the majority
/// of users, who signed in with Arweave and have no other wallet at all. So it
/// is asked narrowly: only when this sheet is about to refuse the upload, and
/// only for somebody who signed in with another chain's wallet.
void main() {
  late MockProfileCubit profileCubit;
  late MockArDriveAuth auth;
  late _MockUploadPreparationManager preparationManager;
  late _MockPaymentService paymentService;
  late _MockUser user;
  late _MockUploadParams params;
  late _MockCreditSharingService sharing;

  setUpAll(() {
    registerFallbackValue(_FakeUploadParams());
    registerFallbackValue(WalletType.solana);
    // `approvedWinc` is matched with `any()` in setUp, which runs before every
    // test - so without this every test here fails, including the ones that
    // never touch sharing.
    registerFallbackValue(BigInt.zero);
  });

  /// A preparation whose Turbo balance is [turboBalance] against a cost of 100.
  UploadPreparation preparationWith({required BigInt turboBalance}) {
    final cost = UploadCostEstimate(
      pstFee: BigInt.zero,
      totalCost: BigInt.from(100),
      totalSize: 1,
      usdUploadCost: 1,
    );

    return UploadPreparation(
      // Mocked: nothing here reads a plan. What is under test is which
      // question the sheet asks after it refuses, not what it would have
      // uploaded.
      uploadPlansPreparation: UploadPlansPreparation(
        uploadPlanForAr: _MockUploadPlan(),
        uploadPlanForTurbo: _MockUploadPlan(),
      ),
      uploadPaymentInfo: UploadPaymentInfo(
        defaultPaymentMethod: UploadMethod.turbo,
        isUploadEligibleToTurbo: true,
        isTurboAvailable: true,
        arCostEstimate: cost,
        turboCostEstimate: cost,
        freeStatus: FreeUploadStatus.notEligible,
        totalSize: 1,
        turboBalance: TurboBalanceInterface(
          balance: turboBalance,
          paidBy: const [],
        ),
      ),
    );
  }

  setUp(() {
    profileCubit = MockProfileCubit();
    auth = MockArDriveAuth();
    preparationManager = _MockUploadPreparationManager();
    paymentService = _MockPaymentService();
    user = _MockUser();
    params = _MockUploadParams();
    sharing = _MockCreditSharingService();
    when(() => sharing.isSupported).thenReturn(true);

    when(() => sharing.shareCreditsFromSignInWallet(
          sourceAddress: any(named: 'sourceAddress'),
          approvedAddress: any(named: 'approvedAddress'),
          approvedWinc: any(named: 'approvedWinc'),
        )).thenAnswer((_) async {});

    // The bloc threads approvals onto the params before it emits.
    when(() => params.copyWith(paidBy: any(named: 'paidBy')))
        .thenReturn(params);

    when(() => profileCubit.isCurrentProfileArConnect())
        .thenAnswer((_) async => false);
    when(() => profileCubit.checkIfWalletMismatch())
        .thenAnswer((_) async => false);
    when(() => profileCubit.state).thenReturn(
      ProfileLoggedIn(
        user: user,
        useTurbo: true,
      ),
    );

    when(() => user.walletAddress).thenReturn('arweave-address');
    when(() => user.walletBalance).thenReturn(BigInt.zero);
    when(() => auth.currentUser).thenReturn(user);

    when(() => paymentService.getBalanceForAddress(
          address: any(named: 'address'),
          walletType: any(named: 'walletType'),
        )).thenAnswer((_) async => BigInt.zero);
  });

  UploadPaymentMethodBloc build({
    required BigInt turboBalance,
    required String? sourceAddress,
  }) {
    when(() => user.sourceWalletAddress).thenReturn(sourceAddress);
    when(() => preparationManager.prepareUpload(params: any(named: 'params')))
        .thenAnswer((_) async => preparationWith(turboBalance: turboBalance));

    return UploadPaymentMethodBloc(
      profileCubit,
      preparationManager,
      auth,
      paymentService,
      sharing,
    );
  }

  Future<void> prepare(UploadPaymentMethodBloc bloc) async {
    bloc.add(PrepareUploadPaymentMethod(params: params));

    // The lookup is awaited after the sheet is emitted, so this takes more
    // than one turn.
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('is asked when the sheet refuses and there is a wallet to ask about',
      () async {
    final bloc = build(
      turboBalance: BigInt.zero,
      sourceAddress: '4WkBm7vD1qF9xYz',
    );
    addTearDown(bloc.close);

    await prepare(bloc);

    verify(() => paymentService.getBalanceForAddress(
          address: '4WkBm7vD1qF9xYz',
          walletType: WalletType.solana,
        )).called(1);
  });

  /// Most users. Nothing to ask about, and no round trip spent asking.
  test('is not asked of somebody who signed in with Arweave', () async {
    final bloc = build(turboBalance: BigInt.zero, sourceAddress: null);
    addTearDown(bloc.close);

    await prepare(bloc);

    verifyNever(() => paymentService.getBalanceForAddress(
          address: any(named: 'address'),
          walletType: any(named: 'walletType'),
        ));
  });

  /// The credits are already here and spendable. Where else they might also be
  /// is not a question anybody is asking.
  test('is not asked when the balance already covers the upload', () async {
    final bloc = build(
      turboBalance: BigInt.from(1000),
      sourceAddress: '4WkBm7vD1qF9xYz',
    );
    addTearDown(bloc.close);

    await prepare(bloc);

    verifyNever(() => paymentService.getBalanceForAddress(
          address: any(named: 'address'),
          walletType: any(named: 'walletType'),
        ));
  });

  test('reports what it finds, with both addresses', () async {
    when(() => paymentService.getBalanceForAddress(
          address: any(named: 'address'),
          walletType: any(named: 'walletType'),
        )).thenAnswer((_) async => BigInt.from(12080));

    final bloc = build(
      turboBalance: BigInt.zero,
      sourceAddress: '4WkBm7vD1qF9xYz',
    );
    addTearDown(bloc.close);

    await prepare(bloc);

    final found = (bloc.state as UploadPaymentMethodLoaded)
        .paymentMethodInfo
        .sourceWalletCredits;

    expect(found, isNotNull);
    expect(found!.balance, BigInt.from(12080));
    expect(found.sourceAddress, '4WkBm7vD1qF9xYz');
    expect(found.walletType, WalletType.solana);
    expect(
      found.arweaveAddress,
      'arweave-address',
      reason: 'the reader has to be told which address to share the credits to',
    );
  });

  /// An empty account somewhere else is not news, and saying so would turn an
  /// ordinary out-of-credits message into a puzzle.
  test('says nothing when the other wallet is empty too', () async {
    final bloc = build(
      turboBalance: BigInt.zero,
      sourceAddress: '4WkBm7vD1qF9xYz',
    );
    addTearDown(bloc.close);

    await prepare(bloc);

    expect(
      (bloc.state as UploadPaymentMethodLoaded)
          .paymentMethodInfo
          .sourceWalletCredits,
      isNull,
    );
  });

  /// An unanswered question is not a fact about somebody's money.
  test('and says nothing when it cannot find out', () async {
    when(() => paymentService.getBalanceForAddress(
          address: any(named: 'address'),
          walletType: any(named: 'walletType'),
        )).thenThrow(Exception('gateway'));

    final bloc = build(
      turboBalance: BigInt.zero,
      sourceAddress: '4WkBm7vD1qF9xYz',
    );
    addTearDown(bloc.close);

    await prepare(bloc);

    final state = bloc.state;

    expect(state, isA<UploadPaymentMethodLoaded>());
    expect(
      (state as UploadPaymentMethodLoaded)
          .paymentMethodInfo
          .sourceWalletCredits,
      isNull,
      reason: 'a failed lookup must not become a claim, and must not break the '
          'sheet that was already showing',
    );
  });

  /// Events here run concurrently, so a lookup can still be out when the sheet
  /// is prepared again, after a top-up for instance. Its answer belongs to the
  /// preparation that asked, not to whatever is on screen when it lands.
  test('a late answer is not applied to a newer preparation', () async {
    final lookup = Completer<BigInt>();
    when(() => paymentService.getBalanceForAddress(
          address: any(named: 'address'),
          walletType: any(named: 'walletType'),
        )).thenAnswer((_) => lookup.future);

    final bloc = build(
      turboBalance: BigInt.zero,
      sourceAddress: '4WkBm7vD1qF9xYz',
    );
    addTearDown(bloc.close);
    await prepare(bloc);

    // Topped up while the gateway was still answering.
    when(() => preparationManager.prepareUpload(params: any(named: 'params')))
        .thenAnswer(
            (_) async => preparationWith(turboBalance: BigInt.from(1000)));
    await prepare(bloc);

    lookup.complete(BigInt.from(12080));
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }

    final info = (bloc.state as UploadPaymentMethodLoaded).paymentMethodInfo;
    expect(info.sufficentCreditsBalance, isTrue,
        reason: 'the newer preparation is the one on screen');
    expect(info.sourceWalletCredits, isNull);
  });

  /// Granting the derived wallet the right to spend what the sign-in wallet
  /// holds. An approval is the holder's decision, so this is signed by the
  /// wallet the reader signed in with, not by the account being credited.
  group('sharing the credits across', () {
    Future<UploadPaymentMethodBloc> refusedWithCredits() async {
      when(() => paymentService.getBalanceForAddress(
            address: any(named: 'address'),
            walletType: any(named: 'walletType'),
          )).thenAnswer((_) async => BigInt.from(12080));

      final bloc = build(
        turboBalance: BigInt.zero,
        sourceAddress: '4WkBm7vD1qF9xYz',
      );
      addTearDown(bloc.close);
      await prepare(bloc);

      return bloc;
    }

    test('grants the derived address exactly what was found', () async {
      final bloc = await refusedWithCredits();

      expect(await bloc.shareSourceWalletCredits(), isTrue);

      verify(() => sharing.shareCreditsFromSignInWallet(
            sourceAddress: '4WkBm7vD1qF9xYz',
            approvedAddress: 'arweave-address',
            approvedWinc: BigInt.from(12080),
          )).called(1);
    });

    /// The grant changes what Turbo reports, so the sheet asks again rather
    /// than patching its own state from a second source of truth.
    test('and prepares the sheet again so the new balance is read', () async {
      final bloc = await refusedWithCredits();

      clearInteractions(preparationManager);
      await bloc.shareSourceWalletCredits();
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      verify(() => preparationManager.prepareUpload(
            params: any(named: 'params'),
          )).called(greaterThanOrEqualTo(1));
    });

    /// A declined signature or a wallet that is gone. Not an error state: the
    /// sheet keeps its instructions and the control says so itself.
    test('a refusal is answered, not thrown', () async {
      final bloc = await refusedWithCredits();

      when(() => sharing.shareCreditsFromSignInWallet(
            sourceAddress: any(named: 'sourceAddress'),
            approvedAddress: any(named: 'approvedAddress'),
            approvedWinc: any(named: 'approvedWinc'),
          )).thenThrow(Exception('user rejected'));

      expect(await bloc.shareSourceWalletCredits(), isFalse);
      expect(bloc.state, isA<UploadPaymentMethodLoaded>());
    });

    /// A reader who closes the sheet while the wallet is still answering. The
    /// grant went through, so that is the answer, and a closed sheet cannot be
    /// prepared again. Bloc closes its event controller before the state
    /// controller `isClosed` reads, so this must not throw on the way out.
    test('a sheet closed mid-grant still reports the grant', () async {
      final bloc = await refusedWithCredits();
      final wallet = Completer<void>();

      when(() => sharing.shareCreditsFromSignInWallet(
            sourceAddress: any(named: 'sourceAddress'),
            approvedAddress: any(named: 'approvedAddress'),
            approvedWinc: any(named: 'approvedWinc'),
          )).thenAnswer((_) => wallet.future);

      final shared = bloc.shareSourceWalletCredits();
      await Future<void>.delayed(Duration.zero);

      await bloc.close();
      wallet.complete();

      expect(await shared, isTrue);
    });

    /// A button that could only ever fail is not offered. Off the web there is
    /// nothing to sign with, and on the web the signer is a Solana wallet.
    group('is offered only where the grant can be signed', () {
      test('on the web, for credits on a Solana wallet', () async {
        final bloc = await refusedWithCredits();

        expect(bloc.canShareSourceWalletCredits, isTrue);
      });

      test('not off the web', () async {
        when(() => sharing.isSupported).thenReturn(false);
        final bloc = await refusedWithCredits();

        expect(bloc.canShareSourceWalletCredits, isFalse);
        expect(await bloc.shareSourceWalletCredits(), isFalse);
        verifyNever(() => sharing.shareCreditsFromSignInWallet(
              sourceAddress: any(named: 'sourceAddress'),
              approvedAddress: any(named: 'approvedAddress'),
              approvedWinc: any(named: 'approvedWinc'),
            ));
      });

      test('not where no service was given', () async {
        when(() => paymentService.getBalanceForAddress(
              address: any(named: 'address'),
              walletType: any(named: 'walletType'),
            )).thenAnswer((_) async => BigInt.from(12080));
        when(() => user.sourceWalletAddress).thenReturn('4WkBm7vD1qF9xYz');
        when(() => preparationManager.prepareUpload(
                  params: any(named: 'params'),
                ))
            .thenAnswer(
                (_) async => preparationWith(turboBalance: BigInt.zero));

        final bloc = UploadPaymentMethodBloc(
          profileCubit,
          preparationManager,
          auth,
          paymentService,
        );
        addTearDown(bloc.close);
        await prepare(bloc);

        expect(bloc.canShareSourceWalletCredits, isFalse);
      });

      /// Found, so the only thing that can withhold the share is whose wallet
      /// the credits are on.
      test('not for credits on an Ethereum wallet', () async {
        when(() => paymentService.getBalanceForAddress(
              address: any(named: 'address'),
              walletType: any(named: 'walletType'),
            )).thenAnswer((_) async => BigInt.from(12080));

        final bloc = build(
          turboBalance: BigInt.zero,
          sourceAddress: '0x3aF1c9E2b7D40c5E8f6A1B2C3D4E5F60718293A4',
        );
        addTearDown(bloc.close);
        await prepare(bloc);

        final found = (bloc.state as UploadPaymentMethodLoaded)
            .paymentMethodInfo
            .sourceWalletCredits;
        expect(found?.walletType, WalletType.ethereum);
        expect(bloc.canShareSourceWalletCredits, isFalse);
        expect(await bloc.shareSourceWalletCredits(), isFalse);
      });
    });

    test('and there is nothing to grant when nothing was found', () async {
      final bloc = build(
        turboBalance: BigInt.zero,
        sourceAddress: '4WkBm7vD1qF9xYz',
      );
      addTearDown(bloc.close);
      await prepare(bloc);

      expect(await bloc.shareSourceWalletCredits(), isFalse);
      verifyNever(() => sharing.shareCreditsFromSignInWallet(
            sourceAddress: any(named: 'sourceAddress'),
            approvedAddress: any(named: 'approvedAddress'),
            approvedWinc: any(named: 'approvedWinc'),
          ));
    });
  });
}
