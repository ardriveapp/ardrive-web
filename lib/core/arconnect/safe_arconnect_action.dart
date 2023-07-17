import 'package:ardrive/utils/html/html_util.dart';
import 'package:ardrive/utils/logger/logger.dart';

Future<R> safeArConnectAction<R>(
  TabVisibilitySingleton tabVisibility,
  Future<R> Function(dynamic) action, [
  dynamic args,
]) async {
  try {
    logger.d('Calling action');
    R result = await action(args);
    logger.d('Action called');
    logger.d('Result: $result');

    return result;
  } catch (e) {
    logger.e('An issue occured. Verifying if the tab is focused...', e);

    late R result;

    if (!tabVisibility.isTabFocused()) {
      logger.i(
        'Preparing snapshot transaction while user is not focusing the tab. Waiting...',
      );
      logger.e('Error preparing bundle', e);

      await tabVisibility.onTabGetsFocusedFuture(() async {
        logger.i('Preparing bundle after get the focus...');

        result = await safeArConnectAction(tabVisibility, action, args);
      });

      logger.i('Preparing bundle after get the focus... Done');

      return result;
    } else {
      logger.e('Error preparing bundle', e);
      rethrow;
    }
  }
}
