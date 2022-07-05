import 'package:ardrive/misc/resources.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> launchInfernoRulesURL(String localeName) async {
  final url = getUrlForCurrentLocalization(localeName);
  if (await canLaunch(url)) {
    await launch(url);
  } else {
    throw 'Could not launch $url';
  }
}

String getUrlForCurrentLocalization(String localeName) {
  final _infernoRulesLinkMap = {
    'zh': Resources.infernoRulesLinkZh,
    'en': Resources.infernoRulesLinkEn
  };

  final urlForCurrentLocalization = _infernoRulesLinkMap[localeName];

  return urlForCurrentLocalization ?? Resources.infernoRulesLinkEn;
}
