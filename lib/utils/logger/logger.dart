import 'dart:collection';

import 'package:flutter/foundation.dart';

final logger = Logger(
  logLevel: kReleaseMode ? LogLevel.warning : LogLevel.debug,
  storeLogsInMemory: true,
);

enum LogLevel {
  debug,
  info,
  warning,
  error,
}

class Logger {
  final LogLevel _logLevel;
  final bool _storeLogsInMemory;
  final LogLevel _memoryLogLevel;
  final int _memoryLogSize;
  late ListQueue<String> inMemoryLogs;

  Logger({
    LogLevel logLevel = LogLevel.warning,
    bool storeLogsInMemory = false,
    LogLevel memoryLogLevel = LogLevel.debug,
    int memoryLogSize = 500,
  })  : _logLevel = logLevel,
        _storeLogsInMemory = storeLogsInMemory,
        _memoryLogLevel = memoryLogLevel,
        _memoryLogSize = memoryLogSize {
    inMemoryLogs = ListQueue(storeLogsInMemory ? memoryLogSize : 0);
  }

  void d(String message) {
    log(LogLevel.debug, message);
  }

  void i(String message) {
    log(LogLevel.info, message);
  }

  void w(String message) {
    log(LogLevel.warning, message);
  }

  void e(String message) {
    log(LogLevel.error, message);
  }

  void log(LogLevel level, String message) {
    final shouldLog = _shouldLog(level);
    final shouldSaveInMemory = _shouldSaveInMemory(level);
    String? finalMessage;

    if (shouldLog || shouldSaveInMemory) {
      DateTime time = DateTime.now();
      finalMessage =
          '[${level.name.substring(0, 1).toUpperCase()}][${time.toIso8601String()}] $message';
    }

    if (finalMessage != null) {
      if (shouldLog) {
        // ignore: avoid_print
        print(finalMessage);
      }

      if (shouldSaveInMemory) {
        if (inMemoryLogs.length == _memoryLogSize) {
          inMemoryLogs.removeFirst();
        }

        inMemoryLogs.add(finalMessage);
      }
    }
  }

  bool _shouldLog(LogLevel level) {
    return level.index >= _logLevel.index;
  }

  bool _shouldSaveInMemory(LogLevel level) {
    return _storeLogsInMemory && level.index >= _memoryLogLevel.index;
  }
}
