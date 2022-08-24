import 'package:ardrive/services/analytics/ardrive_analytics.dart';
import 'package:pendo_sdk/pendo_sdk.dart';

class PendoAnalytics implements ArDriveAnalytics {
  String? userId;

  @override
  void clearUserId() async {
    // End the current session, and start a new session with an anonymous visitor.
    await PendoFlutterPlugin.clearVisitor();

    // End the current session without starting a new one.
    await PendoFlutterPlugin.endSession();
  }

  @override
  void setUserId(String userId) async {
    final dynamic visitorData = {};
    final dynamic accountData = {};

    if (this.userId != null && this.userId == userId) {
      return;
    }

    this.userId = userId;

    await PendoFlutterPlugin.startSession(
      userId,
      userId,
      visitorData,
      accountData,
    );
  }

  @override
  void trackEvent({
    required String eventName,
    Map<String, dynamic> dimensions = const {},
    Map<String, num> metrics = const {},
  }) async {
    final eventParameters = {
      ...dimensions,
      ...metrics,
    };

    await PendoFlutterPlugin.track(eventName, eventParameters);
  }

  @override
  void trackScreenEvent({
    required String screenName,
    required String eventName,
    Map<String, dynamic> dimensions = const {},
    Map<String, num> metrics = const {},
  }) async {
    final eventParameters = {
      'eventName': eventName,
      ...dimensions,
      ...metrics,
    };

    await PendoFlutterPlugin.track(screenName, eventParameters);
  }
}
