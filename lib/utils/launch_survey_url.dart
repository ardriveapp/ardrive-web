import 'package:url_launcher/url_launcher.dart';

Future<void> launchSurveyURL() async {
  const url = 'https://ardrive.typeform.com/UserSurvey';
  if (await canLaunch(url)) {
    await launch(url);
  } else {
    throw 'Could not launch $url';
  }
}
