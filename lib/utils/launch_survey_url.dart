import 'package:ardrive/misc/resources.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> launchSurveyURL() async {
  const url = Resources.surveyFeedbackFormUrl;
  if (await canLaunch(url)) {
    await launch(url);
  } else {
    throw 'Could not launch $url';
  }
}
