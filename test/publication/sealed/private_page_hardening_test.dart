import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/publication/domain/private_page.dart';
import 'package:ardrive/publication/domain/sealed/seal_codec.dart';
import 'package:ardrive/publication/domain/sealed/sealing.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sealing_vectors.dart';

/// The vectors' folder page, which has a password slot, as a mutable copy.
Map<String, dynamic> _settings() {
  final page = listOf('pages').first;
  return jsonDecode(page['publicationJson'] as String) as Map<String, dynamic>;
}

Map<String, dynamic> _passwordSlot(Map<String, dynamic> settings) =>
    (settings['slots'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((s) => s['type'] == 'password');

Map<String, dynamic> _block() =>
    jsonDecode(listOf('pages').first['sealedPlaintext'] as String)
        as Map<String, dynamic>;

Map<String, Object?> _blockWithFiles(int count) => {
      ..._block()..remove('pad'),
      'files': {
        for (var i = 0; i < count; i++)
          '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}': 'A' * 43,
      },
    };

void main() {
  group('argon2id bounds', () {
    test('the maximums are accepted and one past each is refused', () {
      expect(argon2MemoryBounds, (8192, 131072));
      expect(argon2PassesBounds, (1, 6));
      expect(argon2LanesBounds, (1, 4));
      checkArgon2Settings(131072, 6, 4);
      checkArgon2Settings(8192, 1, 1);
      for (final bad in [
        (131073, 3, 1),
        (65536, 7, 1),
        (65536, 3, 5),
        (8191, 3, 1),
      ]) {
        expect(() => checkArgon2Settings(bad.$1, bad.$2, bad.$3),
            throwsA(sealError(SealErrorCode.outOfBounds)),
            reason: '$bad');
      }
    });

    test('a password slot at the maximums is read, one past is not', () {
      final ok = _settings();
      _passwordSlot(ok)
        ..['m'] = 131072
        ..['t'] = 6
        ..['p'] = 4;
      expect(readPrivatePublication(ok).passwordSlot, isNotNull);

      for (final (field, value) in [('m', 131073), ('t', 7)]) {
        final bad = _settings();
        _passwordSlot(bad)[field] = value;
        expect(readPrivatePublication(bad).passwordSlot, isNull,
            reason: '$field=$value');
      }
    });
  });

  group('sealed block padding', () {
    test('is a multiple of 4096 bytes, and a bucket gives one sealed length',
        () async {
      final seal = Sealing();
      final key = Uint8List(32);
      final iv = Uint8List(12);
      final header = _settings();
      Future<int> sealedLength(int files) async => (await seal.sealBlock(
              key, iv, padSealedBlock(_blockWithFiles(files)), header))
          .length;
      for (final n in [2, 3, 10]) {
        final padded = padSealedBlock(_blockWithFiles(n));
        expect(utf8.encode(canonicalJson(padded)).length % sealedPadUnit, 0);
        expect(padded['pad'], matches(RegExp(r'^ *$')));
      }
      expect(await sealedLength(2), await sealedLength(10));
      expect(await sealedLength(3), await sealedLength(10));
      expect(await sealedLength(100), greaterThan(await sealedLength(2)));
      expect(await sealedLength(100) % sealedPadUnit, tagBytes);
    });

    test('a reader ignores pad, and reads a block without one', () {
      final config = _settings();
      final plain = _block();
      final unpadded = {...plain}..remove('pad');
      readSealedBlock(unpadded, config);
      readSealedBlock({...plain, 'pad': 'not spaces'}, config);
      readSealedBlock({...plain, 'pad': 5}, config);
      readSealedBlock({...plain, 'pad': null}, config);
    });
  });

  group('carrying slots forward', () {
    test('keeps an unknown field, even a null one, as it was', () async {
      final settings = _settings();
      for (final slot in (settings['slots'] as List).cast<Map>()) {
        slot['future'] = null;
        slot['extra'] = {'a': 1};
      }
      final slots = slotsOf(settings);
      expect(slots, hasLength(2));
      for (final slot in slots) {
        expect(slot.containsKey('future'), isTrue);
        expect(slot['future'], isNull);
        expect(slot['extra'], {'a': 1});
      }

      final next = await pageSlots(
        publicationKey: Uint8List(32),
        publicationId: settings['publicationId'] as String,
        driveKey: Uint8List(32),
        previous: slots,
      );
      expect(jsonEncode(next), jsonEncode(slots));
    });

    test('refuses a password slot the reader would never run', () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (s) => s['m'] = 131073,
        (s) => s['t'] = 7,
        (s) => s['salt'] = 'AAAA',
        (s) => s['wrapped'] = 'AAAA',
        (s) => s['kdf'] = 'scrypt',
        (s) => s.remove('iv'),
      ]) {
        final settings = _settings();
        mutate(_passwordSlot(settings));
        expect(
            () => slotsOf(settings), throwsA(sealError(SealErrorCode.invalid)));
      }
    });

    test('accepts a good password slot, and a page with none', () {
      expect(slotsOf(_settings()), hasLength(2));
      final noPassword = _settings();
      (noPassword['slots'] as List).removeWhere((s) => s['type'] == 'password');
      expect(slotsOf(noPassword), hasLength(1));
    });
  });
}
