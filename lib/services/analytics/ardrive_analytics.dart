import 'package:firebase_analytics/firebase_analytics.dart';

abstract class ArDriveAnalytics {
  void trackScreenEvent({
    required String screenName,
    required String eventName,
    Map<String, dynamic> dimensions = const {},
    Map<String, num> metrics = const {},
  });

  void trackEvent({
    required String eventName,
    Map<String, dynamic> dimensions = const {},
    Map<String, num> metrics = const {},
  });

  void setUserId(String userId);
}

class CompoundArDriveAnalytics extends ArDriveAnalytics {
  final List<ArDriveAnalytics> _implementations;
  CompoundArDriveAnalytics(this._implementations);

  @override
  void trackScreenEvent({
    required String screenName,
    required String eventName,
    Map<String, dynamic> dimensions = const {},
    Map<String, num> metrics = const {},
  }) {
    for (final implementation in _implementations) {
      implementation.trackScreenEvent(
        screenName: screenName,
        eventName: eventName,
        dimensions: dimensions,
        metrics: metrics,
      );
    }
  }

  @override
  void trackEvent({
    required String eventName,
    Map<String, dynamic> dimensions = const {},
    Map<String, num> metrics = const {},
  }) {
    for (final implementation in _implementations) {
      implementation.trackEvent(
        eventName: eventName,
        dimensions: dimensions,
        metrics: metrics,
      );
    }
  }

  @override
  void setUserId(String userId) {
    for (final implementation in _implementations) {
      implementation.setUserId(userId);
    }
  }
}

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
