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
}
