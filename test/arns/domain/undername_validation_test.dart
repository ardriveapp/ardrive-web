import 'package:ardrive/arns/domain/undername_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('validateUndername', () {
    test('accepts letters, digits, - and _ starting with a letter or digit',
        () {
      for (final undername in ['blog', 'v2', '2024-report', 'my_site', 'A']) {
        expect(validateUndername(undername, name: 'ardrive'), isNull,
            reason: undername);
      }
    });

    test('@ is the name itself and always valid', () {
      expect(validateUndername('@', name: 'a' * 63), isNull);
    });

    test('rejects an empty undername', () {
      expect(validateUndername('', name: 'ardrive'), UndernameProblem.empty);
    });

    test('rejects a leading - or _ and characters outside the rule', () {
      for (final undername in ['-blog', '_blog', 'my blog', 'blog.site', 'é']) {
        expect(
          validateUndername(undername, name: 'ardrive'),
          UndernameProblem.invalid,
          reason: undername,
        );
      }
    });

    test('61 characters is the longest undername', () {
      expect(validateUndername('a' * 61, name: 'x'), isNull);
      expect(validateUndername('a' * 62, name: 'x'), UndernameProblem.tooLong);
    });

    test('undername_name must fit in 63 characters', () {
      // 30 + '_' + 32 = 63
      expect(validateUndername('a' * 30, name: 'b' * 32), isNull);
      expect(
        validateUndername('a' * 31, name: 'b' * 32),
        UndernameProblem.labelTooLong,
      );
    });
  });

  test('literalArNSName joins with _ and maps @ to the name', () {
    expect(literalArNSName('blog', 'ardrive'), 'blog_ardrive');
    expect(literalArNSName('@', 'ardrive'), 'ardrive');
  });
}
