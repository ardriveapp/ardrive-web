import 'package:ardrive/misc/resources.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> launchInfernoRulesURL(String localeName) async {
  final url = getUrlForCurrentLocalization(localeName);
  final uri = Uri.parse(url);
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  } else {
    throw 'Could not launch $url';
  }
}

String getUrlForCurrentLocalization(String localeName) {
  final infernoRulesLinkMap = {
    'zh': Resources.infernoRulesLinkZh,
    'en': Resources.infernoRulesLinkEn
  };

  final urlForCurrentLocalization = infernoRulesLinkMap[localeName];

  return urlForCurrentLocalization ?? Resources.infernoRulesLinkEn;
}
