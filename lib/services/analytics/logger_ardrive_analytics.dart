import 'ardrive_analytics.dart';

class LoggerArDriveAnalytics extends ArDriveAnalytics {
  @override
  void trackScreenEvent({
    required String screenName,
    required String eventName,
    Map<String, dynamic> dimensions = const {},
    Map<String, num> metrics = const {},
  }) {
    print("""[A8s] Tracked Event:
    Screen: ${screenName}
    Name: ${evenName}
    Dimensions: ${dimensions}
    Metrics: ${metrics}""");
  }

  @override
  void trackEvent({
    required String eventName,
    Map<String, dynamic> dimensions = const {},
    Map<String, num> metrics = const {},
  }) {
    print("""[A8s] Tracked Event:
    Name: ${evenName}
    Dimensions: ${dimensions}
    Metrics: ${metrics}""");
  }

  @override
  void setUserId(String userId) {
    print("[A8s] Set user ID: ${userId}");
  }
}
