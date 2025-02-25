import 'dart:async';

import 'package:ardrive/arns/data/arns_dao.dart';
import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/arns/domain/exceptions.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/user.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockArioSDK extends Mock implements ArioSDK {}

class MockArDriveAuth extends Mock implements ArDriveAuth {}

class MockFileRepository extends Mock implements FileRepository {}

class MockARNSDao extends Mock implements ARNSDao {}

class MockDriveDao extends Mock implements DriveDao {}

class MockTurboUploadService extends Mock implements TurboUploadService {}

class MockArweaveService extends Mock implements ArweaveService {}

class MockWallet extends Mock implements Wallet {}

class MockSelectable extends Mock implements Selectable<ArnsRecord> {}

void main() {
  setUpAll(() {
    // Register fallback value for ARNSUndername
    final fallbackUndername = ARNSUndernameFactory.create(
      name: 'fallback',
      domain: 'fallback.arweave',
      transactionId: 'fallback-tx-id',
    );
    registerFallbackValue(fallbackUndername);

    // Register fallback value for ArnsRecord
    registerFallbackValue(const ArnsRecord(
      transactionId: 'fallback-tx-id',
      fileId: 'fallback-file-id',
      ttl: 900,
      name: 'fallback',
      domain: 'fallback.arweave',
      id: 'fallback-id',
      isActive: true,
    ));
  });

  group('ARNSRepository - getPrimaryName', () {
    late ARNSRepository arnsRepository;
    late MockArioSDK sdk;
    late MockArDriveAuth auth;
    late MockFileRepository fileRepository;
    late MockARNSDao arnsDao;
    late MockDriveDao driveDao;
    late MockTurboUploadService turboUploadService;
    late MockArweaveService arweave;
    late StreamController<User?> authStateController;

    const testAddress = '0x123456789';
    const testPrimaryName = 'test.arweave';

    setUp(() {
      sdk = MockArioSDK();
      auth = MockArDriveAuth();
      fileRepository = MockFileRepository();
      arnsDao = MockARNSDao();
      driveDao = MockDriveDao();
      turboUploadService = MockTurboUploadService();
      arweave = MockArweaveService();
      authStateController = StreamController<User?>.broadcast();

      // Mock the auth state stream
      when(() => auth.onAuthStateChanged())
          .thenAnswer((_) => authStateController.stream);

      arnsRepository = ARNSRepository(
        sdk: sdk,
        auth: auth,
        fileRepository: fileRepository,
        arnsDao: arnsDao,
        driveDao: driveDao,
        turboUploadService: turboUploadService,
        arweave: arweave,
      );
    });

    tearDown(() {
      authStateController.close();
    });

    test('clears cached undernames when user logs out', () async {
      // Setup initial state with cached primary name
      when(() => sdk.getPrimaryNameDetails(testAddress, true))
          .thenAnswer((_) async => const PrimaryNameDetails(
                primaryName: testPrimaryName,
                logo: null,
              ));

      // Get primary name to populate cache
      await arnsRepository.getPrimaryName(testAddress);

      // Verify first call works and caches
      verify(() => sdk.getPrimaryNameDetails(testAddress, true)).called(1);

      // Simulate user logout
      authStateController.add(null);

      // Wait for the cache to clear
      await Future.delayed(const Duration(milliseconds: 100));

      // Get primary name again - should call SDK again since cache was cleared
      await arnsRepository.getPrimaryName(testAddress);

      // Verify SDK was called again after cache clear
      verify(() => sdk.getPrimaryNameDetails(testAddress, true)).called(1);
    });

    test('returns cached primary name when available and update is false',
        () async {
      // First call to populate cache
      when(() => sdk.getPrimaryNameDetails(testAddress, true))
          .thenAnswer((_) async => const PrimaryNameDetails(
                primaryName: testPrimaryName,
                logo: null,
                recordId: null,
              ));

      final result1 = await arnsRepository.getPrimaryName(testAddress);
      expect(result1, isA<PrimaryNameDetails>());

      // Verify SDK was called once
      verify(() => sdk.getPrimaryNameDetails(testAddress, true)).called(1);

      // Second call should use cache
      final result2 = await arnsRepository.getPrimaryName(testAddress);
      expect(result2, isA<PrimaryNameDetails>());

      // Verify SDK wasn't called again
      verifyNoMoreInteractions(sdk);
    });

    test('bypasses cache when update is true', () async {
      when(() => sdk.getPrimaryNameDetails(testAddress, true))
          .thenAnswer((_) async => const PrimaryNameDetails(
                primaryName: testPrimaryName,
                logo: null,
                recordId: null,
              ));

      // First call to populate cache
      await arnsRepository.getPrimaryName(testAddress);

      // Second call with update=true should bypass cache
      final result = await arnsRepository.getPrimaryName(
        testAddress,
        update: true,
      );

      expect(result, isA<PrimaryNameDetails>());
      // Verify SDK was called twice
      verify(() => sdk.getPrimaryNameDetails(testAddress, true)).called(2);
    });

    test('throws exception when SDK call fails', () async {
      when(() => sdk.getPrimaryNameDetails(testAddress, true))
          .thenThrow(Exception('Failed to get primary name'));

      expect(
        () => arnsRepository.getPrimaryName(testAddress),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('ARNSRepository - createUndername', () {
    late ARNSRepository arnsRepository;
    late MockArioSDK sdk;
    late MockArDriveAuth auth;
    late MockFileRepository fileRepository;
    late MockARNSDao arnsDao;
    late MockDriveDao driveDao;
    late MockTurboUploadService turboUploadService;
    late MockArweaveService arweave;
    late StreamController<User?> authStateController;
    late MockWallet mockWallet;
    late MockSelectable mockSelectableByName;
    late MockSelectable mockSelectableById;

    const testDomain = 'test.arweave';
    const testName = 'myname';
    const testTxId = 'test-tx-id';

    setUp(() {
      sdk = MockArioSDK();
      auth = MockArDriveAuth();
      fileRepository = MockFileRepository();
      arnsDao = MockARNSDao();
      driveDao = MockDriveDao();
      turboUploadService = MockTurboUploadService();
      arweave = MockArweaveService();
      authStateController = StreamController<User?>.broadcast();
      mockWallet = MockWallet();
      mockSelectableByName = MockSelectable();
      mockSelectableById = MockSelectable();

      when(() => auth.onAuthStateChanged())
          .thenAnswer((_) => authStateController.stream);

      // Mock getARNSRecordByName to return a record
      when(() => arnsDao.getARNSRecordByName(
            domain: any(named: 'domain'),
            name: any(named: 'name'),
          )).thenReturn(mockSelectableByName);
      when(() => mockSelectableByName.get()).thenAnswer((_) async => [
            const ArnsRecord(
              transactionId: testTxId,
              fileId: 'test-file-id',
              ttl: 900,
              name: testName,
              domain: testDomain,
              id: 'test-id',
              isActive: true,
            )
          ]);

      // Mock getARNSRecordById to return a record
      when(() => arnsDao.getARNSRecordById(
            id: any(named: 'id'),
          )).thenReturn(mockSelectableById);
      when(() => mockSelectableById.getSingle())
          .thenAnswer((_) async => const ArnsRecord(
                transactionId: testTxId,
                fileId: 'test-file-id',
                ttl: 900,
                name: testName,
                domain: testDomain,
                id: 'test-id',
                isActive: true,
              ));

      // Mock updateARNSRecordActiveStatus
      when(() => arnsDao.updateARNSRecordActiveStatus(
            id: any(named: 'id'),
            isActive: any(named: 'isActive'),
          )).thenAnswer((_) async => {});

      arnsRepository = ARNSRepository(
        sdk: sdk,
        auth: auth,
        fileRepository: fileRepository,
        arnsDao: arnsDao,
        driveDao: driveDao,
        turboUploadService: turboUploadService,
        arweave: arweave,
      );
    });

    tearDown(() {
      authStateController.close();
    });

    test('throws UndernameAlreadyExistsException when undername exists',
        () async {
      const record =
          ANTRecord(domain: testDomain, processId: 'test-process-id');
      final existingUndername = ARNSUndernameFactory.create(
        name: testName,
        domain: testDomain,
        transactionId: testTxId,
      );

      // Add existing undername to cache
      arnsRepository.addToCacheForTesting(record, [existingUndername]);

      // Try to create the same undername
      expect(
        () => arnsRepository.createUndername(undername: existingUndername),
        throwsA(isA<UndernameAlreadyExistsException>()),
      );

      // Verify no interactions with SDK or DAO
      verifyNever(() => sdk.createUndername(
            undername: any(named: 'undername'),
            isArConnect: any(named: 'isArConnect'),
            txId: any(named: 'txId'),
            jwtString: any(named: 'jwtString'),
          ));
      verifyNever(() => arnsDao.saveARNSRecord(
            domain: any(named: 'domain'),
            transactionId: any(named: 'transactionId'),
            isActive: any(named: 'isActive'),
            undername: any(named: 'undername'),
            ttl: any(named: 'ttl'),
            fileId: any(named: 'fileId'),
          ));
    });

    test('creates undername successfully with ArConnect profile', () async {
      const record =
          ANTRecord(domain: testDomain, processId: 'test-process-id');
      final newUndername = ARNSUndernameFactory.create(
        name: 'newname',
        domain: testDomain,
        transactionId: testTxId,
      );

      // Setup empty cache for the domain
      arnsRepository.addToCacheForTesting(record, []);

      // Mock user with ArConnect profile
      when(() => auth.currentUser).thenReturn(
        User(
          password: 'test-password',
          wallet: mockWallet,
          walletAddress: 'test-address',
          walletBalance: BigInt.zero,
          cipherKey: SecretKey([1, 2, 3]),
          profileType: ProfileType.arConnect,
          errorFetchingIOTokens: false,
        ),
      );

      // Mock SDK response
      when(() => sdk.createUndername(
            undername: newUndername,
            isArConnect: true,
            txId: testTxId,
            jwtString: null,
          )).thenAnswer((_) async => 'new-tx-id');

      // Mock DAO
      when(() => arnsDao.saveARNSRecord(
            domain: testDomain,
            transactionId: testTxId,
            isActive: false,
            undername: 'newname',
            ttl: 900,
            fileId: '',
          )).thenAnswer((_) async => {});

      // Execute
      await arnsRepository.createUndername(undername: newUndername);

      // Verify SDK call
      verify(() => sdk.createUndername(
            undername: newUndername,
            isArConnect: true,
            txId: testTxId,
            jwtString: null,
          )).called(1);

      // Verify DAO call
      verify(() => arnsDao.saveARNSRecord(
            domain: testDomain,
            transactionId: testTxId,
            isActive: false,
            undername: 'newname',
            ttl: 900,
            fileId: '',
          )).called(1);

      // Verify updateARNSRecordActiveStatus was called
      verify(() => arnsDao.updateARNSRecordActiveStatus(
            id: 'test-id',
            isActive: true,
          )).called(1);
    });

    test('creates undername successfully with keyfile', () async {
      const record =
          ANTRecord(domain: testDomain, processId: 'test-process-id');
      final newUndername = ARNSUndernameFactory.create(
        name: 'newname',
        domain: testDomain,
        transactionId: testTxId,
      );

      // Setup empty cache for the domain
      arnsRepository.addToCacheForTesting(record, []);

      // Mock user with regular profile
      when(() => auth.currentUser).thenReturn(
        User(
          password: 'test-password',
          wallet: mockWallet,
          walletAddress: 'test-address',
          walletBalance: BigInt.zero,
          cipherKey: SecretKey([1, 2, 3]),
          profileType: ProfileType.json,
          errorFetchingIOTokens: false,
        ),
      );

      // Mock JWT
      when(() => auth.getJWTAsString()).thenReturn('test-jwt');

      // Mock SDK response
      when(() => sdk.createUndername(
            undername: newUndername,
            isArConnect: false,
            txId: testTxId,
            jwtString: 'test-jwt',
          )).thenAnswer((_) async => 'new-tx-id');

      // Mock DAO
      when(() => arnsDao.saveARNSRecord(
            domain: testDomain,
            transactionId: testTxId,
            isActive: false,
            undername: 'newname',
            ttl: 900,
            fileId: '',
          )).thenAnswer((_) async => {});

      // Execute
      await arnsRepository.createUndername(undername: newUndername);

      // Verify SDK call
      verify(() => sdk.createUndername(
            undername: newUndername,
            isArConnect: false,
            txId: testTxId,
            jwtString: 'test-jwt',
          )).called(1);

      // Verify DAO call
      verify(() => arnsDao.saveARNSRecord(
            domain: testDomain,
            transactionId: testTxId,
            isActive: false,
            undername: 'newname',
            ttl: 900,
            fileId: '',
          )).called(1);

      // Verify updateARNSRecordActiveStatus was called
      verify(() => arnsDao.updateARNSRecordActiveStatus(
            id: 'test-id',
            isActive: true,
          )).called(1);
    });
  });
}
