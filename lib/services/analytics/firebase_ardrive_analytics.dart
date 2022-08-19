import 'package:firebase_analytics/firebase_analytics.dart';

import 'ardrive_analytics.dart';

class FirebaseArDriveAnalytics extends ArDriveAnalytics {
  @override
  void trackScreenEvent({
    required String screenName,
    required String eventName,
    Map<String, dynamic> dimensions = const {},
    Map<String, num> metrics = const {},
  }) {
    final eventParameters = {
      ...dimensions,
      ...metrics,
    };
    FirebaseAnalytics.instance.logEvent(
      name: '${screenName}.${eventName}',
      parameters: eventParameters,
    );
  }

  @override
  void trackEvent({
    required String eventName,
    Map<String, dynamic> dimensions = const {},
    Map<String, num> metrics = const {},
  }) {
    final eventParameters = {
      ...dimensions,
      ...metrics,
    };
    FirebaseAnalytics.instance.logEvent(
      name: eventName,
      parameters: eventParameters,
    );
  }

  @override
  void setUserId(String userId) {
    FirebaseAnalytics.instance.setUserId(id: userId);
  }
}
