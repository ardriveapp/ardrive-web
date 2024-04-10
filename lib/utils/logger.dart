import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_logger/ardrive_logger.dart';

final logger = Logger(
  logLevel: LogLevel.debug,
  storeLogsInMemory: true,
  logExporter: LogExporter(),
  shouldLogErrorCallback: (error) {
    if (error is ActionCanceledException) {
      return false;
    }

    return true;
  },
);
