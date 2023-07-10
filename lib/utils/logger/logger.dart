import 'package:ardrive/services/config/config_service.dart';
import 'package:logger/logger.dart';

final logger = Logger(filter: Filter(), printer: SimpleLogPrinter());

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
