import 'package:ardrive/utils/plausible_event_tracker/plausible_event_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late List<http.Request> sent;

  Future<void> trackEvent() => http.runWithClient(
        () => PlausibleEventTracker.trackPageview(
          page: PlausiblePageView.welcomePage,
        ),
        () => MockClient((request) async {
          sent.add(request);
          return http.Response('ok', 202);
        }),
      );

  setUp(() => sent = []);
  tearDown(() => PlausibleEventTracker.disabled = false);

  test('sends an event when enabled', () async {
    await trackEvent();

    expect(sent, hasLength(1));
    expect(sent.single.url.host, 'plausible.io');
  });

  test('sends nothing when disabled', () async {
    PlausibleEventTracker.disabled = true;

    await trackEvent();

    expect(sent, isEmpty);
  });
}
