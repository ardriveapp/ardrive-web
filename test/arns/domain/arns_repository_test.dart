import 'dart:async';

import 'package:ardrive/arns/data/arns_dao.dart';
import 'package:ardrive/arns/domain/arns_repository.dart';
import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/core/arfs/repository/file_repository.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:ardrive/user/user.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockArioSDK extends Mock implements ArioSDK {}

class MockArDriveAuth extends Mock implements ArDriveAuth {}

class MockFileRepository extends Mock implements FileRepository {}

class MockARNSDao extends Mock implements ARNSDao {}

class MockDriveDao extends Mock implements DriveDao {}

class MockTurboUploadService extends Mock implements TurboUploadService {}

class MockArweaveService extends Mock implements ArweaveService {}

void main() {
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
}
