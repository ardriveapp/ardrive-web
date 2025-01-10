import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/d2n_streamed_upload.dart';
import 'package:ardrive_uploader/src/data_bundler.dart';
import 'package:ardrive_uploader/src/turbo_streamed_upload.dart';
import 'package:ardrive_uploader/src/turbo_upload_service.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pst/pst.dart';
import 'package:test/test.dart';

class MockARFSUploadMetadataGenerator extends Mock
    implements ARFSUploadMetadataGenerator {}

class MockArweave extends Mock implements Arweave {}

class MockPstService extends Mock implements PstService {}

class MockDataBundlerFactory extends Mock implements DataBundlerFactory {}

class MockDataBundler extends Mock implements DataBundler {}

class MockStreamedUploadFactory extends Mock implements StreamedUploadFactory {}

class MockFileUploadTask extends Mock implements FileUploadTask {}

class MockFile extends Mock implements IOFile {}

class MockUploadTask extends Mock implements UploadTask {}

void main() {
  setUpAll(() {
    registerFallbackValue(UploadType.turbo);
  });

  group('_DataBundlerFactory', () {
    late MockARFSUploadMetadataGenerator mockMetadataGenerator;
    late MockArweave mockArweave;
    late MockPstService mockPstService;
    late DataBundlerFactory dataBundlerFactory;

    setUp(() {
      mockMetadataGenerator = MockARFSUploadMetadataGenerator();
      mockArweave = MockArweave();
      mockPstService = MockPstService();
      dataBundlerFactory = DataBundlerFactory(
        metadataGenerator: mockMetadataGenerator,
        arweaveService: mockArweave,
        pstService: mockPstService,
      );
    });

    test('should return BDIDataBundler for UploadType.turbo', () {
      var bundler = dataBundlerFactory.createDataBundler(UploadType.turbo);
      expect(bundler, isA<BDIDataBundler>());
    });

    test('should return D2NDataBundler for UploadType.d2n', () {
      var bundler = dataBundlerFactory.createDataBundler(UploadType.d2n);
      expect(bundler, isA<DataTransactionBundler>());
    });
  });

  group('UploadFileStrategyFactory', () {
    late MockDataBundlerFactory mockDataBundlerFactory;
    late UploadFileStrategyFactory strategyFactory;
    late MockStreamedUploadFactory mockStreamedUploadFactory;

    setUp(() {
      mockDataBundlerFactory = MockDataBundlerFactory();
      mockStreamedUploadFactory = MockStreamedUploadFactory();
      strategyFactory = UploadFileStrategyFactory(
          mockDataBundlerFactory, mockStreamedUploadFactory);
    });

    test('should return UploadFileUsingDataItemFiles for UploadType.turbo', () {
      when(() => mockDataBundlerFactory.createDataBundler(any()))
          .thenReturn(MockDataBundler());

      var strategy =
          strategyFactory.createUploadStrategy(type: UploadType.turbo);

      expect(strategy, isA<UploadFileUsingDataItemFiles>());
    });

    test('should return UploadFileUsingDataItemFiles for UploadType.d2n', () {
      when(() => mockDataBundlerFactory.createDataBundler(any()))
          .thenReturn(MockDataBundler());

      var strategy = strategyFactory.createUploadStrategy(type: UploadType.d2n);

      expect(strategy, isA<UploadFileUsingBundleStrategy>());
    });
  });
  group('StreamedUploadFactory', () {
    late Uri mockUri;
    late StreamedUploadFactory uploadFactory;

    setUp(() {
      mockUri = Uri.parse('https://example.com');
      uploadFactory = StreamedUploadFactory(turboUploadUri: mockUri);
    });

    test('should return D2NStreamedUpload for UploadType.d2n', () async {
      final task = MockFileUploadTask();
      when(() => task.type).thenReturn(UploadType.d2n);

      final streamedUpload = await uploadFactory.fromUploadType(task);
      expect(streamedUpload, isA<D2NStreamedUpload>());
    });

    group('TurboStreamedUpload', () {
      test('should use multipart for files equal or larger than 5MB', () async {
        final task = MockFileUploadTask();
        final file = MockFile();
        when(() => task.type).thenReturn(UploadType.turbo);
        when(() => task.file).thenReturn(file);
        when(() => file.length).thenAnswer((_) async => MiB(5).size);

        final streamedUpload = await uploadFactory.fromUploadType(task);
        expect(streamedUpload, isA<TurboStreamedUpload>());
        expect((streamedUpload as TurboStreamedUpload).service,
            isA<TurboUploadServiceMultipart>());
      });

      test('should use chunked for files smaller than 5MB', () async {
        final task = MockFileUploadTask();
        final file = MockFile();
        when(() => task.type).thenReturn(UploadType.turbo);
        when(() => task.file).thenReturn(file);
        when(() => file.length).thenAnswer((_) async => MiB(4).size);

        final streamedUpload = await uploadFactory.fromUploadType(task);
        expect(streamedUpload, isA<TurboStreamedUpload>());
        expect((streamedUpload as TurboStreamedUpload).service,
            isA<TurboUploadServiceNonChunked>());
      });

      test('should use multipart for non-file upload tasks', () async {
        final task = MockUploadTask();
        when(() => task.type).thenReturn(UploadType.turbo);

        final streamedUpload = await uploadFactory.fromUploadType(task);
        expect(streamedUpload, isA<TurboStreamedUpload>());
        expect((streamedUpload as TurboStreamedUpload).service,
            isA<TurboUploadServiceNonChunked>());
      });
    });
  });
}
