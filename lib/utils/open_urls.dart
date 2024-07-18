import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/open_url.dart';

Future<void> openDocs() {
  return openUrl(url: Resources.docsLink);
}

Future<void> openHelp() {
  return openUrl(url: Resources.helpLink);
}
