import 'package:logger/logger.dart';

import 'console_logger.dart';

/// Logger
abstract class ArDriveLogger {
  factory ArDriveLogger() => ConsoleLogger(Logger());

  void debug(String message, {String? error, StackTrace? stackTrace});
  void info(String message, {String? error, StackTrace? stackTrace});
  void warning(String message, {String? error, StackTrace? stackTrace});
  void error(String message, {String? error, StackTrace? stackTrace});
}
