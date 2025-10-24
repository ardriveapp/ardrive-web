// ignore_for_file: avoid_web_libraries_in_flutter

@JS()
library eml_parser;

import 'package:js/js.dart';
import 'dart:js_util' as js_util;
import 'dart:convert';
import 'models/parsed_email.dart';

/// External reference to the global ArDriveEmlParser.parseEml function
@JS('window.ArDriveEmlParser.parseEml')
external dynamic _parseEml(String emlContent);

class EmlParserWeb {
  /// Parse EML file content
  static Future<ParsedEmail> parse(String emlContent) async {
    try {
      // Call JS function which now returns a Promise
      final jsPromise = _parseEml(emlContent);

      // Convert Promise to Future
      final jsResult = await js_util.promiseToFuture(jsPromise);

      // Convert JS object to Dart Map
      // js_util.dartify can return LinkedMap, so we need to convert it properly
      final dynamic dartified = js_util.dartify(jsResult);

      // Convert to proper Map<String, dynamic> by encoding and decoding as JSON
      final String jsonString = jsonEncode(dartified);
      final Map<String, dynamic> result = jsonDecode(jsonString) as Map<String, dynamic>;

      // Check for success
      if (result['success'] != true) {
        throw Exception(result['error'] ?? 'Failed to parse EML file');
      }

      // Convert to Dart model
      return ParsedEmail.fromJS(result);
    } catch (e) {
      throw Exception('EML parsing error: $e');
    }
  }
}
