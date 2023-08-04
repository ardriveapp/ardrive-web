import 'package:ardrive/misc/misc.dart';
import 'package:ardrive/utils/open_url.dart';

Future<void> openFeedbackSurveyUrl() {
  return openUrl(url: Resources.surveyFeedbackFormUrl);
}
