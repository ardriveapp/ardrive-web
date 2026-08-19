import 'dart:typed_data';

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/drive_state/data/arweave_drive_state_uploader.dart';
import 'package:ardrive/drive_state/domain/drive_state_creation_service.dart';
import 'package:ardrive/drive_state/domain/drive_state_entity.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/user.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart' show SecretKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

/// The one code path in the app that spends money on an artifact.
///
/// Every collaborator here is a mock. Nothing in this file — and nothing in
/// any file — posts an artifact to a network, a testnet included:
/// `docs/drive-state/DECISIONS.md` D8 makes "nothing is uploaded by any agent"
/// a rail, and a test that quietly spent money would be the thing that broke
/// it. What is asserted is orchestration: which transport is used, that the
/// transaction is prepared unsigned and signed afterwards, and that every
/// refusal happens before anything is posted.
void main() {
  late MockArweaveService arweave;
  late MockTurboUploadService turboUploadService;
  late MockProfileCubit profileCubit;
  late MockTabVisibilitySingleton tabVisibility;
  late ArweaveDriveStateUploader uploader;
  late _MockDataItem dataItem;
  late _MockTransaction transaction;

  final wallet = getTestWallet();

  setUpAll(() {
    registerFallbackValue(DriveStateEntity());
    registerFallbackValue(getTestWallet());
    registerFallbackValue(ArweaveSigner(getTestWallet()));
    registerFallbackValue(_MockDataItem());
    registerFallbackValue(_MockTransaction());
  });

  setUp(() {
    arweave = MockArweaveService();
    turboUploadService = MockTurboUploadService();
    profileCubit = MockProfileCubit();
    tabVisibility = MockTabVisibilitySingleton();
    dataItem = _MockDataItem();
    transaction = _MockTransaction();

    uploader = ArweaveDriveStateUploader(
      arweave: arweave,
      turboUploadService: turboUploadService,
      profileCubit: profileCubit,
      tabVisibility: tabVisibility,
    );

    when(() => profileCubit.state).thenReturn(
      ProfileLoggedIn(
        user: User(
          password: 'password',
          wallet: wallet,
          walletAddress: 'owner-address',
          walletBalance: BigInt.from(1000000000),
          cipherKey: SecretKey(List.filled(32, 3)),
          profileType: ProfileType.json,
          errorFetchingIOTokens: false,
        ),
        useTurbo: false,
      ),
    );
    when(() => profileCubit.logoutIfWalletMismatch())
        .thenAnswer((_) async => false);
    when(() => profileCubit.isCurrentProfileArConnect())
        .thenAnswer((_) async => false);

    when(() => dataItem.id).thenReturn('data-item-id');
    when(() => dataItem.sign(any())).thenAnswer((_) async => Uint8List(0));
    when(() => transaction.id).thenReturn('transaction-id');
    when(() => transaction.sign(any())).thenAnswer((_) async {});

    when(() => arweave.prepareEntityDataItem(
          any(),
          any(),
          skipSignature: any(named: 'skipSignature'),
        )).thenAnswer((_) async => dataItem);
    when(() => arweave.prepareEntityTx(
          any(),
          any(),
          any(),
          skipSignature: any(named: 'skipSignature'),
        )).thenAnswer((_) async => transaction);

    when(() => turboUploadService.postDataItem(
          dataItem: any(named: 'dataItem'),
          wallet: any(named: 'wallet'),
        )).thenAnswer((_) async {});
    when(() => arweave.uploadTx(
          any(),
          maxConcurrentUploadCount: any(named: 'maxConcurrentUploadCount'),
        )).thenAnswer((_) async {});

    when(() => tabVisibility.isTabFocused()).thenReturn(true);
  });

  PreparedDriveStateArtifact artifact() => PreparedDriveStateArtifact(
        entity: DriveStateEntity(
          id: 'artifact-id',
          driveId: 'drive-id',
          blockEnd: 1814228,
          dataStart: 0,
          dataEnd: 1814228,
          entityCount: 12,
          cipher: 'AES256-GCM',
          cipherIv: 'aXY=',
        ),
        driveId: 'drive-id',
        driveName: 'My Drive',
        entityCount: 12,
        sizeInBytes: 6979321,
      );

  group('both transports, as DRIVE_STATE_ARTIFACT.md 4.4 requires', () {
    test('Turbo publishes a bundled data item and reports its id', () async {
      final result = await uploader.publish(
        artifact(),
        method: UploadMethod.turbo,
      );

      expect(result.isPublished, isTrue);
      expect(result.txId, 'data-item-id');

      verify(() => turboUploadService.postDataItem(
            dataItem: dataItem,
            wallet: wallet,
          )).called(1);
      verifyNever(() => arweave.uploadTx(any(),
          maxConcurrentUploadCount: any(named: 'maxConcurrentUploadCount')));
    });

    test('AR publishes a top-level transaction and reports its id', () async {
      final result = await uploader.publish(
        artifact(),
        method: UploadMethod.ar,
      );

      expect(result.isPublished, isTrue);
      expect(result.txId, 'transaction-id');

      verify(() => arweave.uploadTx(transaction, maxConcurrentUploadCount: 1))
          .called(1);
      verifyNever(() => turboUploadService.postDataItem(
            dataItem: any(named: 'dataItem'),
            wallet: any(named: 'wallet'),
          ));
    });

    test('the L1 path never asks the entity to encrypt an already sealed body',
        () async {
      await uploader.publish(artifact(), method: UploadMethod.ar);

      final key = verify(() => arweave.prepareEntityTx(
            any(),
            any(),
            captureAny(),
            skipSignature: any(named: 'skipSignature'),
          )).captured.single;

      expect(key, isNull);
    });
  });

  group('prepared unsigned, signed afterwards', () {
    test('a data item is prepared with skipSignature and then signed',
        () async {
      await uploader.publish(artifact(), method: UploadMethod.turbo);

      final skipSignature = verify(() => arweave.prepareEntityDataItem(
            any(),
            any(),
            skipSignature: captureAny(named: 'skipSignature'),
          )).captured.single;

      expect(skipSignature, isTrue);
      verify(() => dataItem.sign(any())).called(1);
    });

    test('a transaction is prepared with skipSignature and then signed',
        () async {
      await uploader.publish(artifact(), method: UploadMethod.ar);

      final skipSignature = verify(() => arweave.prepareEntityTx(
            any(),
            any(),
            any(),
            skipSignature: captureAny(named: 'skipSignature'),
          )).captured.single;

      expect(skipSignature, isTrue);
      verify(() => transaction.sign(any())).called(1);
    });
  });

  group('refusals happen before anything is posted', () {
    test('a logged out profile publishes nothing', () async {
      when(() => profileCubit.state).thenReturn(ProfileLoggingOut());

      final result = await uploader.publish(
        artifact(),
        method: UploadMethod.turbo,
      );

      expect(result.isFailed, isTrue);
      expect(result.reason, contains('nothing was spent'));
      verifyNever(() => arweave.prepareEntityDataItem(any(), any(),
          skipSignature: any(named: 'skipSignature')));
      verifyNever(() => turboUploadService.postDataItem(
            dataItem: any(named: 'dataItem'),
            wallet: any(named: 'wallet'),
          ));
    });

    test('a wallet switched mid-flow publishes nothing', () async {
      when(() => profileCubit.logoutIfWalletMismatch())
          .thenAnswer((_) async => true);

      final result = await uploader.publish(
        artifact(),
        method: UploadMethod.turbo,
      );

      expect(result.isFailed, isTrue);
      expect(result.reason, contains('wallet changed'));
      verifyNever(() => arweave.prepareEntityDataItem(any(), any(),
          skipSignature: any(named: 'skipSignature')));
      verifyNever(() => turboUploadService.postDataItem(
            dataItem: any(named: 'dataItem'),
            wallet: any(named: 'wallet'),
          ));
    });
  });

  group('ArConnect and the unfocused tab', () {
    setUp(() {
      when(() => profileCubit.isCurrentProfileArConnect())
          .thenAnswer((_) async => true);
      when(() => tabVisibility.isTabFocused()).thenReturn(false);
      when(() => tabVisibility.onTabGetsFocusedFuture(any()))
          .thenAnswer((invocation) async {
        final onFocus =
            invocation.positionalArguments.first as Future Function();
        await onFocus();
      });
    });

    test('a preparation refused while backgrounded is retried on focus',
        () async {
      var calls = 0;
      when(() => arweave.prepareEntityDataItem(
            any(),
            any(),
            skipSignature: any(named: 'skipSignature'),
          )).thenAnswer((_) async {
        calls++;
        if (calls == 1) throw Exception('ArConnect: tab is not focused');
        return dataItem;
      });

      final result = await uploader.publish(
        artifact(),
        method: UploadMethod.turbo,
      );

      expect(result.isPublished, isTrue);
      expect(result.txId, 'data-item-id');
      expect(calls, 2);
      verify(() => tabVisibility.onTabGetsFocusedFuture(any())).called(1);
    });

    test('a signature refused while backgrounded is retried on focus',
        () async {
      var calls = 0;
      when(() => dataItem.sign(any())).thenAnswer((_) async {
        calls++;
        if (calls == 1) throw Exception('ArConnect: tab is not focused');
        return Uint8List(0);
      });

      final result = await uploader.publish(
        artifact(),
        method: UploadMethod.turbo,
      );

      expect(result.isPublished, isTrue);
      expect(calls, 2);
    });

    test('a focused tab is not a background failure, so it is not retried',
        () async {
      when(() => tabVisibility.isTabFocused()).thenReturn(true);
      when(() => arweave.prepareEntityDataItem(
            any(),
            any(),
            skipSignature: any(named: 'skipSignature'),
          )).thenThrow(Exception('the wallet said no'));

      final result = await uploader.publish(
        artifact(),
        method: UploadMethod.turbo,
      );

      expect(result.isFailed, isTrue);
      verifyNever(() => tabVisibility.onTabGetsFocusedFuture(any()));
      verifyNever(() => turboUploadService.postDataItem(
            dataItem: any(named: 'dataItem'),
            wallet: any(named: 'wallet'),
          ));
    });
  });

  group('failures', () {
    test('a JSON wallet failing to prepare is not waited on', () async {
      when(() => tabVisibility.isTabFocused()).thenReturn(false);
      when(() => arweave.prepareEntityTx(
            any(),
            any(),
            any(),
            skipSignature: any(named: 'skipSignature'),
          )).thenThrow(Exception('the gateway went away'));

      final result = await uploader.publish(
        artifact(),
        method: UploadMethod.ar,
      );

      expect(result.isFailed, isTrue);
      verifyNever(() => tabVisibility.onTabGetsFocusedFuture(any()));
    });

    test('a Turbo payment rejection says so, and says what to do', () async {
      when(() => turboUploadService.postDataItem(
            dataItem: any(named: 'dataItem'),
            wallet: any(named: 'wallet'),
          )).thenThrow(TurboPaymentRequiredException());

      final result = await uploader.publish(
        artifact(),
        method: UploadMethod.turbo,
      );

      expect(result.isFailed, isTrue);
      expect(result.reason, contains('Turbo declined the payment'));
    });

    test('a posting failure is reported rather than thrown', () async {
      when(() => arweave.uploadTx(
            any(),
            maxConcurrentUploadCount: any(named: 'maxConcurrentUploadCount'),
          )).thenThrow(Exception('the node went away'));

      final result = await uploader.publish(
        artifact(),
        method: UploadMethod.ar,
      );

      expect(result.isFailed, isTrue);
      expect(result.reason, contains('could not be published'));
    });
  });
}

class _MockDataItem extends Mock implements DataItem {}

class _MockTransaction extends Mock implements Transaction {}
