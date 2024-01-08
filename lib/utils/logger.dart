import 'package:ardrive_logger/ardrive_logger.dart';

final logger = Logger(
  logLevel: LogLevel.debug,
  storeLogsInMemory: true,
  logExporter: LogExporter(),
);
