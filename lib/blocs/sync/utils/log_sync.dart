part of 'package:ardrive/blocs/sync/sync_cubit.dart';

void logSync(String message) {
  // ignore: avoid_print
  print('sync: $message');
}

void logSyncError(Object error, StackTrace stackTrace) {
  logSync(
    '''
    an error occurred during sync. \n
    error: ${error.toString()} \n
    stacktrace: ${stackTrace.toString()}
    ''',
  );
}
