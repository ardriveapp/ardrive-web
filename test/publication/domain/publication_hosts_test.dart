import 'package:ardrive/publication/domain/publication_hosts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final page = Uri.parse('https://adaicvhe.turbo-gateway.com/PageManifest/');
  final gateway = Uri.parse('https://turbo-gateway.com');

  bool mayFetch(String url) =>
      publicationMayFetch(Uri.parse(url), page: page, gateway: gateway);

  test('the page may fetch from its own host and its gateway', () {
    expect(mayFetch('https://adaicvhe.turbo-gateway.com/icon-32.png'), isTrue);
    expect(mayFetch('https://turbo-gateway.com/raw/abc'), isTrue);
    expect(mayFetch('https://xyz.turbo-gateway.com/abc'), isTrue);
    expect(mayFetch('icon-32.png'), isTrue);
    expect(mayFetch('/raw/abc'), isTrue);
    expect(mayFetch('//turbo-gateway.com/raw/abc'), isTrue);
  });

  test('and from nowhere else', () {
    expect(mayFetch('https://tracker.example/pixel.png'), isFalse);
    expect(mayFetch('//tracker.example/pixel.png'), isFalse);
    expect(mayFetch('https://arweave.net/abc'), isFalse);
    expect(mayFetch('https://turbo-gateway.com.evil.example/x.png'), isFalse);
    expect(mayFetch('https://evilturbo-gateway.com/x.png'), isFalse);
    expect(mayFetch('data:image/png;base64,AAAA'), isFalse);
  });
}
