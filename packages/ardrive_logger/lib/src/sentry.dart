import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

FutureOr<SentryEvent?> _beforeSend(SentryEvent event, {Hint? hint}) async {
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

Future<void> initSentry() async {
  await SentryFlutter.init(
    (options) {
      options.beforeSend = _beforeSend;
      options.tracesSampleRate = 1.0;
    },
  );
}
