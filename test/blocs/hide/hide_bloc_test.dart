import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/blocs/hide/hide_bloc.dart';
import 'package:ardrive/blocs/hide/hide_event.dart';
import 'package:ardrive/blocs/hide/hide_state.dart';
import 'package:ardrive/blocs/upload/models/upload_review_summary.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/core/upload/metadata_write_cost.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/user.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:uuid/uuid.dart';

import '../../test_utils/utils.dart';

class _MockCostReader extends Mock implements MetadataWriteCostReader {}

UploadReviewSummary _summary({
  bool isFree = false,
  bool isCovered = false,
  bool priceUnavailable = false,
}) =>
    UploadReviewSummary(
      method: UploadMethod.turbo,
      isFree: isFree,
      priceUnavailable: priceUnavailable,
      isCovered: isCovered,
      overFreeAllowance: !isFree,
      offersPaymentChoice: false,
      usesLegacySelector: false,
      creditsCost: BigInt.from(40000000),
      creditsBalance: isCovered ? BigInt.from(10).pow(12) : BigInt.zero,
      usdCost: 0.0002,
      arCost: BigInt.zero,
    );

/// Hiding and unhiding go through Turbo like every other change: free under
/// the free upload allowance, Turbo Credits after it, and the wallet only when
/// Turbo uploads are off. They used to send an AR transaction from the wallet,
/// unasked, whenever the allowance did not cover them.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late MockArweaveService arweave;
  late MockTurboUploadService turbo;
  late _MockCostReader costReader;
  late MockProfileCubit profileCubit;
  late HideBloc bloc;
  final wallet = getTestWallet();
  const driveId = 'drive';
  const rootFolderId = 'root';
  const fileId = 'file';

  setUpAll(() {
    registerFallbackValue(FileEntity());
    registerFallbackValue(Wallet());
    registerFallbackValue(BigInt.zero);
    registerFallbackValue(<int>[]);
    registerFallbackValue(<String, String>{});
    registerFallbackValue(DataBundle(blob: Uint8List(0)));
    registerFallbackValue(Transaction());
    registerFallbackValue(DataItem.withBlobData(data: Uint8List(0)));
  });

  setUp(() async {
    db = getTestDb();
    final date = DateTime(2026);
    await db.batch((batch) {
      batch.insert(
        db.drives,
        DrivesCompanion.insert(
          id: driveId,
          rootFolderId: rootFolderId,
          ownerAddress: 'owner',
          name: 'drive',
          privacy: DrivePrivacyTag.public,
        ),
      );
      batch.insert(
        db.folderEntries,
        FolderEntriesCompanion.insert(
          id: rootFolderId,
          driveId: driveId,
          name: 'drive',
          isHidden: const Value(false),
          path: '',
        ),
      );
      batch.insert(
        db.fileEntries,
        FileEntriesCompanion.insert(
          id: fileId,
          driveId: driveId,
          parentFolderId: rootFolderId,
          name: 'notes.txt',
          dataTxId: 'data',
          size: 10,
          dateCreated: Value(date),
          lastModifiedDate: date,
          dataContentType: const Value('text/plain'),
          isHidden: const Value(false),
          path: '',
        ),
      );
    });

    PackageInfo.setMockInitialValues(
      appName: 'app',
      packageName: 'package',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    AppPlatform.setMockPlatform(platform: SystemPlatform.unknown);

    arweave = MockArweaveService();
    when(() =>
            arweave.prepareEntityDataItem(any(), any(), key: any(named: 'key')))
        .thenAnswer((_) async {
      final item = DataItem.withBlobData(
          data: Uint8List.fromList(const Uuid().v4().codeUnits))
        ..setOwner(await wallet.getOwner());
      await item.sign(ArweaveSigner(wallet));
      return item;
    });
    when(() => arweave.prepareDataBundleTx(any(), any())).thenAnswer(
        (_) async => getTestTransaction('test/fixtures/signed_v2_tx.json'));
    when(() => arweave.postTx(any())).thenAnswer((_) async {});

    turbo = MockTurboUploadService();
    when(() => turbo.useTurboUpload).thenReturn(true);
    when(() => turbo.postDataItem(
          dataItem: any(named: 'dataItem'),
          wallet: any(named: 'wallet'),
          headers: any(named: 'headers'),
        )).thenAnswer((_) async {});

    costReader = _MockCostReader();
    when(() => costReader.usesTurbo).thenReturn(true);

    profileCubit = MockProfileCubit();
    when(() => profileCubit.state).thenReturn(ProfileLoggedIn(
      user: User(
        password: 'password',
        wallet: wallet,
        cipherKey: SecretKey(List.filled(32, 1)),
        walletAddress: await wallet.getAddress(),
        walletBalance: BigInt.from(10).pow(15),
        profileType: ProfileType.json,
        errorFetchingIOTokens: false,
      ),
      useTurbo: true,
    ));

    bloc = HideBloc(
      arweaveService: arweave,
      crypto: ArDriveCrypto(),
      turboUploadService: turbo,
      driveDao: db.driveDao,
      profileCubit: profileCubit,
      costReader: costReader,
    );
  });

  tearDown(() async {
    await bloc.close();
    await db.close();
  });

  void costs(UploadReviewSummary summary, {List<String> paidBy = const []}) =>
      when(() => costReader.read(
                itemSizes: any(named: 'itemSizes'),
                wallet: any(named: 'wallet'),
                walletBalance: any(named: 'walletBalance'),
                refusedByTurbo: any(named: 'refusedByTurbo'),
              ))
          .thenAnswer((_) async => MetadataWriteCost(summary, paidBy: paidBy));

  Future<ConfirmingHideState> confirming() async {
    bloc.add(const HideFileEvent(driveId: driveId, fileId: fileId));
    return await bloc.stream
            .firstWhere((s) => s is ConfirmingHideState && s.summary != null)
        as ConfirmingHideState;
  }

  Future<bool> fileHidden() async =>
      (await db.driveDao.fileById(fileId: fileId).getSingle()).isHidden;

  void verifyNoWalletPost() {
    verifyNever(() => arweave.prepareDataBundleTx(any(), any()));
    verifyNever(() => arweave.postTx(any()));
  }

  test('free: written straight away through Turbo, no review', () async {
    costs(_summary(isFree: true, isCovered: true));

    final state = await confirming();
    expect(state.isInstant, isTrue);

    bloc.add(const ConfirmUploadEvent());
    await bloc.stream.firstWhere((s) => s is SuccessHideState);

    verify(() => turbo.postDataItem(
          dataItem: any(named: 'dataItem'),
          wallet: any(named: 'wallet'),
          headers: any(named: 'headers'),
        )).called(1);
    verifyNoWalletPost();
    expect(await fileHidden(), isTrue);
  });

  test('the review prices the item it writes', () async {
    costs(_summary(isFree: true, isCovered: true));

    await confirming();

    final sizes = verify(() => costReader.read(
          itemSizes: captureAny(named: 'itemSizes'),
          wallet: any(named: 'wallet'),
          walletBalance: any(named: 'walletBalance'),
          refusedByTurbo: false,
        )).captured.single as List<int>;
    expect(sizes, hasLength(1));
    expect(sizes.single, greaterThan(1000));
  });

  test(
      'not free, credits cover it: a review, then Turbo Credits, never '
      'the wallet', () async {
    costs(_summary(isCovered: true), paidBy: ['sharer']);

    final state = await confirming();
    expect(state.isInstant, isFalse);

    bloc.add(const ConfirmUploadEvent());
    await bloc.stream.firstWhere((s) => s is SuccessHideState);

    verify(() => turbo.postDataItem(
          dataItem: any(named: 'dataItem'),
          wallet: any(named: 'wallet'),
          headers: {'x-paid-by': 'sharer'},
        )).called(1);
    verifyNoWalletPost();
    expect(await fileHidden(), isTrue);
  });

  for (final (name, summary) in [
    ('the credits are short', _summary()),
    ('there is no price', _summary(priceUnavailable: true)),
  ]) {
    test('Confirm writes nothing when $name, and never pays from the wallet',
        () async {
      costs(summary);
      final state = await confirming();
      expect(state.isInstant, isFalse);

      bloc.add(const ConfirmUploadEvent());
      await Future.delayed(const Duration(milliseconds: 200));

      verifyNever(() => turbo.postDataItem(
            dataItem: any(named: 'dataItem'),
            wallet: any(named: 'wallet'),
            headers: any(named: 'headers'),
          ));
      verifyNoWalletPost();
      expect(await fileHidden(), isFalse);
    });
  }

  test(
      'refused as not paid for: back to the review, read again as refused, '
      'Add credits, nothing saved, never the wallet', () async {
    costs(_summary(isFree: true, isCovered: true));
    when(() => turbo.postDataItem(
          dataItem: any(named: 'dataItem'),
          wallet: any(named: 'wallet'),
          headers: any(named: 'headers'),
        )).thenThrow(TurboPaymentRequiredException());
    await confirming();
    costs(_summary());

    bloc.add(const ConfirmUploadEvent());
    final back = await bloc.stream.firstWhere(
            (s) => s is ConfirmingHideState && s.refused && s.summary != null)
        as ConfirmingHideState;

    expect(back.isInstant, isFalse);
    expect(back.summary!.needsCredits, isTrue);
    verify(() => costReader.read(
          itemSizes: any(named: 'itemSizes'),
          wallet: any(named: 'wallet'),
          walletBalance: any(named: 'walletBalance'),
          refusedByTurbo: true,
        )).called(1);
    verifyNoWalletPost();
    expect(await fileHidden(), isFalse);
  });

  test('after credits are added, the review reads the cost again', () async {
    costs(_summary());
    await confirming();
    costs(_summary(isCovered: true));

    bloc.add(const HideCostRefreshEvent());
    final state = await bloc.stream.firstWhere(
            (s) => s is ConfirmingHideState && (s.summary?.isCovered ?? false))
        as ConfirmingHideState;

    expect(state.summary!.needsCredits, isFalse);
  });

  test('two Confirms write it once', () async {
    costs(_summary(isFree: true, isCovered: true));
    await confirming();

    bloc
      ..add(const ConfirmUploadEvent())
      ..add(const ConfirmUploadEvent());
    await bloc.stream.firstWhere((s) => s is SuccessHideState);
    await Future.delayed(const Duration(milliseconds: 200));

    verify(() => turbo.postDataItem(
          dataItem: any(named: 'dataItem'),
          wallet: any(named: 'wallet'),
          headers: any(named: 'headers'),
        )).called(1);
  });

  test('Turbo uploads off: the wallet pays, as configured', () async {
    when(() => turbo.useTurboUpload).thenReturn(false);
    when(() => costReader.usesTurbo).thenReturn(false);
    costs(UploadReviewSummary(
      method: UploadMethod.ar,
      isFree: false,
      priceUnavailable: false,
      isCovered: true,
      overFreeAllowance: false,
      offersPaymentChoice: false,
      usesLegacySelector: true,
      creditsCost: BigInt.zero,
      creditsBalance: BigInt.zero,
      usdCost: null,
      arCost: BigInt.from(1000),
    ));
    final state = await confirming();
    expect(state.isInstant, isFalse);

    bloc.add(const ConfirmUploadEvent());
    await bloc.stream.firstWhere((s) => s is SuccessHideState);

    verify(() => arweave.postTx(any())).called(1);
    verifyNever(() => turbo.postDataItem(
          dataItem: any(named: 'dataItem'),
          wallet: any(named: 'wallet'),
          headers: any(named: 'headers'),
        ));
  });
}
