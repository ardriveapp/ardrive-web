import 'dart:convert';

import 'package:ardrive/services/analytics/ardrive_analytics.dart';
import 'package:http/http.dart' as http;
import 'package:pendo_sdk/pendo_sdk.dart';
// import 'package:pendo_sdk/pendo_sdk.dart';

class PendoAgentAnalytics implements ArDriveAnalytics {
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
    final Map<String, dynamic> visitorData = {};
    final Map<String, dynamic> accountData = {};

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
      ...dimensions,
      ...metrics,
    };

    await PendoFlutterPlugin.track(
      '$screenName.$eventName',
      eventParameters,
    );
  }
}

// TODO: IMPLEMENT WITH HTTP API CALLS
class PendoAPIAnalytics implements ArDriveAnalytics {
  String? _userId;
  final _httpClient = http.Client();
  late final String _pendoKey;

  PendoAPIAnalytics({required String pendoKey}) : _pendoKey = pendoKey;

  @override
  void clearUserId() async {
    _userId = null;
  }

  @override
  void setUserId(String userId) async {
    final Map<String, dynamic> visitorData = {};
    final Map<String, dynamic> accountData = {};

    if (_userId != null && _userId == userId) {
      return;
    }

    _userId = userId;
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

    try {
      await _httpClient
          .post(
        Uri.parse('https://app.pendo.io/data/track'),
        headers: {
          'Content-Type': 'application/json',
          'x-pendo-integration-key': _pendoKey,
        },
        body: jsonEncode({
          "type": "track",
          "event": eventName,
          "visitorId": _userId ?? 'anonymous',
          "accountId": _userId ?? 'anonymous',
          "timestamp": DateTime.now().millisecondsSinceEpoch,
          "properties": eventParameters,
          "context": {
            //"ip": "76.253.187.23",
            //"userAgent": "Mozilla/5.0",
            //"url": "http://MuqrevujORTeLIzvMFcBSW.vitaO",
            //"title": "My Page - Admin"
          }
        }),
      )
          .then((res) {
        if (res.statusCode != 200) {
          print('[A8s] ERROR SENDING TRACK EVENT! Status: ${res.statusCode}');
        }
      });
    } catch (e) {
      print('[A8s] TRACKING ERROR! ${e}');
    }
  }

  @override
  void trackScreenEvent({
    required String screenName,
    required String eventName,
    Map<String, dynamic> dimensions = const {},
    Map<String, num> metrics = const {},
  }) async {
    final eventParameters = {
      ...dimensions,
      ...metrics,
    };

    try {
      await _httpClient
          .post(
        Uri.parse('https://app.pendo.io/data/track'),
        headers: {
          'Content-Type': 'application/json',
          'x-pendo-integration-key': _pendoKey,
        },
        body: jsonEncode({
          "type": "track",
          "event": '$screenName.$eventName',
          "visitorId": _userId ?? 'anonymous',
          "accountId": _userId ?? 'anonymous',
          "timestamp": DateTime.now().millisecondsSinceEpoch,
          "properties": eventParameters,
          "context": {
            //"ip": "76.253.187.23",
            //"userAgent": "Mozilla/5.0",
            //"url": "http://MuqrevujORTeLIzvMFcBSW.vitaO",
            //"title": "My Page - Admin"
          }
        }),
      )
          .then((res) {
        if (res.statusCode != 200) {
          print('[A8s] ERROR SENDING TRACK EVENT! Status: ${res.statusCode}');
        }
      });
    } catch (e) {
      print('[A8s] TRACKING ERROR! ${e}');
    }
  }
}
