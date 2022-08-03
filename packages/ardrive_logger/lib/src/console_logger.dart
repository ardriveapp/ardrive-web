import 'package:logger/logger.dart';

import 'ardrive_logger.dart';

class ConsoleLogger implements ArDriveLogger {
  ConsoleLogger(this._logger);

  final Logger _logger;

  @override
  void debug(String message, {String? error, StackTrace? stackTrace}) {
    _logger.d(message, error, stackTrace);
  }

  @override
  void error(String message, {String? error, StackTrace? stackTrace}) {
    _logger.e(message, error, stackTrace);
  }

  @override
  void info(String message, {String? error, StackTrace? stackTrace}) {
    _logger.i(message, error, stackTrace);
  }

  @override
  void warning(String message, {String? error, StackTrace? stackTrace}) {
    _logger.w(message, error, stackTrace);
  }
}
