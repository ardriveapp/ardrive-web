import 'package:ardrive/misc/resources.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> launchSurveyURL() async {
  const url = Resources.surveyFeedbackFormUrl;
  final uri = Uri.parse(url);

  if (await canLaunchUrl(uri)) {
    await launchUrl(uri);
  } else {
    throw 'Could not launch $url';
  }
}
