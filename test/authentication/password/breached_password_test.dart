import 'package:ardrive/authentication/password/breached_password.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// SHA-1 of "password": 5BAA61E4C9B93F3F0682250B6CF8331B7EE68FD8.
const _prefix = '5BAA6';
const _suffix = '1E4C9B93F3F0682250B6CF8331B7EE68FD8';

void main() {
  late List<http.Request> requests;

  BreachedPasswordCheck checkAnswering(String body, {int status = 200}) {
    requests = [];
    return BreachedPasswordCheck(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(body, status);
      }),
    );
  }

  test('a listed password is breached', () async {
    final check = checkAnswering(
        '0018A45C4D1DEF81644B54AB7F969B88D65:1\r\n$_suffix:9545824\r\n');

    expect(await check.isBreached('password'), isTrue);
  });

  test('only the first 5 characters of the hash leave the device', () async {
    final check = checkAnswering('$_suffix:1');

    await check.isBreached('password');

    final request = requests.single;
    expect(request.url.toString(),
        'https://api.pwnedpasswords.com/range/$_prefix');
    expect(request.headers['Add-Padding'], 'true');
    expect(request.url.pathSegments.last, _prefix);
    expect(request.url.query, isEmpty);
    expect(request.url.toString(), isNot(contains(_suffix)));
    expect(request.body, isEmpty);
  });

  test('an unlisted password, or a padding decoy, is not breached', () async {
    expect(
        await checkAnswering('0018A45C4D1DEF81644B54AB7F969B88D65:3')
            .isBreached('password'),
        isFalse);
    expect(await checkAnswering('$_suffix:0').isBreached('password'), isFalse);
  });

  test('says nothing when the service cannot be asked', () async {
    expect(
        await checkAnswering('', status: 503).isBreached('password'), isNull);

    final throwing = BreachedPasswordCheck(
        client: MockClient((_) async => throw http.ClientException('offline')));
    expect(await throwing.isBreached('password'), isNull);

    final slow = BreachedPasswordCheck(
      client: MockClient((_) => Future.delayed(
          const Duration(seconds: 1), () => http.Response('', 200))),
      timeout: const Duration(milliseconds: 10),
    );
    expect(await slow.isBreached('password'), isNull);
  });
}
