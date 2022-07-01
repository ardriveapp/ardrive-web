import 'package:ardrive/misc/resources.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> launchInfernoRulesURL() async {
  const url = R.infernoRulesLink;
  if (await canLaunch(url)) {
    await launch(url);
  } else {
    throw 'Could not launch $url';
  }
}
