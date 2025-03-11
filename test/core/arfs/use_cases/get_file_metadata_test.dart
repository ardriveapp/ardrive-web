import 'package:ardrive/core/arfs/repository/file_metadata_repository.dart';
import 'package:ardrive/core/arfs/use_cases/get_file_metadata.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFileMetadataRepository extends Mock
    implements FileMetadataRepository {}

void main() {
  late GetFileMetadata useCase;
  late MockFileMetadataRepository repository;

  setUp(() {
    repository = MockFileMetadataRepository();
    useCase = GetFileMetadata(repository);
  });

  group('GetFileMetadata', () {
    const testFileId = 'test-file-id';
    final testMetadata = FileMetadata(
      id: testFileId,
      name: 'test-file.txt',
      dataTxId: 'data-tx-id',
      contentType: 'text/plain',
      size: 1024,
      lastModifiedDate: DateTime(2024),
      customMetadata: {'key': 'value'},
    );

    test('call returns FileMetadataResult with metadata for multiple files',
        () async {
      final fileIds = ['file1', 'file2'];
      final expectedResult = FileMetadataResult(
        metadata: {
          'file1': testMetadata,
          'file2': testMetadata,
        },
        failures: [],
      );

      when(() => repository.getFileMetadata(fileIds))
          .thenAnswer((_) async => expectedResult);

      final result = await useCase(fileIds);

      expect(result.metadata, expectedResult.metadata);
      expect(result.failures, isEmpty);
      verify(() => repository.getFileMetadata(fileIds)).called(1);
    });

    test('getMetadataForFile returns FileMetadata for single file', () async {
      final expectedResult = FileMetadataResult(
        metadata: {testFileId: testMetadata},
        failures: [],
      );

      when(() => repository.getFileMetadata([testFileId]))
          .thenAnswer((_) async => expectedResult);

      final result = await useCase.getMetadataForFile(testFileId);

      expect(result, testMetadata);
      verify(() => repository.getFileMetadata([testFileId])).called(1);
    });
  });
}
