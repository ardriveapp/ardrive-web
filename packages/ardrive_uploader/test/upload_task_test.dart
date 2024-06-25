import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:cryptography/cryptography.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';
import 'package:uuid/uuid.dart';

// Mocks
class MockIOFile extends Mock implements IOFile {}

class MockARFSFileUploadMetadata extends Mock
    implements ARFSFileUploadMetadata {}

class MockUploadItem extends Mock implements UploadItem {}

class MockARFSUploadMetadata extends Mock implements ARFSUploadMetadata {}

class MockSecretKey extends Mock implements SecretKey {}

class MockUploadTaskCancelToken extends Mock implements UploadTaskCancelToken {}

void main() {
  group('FileUploadTask', () {
    late MockIOFile mockFile;
    late MockARFSFileUploadMetadata mockMetadata;
    late MockUploadItem mockUploadItem;
    late MockSecretKey mockEncryptionKey;
    late MockUploadTaskCancelToken mockCancelToken;

    setUp(() {
      mockFile = MockIOFile();
      mockMetadata = MockARFSFileUploadMetadata();
      mockUploadItem = MockUploadItem();
      mockEncryptionKey = MockSecretKey();
      mockCancelToken = MockUploadTaskCancelToken();
    });

    test('Initialization with default values', () {
      final task = FileUploadTask(
        file: mockFile,
        metadata: mockMetadata,
        type: UploadType.turbo,
        uploadThumbnail: true,
      );

      expect(task.file, mockFile);
      expect(task.metadata, mockMetadata);
      expect(task.type, UploadType.turbo);
      expect(task.progress, 0);
      expect(task.isProgressAvailable, true);
      expect(task.metadataUploaded, false);
      expect(task.status, UploadStatus.notStarted);
      expect(task.id, isNotNull);
    });

    test('Initialization with custom values', () {
      final customId = const Uuid().v4();
      final task = FileUploadTask(
        file: mockFile,
        metadata: mockMetadata,
        type: UploadType.turbo,
        progress: 50,
        isProgressAvailable: false,
        status: UploadStatus.inProgress,
        id: customId,
        encryptionKey: mockEncryptionKey,
        cancelToken: mockCancelToken,
        metadataUploaded: true,
        uploadItem: mockUploadItem,
        uploadThumbnail: true,
      );

      expect(task.file, mockFile);
      expect(task.metadata, mockMetadata);
      expect(task.type, UploadType.turbo);
      expect(task.progress, 50);
      expect(task.isProgressAvailable, false);
      expect(task.metadataUploaded, true);
      expect(task.status, UploadStatus.inProgress);
      expect(task.id, customId);
      expect(task.encryptionKey, mockEncryptionKey);
      expect(task.cancelToken, mockCancelToken);
      expect(task.uploadItem, mockUploadItem);
    });

    test('CopyWith method functionality', () {
      final task = FileUploadTask(
        file: mockFile,
        metadata: mockMetadata,
        type: UploadType.turbo,
        uploadThumbnail: true,
      );

      final newTask = task.copyWith(
        progress: 75,
        status: UploadStatus.complete,
      );

      expect(newTask.progress, 75);
      expect(newTask.status, UploadStatus.complete);
      expect(newTask.file, task.file); // unchanged
      expect(newTask.metadata, task.metadata); // unchanged
      expect(newTask.type, task.type); // unchanged
      expect(
          newTask.isProgressAvailable, task.isProgressAvailable); // unchanged
    });

    test('ErrorInfo method', () {
      final task = FileUploadTask(
        file: mockFile,
        metadata: mockMetadata,
        type: UploadType.turbo,
        uploadThumbnail: true,
      );

      final errorInfo = task.errorInfo();
      expect(errorInfo, contains('progress: 0'));
      expect(errorInfo, contains('status: UploadStatus.notStarted'));
      expect(errorInfo, contains('type: UploadType.turbo'));
    });
  });

  group('FolderUploadTask', () {
    late List<(ARFSFolderUploadMetatadata, IOEntity)> mockFolders;
    late MockUploadItem mockUploadItem;
    late MockSecretKey mockEncryptionKey;
    late MockUploadTaskCancelToken mockCancelToken;

    setUp(() {
      mockUploadItem = MockUploadItem();
      mockEncryptionKey = MockSecretKey();
      mockCancelToken = MockUploadTaskCancelToken();
      mockFolders = <(ARFSFolderUploadMetatadata, IOEntity)>[];
    });

    test('Initialization with default values', () {
      final task = FolderUploadTask(
        folders: mockFolders,
        type: UploadType.turbo,
      );

      expect(task.folders, mockFolders);
      expect(task.type, UploadType.turbo);
      expect(task.progress, 0);
      expect(task.isProgressAvailable, true);
      expect(task.status, UploadStatus.notStarted);
      expect(task.id, isNotNull);
    });

    test('Initialization with custom values', () {
      final customId = const Uuid().v4();
      final task = FolderUploadTask(
        folders: mockFolders,
        type: UploadType.turbo,
        progress: 50,
        isProgressAvailable: false,
        status: UploadStatus.inProgress,
        id: customId,
        encryptionKey: mockEncryptionKey,
        cancelToken: mockCancelToken,
        uploadItem: mockUploadItem,
      );

      expect(task.folders, mockFolders);
      expect(task.type, UploadType.turbo);
      expect(task.progress, 50);
      expect(task.isProgressAvailable, false);
      expect(task.status, UploadStatus.inProgress);
      expect(task.id, customId);
      expect(task.encryptionKey, mockEncryptionKey);
      expect(task.cancelToken, mockCancelToken);
      expect(task.uploadItem, mockUploadItem);
    });

    test('CopyWith method functionality', () {
      final task = FolderUploadTask(
        folders: mockFolders,
        type: UploadType.turbo,
      );

      final newTask = task.copyWith(
        progress: 75,
        status: UploadStatus.complete,
      );

      expect(newTask.progress, 75);
      expect(newTask.status, UploadStatus.complete);
      expect(newTask.folders, task.folders); // unchanged
      expect(newTask.type, task.type); // unchanged
      expect(
          newTask.isProgressAvailable, task.isProgressAvailable); // unchanged
    });

    test('ErrorInfo method', () {
      final task = FolderUploadTask(
        folders: mockFolders,
        type: UploadType.turbo,
      );

      final errorInfo = task.errorInfo();
      expect(errorInfo, contains('progress: 0'));
      expect(errorInfo, contains('status: UploadStatus.notStarted'));
      expect(errorInfo, contains('type: UploadType.turbo'));
    });
  });
}
