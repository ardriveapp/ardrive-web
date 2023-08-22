import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/services/config/config_service.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:logger/logger.dart';

final logger = Logger(
  filter: Filter(),
  printer: SimpleLogPrinter(),
  output: LogExporterSystem(),
);

class Filter extends LogFilter {
  @override
  bool shouldLog(LogEvent event) {
    // Print info, warning, error and wtf in production
    if (isProduction && event.level.index < 2) {
      return false;
    }

    return true;
  }
}

class SimpleLogPrinter extends LogPrinter {
  static final levelPrefixes = {
    Level.verbose: 'verbose',
    Level.debug: 'debug',
    Level.info: 'info',
    Level.warning: 'warning',
    Level.error: 'error',
    Level.wtf: 'wtf',
  };

  @override
  List<String> log(LogEvent event) {
    var time = event.time.toIso8601String();
    var output = StringBuffer('level=${levelPrefixes[event.level]} time=$time');

    if (event.message is String) {
      output.write(' msg="${event.message}"');
    } else if (event.message is Map) {
      event.message.entries.forEach((entry) {
        if (entry.value is num) {
          output.write(' ${entry.key}=${entry.value}');
        } else {
          output.write(' ${entry.key}="${entry.value}"');
        }
      });
    }

    if (event.error != null) {
      output.write(' error="${event.error}"');
    }

    return [output.toString()];
  }
}

bool isProduction = false;

setLoggerLevel(Flavor flavor) {
  isProduction = flavor == Flavor.production;
}

class LogExporterSystem extends LogOutput {
  static LogExporterSystem? _instance;
  final List<String> _logCache = [];
  final int _maxCacheSize = 10000; // Define a suitable max cache size

  // Private constructor
  LogExporterSystem._();

  factory LogExporterSystem() {
    return _instance ??= LogExporterSystem._();
  }

  void log(String message) {
    // Prune the log cache if it's too big
    if (_logCache.length >= _maxCacheSize) {
      _logCache.removeAt(0);
    }

    _logCache.add(message);
  }

  Future<void> exportLogs() async {
    // Convert log to JSON
    String logString = '';

    for (final log in _logCache) {
      logString += '$log\n';
    }

    // Write the log to a file
    _convertTextToIOFile(logString).then((file) async {
      ArDriveIO().saveFile(file);
    });
  }

  @override
  void output(OutputEvent event) {
    event.lines.forEach(log);
  }
}

Future<IOFile> _convertTextToIOFile(String text) {
  final fileName = 'ardrive_logs_${DateTime.now().toIso8601String()}.txt';
  final dataBytes = utf8.encode(text) as Uint8List;

  return IOFile.fromData(
    dataBytes,
    name: fileName,
    lastModifiedDate: DateTime.now(),
  );
}
