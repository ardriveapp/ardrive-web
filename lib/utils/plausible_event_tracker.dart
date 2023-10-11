import 'dart:convert';

import 'package:ardrive/utils/logger/logger.dart';
import 'package:http/http.dart' as http;

class PlausibleEventTracker {
  static Future<void> track(String name, String url) async {
    final response = await http.post(
      Uri.parse('https://plausible.io/api/event'),
      body: jsonEncode({
        'name': name,
        'url': 'http://app.ardrive.io/$url',
        'domain': 'app.ardrive.io',
      }),
    );

    logger.d('Plausible response: ${response.statusCode}');
  }
}
