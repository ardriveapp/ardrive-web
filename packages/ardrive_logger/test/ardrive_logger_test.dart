import 'package:ardrive_logger/src/logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockLoggerExporter extends Mock implements LogExporter {}

void main() {
  late Logger logger;
  late MockLoggerExporter exporter;
  final logExportInfo = LogExportInfo(
    emailBody: '',
    emailSubject: '',
    shareText: '',
    shareSubject: '',
    emailSupport: '',
  );

  setUp(() {
    exporter = MockLoggerExporter();
    logger = Logger(logExporter: exporter);
    registerFallbackValue(logExportInfo);
  });

  group('LogExporter integration with Logger', () {
    test('should export the logs when export logs is called', () {
      when(() => exporter.exportLogs(
            logs: any(named: 'logs'),
            info: logExportInfo,
            share: true,
            shareAsEmail: true,
          )).thenAnswer((_) => Future.value());

      logger.d('test');

      logger.exportLogs(share: true, shareAsEmail: true, info: logExportInfo);

      verify(() => exporter.exportLogs(
            logs: any(named: 'logs'),
            info: logExportInfo,
            share: true,
            shareAsEmail: true,
          )).called(1);
    });
  });
}
