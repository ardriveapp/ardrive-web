import 'dart:convert';

import 'package:ardrive/turbo/models/turbo_free_allowance.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TurboFreeAllowance.fromJson', () {
    test('parses a finite allowance', () {
      final allowance =
          TurboFreeAllowance.fromJson(const {'bytesRemaining': 7340032});

      expect(allowance.status, TurboFreeAllowanceStatus.limited);
      expect(allowance.bytesRemaining, 7340032);
      expect(allowance.isKnown, isTrue);
    });

    test('treats an explicit null as unlimited, not unknown', () {
      final allowance =
          TurboFreeAllowance.fromJson(const {'bytesRemaining': null});

      expect(allowance.status, TurboFreeAllowanceStatus.unlimited);
      expect(allowance.isKnown, isTrue);
    });

    test('treats zero as the free tier being off', () {
      final allowance =
          TurboFreeAllowance.fromJson(const {'bytesRemaining': 0});

      expect(allowance.status, TurboFreeAllowanceStatus.disabled);
      expect(allowance.isKnown, isTrue);
    });

    test('normalises a negative allowance to disabled', () {
      final allowance =
          TurboFreeAllowance.fromJson(const {'bytesRemaining': -1});

      expect(allowance.status, TurboFreeAllowanceStatus.disabled);
    });

    test('parses a decoded JSON string payload', () {
      final allowance = TurboFreeAllowance.fromJson(
        json.decode('{"bytesRemaining": 1024}'),
      );

      expect(allowance.bytesRemaining, 1024);
    });

    test('accepts a non-int number', () {
      final allowance =
          TurboFreeAllowance.fromJson(const {'bytesRemaining': 1024.0});

      expect(allowance.status, TurboFreeAllowanceStatus.limited);
      expect(allowance.bytesRemaining, 1024);
    });

    group('is unknown rather than throwing when the payload is unusable', () {
      test('missing field', () {
        expect(TurboFreeAllowance.fromJson(const {}).isKnown, isFalse);
      });

      test('not a map', () {
        expect(TurboFreeAllowance.fromJson('nope').isKnown, isFalse);
        expect(TurboFreeAllowance.fromJson(null).isKnown, isFalse);
      });

      test('wrong value type', () {
        expect(
          TurboFreeAllowance.fromJson(const {'bytesRemaining': 'lots'}).isKnown,
          isFalse,
        );
      });
    });
  });

  group('covers', () {
    test('a limited allowance covers only what fits', () {
      final allowance = TurboFreeAllowance.bytes(1000);

      expect(allowance.covers(999), isTrue);
      expect(allowance.covers(1000), isTrue, reason: 'boundary is inclusive');
      expect(allowance.covers(1001), isFalse);
    });

    test('unlimited covers anything', () {
      expect(const TurboFreeAllowance.unlimited().covers(1 << 40), isTrue);
    });

    test('disabled covers nothing, including a zero-byte upload', () {
      expect(const TurboFreeAllowance.disabled().covers(1), isFalse);
      expect(const TurboFreeAllowance.disabled().covers(0), isFalse);
    });

    test('unknown fails open so an unreachable endpoint never forces payment',
        () {
      expect(const TurboFreeAllowance.unknown().covers(1 << 40), isTrue);
    });
  });

  group('isExhaustedFor', () {
    test('is true only when the allowance is known not to cover the upload',
        () {
      expect(TurboFreeAllowance.bytes(100).isExhaustedFor(101), isTrue);
      expect(const TurboFreeAllowance.disabled().isExhaustedFor(1), isTrue);
    });

    test('is false when the allowance covers the upload', () {
      expect(TurboFreeAllowance.bytes(100).isExhaustedFor(100), isFalse);
      expect(const TurboFreeAllowance.unlimited().isExhaustedFor(1), isFalse);
    });

    test('is false when unknown — "could not check" is not "used up"', () {
      expect(
          const TurboFreeAllowance.unknown().isExhaustedFor(1 << 40), isFalse);
    });
  });

  test(
      'bytes() normalises zero to disabled so callers need not special-case it',
      () {
    expect(TurboFreeAllowance.bytes(0), const TurboFreeAllowance.disabled());
  });

  test('value equality', () {
    expect(TurboFreeAllowance.bytes(10), TurboFreeAllowance.bytes(10));
    expect(
      TurboFreeAllowance.bytes(10),
      isNot(TurboFreeAllowance.bytes(11)),
    );
    expect(
      const TurboFreeAllowance.unknown(),
      isNot(const TurboFreeAllowance.disabled()),
      reason: 'unknown and disabled drive different UX and must not compare '
          'equal',
    );
  });
}
