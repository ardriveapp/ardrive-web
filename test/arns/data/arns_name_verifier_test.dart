import 'dart:async';

import 'package:ardrive/arns/data/arns_name_verifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _tx = 'FWswWiH1FMFnuzLFzpqzdgxOBlMS8L7DiP5MxUnWODE';

void main() {
  test('confirms a name the gateway resolves to the file', () async {
    final requests = <http.Request>[];
    final verifier = ArNSNameVerifier(
      gatewayUrl: () => 'https://turbo-gateway.com',
      client: MockClient((request) async {
        requests.add(request);
        return http.Response('', 200, headers: {'x-arns-resolved-id': _tx});
      }),
    );

    expect(await verifier.confirms('blog_acme', _tx), isTrue);
    expect(await verifier.confirms('blog_acme', 'other'), isFalse);
    expect(requests, hasLength(1), reason: 'cached for the session');
    expect(requests.single.method, 'HEAD');
    expect(
        requests.single.url.toString(), 'https://blog_acme.turbo-gateway.com/');
  });

  test('a failed or unresolved name is never shown', () async {
    final verifier = ArNSNameVerifier(
      gatewayUrl: () => 'https://turbo-gateway.com',
      client: MockClient((request) async {
        if (request.url.host.startsWith('gone')) {
          return http.Response('', 404);
        }
        throw http.ClientException('offline');
      }),
    );

    expect(await verifier.confirms('gone', _tx), isFalse);
    expect(await verifier.confirms('acme', _tx), isFalse);
  });

  test('a hint that is not a name is not requested', () async {
    var requested = false;
    final verifier = ArNSNameVerifier(
      gatewayUrl: () => 'https://turbo-gateway.com',
      client: MockClient((request) async {
        requested = true;
        return http.Response('', 200);
      }),
    );

    expect(await verifier.confirms('evil.com/x', _tx), isFalse);
    expect(requested, isFalse);
  });

  // A busy gateway once hid the name for the whole session, and a name
  // pointed elsewhere kept showing on the old file until a reload.
  group('answers are kept for a while', () {
    late DateTime now;
    late int requests;
    late http.Response Function() answer;
    late ArNSNameVerifier verifier;

    setUp(() {
      now = DateTime(2026, 10, 27, 12);
      requests = 0;
      verifier = ArNSNameVerifier(
        gatewayUrl: () => 'https://turbo-gateway.com',
        clock: () => now,
        client: MockClient((request) async {
          requests++;
          return answer();
        }),
      );
    });

    test('a failure is asked again after a minute', () async {
      answer = () => http.Response('', 429);
      expect(await verifier.confirms('blog_acme', _tx), isFalse);

      answer =
          () => http.Response('', 200, headers: {'x-arns-resolved-id': _tx});
      now = now.add(const Duration(seconds: 30));
      expect(await verifier.confirms('blog_acme', _tx), isFalse);
      now = now.add(const Duration(seconds: 31));
      expect(await verifier.confirms('blog_acme', _tx), isTrue);
      expect(requests, 2);
    });

    test('an answer is asked again after five minutes', () async {
      answer =
          () => http.Response('', 200, headers: {'x-arns-resolved-id': _tx});
      expect(await verifier.confirms('blog_acme', _tx), isTrue);

      answer = () =>
          http.Response('', 200, headers: {'x-arns-resolved-id': 'moved'});
      now = now.add(const Duration(minutes: 4));
      expect(await verifier.confirms('blog_acme', _tx), isTrue);
      now = now.add(const Duration(minutes: 2));
      expect(await verifier.confirms('blog_acme', _tx), isFalse);
      expect(requests, 2);
    });
  });

  test('at most four names are asked at once', () async {
    var running = 0;
    var most = 0;
    final release = Completer<void>();
    final verifier = ArNSNameVerifier(
      gatewayUrl: () => 'https://turbo-gateway.com',
      client: MockClient((request) async {
        running++;
        if (running > most) most = running;
        await release.future;
        running--;
        return http.Response('', 200, headers: {'x-arns-resolved-id': _tx});
      }),
    );

    final all = [
      for (var i = 0; i < 10; i++) verifier.confirms('name$i', _tx),
    ];
    await pumpEventQueue();
    expect(most, 4);
    release.complete();

    expect(await Future.wait(all), everyElement(isTrue));
    expect(most, 4);
  });
}
