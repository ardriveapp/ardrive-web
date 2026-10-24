// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;

/// StreamSaver's helper page, `mitm.html` beside its `sw.js`, as
/// `web/js/StreamSaver.min.js` names it.
const _helper = 'Lhx_Luxz7N1lg1ODAsGMs_BYeFq5MQf1bPhOuJvyXhI/mitm.html';

void useGatewayForDownloadHelper(Uri gateway) {
  final saver = js_util.getProperty<Object?>(html.window, 'streamSaver');
  if (saver == null) return;
  js_util.setProperty(saver, 'mitm', gateway.resolve('/$_helper').toString());
}
