import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> launchInfernoRulesURL(BuildContext context) async {
  final url = _getUrlForCurrentLocalization(context);
  if (await canLaunch(url)) {
    await launch(url);
  } else {
    throw 'Could not launch $url';
  }
}

String _getUrlForCurrentLocalization(BuildContext context) {
  if (appLocalizationsOf(context).localeName == 'zh') {
    return R.infernoRulesLinkZh;
  }
  return R.infernoRulesLinkEn;
}
