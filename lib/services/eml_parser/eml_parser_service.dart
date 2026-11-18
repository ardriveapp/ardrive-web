import 'models/parsed_email.dart';
import 'eml_parser_stub.dart'
    if (dart.library.html) 'eml_parser_web.dart';

class EmlParserService {
  /// Parse EML file content and return structured email data
  static Future<ParsedEmail> parseEml(String emlContent) {
    return EmlParserWeb.parse(emlContent);
  }
}
