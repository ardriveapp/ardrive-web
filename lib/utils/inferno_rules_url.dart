import 'package:ardrive/misc/resources.dart';

String getInfernoUrlForCurrentLocalization(String localeName) {
  final infernoRulesLinkMap = {
    'zh': Resources.infernoRulesLinkZh,
    'en': Resources.infernoRulesLinkEn
  };

  final urlForCurrentLocalization = infernoRulesLinkMap[localeName];

  return urlForCurrentLocalization ?? Resources.infernoRulesLinkEn;
}
