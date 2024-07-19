import 'package:ardrive/authentication/ardrive_auth.dart';
import 'package:ardrive/core/arfs/repository/drive_repository.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/models/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../upload/uploader_test.dart';

class MockDriveDao extends Mock implements DriveDao {}

class MockArDriveAuth extends Mock implements ArDriveAuth {}

class MockDrive extends Mock implements Drive {}

class MockFileWithLatestRevisionTransactions extends Mock
    implements FileWithLatestRevisionTransactions {}

class MockSelectable<T> extends Mock implements Selectable<T> {}

void main() {
  late DriveRepository driveRepository;
  late MockDriveDao mockDriveDao;
  late MockArDriveAuth mockArDriveAuth;
  late MockSelectable<Drive> mockSelectableDrive;
  late MockSelectable<FileWithLatestRevisionTransactions> mockSelectableFile;

  setUp(() {
    mockDriveDao = MockDriveDao();
    mockArDriveAuth = MockArDriveAuth();
    mockSelectableDrive = MockSelectable<Drive>();
    mockSelectableFile = MockSelectable<FileWithLatestRevisionTransactions>();
    driveRepository =
        DriveRepository(driveDao: mockDriveDao, auth: mockArDriveAuth);
  });

  group('getAllUserDrives', () {
    final mockDrive1 = MockDrive();
    final mockDrive2 = MockDrive();
    const ownerAddress = 'walletAddress';

    setUp(() {
      when(() => mockArDriveAuth.currentUser).thenReturn(getFakeUser());
    });

    test('returns drives owned by the current user', () async {
      when(() => mockDrive1.ownerAddress).thenReturn(ownerAddress);
      when(() => mockDrive2.ownerAddress).thenReturn('another_wallet_address');
      when(() => mockSelectableDrive.get())
          .thenAnswer((_) async => [mockDrive1, mockDrive2]);
      when(() => mockDriveDao.allDrives()).thenReturn(mockSelectableDrive);

      final result = await driveRepository.getAllUserDrives();

      expect(result, [mockDrive1]);
    });

    test('returns empty list when there are no drives', () async {
      when(() => mockSelectableDrive.get()).thenAnswer((_) async => []);
      when(() => mockDriveDao.allDrives()).thenReturn(mockSelectableDrive);

      final result = await driveRepository.getAllUserDrives();

      expect(result, isEmpty);
    });

    test('returns empty list when user owns no drives', () async {
      when(() => mockDrive1.ownerAddress).thenReturn('another_wallet_address');
      when(() => mockSelectableDrive.get())
          .thenAnswer((_) async => [mockDrive1]);
      when(() => mockDriveDao.allDrives()).thenReturn(mockSelectableDrive);

      final result = await driveRepository.getAllUserDrives();

      expect(result, isEmpty);
    });
  });

  group('getAllFileEntriesInDrive', () {
    final mockFile1 = MockFileWithLatestRevisionTransactions();
    final mockFile2 = MockFileWithLatestRevisionTransactions();
    const driveId = 'drive_id';

    test('returns all files in the drive', () async {
      when(() => mockSelectableFile.get())
          .thenAnswer((_) async => [mockFile1, mockFile2]);
      when(() => mockDriveDao.filesInDriveWithRevisionTransactions(
          driveId: driveId)).thenReturn(mockSelectableFile);

      final result =
          await driveRepository.getAllFileEntriesInDrive(driveId: driveId);

      expect(result, [mockFile1, mockFile2]);
    });

    test('returns empty list when there are no files in the drive', () async {
      when(() => mockSelectableFile.get()).thenAnswer((_) async => []);
      when(() => mockDriveDao.filesInDriveWithRevisionTransactions(
          driveId: driveId)).thenReturn(mockSelectableFile);

      final result =
          await driveRepository.getAllFileEntriesInDrive(driveId: driveId);

      expect(result, isEmpty);
    });
  });

  group('watchDrive', () {
    const driveId = 'test-drive-id';
    final mockDrive1 = MockDrive();

    test('should return a stream of Drive when drive is found', () {
      // Arrange
      when(() => mockDriveDao.driveById(driveId: driveId))
          .thenAnswer((_) => mockSelectableDrive);

      when(() => mockSelectableDrive.watchSingleOrNull()).thenAnswer((_) {
        return Stream.value(mockDrive1);
      });

      // Act
      final driveStream = driveRepository.watchDrive(driveId: driveId);

      // Assert
      expectLater(driveStream, emits(mockDrive1));
    });

    test('should return a stream of null when drive is not found', () {
      // Arrange
      when(() => mockDriveDao.driveById(driveId: driveId))
          .thenAnswer((_) => mockSelectableDrive);

      when(() => mockSelectableDrive.watchSingleOrNull()).thenAnswer((_) {
        return Stream.value(null);
      });

      // Act
      final driveStream = driveRepository.watchDrive(driveId: driveId);

      // Assert
      expectLater(driveStream, emits(null));
    });
  });
}
