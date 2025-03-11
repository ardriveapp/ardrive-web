// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_logger/ardrive_logger.dart';
import 'package:ardrive_logger/src/ardrive_context.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:share_plus/share_plus.dart';

Future<IOFile> _convertTextToIOFile({
  required String text,
  required String filePrefix,
}) {
  final fileName = '${filePrefix}_${DateTime.now().toIso8601String()}.txt';
  final dataBytes = utf8.encode(text);

  return IOFile.fromData(
    dataBytes,
    name: fileName,
    lastModifiedDate: DateTime.now(),
  );
}

enum LogLevel {
  debug,
  info,
  warning,
  error,
}

/// A callback that determines whether an error should be logged to Sentry.
/// If the callback returns false, the error will not be logged to Sentry.
typedef ShouldLogErrorCallback = bool Function(Object? error);

class Logger {
  final LogLevel _logLevel;
  final bool _storeLogsInMemory;
  final LogLevel _memoryLogLevel;
  final int _memoryLogSize;
  final LogExporter _logExporter;
  late ListQueue<String> inMemoryLogs;

  ArDriveContext _context = ArDriveContext();

  /// A null value means that all errors will be logged to Sentry.
  final ShouldLogErrorCallback? _shouldLogErrorCallback;

  Logger({
    LogLevel logLevel = LogLevel.debug,
    bool storeLogsInMemory = false,
    LogLevel memoryLogLevel = LogLevel.debug,
    int memoryLogSize = 500,
    required LogExporter logExporter,
    ShouldLogErrorCallback? shouldLogErrorCallback,
  })  : _logLevel = logLevel,
        _logExporter = logExporter,
        _storeLogsInMemory = storeLogsInMemory,
        _memoryLogLevel = memoryLogLevel,
        _shouldLogErrorCallback = shouldLogErrorCallback,
        _memoryLogSize = memoryLogSize {
    inMemoryLogs = ListQueue(storeLogsInMemory ? memoryLogSize : 0);
  }

  void d(String message) {
    log(LogLevel.debug, message);
  }

  void i(String message) {
    log(LogLevel.info, message);
    Sentry.addBreadcrumb(Breadcrumb(message: message));
  }

  void w(String message) {
    log(LogLevel.warning, message);
  }

  void e(String message, [Object? error, StackTrace? stackTrace]) {
    String errorMessage = message;

    if (error != null) {
      errorMessage += '\nError: $error';
    }

    if (stackTrace != null) {
      errorMessage += '\nStackTrace: $stackTrace';
    }

    log(LogLevel.error, errorMessage);

    Sentry.captureException(error ?? message, stackTrace: stackTrace);
  }

  ArDriveContext get context => _context;

  void setContext(ArDriveContext context) {
    _context = context;
    debugPrint('Context updated: ${_context.toString()}');

    Sentry.addBreadcrumb(Breadcrumb(message: _context.toString()));
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

  Future<void> initSentry() async {
    String dsn = const String.fromEnvironment('SENTRY_DSN');

    await SentryFlutter.init(
      (options) {
        options.beforeSend = _beforeSendEvent;
        options.beforeSendTransaction = _beforeSendTransaction;
        options.tracesSampleRate = 1.0;
        options.dsn = dsn;
      },
    );
  }

  FutureOr<SentryEvent?> _beforeSendEvent(SentryEvent event,
      {Hint? hint}) async {
    if (_shouldLogError(event.throwable)) {
      event = event.copyWith(
        user: SentryUser(
          id: null,
          username: null,
          email: null,
          ipAddress: null,
          geo: null,
          name: null,
          data: null,
        ),
      );

      return event;
    }

    return null;
  }

  FutureOr<SentryTransaction?> _beforeSendTransaction(
    SentryTransaction transaction,
  ) async {
    if (_shouldLogError(transaction.throwable)) {
      transaction = transaction.copyWith(
        user: SentryUser(
          id: null,
          username: null,
          email: null,
          ipAddress: null,
          geo: null,
          name: null,
          data: null,
        ),
      );

      return transaction;
    }

    return null;
  }

  bool _shouldLogError(Object? throwable) {
    if (throwable == null || throwable is UntrackedException) {
      return false;
    }

    if (_shouldLogErrorCallback != null) {
      return _shouldLogErrorCallback!(throwable);
    }

    return true;
  }

  Future<String> getLogs() async {
    final logs = inMemoryLogs.toList();
    return logs.join('\n');
  }

  Future<void> exportLogs({
    bool share = false,
    bool shareAsEmail = false,
    required LogExportInfo info,
  }) async {
    final logs = inMemoryLogs.toList();
    await _logExporter.exportLogs(
      share: share,
      shareAsEmail: shareAsEmail,
      logs: logs,
      info: info,
    );
  }

  bool _shouldLog(LogLevel level) {
    return level.index >= _logLevel.index;
  }

  bool _shouldSaveInMemory(LogLevel level) {
    return _storeLogsInMemory && level.index >= _memoryLogLevel.index;
  }
}

abstract class LogExporter {
  Future<void> exportLogs({
    bool share = false,
    bool shareAsEmail = false,
    required Iterable<String> logs,
    required LogExportInfo info,
  });

  factory LogExporter() {
    return _LogExporter();
  }
}

class _LogExporter implements LogExporter {
  @override
  Future<void> exportLogs({
    bool share = false,
    bool shareAsEmail = false,
    required Iterable<String> logs,
    required LogExportInfo info,
  }) async {
    String logString = '';

    for (final log in logs) {
      logString += '$log\n';
    }

    final file = await _convertTextToIOFile(
      text: logString,
      filePrefix: info.filePrefix,
    );

    /// prompt the user to select a location to save the file
    if (kIsWeb || (!share && !shareAsEmail)) {
      ArDriveIO().saveFile(file);
      return;
    }

    final mobileIO = ArDriveIO() as MobileIO;

    // saves the file on the app directory so that it can be shared
    await mobileIO.saveFile(file, true);

    if (share) {
      _exportWithNativeShare(file, info);
      return;
    }

    if (shareAsEmail) {
      _shareAsEmail(file, info);
      return;
    }
  }

  Future<void> _shareAsEmail(IOFile file, LogExportInfo info) async {
    final Email email = Email(
      body: info.emailBody,
      subject: info.emailSubject,
      recipients: [info.emailSupport],
      attachmentPaths: [await getDefaultAppDir() + file.name],
      isHTML: false,
    );

    try {
      await FlutterEmailSender.send(email);

      return;
    } catch (error) {
      debugPrint('Failed to send email');
    }
  }

  Future<void> _exportWithNativeShare(
    IOFile file,
    LogExportInfo info,
  ) async {
    final filePath = await getDefaultAppDir() + file.name;

    Share.shareXFiles(
      [XFile(filePath)],
      text: info.shareText,
      subject: info.shareSubject,
    );
  }
}

class LogExportInfo {
  final String filePrefix = 'ardrive_logs';
  final String emailSubject;
  final String emailBody;
  final String shareText;
  final String shareSubject;
  final String emailSupport;

  LogExportInfo({
    required this.emailSubject,
    required this.emailBody,
    required this.shareText,
    required this.shareSubject,
    required this.emailSupport,
  });
}
