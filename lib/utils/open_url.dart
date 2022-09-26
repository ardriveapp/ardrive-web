import 'package:url_launcher/url_launcher.dart';

Future<void> openUrl({
  required String url,
  bool openInWebview = false,
  String? webOnlyWindowName,
}) async {
  final uri = Uri.parse(url);
  final mode = openInWebview
      ? LaunchMode.platformDefault
      : LaunchMode.externalApplication;

  if (await canLaunchUrl(uri)) {
    await launchUrl(
      uri,
      mode: mode,
      webOnlyWindowName: webOnlyWindowName,
    );
  } else {
    throw 'Could not launch $url';
  }
}
