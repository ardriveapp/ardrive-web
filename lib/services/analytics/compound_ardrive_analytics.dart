import 'ardrive_analytics.dart';

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
