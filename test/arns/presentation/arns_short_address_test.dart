import 'package:ardrive/arns/presentation/widgets/arns_widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The linked ArNS wallet sat at four and four under the main address at
  // six and four (issue #2370).
  test('the linked wallet is shortened like every other address', () {
    expect(shortArNSAddress('7xKpH3nV9qR2bT5mW8cY4dF6gJ1kL3sA9eZ2uQ7q2Fd'),
        '7xKpH3...q2Fd');
  });
}
