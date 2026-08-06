import 'package:ardrive/utils/shared_file_link.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart' show Cipher;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fileId = '8f3c2a10-6f4e-4c7a-9b2e-1d2f3a4b5c6d';

  // The ids from the example links of the design plan, §1.3. Every Arweave id
  // is 43 base64url characters.
  const dataTxId = 'nS7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWeR';
  const metadataTxId = 'S1QzT9YbPo8iU7yT6rE5wQ4aS3dF2gH1jK0lZxCvBnM';
  const ownerAddress = 'Zvp8dEkO3nQ2wX9yV8uT7sR6qP5oN4mL3kJ2iH1gF0e';
  const bundledInTxId = 'oLd7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWe';
  const thumbnailTxId = 'oLdzT9YbPo8iU7yT6rE5wQ4aS3dF2gH1jK0lZxCvBn0';

  // A 12 byte IV is 16 base64url characters. The plan's example (`9tR2kX0pLmQz`)
  // is 12 characters, which is 9 bytes - illustrative, not a real IV.
  const cipherIv = '9tR2kX0pLmQz8sQ1';

  // A well formed file key: 43 base64url characters whose final character
  // carries only 4 significant bits, so its low 2 bits must be zero. 'Q'
  // (alphabet index 16) qualifies; 'q' (index 42) does not. The plan's example
  // key ends in 'G' and is therefore not decodable - also illustrative.
  const fileKey = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopQ';
  const otherFileKey = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';

  Map<String, String> fullParameters() => {
        SharedFileLinkParams.version: '2',
        SharedFileLinkParams.dataTxId: dataTxId,
        SharedFileLinkParams.metadataTxId: metadataTxId,
        SharedFileLinkParams.owner: ownerAddress,
        SharedFileLinkParams.name: 'Q3 Report.pdf',
        SharedFileLinkParams.size: '4821133',
        SharedFileLinkParams.contentType: 'application/pdf',
        SharedFileLinkParams.cipher: Cipher.aes256gcm,
        SharedFileLinkParams.cipherIv: cipherIv,
        SharedFileLinkParams.pinned: '1',
        SharedFileLinkParams.bundledIn: bundledInTxId,
        SharedFileLinkParams.thumbnailTxId: thumbnailTxId,
        SharedFileLinkParams.hidden: '1',
      };

  /// [fullParameters] with one parameter replaced by something malformed.
  SharedFileLinkPayload parseWithCorrupted(String name, String value) {
    final parameters = fullParameters()..[name] = value;
    final payload = SharedFileLinkPayload.tryParseParameters(parameters);

    // Total degradation: one bad field never costs us the payload.
    expect(payload, isNotNull);

    return payload!;
  }

  /// Asserts that every field of [fullParameters] except [except] survived.
  void expectIntactExcept(SharedFileLinkPayload payload, String except) {
    if (except != SharedFileLinkParams.dataTxId) {
      expect(payload.dataTxId, dataTxId);
    }
    if (except != SharedFileLinkParams.metadataTxId) {
      expect(payload.metadataTxId, metadataTxId);
    }
    if (except != SharedFileLinkParams.owner) {
      expect(payload.ownerAddress, ownerAddress);
    }
    if (except != SharedFileLinkParams.name) {
      expect(payload.name, 'Q3 Report.pdf');
    }
    if (except != SharedFileLinkParams.size) {
      expect(payload.size, 4821133);
    }
    if (except != SharedFileLinkParams.contentType) {
      expect(payload.contentType, 'application/pdf');
    }
    if (except != SharedFileLinkParams.cipher) {
      expect(payload.cipher, Cipher.aes256gcm);
    }
    if (except != SharedFileLinkParams.cipherIv) {
      expect(payload.cipherIv, cipherIv);
    }
    if (except != SharedFileLinkParams.pinned) {
      expect(payload.isPinned, isTrue);
    }
    if (except != SharedFileLinkParams.bundledIn) {
      expect(payload.bundledInTxId, bundledInTxId);
    }
    if (except != SharedFileLinkParams.thumbnailTxId) {
      expect(payload.thumbnailTxId, thumbnailTxId);
    }
    if (except != SharedFileLinkParams.hidden) {
      expect(payload.detailsAreHidden, isTrue);
    }
  }

  // Every test below this one reaches for [SharedFileLinkParams], which is the
  // right thing to do everywhere - and is exactly why none of them can hold
  // the wire format still. Rename `pinned` to `'p'` and they all keep passing,
  // while every pinned link already sent to somebody quietly loses its `pin`:
  // the new build reads no flag, falls back to live semantics, and hands the
  // recipient a *newer* revision than the sharer chose to send them, with
  // nothing on screen to say so. Same shape for the other three.
  //
  // These are the only assertions in the suite that spell the names out.
  group('the parameter names on the wire', () {
    const wireFormat = <String, String>{
      'v': '2',
      'dtx': dataTxId,
      'mtx': metadataTxId,
      'own': ownerAddress,
      'n': 'Q3 Report.pdf',
      's': '4821133',
      'ct': 'application/pdf',
      'c': 'AES256-GCM',
      'iv': cipherIv,
      'pin': '1',
      'in': bundledInTxId,
      'thn': thumbnailTxId,
      'hid': '1',
    };

    test('are what a link already in the wild is read with', () {
      final payload = SharedFileLinkPayload.tryParseParameters(wireFormat);

      expect(payload, isNotNull);
      expect(payload!.version, 2);
      expect(payload.dataTxId, dataTxId);
      expect(payload.metadataTxId, metadataTxId);
      expect(payload.ownerAddress, ownerAddress);
      expect(payload.name, 'Q3 Report.pdf');
      expect(payload.size, 4821133);
      expect(payload.contentType, 'application/pdf');
      expect(payload.cipher, Cipher.aes256gcm);
      expect(payload.cipherIv, cipherIv);

      // The four the suite never spelled out. `pin` is the one with teeth: a
      // link that loses it silently changes which bytes the recipient gets.
      expect(payload.isPinned, isTrue, reason: '`pin=1` is a pinned link');
      expect(
        payload.detailsAreHidden,
        isTrue,
        reason: '`hid=1` is a link whose sharer hid the name and size',
      );
      expect(
        payload.bundledInTxId,
        bundledInTxId,
        reason: '`in` is the bundle the data item was posted in',
      );
      expect(
        payload.thumbnailTxId,
        thumbnailTxId,
        reason: '`thn` is the thumbnail transaction',
      );
    });

    test('are what a new link is written with', () {
      final payload =
          SharedFileLinkPayload.tryParseParameters(fullParameters())!;

      expect(payload.toQueryParameters(), wireFormat);
    });
  });

  group('SharedFileLinkPayload version gate', () {
    test('a link with no version has no payload', () {
      // Every link ArDrive ever produced. It must keep resolving over GraphQL.
      expect(
        SharedFileLinkPayload.tryParse(
          Uri.parse('/file/$fileId/view?fileKey=$fileKey'),
        ),
        isNull,
      );
    });

    test('an empty version has no payload', () {
      expect(
        SharedFileLinkPayload.tryParseParameters(
          {SharedFileLinkParams.version: ''},
        ),
        isNull,
      );
    });

    test('an unreadable version has no payload instead of throwing', () {
      final parameters = fullParameters()
        ..[SharedFileLinkParams.version] = 'two';

      expect(SharedFileLinkPayload.tryParseParameters(parameters), isNull);
    });

    test('a future version has no payload', () {
      // A v3 link read by a v2 client falls back to full GraphQL resolution,
      // which cannot be wrong about anything the link asserted.
      final parameters = fullParameters()
        ..[SharedFileLinkParams.version] = '3';

      expect(SharedFileLinkPayload.tryParseParameters(parameters), isNull);
    });

    test('v2 with nothing else is a valid, empty payload', () {
      final payload = SharedFileLinkPayload.tryParseParameters(
        {SharedFileLinkParams.version: '2'},
      );

      expect(payload, isNotNull);
      expect(payload!.version, SharedFileLinkPayload.currentVersion);
      expect(payload.dataTxId, isNull);
      expect(payload.metadataTxId, isNull);
      expect(payload.ownerAddress, isNull);
      expect(payload.name, isNull);
      expect(payload.size, isNull);
      expect(payload.contentType, isNull);
      expect(payload.cipher, isNull);
      expect(payload.cipherIv, isNull);
      expect(payload.bundledInTxId, isNull);
      expect(payload.thumbnailTxId, isNull);
      expect(payload.isPinned, isFalse);
      expect(payload.detailsAreHidden, isFalse);
      expect(payload.key, SharedFileLinkKey.absent);
      expect(payload.hasFastPathTarget, isFalse);
      expect(payload.hasCipherDetails, isFalse);
    });
  });

  group('SharedFileLinkPayload parsing', () {
    test('parses every field of a complete link', () {
      final payload =
          SharedFileLinkPayload.tryParseParameters(fullParameters())!;

      expect(payload.version, 2);
      expect(payload.dataTxId, dataTxId);
      expect(payload.metadataTxId, metadataTxId);
      expect(payload.ownerAddress, ownerAddress);
      expect(payload.name, 'Q3 Report.pdf');
      expect(payload.size, 4821133);
      expect(payload.contentType, 'application/pdf');
      expect(payload.cipher, Cipher.aes256gcm);
      expect(payload.cipherIv, cipherIv);
      expect(payload.isPinned, isTrue);
      expect(payload.bundledInTxId, bundledInTxId);
      expect(payload.thumbnailTxId, thumbnailTxId);
      expect(payload.detailsAreHidden, isTrue);
      expect(payload.hasFastPathTarget, isTrue);
      expect(payload.hasCipherDetails, isTrue);
    });

    test('ignores unknown parameters', () {
      final parameters = fullParameters()
        ..['utm_source'] = 'newsletter'
        ..['zzz'] = 'whatever';

      final payload = SharedFileLinkPayload.tryParseParameters(parameters)!;

      expectIntactExcept(payload, '');
    });

    test('accepts the second cipher', () {
      final parameters = fullParameters()
        ..[SharedFileLinkParams.cipher] = Cipher.aes256ctr;

      expect(
        SharedFileLinkPayload.tryParseParameters(parameters)!.cipher,
        Cipher.aes256ctr,
      );
    });
  });

  group('SharedFileLinkPayload total degradation', () {
    test('a non-integer size is dropped', () {
      final payload =
          parseWithCorrupted(SharedFileLinkParams.size, '4,821,133');

      expect(payload.size, isNull);
      expectIntactExcept(payload, SharedFileLinkParams.size);
    });

    test('a negative size is dropped', () {
      final payload = parseWithCorrupted(SharedFileLinkParams.size, '-1');

      expect(payload.size, isNull);
      expectIntactExcept(payload, SharedFileLinkParams.size);
    });

    test('an over-long name is dropped', () {
      final tooLong = 'a' * (SharedFileLinkPayload.maxNameLength + 1);
      final payload = parseWithCorrupted(SharedFileLinkParams.name, tooLong);

      expect(payload.name, isNull);
      expectIntactExcept(payload, SharedFileLinkParams.name);
    });

    test('a name at the limit is kept', () {
      final atLimit = 'a' * SharedFileLinkPayload.maxNameLength;
      final payload = parseWithCorrupted(SharedFileLinkParams.name, atLimit);

      expect(payload.name, atLimit);
    });

    test('a name with control characters is dropped', () {
      final payload =
          parseWithCorrupted(SharedFileLinkParams.name, 'Q3\nReport.pdf');

      expect(payload.name, isNull);
      expectIntactExcept(payload, SharedFileLinkParams.name);
    });

    // `n` is not only rendered: it is the name the file is saved under, on the
    // fast path without anything else ever being consulted. A direction
    // override turns the extension around in the card *and* in the operating
    // system's save dialog, so a `.exe` arrives looking like a `.pdf`.
    for (final entry in const <String, String>{
      'a right-to-left override': '\u202E',
      'a left-to-right override': '\u202D',
      'a right-to-left embedding': '\u202B',
      'a left-to-right isolate': '\u2066',
      'a pop directional isolate': '\u2069',
      'a right-to-left mark': '\u200F',
    }.entries) {
      test('a name with ${entry.key} is dropped', () {
        final payload = parseWithCorrupted(
          SharedFileLinkParams.name,
          'Q3-Report${entry.value}fdp.exe',
        );

        expect(payload.name, isNull);
        expectIntactExcept(payload, SharedFileLinkParams.name);
      });
    }

    test('a name written in a right-to-left script is kept', () {
      // The rule is about the characters that misrepresent a name, never about
      // the script it is written in: `\u05D3\u05D5\u05D7.pdf` is Hebrew for
      // "report.pdf" and is a file name like any other. (Escaped rather than
      // pasted so that this file reads the same everywhere.)
      const rightToLeftName = '\u05D3\u05D5\u05D7.pdf';

      final payload = parseWithCorrupted(
        SharedFileLinkParams.name,
        rightToLeftName,
      );

      expect(payload.name, rightToLeftName);
    });

    test('an unknown cipher is dropped', () {
      final payload =
          parseWithCorrupted(SharedFileLinkParams.cipher, 'AES128-XYZ');

      expect(payload.cipher, isNull);
      expect(payload.hasCipherDetails, isFalse);
      expectIntactExcept(payload, SharedFileLinkParams.cipher);
    });

    test('a malformed IV is dropped', () {
      final payload =
          parseWithCorrupted(SharedFileLinkParams.cipherIv, 'not base64!!');

      expect(payload.cipherIv, isNull);
      expectIntactExcept(payload, SharedFileLinkParams.cipherIv);
    });

    test('an IV of the wrong length is dropped', () {
      // 12 characters is 9 bytes, not the 12 bytes both ciphers use.
      final payload =
          parseWithCorrupted(SharedFileLinkParams.cipherIv, '9tR2kX0pLmQz');

      expect(payload.cipherIv, isNull);
      expectIntactExcept(payload, SharedFileLinkParams.cipherIv);
    });

    test('a truncated content type is dropped', () {
      final payload =
          parseWithCorrupted(SharedFileLinkParams.contentType, 'application');

      expect(payload.contentType, isNull);
      expectIntactExcept(payload, SharedFileLinkParams.contentType);
    });

    test('a truncated data tx id is dropped', () {
      final payload = parseWithCorrupted(
        SharedFileLinkParams.dataTxId,
        dataTxId.substring(0, 41),
      );

      expect(payload.dataTxId, isNull);
      expect(payload.hasFastPathTarget, isFalse);
      expectIntactExcept(payload, SharedFileLinkParams.dataTxId);
    });

    test('a metadata tx id with invalid characters is dropped', () {
      final payload = parseWithCorrupted(
        SharedFileLinkParams.metadataTxId,
        'not a transaction id at all!!!!!!!!!!!!!!!!',
      );

      expect(payload.metadataTxId, isNull);
      expectIntactExcept(payload, SharedFileLinkParams.metadataTxId);
    });

    test('a malformed owner address is dropped', () {
      final payload =
          parseWithCorrupted(SharedFileLinkParams.owner, 'not-an-address');

      expect(payload.ownerAddress, isNull);
      expectIntactExcept(payload, SharedFileLinkParams.owner);
    });

    test('a malformed bundle id is dropped', () {
      final payload =
          parseWithCorrupted(SharedFileLinkParams.bundledIn, 'garbage');

      expect(payload.bundledInTxId, isNull);
      expectIntactExcept(payload, SharedFileLinkParams.bundledIn);
    });

    test('a malformed thumbnail id is dropped', () {
      final payload =
          parseWithCorrupted(SharedFileLinkParams.thumbnailTxId, 'garbage');

      expect(payload.thumbnailTxId, isNull);
      expectIntactExcept(payload, SharedFileLinkParams.thumbnailTxId);
    });

    test('junk in pin reads as absent, which is live semantics', () {
      final payload = parseWithCorrupted(SharedFileLinkParams.pinned, 'yes');

      expect(payload.isPinned, isFalse);
      expectIntactExcept(payload, SharedFileLinkParams.pinned);
    });

    test('junk in hid reads as absent', () {
      final payload = parseWithCorrupted(SharedFileLinkParams.hidden, 'true');

      expect(payload.detailsAreHidden, isFalse);
      expectIntactExcept(payload, SharedFileLinkParams.hidden);
    });

    test('a link where everything is malformed still parses', () {
      final payload = SharedFileLinkPayload.tryParseParameters({
        SharedFileLinkParams.version: '2',
        SharedFileLinkParams.dataTxId: '!',
        SharedFileLinkParams.metadataTxId: '!',
        SharedFileLinkParams.owner: '!',
        SharedFileLinkParams.name: 'a' * 500,
        SharedFileLinkParams.size: 'huge',
        SharedFileLinkParams.contentType: '///',
        SharedFileLinkParams.cipher: 'ROT13',
        SharedFileLinkParams.cipherIv: '!!',
        SharedFileLinkParams.pinned: 'maybe',
        SharedFileLinkParams.bundledIn: '!',
        SharedFileLinkParams.thumbnailTxId: '!',
        SharedFileLinkParams.hidden: 'maybe',
        SharedFileLinkParams.key: 'nope',
      })!;

      expect(payload.version, 2);
      expect(payload.dataTxId, isNull);
      expect(payload.metadataTxId, isNull);
      expect(payload.ownerAddress, isNull);
      expect(payload.name, isNull);
      expect(payload.size, isNull);
      expect(payload.contentType, isNull);
      expect(payload.cipher, isNull);
      expect(payload.cipherIv, isNull);
      expect(payload.isPinned, isFalse);
      expect(payload.bundledInTxId, isNull);
      expect(payload.thumbnailTxId, isNull);
      expect(payload.detailsAreHidden, isFalse);
      // The key was there and was unusable, which the page must be able to say.
      expect(payload.key.isDamaged, isTrue);
      expect(payload.key.isUsable, isFalse);
    });

    test('empty values read as absent', () {
      final payload = SharedFileLinkPayload.tryParseParameters({
        SharedFileLinkParams.version: '2',
        SharedFileLinkParams.dataTxId: '',
        SharedFileLinkParams.name: '',
        SharedFileLinkParams.size: '',
        SharedFileLinkParams.cipherIv: '',
        SharedFileLinkParams.key: '',
      })!;

      expect(payload.dataTxId, isNull);
      expect(payload.name, isNull);
      expect(payload.size, isNull);
      expect(payload.cipherIv, isNull);
      // An empty parameter is an absent key, not a mangled one.
      expect(payload.key, SharedFileLinkKey.absent);
      expect(payload.key.isDamaged, isFalse);
    });
  });

  group('SharedFileLinkKey shape validation', () {
    test('accepts a canonical key', () {
      expect(SharedFileLinkKey.isWellFormed(fileKey), isTrue);
      expect(SharedFileLinkKey.isWellFormed(otherFileKey), isTrue);
    });

    test('rejects a key whose final character is not canonical', () {
      // 'q' carries bits that a 32 byte key does not have, so the strict
      // decoder throws `Invalid encoding before padding` on it.
      final notCanonical = '${fileKey.substring(0, 42)}q';

      expect(SharedFileLinkKey.isWellFormed(notCanonical), isFalse);
    });

    test('rejects a truncated key', () {
      expect(
        SharedFileLinkKey.isWellFormed(fileKey.substring(0, 41)),
        isFalse,
      );
    });

    test('rejects a key with characters outside base64url', () {
      expect(
        SharedFileLinkKey.isWellFormed('${fileKey.substring(0, 42)}!'),
        isFalse,
      );
    });

    test('a valid key decodes to 32 bytes', () {
      final key = SharedFileLinkKey.parse(
        fileKey,
        source: SharedFileLinkKeySource.query,
      );

      expect(key.isUsable, isTrue);
      expect(key.isDamaged, isFalse);
      expect(key.raw, fileKey);
      expect(key.bytes, hasLength(SharedFileLinkKey.lengthInBytes));
      expect(key.secretKey, isNotNull);
      expect(key.fragment, 'k=$fileKey');
    });

    test('a damaged key keeps no key material and never throws', () {
      final key = SharedFileLinkKey.parse(
        fileKey.substring(0, 41),
        source: SharedFileLinkKeySource.query,
      );

      expect(key.isDamaged, isTrue);
      expect(key.isUsable, isFalse);
      expect(key.raw, isNull);
      expect(key.secretKey, isNull);
      expect(key.source, SharedFileLinkKeySource.query);
    });

    test('never prints key material', () {
      final key = SharedFileLinkKey.parse(
        fileKey,
        source: SharedFileLinkKeySource.fragment,
      );

      expect(key.toString(), isNot(contains(fileKey)));
      expect(
        SharedFileLinkPayload(key: key).toString(),
        isNot(contains(fileKey)),
      );
    });
  });

  group('SharedFileLinkKey precedence', () {
    SharedFileLinkKey resolve(String location) =>
        SharedFileLinkKey.resolve(Uri.parse(location));

    test('a fragment key wins over both query sources', () {
      final key = resolve(
        '/file/$fileId/view?v=2'
        '&${SharedFileLinkParams.key}=$otherFileKey'
        '&${SharedFileLinkParams.legacyKey}=$otherFileKey'
        '#${SharedFileLinkParams.key}=$fileKey',
      );

      expect(key.source, SharedFileLinkKeySource.fragment);
      expect(key.raw, fileKey);
    });

    test('the v2 key wins over the legacy key', () {
      final key = resolve(
        '/file/$fileId/view?v=2'
        '&${SharedFileLinkParams.key}=$fileKey'
        '&${SharedFileLinkParams.legacyKey}=$otherFileKey',
      );

      expect(key.source, SharedFileLinkKeySource.query);
      expect(key.raw, fileKey);
    });

    test('the legacy key is honored on its own', () {
      final key = resolve(
        '/file/$fileId/view?${SharedFileLinkParams.legacyKey}=$fileKey',
      );

      expect(key.source, SharedFileLinkKeySource.legacyQuery);
      expect(key.raw, fileKey);
      expect(key.isUsable, isTrue);
    });

    test('no key source at all', () {
      final key = resolve('/file/$fileId/view?v=2&dtx=$dataTxId');

      expect(key, SharedFileLinkKey.absent);
      expect(key.source, SharedFileLinkKeySource.none);
      expect(key.isDamaged, isFalse);
      expect(key.isUsable, isFalse);
    });

    test('a damaged winner is not replaced by an intact lower source', () {
      // The highest present source wins, damaged or not: substituting a
      // different key silently would be worse than saying the link is damaged
      // and letting the recipient paste the key they were sent.
      final key = resolve(
        '/file/$fileId/view?v=2'
        '&${SharedFileLinkParams.key}=${fileKey.substring(0, 41)}'
        '&${SharedFileLinkParams.legacyKey}=$otherFileKey',
      );

      expect(key.source, SharedFileLinkKeySource.query);
      expect(key.isDamaged, isTrue);
      expect(key.raw, isNull);
    });

    test('an empty higher source defers to a present lower source', () {
      final key = resolve(
        '/file/$fileId/view?v=2&${SharedFileLinkParams.key}='
        '&${SharedFileLinkParams.legacyKey}=$fileKey',
      );

      expect(key.source, SharedFileLinkKeySource.legacyQuery);
      expect(key.raw, fileKey);
    });

    test('a junk fragment does not throw', () {
      final key = resolve('/file/$fileId/view?v=2#not-a-parameter-list');

      expect(key, SharedFileLinkKey.absent);
    });
  });

  group('SharedFileLinkPayload building', () {
    test('omits the key unless it is asked for', () {
      final payload = SharedFileLinkPayload(
        dataTxId: dataTxId,
        key: SharedFileLinkKey.parse(
          fileKey,
          source: SharedFileLinkKeySource.query,
        ),
      );

      expect(
        payload.toQueryParameters().containsKey(SharedFileLinkParams.key),
        isFalse,
      );
      expect(
        payload.toQueryParameters(includeKey: true)[SharedFileLinkParams.key],
        fileKey,
      );
    });

    test('omits absent fields and false flags', () {
      const payload = SharedFileLinkPayload(dataTxId: dataTxId);

      expect(payload.toQueryParameters(), {
        SharedFileLinkParams.version: '2',
        SharedFileLinkParams.dataTxId: dataTxId,
      });
    });

    test('writes flags only when set', () {
      const payload = SharedFileLinkPayload(
        isPinned: true,
        detailsAreHidden: true,
      );

      expect(payload.toQueryParameters(), {
        SharedFileLinkParams.version: '2',
        SharedFileLinkParams.pinned: '1',
        SharedFileLinkParams.hidden: '1',
      });
    });

    test('every parameter name it writes is part of the schema', () {
      final payload =
          SharedFileLinkPayload.tryParseParameters(fullParameters())!;

      expect(
        payload.toQueryParameters(includeKey: true).keys,
        everyElement(isIn(SharedFileLinkParams.all)),
      );
    });

    test('copyWith replaces only what it is given', () {
      const payload = SharedFileLinkPayload(dataTxId: dataTxId);
      final withCipher = payload.copyWith(
        cipher: Cipher.aes256gcm,
        cipherIv: cipherIv,
      );

      expect(withCipher.dataTxId, dataTxId);
      expect(withCipher.hasCipherDetails, isTrue);
      expect(payload.hasCipherDetails, isFalse);
    });
  });

  group('buildSharedFileLinkLocation', () {
    SharedFileLinkPayload? parse(String location) =>
        SharedFileLinkPayload.tryParse(Uri.parse(location));

    test('builds the v1 shape when there is no payload', () {
      expect(
        buildSharedFileLinkLocation(fileId: fileId, rawFileKey: fileKey),
        '/file/$fileId/view?fileKey=$fileKey',
      );
      expect(
        buildSharedFileLinkLocation(fileId: fileId),
        '/file/$fileId/view',
      );
    });

    test('percent-encodes a space as %20, not +', () {
      const payload = SharedFileLinkPayload(name: 'Q3 Report.pdf');
      final location =
          buildSharedFileLinkLocation(fileId: fileId, payload: payload);

      expect(location, contains('n=Q3%20Report.pdf'));
      expect(parse(location)!.name, 'Q3 Report.pdf');
    });

    test('escapes separators inside a value', () {
      const payload = SharedFileLinkPayload(name: 'a&b=c?d#e.txt');
      final location =
          buildSharedFileLinkLocation(fileId: fileId, payload: payload);

      expect(parse(location)!.name, 'a&b=c?d#e.txt');
    });

    test('writes the key into the query by default', () {
      final key = SharedFileLinkKey.parse(
        fileKey,
        source: SharedFileLinkKeySource.query,
      );
      final location = buildSharedFileLinkLocation(
        fileId: fileId,
        payload: SharedFileLinkPayload(dataTxId: dataTxId, key: key),
      );

      expect(location, contains('&k=$fileKey'));
      expect(location, isNot(contains('#')));

      final resolved = SharedFileLinkKey.resolve(Uri.parse(location));

      expect(resolved.source, SharedFileLinkKeySource.query);
      expect(resolved.raw, fileKey);
    });

    test('writes the key into a fragment when asked', () {
      final key = SharedFileLinkKey.parse(
        fileKey,
        source: SharedFileLinkKeySource.fragment,
      );
      final location = buildSharedFileLinkLocation(
        fileId: fileId,
        payload: SharedFileLinkPayload(dataTxId: dataTxId, key: key),
        keyPlacement: SharedFileLinkKeyPlacement.fragment,
      );

      expect(location, endsWith('#k=$fileKey'));

      // The key is in the fragment and nowhere else.
      final query = location.substring(
        location.indexOf('?') + 1,
        location.indexOf('#'),
      );

      expect(query, isNot(contains('k=')));

      final resolved = SharedFileLinkKey.resolve(Uri.parse(location));

      expect(resolved.source, SharedFileLinkKeySource.fragment);
      expect(resolved.raw, fileKey);
    });

    test('never writes a key that is not there', () {
      const payload = SharedFileLinkPayload(dataTxId: dataTxId);

      expect(
        buildSharedFileLinkLocation(fileId: fileId, payload: payload),
        isNot(contains('k=')),
      );
    });

    test('builds the legacy route by default', () {
      expect(SharedFileLinkRoute.legacy.pathFor(fileId), '/file/$fileId/view');
      expect(SharedFileLinkRoute.share.pathFor(fileId), '/share/$fileId');
      expect(
        buildSharedFileLinkLocation(fileId: fileId),
        SharedFileLinkRoute.legacy.pathFor(fileId),
      );
    });

    test('builds the /share route when asked', () {
      const payload = SharedFileLinkPayload(dataTxId: dataTxId);

      expect(
        buildSharedFileLinkLocation(
          fileId: fileId,
          payload: payload,
          route: SharedFileLinkRoute.share,
        ),
        '/share/$fileId?v=2&dtx=$dataTxId',
      );
    });

    test('a v1 key moves to the fragment when the placement says so', () {
      // What a keyed v1 link has to look like on a path route: `?fileKey=` is
      // safe on the hash route and only there.
      final location = buildSharedFileLinkLocation(
        fileId: fileId,
        rawFileKey: fileKey,
        route: SharedFileLinkRoute.share,
        keyPlacement: SharedFileLinkKeyPlacement.fragment,
      );

      expect(location, '/share/$fileId#k=$fileKey');
      expect(location.split('#').first, isNot(contains(fileKey)));

      final resolved = SharedFileLinkKey.resolve(Uri.parse(location));

      expect(resolved.raw, fileKey);
      expect(resolved.source, SharedFileLinkKeySource.fragment);
    });
  });

  group('round trips of the example links of §1.3', () {
    // The plan's examples are written on the Phase 3 path route
    // (`/share/{fileId}?...`); the schema is transport independent, so these
    // exercise the same parameters on the Phase 1 hash route.
    void expectRoundTrip(SharedFileLinkPayload payload) {
      final location = buildSharedFileLinkLocation(
        fileId: fileId,
        payload: payload,
      );

      expect(
        SharedFileLinkPayload.tryParse(Uri.parse(location)),
        payload,
        reason: 'built: $location',
      );
    }

    test('public file, live semantics', () {
      expectRoundTrip(const SharedFileLinkPayload(
        dataTxId: dataTxId,
        metadataTxId: metadataTxId,
        ownerAddress: ownerAddress,
        name: 'Q3 Report.pdf',
        size: 4821133,
        contentType: 'application/pdf',
      ));
    });

    test('private file, keyless', () {
      expectRoundTrip(const SharedFileLinkPayload(
        dataTxId: dataTxId,
        metadataTxId: metadataTxId,
        ownerAddress: ownerAddress,
        name: 'Q3 Report.pdf',
        size: 4821133,
        contentType: 'application/pdf',
        cipher: Cipher.aes256gcm,
        cipherIv: cipherIv,
      ));
    });

    test('private file, key in link', () {
      final payload = SharedFileLinkPayload(
        dataTxId: dataTxId,
        metadataTxId: metadataTxId,
        ownerAddress: ownerAddress,
        name: 'Q3 Report.pdf',
        size: 4821133,
        contentType: 'application/pdf',
        cipher: Cipher.aes256gcm,
        cipherIv: cipherIv,
        key: SharedFileLinkKey.parse(
          fileKey,
          source: SharedFileLinkKeySource.query,
        ),
      );

      // The key is part of the payload, so the round trip carries it: on the
      // hash route it rides in the pseudo query, which no server ever sees.
      expectRoundTrip(payload);
    });

    test('pinned to a version, private, name hidden', () {
      expectRoundTrip(const SharedFileLinkPayload(
        isPinned: true,
        detailsAreHidden: true,
        dataTxId: bundledInTxId,
        metadataTxId: thumbnailTxId,
        ownerAddress: ownerAddress,
        size: 4821133,
        cipher: Cipher.aes256ctr,
        cipherIv: cipherIv,
      ));
    });

    test('generalized viewer hints', () {
      // `/view/{txId}?n=…&ct=…` is a Phase 3 route; only the hint parameters
      // exist today, and they parse through the same payload.
      expectRoundTrip(const SharedFileLinkPayload(
        name: 'talk.mp4',
        contentType: 'video/mp4',
      ));
    });
  });
}
