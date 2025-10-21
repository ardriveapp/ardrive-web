import 'package:ardrive/components/side_bar.dart';
import 'package:ardrive/misc/resources.dart';
import 'package:ardrive/utils/open_url.dart';
import 'package:flutter/widgets.dart';

Future<void> openDocs() {
  return openUrl(url: Resources.docsLink);
}

Future<void> openHelp(BuildContext context) {
  return showSupportModal(context: context);
}
