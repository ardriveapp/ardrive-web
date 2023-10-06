import 'package:ardrive_utils/ardrive_utils.dart';

Future<R> safeArConnectAction<R>(
  TabVisibilitySingleton tabVisibility,
  Future<R> Function(dynamic) action, [
  dynamic args,
]) async {
  try {
    R result = await action(args);

    return result;
  } catch (e) {
    late R result;

    if (!tabVisibility.isTabFocused()) {
      // logger.i(
      //   'Running safe ArConnect action while user is not focusing the tab.'
      //   'Waiting...',
      // );

      await tabVisibility.onTabGetsFocusedFuture(() async {
        result = await safeArConnectAction(tabVisibility, action, args);
      });

      return result;
    } else {
      // logger.sd('Error while running safe ArConnect action. Re-throwing...');
      rethrow;
    }
  }
}
