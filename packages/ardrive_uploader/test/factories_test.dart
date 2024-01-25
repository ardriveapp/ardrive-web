import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:ardrive_uploader/src/d2n_streamed_upload.dart';
import 'package:ardrive_uploader/src/data_bundler.dart';
import 'package:ardrive_uploader/src/turbo_streamed_upload.dart';
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

    test('should return D2NStreamedUpload for UploadType.d2n', () {
      var streamedUpload = uploadFactory.fromUploadType(UploadType.d2n);
      expect(streamedUpload, isA<D2NStreamedUpload>());
    });

    test('should return TurboStreamedUpload for UploadType.turbo', () {
      var streamedUpload = uploadFactory.fromUploadType(UploadType.turbo);
      expect(streamedUpload, isA<TurboStreamedUpload>());

      // Additional check to verify TurboUploadService initialization
      var turboUploadUri =
          (streamedUpload as TurboStreamedUpload).service.turboUploadUri;
      expect(turboUploadUri, equals(mockUri));
    });

    // TODO: implement new tests here
  });
}
