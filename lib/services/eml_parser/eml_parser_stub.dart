import 'models/parsed_email.dart';

class EmlParserWeb {
  static Future<ParsedEmail> parse(String emlContent) {
    throw UnsupportedError('EML parsing is only supported on web platform');
  }
}
