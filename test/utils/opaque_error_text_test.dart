import 'package:ardrive/utils/opaque_error_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('names what a release build prints for an exception', () {
    expect(isOpaqueErrorText("Instance of 'minified:Xy'"), isTrue);
    expect(isOpaqueErrorText('minified:Ab'), isTrue);
    expect(isOpaqueErrorText('My drive: minified:Ab'), isTrue);
    expect(isOpaqueErrorText("Instance of '_Opaque'"), isTrue);
  });

  test('leaves a message a person can read', () {
    expect(isOpaqueErrorText('Gateway timeout (504)'), isFalse);
    expect(isOpaqueErrorText('Exception: the gateway said no'), isFalse);
  });
}
