@TestOn('browser')
import 'dart:html';

import 'package:test/test.dart';

void main() {
  group('Serialize and Deserialze Tags With AVRO', () {
    test('.split() splits the string on the delimiter', () {
      print(window.toString());
      var string = 'foo,bar,baz';
      expect(string.split(','), equals(['foo', 'bar', 'baz']));
    });

    test('.trim() removes surrounding whitespace', () {
      var string = '  foo ';
      expect(string.trim(), equals('foo'));
    });
  });

  group('int', () {
    test('.remainder() returns the remainder of division', () {
      expect(11.remainder(3), equals(2));
    });

    test('.toRadixString() returns a hex string', () {
      expect(11.toRadixString(16), equals('b'));
    });
  });
}
