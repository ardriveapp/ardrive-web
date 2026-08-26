import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/utils/shared_file_link.dart';
import 'package:ardrive_crypto/ardrive_crypto.dart' show Cipher;
import 'package:flutter_test/flutter_test.dart';

void main() {
  const fileId = '8f3c2a10-6f4e-4c7a-9b2e-1d2f3a4b5c6d';

  // The ids from the example links of the design plan, §1.3. Every Arweave id
  // is 43 base64url characters *and decodes to 32 bytes*: 43 characters carry
  // 258 bits, so the last one's low 2 bits have to be zero. The plan's ids used
  // to end in characters that carry those bits (`R`, `e`), which made them
  // undecodable - harmless while the schema spelled ids out, fatal now that a
  // payload stores them as the bytes they are. See [isCanonical32ByteId].
  const dataTxId = 'nS7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWeQ';
  const metadataTxId = 'S1QzT9YbPo8iU7yT6rE5wQ4aS3dF2gH1jK0lZxCvBnM';
  const ownerAddress = 'Zvp8dEkO3nQ2wX9yV8uT7sR6qP5oN4mL3kJ2iH1gF0c';
  const bundledInTxId = 'oLd7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWc';
  const thumbnailTxId = 'oLdzT9YbPo8iU7yT6rE5wQ4aS3dF2gH1jK0lZxCvBn0';

  // A 12 byte IV is 16 base64url characters, and 16 characters carry exactly 96
  // bits, so every one of them is decodable.
  const cipherIv = '9tR2kX0pLmQz8sQ1';

  const fileName = 'Q3 Report.pdf';
  const fileSize = 4821133;
  const contentType = 'application/pdf';

  // A well formed file key: 43 base64url characters whose final character
  // carries only 4 significant bits, so its low 2 bits must be zero. 'Q'
  // (alphabet index 16) qualifies; 'q' (index 42) does not.
  const fileKey = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopQ';
  const otherFileKey = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ';

  /// The bytes a base64url id spells.
  Uint8List rawBytes(String value) =>
      base64Url.decode(base64Url.normalize(value));

  /// Base64url without padding - what a payload travels as.
  String encodeBytes(List<int> bytes) {
    final encoded = base64Url.encode(bytes);
    final padding = encoded.indexOf('=');

    return padding < 0 ? encoded : encoded.substring(0, padding);
  }

  /// A link carrying [encoded] as its payload.
  Map<String, String> parameters(String encoded) => {
        SharedFileLinkParams.payload: encoded,
      };

  /// Everything a link can assert, as one payload.
  SharedFileLinkPayload fullPayload() => const SharedFileLinkPayload(
        dataTxId: dataTxId,
        metadataTxId: metadataTxId,
        ownerAddress: ownerAddress,
        name: fileName,
        size: fileSize,
        contentType: contentType,
        cipher: Cipher.aes256gcm,
        cipherIv: cipherIv,
        isPinned: true,
        bundledInTxId: bundledInTxId,
        thumbnailTxId: thumbnailTxId,
        detailsAreHidden: true,
      );

  /// The packed bytes of [fullPayload], assembled from the layout rather than
  /// from the encoder, so that either side changing has to break something.
  ///
  /// Every part is overridable, which is what makes a one-field corruption a
  /// one-line test: pass the field the way a mangled link would carry it and
  /// leave the rest of the payload exactly as a real link builds it.
  List<int> packed({
    int version = 2,
    int flags = 0x07,
    int bitmap = 0xff,
    List<int>? dataTx,
    List<int>? metadataTx,
    List<int>? owner,
    List<int>? iv,
    List<int> size = const [3, 0x49, 0x90, 0x8d],
    List<int>? name,
    List<int> contentTypeField = const [1],
    List<int>? records,
  }) =>
      [
        version,
        flags,
        bitmap,
        ...dataTx ?? rawBytes(dataTxId),
        ...metadataTx ?? rawBytes(metadataTxId),
        ...owner ?? rawBytes(ownerAddress),
        ...iv ?? rawBytes(cipherIv),
        ...size,
        ...name ?? [fileName.length, ...utf8.encode(fileName)],
        ...contentTypeField,
        ...records ??
            [
              1, 32, ...rawBytes(bundledInTxId), //
              2, 32, ...rawBytes(thumbnailTxId), //
            ],
      ];

  /// Decodes a payload built from [packed]'s parts.
  SharedFileLinkPayload decodePacked({
    int version = 2,
    int flags = 0x07,
    int bitmap = 0xff,
    List<int>? dataTx,
    List<int>? metadataTx,
    List<int>? owner,
    List<int>? iv,
    List<int> size = const [3, 0x49, 0x90, 0x8d],
    List<int>? name,
    List<int> contentTypeField = const [1],
    List<int>? records,
  }) {
    final payload = SharedFileLinkPayload.decode(
      encodeBytes(
        packed(
          version: version,
          flags: flags,
          bitmap: bitmap,
          dataTx: dataTx,
          metadataTx: metadataTx,
          owner: owner,
          iv: iv,
          size: size,
          name: name,
          contentTypeField: contentTypeField,
          records: records,
        ),
      ),
    );

    // Total degradation: one bad field never costs us the payload.
    expect(payload, isNotNull);

    return payload!;
  }

  /// Asserts that every field of [fullPayload] except [except] survived.
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
      expect(payload.name, fileName);
    }
    if (except != SharedFileLinkParams.size) {
      expect(payload.size, fileSize);
    }
    if (except != SharedFileLinkParams.contentType) {
      expect(payload.contentType, contentType);
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

  // Every other test in this file reaches for the payload's *fields*, which is
  // the right thing to do everywhere - and is exactly why none of them can hold
  // the wire format still. Move `pin` from bit 0 of the flags byte to bit 4 and
  // they all keep passing, while every pinned link already sent to somebody
  // quietly loses its `pin`: the new build reads no flag, falls back to live
  // semantics, and hands the recipient a *newer* revision than the sharer chose
  // to send them, with nothing on screen to say so. Same shape for the rest.
  //
  // These are the only assertions in the suite that spell the layout out. They
  // are written from the format, not from the encoder, so that a change to the
  // encoder cannot quietly redefine what a link in somebody's chat history
  // means.
  group('the bytes on the wire', () {
    test('are what a link already in the wild is read with', () {
      final payload = SharedFileLinkPayload.decode(encodeBytes(packed()));

      expect(payload, isNotNull);
      expect(payload!.version, 2);
      expect(payload.dataTxId, dataTxId);
      expect(payload.metadataTxId, metadataTxId);
      expect(payload.ownerAddress, ownerAddress);
      expect(payload.name, fileName);
      expect(payload.size, fileSize);
      expect(payload.contentType, contentType);
      expect(payload.cipher, Cipher.aes256gcm);
      expect(payload.cipherIv, cipherIv);

      // The four the suite would otherwise never spell out. `pin` is the one
      // with teeth: a link that loses it silently changes which bytes the
      // recipient gets.
      expect(payload.isPinned, isTrue, reason: 'flags bit 0 is `pin`');
      expect(
        payload.detailsAreHidden,
        isTrue,
        reason: 'flags bit 1 is `hid`: the sharer hid the name and size',
      );
      expect(
        payload.bundledInTxId,
        bundledInTxId,
        reason: 'record tag 1 is `in`, the bundle the data item was posted in',
      );
      expect(
        payload.thumbnailTxId,
        thumbnailTxId,
        reason: 'record tag 2 is `thn`, the thumbnail transaction',
      );
    });

    test('are what a new link is written with', () {
      expect(fullPayload().encode(), encodeBytes(packed()));
    });

    test('carry the schema version in the first byte and nowhere else', () {
      expect(packed().first, SharedFileLinkPayload.currentVersion);
      expect(
        fullPayload().toQueryParameters().keys,
        [SharedFileLinkParams.payload],
        reason: 'the version is inside `d`, not a parameter beside it',
      );
    });

    test('spell a content type the table knows as one byte', () {
      // The whole reason the table exists: `application/pdf` is 15 characters
      // that cost 1 byte, and the Office types are 71 characters that cost 1.
      expect(
        const SharedFileLinkPayload(contentType: contentType).encode(),
        encodeBytes([2, 0, 0x40, 1]),
      );
    });

    test('spell a content type the table does not know in full', () {
      const unlisted = 'application/x-ardrive-test';

      expect(
        const SharedFileLinkPayload(contentType: unlisted).encode(),
        encodeBytes([2, 0, 0x40, 0, unlisted.length, ...unlisted.codeUnits]),
      );
      expect(
        SharedFileLinkPayload.decode(
          const SharedFileLinkPayload(contentType: unlisted).encode(),
        )!
            .contentType,
        unlisted,
      );
    });

    test('are one parameter, and that parameter is base64url', () {
      final encoded = fullPayload().encode();

      expect(encoded, matches(RegExp(r'^[A-Za-z0-9_-]+$')));
      expect(
        Uri.encodeComponent(encoded),
        encoded,
        reason: 'nothing in a payload ever needs percent encoding',
      );
    });
  });

  group('SharedFileLinkPayload version gate', () {
    test('a link with no payload parameter has no payload', () {
      // Every link ArDrive ever produced. It must keep resolving over GraphQL.
      expect(
        SharedFileLinkPayload.tryParse(
          Uri.parse('/file/$fileId/view?fileKey=$fileKey'),
        ),
        isNull,
      );
    });

    test('an empty payload parameter has no payload', () {
      expect(SharedFileLinkPayload.tryParseParameters(parameters('')), isNull);
    });

    test('a future version has no payload', () {
      // A v3 link read by a v2 client falls back to full GraphQL resolution,
      // which cannot be wrong about anything the link asserted.
      expect(SharedFileLinkPayload.decode(encodeBytes(packed(version: 3))),
          isNull);
    });

    test('a payload too short to hold a header has none', () {
      expect(SharedFileLinkPayload.decode(encodeBytes([2, 0])), isNull);
    });

    test('a header on its own is a valid, empty payload', () {
      final payload = SharedFileLinkPayload.decode(encodeBytes([2, 0, 0]));

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

    test('an empty payload round trips through the encoder', () {
      const payload = SharedFileLinkPayload();

      expect(SharedFileLinkPayload.decode(payload.encode()), payload);
    });

    // The draft of this schema spelled its fields out as `?v=2&dtx=…`. It never
    // shipped, so no such link exists - but a link that names parameters this
    // build does not know must land somewhere sane rather than half-read, and
    // "somewhere sane" is the same place a v1 link lands.
    test('a link in the abandoned named-parameter draft resolves as v1', () {
      final payload = SharedFileLinkPayload.tryParseParameters({
        'v': '2',
        'dtx': dataTxId,
        'mtx': metadataTxId,
        'n': fileName,
      });

      expect(payload, isNull);
    });
  });

  group('SharedFileLinkPayload parsing', () {
    test('parses every field of a complete link', () {
      final payload = SharedFileLinkPayload.decode(fullPayload().encode())!;

      expect(payload, fullPayload());
      expect(payload.hasFastPathTarget, isTrue);
      expect(payload.hasCipherDetails, isTrue);
    });

    test('ignores unknown parameters', () {
      final payload = SharedFileLinkPayload.tryParseParameters({
        ...parameters(fullPayload().encode()),
        'utm_source': 'newsletter',
        'zzz': 'whatever',
      })!;

      expectIntactExcept(payload, '');
    });

    test('accepts the second cipher', () {
      expect(
        SharedFileLinkPayload.decode(
          const SharedFileLinkPayload(cipher: Cipher.aes256ctr).encode(),
        )!
            .cipher,
        Cipher.aes256ctr,
      );
    });

    test('a field the bitmap does not claim is simply absent', () {
      // Bit 2 cleared and the 32 bytes left out: what a keyless, ownerless link
      // looks like on the wire.
      final payload = SharedFileLinkPayload.decode(
        encodeBytes([
          2,
          0x07,
          0xff & ~0x04,
          ...rawBytes(dataTxId),
          ...rawBytes(metadataTxId),
          ...rawBytes(cipherIv),
          3, 0x49, 0x90, 0x8d, //
          fileName.length, ...utf8.encode(fileName), //
          1,
          1, 32, ...rawBytes(bundledInTxId), //
          2, 32, ...rawBytes(thumbnailTxId), //
        ]),
      )!;

      expect(payload.ownerAddress, isNull);
      expectIntactExcept(payload, SharedFileLinkParams.owner);
    });
  });

  group('SharedFileLinkPayload total degradation', () {
    test('a size longer than the schema can carry is dropped', () {
      final payload = decodePacked(size: const [7, 1, 2, 3, 4, 5, 6, 7]);

      expect(payload.size, isNull);
      expectIntactExcept(payload, SharedFileLinkParams.size);
    });

    test('a zero length size is dropped', () {
      final payload = decodePacked(size: const [0]);

      expect(payload.size, isNull);
      expectIntactExcept(payload, SharedFileLinkParams.size);
    });

    test('a size of zero is a size, not an absence', () {
      final payload = decodePacked(size: const [1, 0]);

      expect(payload.size, 0);
      expect(payload.name, fileName);
    });

    test('a negative size never reaches the wire', () {
      final payload = SharedFileLinkPayload.decode(
        const SharedFileLinkPayload(dataTxId: dataTxId, size: -1).encode(),
      )!;

      expect(payload.size, isNull);
      expect(payload.dataTxId, dataTxId);
    });

    test('an over-long name is dropped', () {
      final tooLong = 'a' * (SharedFileLinkPayload.maxNameLength + 1);
      final payload =
          decodePacked(name: [tooLong.length, ...utf8.encode(tooLong)]);

      expect(payload.name, isNull);
      expectIntactExcept(payload, SharedFileLinkParams.name);
    });

    test('a name at the limit is kept', () {
      final atLimit = 'a' * SharedFileLinkPayload.maxNameLength;
      final payload =
          decodePacked(name: [atLimit.length, ...utf8.encode(atLimit)]);

      expect(payload.name, atLimit);
    });

    test('a name that is not UTF-8 is dropped', () {
      final payload = decodePacked(name: const [3, 0xff, 0xfe, 0xfd]);

      expect(payload.name, isNull);
      expectIntactExcept(payload, SharedFileLinkParams.name);
    });

    test('a name with control characters is dropped', () {
      const mangled = 'Q3\nReport.pdf';
      final payload =
          decodePacked(name: [mangled.length, ...utf8.encode(mangled)]);

      expect(payload.name, isNull);
      expectIntactExcept(payload, SharedFileLinkParams.name);
    });

    // `n` is not only rendered: it is the name the file is saved under, on the
    // fast path without anything else ever being consulted. A direction
    // override turns the extension around in the card *and* in the operating
    // system's save dialog, so a `.exe` arrives looking like a `.pdf`.
    for (final entry in const <String, String>{
      'a right-to-left override': '\u{202E}',
      'a left-to-right override': '\u{202D}',
      'a right-to-left embedding': '\u{202B}',
      'a left-to-right isolate': '\u{2066}',
      'a pop directional isolate': '\u{2069}',
      'a right-to-left mark': '\u{200F}',
    }.entries) {
      test('a name with ${entry.key} is dropped', () {
        final mangled = 'Q3-Report${entry.value}fdp.exe';
        final encoded = utf8.encode(mangled);
        final payload = decodePacked(name: [encoded.length, ...encoded]);

        expect(payload.name, isNull);
        expectIntactExcept(payload, SharedFileLinkParams.name);
      });
    }

    test('a name written in a right-to-left script is kept', () {
      // The rule is about the characters that misrepresent a name, never about
      // the script it is written in: `דוח.pdf` is Hebrew for
      // "report.pdf" and is a file name like any other. (Escaped rather than
      // pasted so that this file reads the same everywhere.)
      const rightToLeftName = 'דוח.pdf';
      final encoded = utf8.encode(rightToLeftName);
      final payload = decodePacked(name: [encoded.length, ...encoded]);

      expect(payload.name, rightToLeftName);
      expect(
        encoded.length,
        greaterThan(rightToLeftName.length),
        reason: 'the length prefix counts bytes, not characters',
      );
    });

    test('a name too long in bytes is truncated on a rune boundary', () {
      // 120 characters is inside the character limit and 360 bytes is outside
      // what a length byte can address, so the encoder has to cut - and cutting
      // between the bytes of a rune would hand the decoder something that is
      // not text at all.
      final wide = '日' * SharedFileLinkPayload.maxNameLength;
      final payload = SharedFileLinkPayload.decode(
        SharedFileLinkPayload(dataTxId: dataTxId, name: wide).encode(),
      )!;

      expect(payload.name, isNotNull);
      expect(payload.name, wide.substring(0, payload.name!.length));
      expect(utf8.encode(payload.name!).length, lessThanOrEqualTo(255));
      expect(payload.dataTxId, dataTxId);
    });

    test('an unknown cipher is dropped', () {
      // Code 3 of bits 2-3 is unassigned.
      final payload = decodePacked(flags: 0x03 | (3 << 2));

      expect(payload.cipher, isNull);
      expect(payload.hasCipherDetails, isFalse);
      expectIntactExcept(payload, SharedFileLinkParams.cipher);
    });

    test('an IV of the wrong length never reaches the wire', () {
      // 12 characters is 9 bytes, not the 12 bytes both ciphers use.
      final payload = SharedFileLinkPayload.decode(
        const SharedFileLinkPayload(
          dataTxId: dataTxId,
          cipher: Cipher.aes256gcm,
          cipherIv: '9tR2kX0pLmQz',
        ).encode(),
      )!;

      expect(payload.cipherIv, isNull);
      expect(payload.cipher, Cipher.aes256gcm);
      expect(payload.dataTxId, dataTxId);
    });

    test('an IV that is not base64 never reaches the wire', () {
      final payload = SharedFileLinkPayload.decode(
        const SharedFileLinkPayload(
          dataTxId: dataTxId,
          cipherIv: 'not base64!!',
        ).encode(),
      )!;

      expect(payload.cipherIv, isNull);
      expect(payload.dataTxId, dataTxId);
    });

    test('a truncated content type is dropped', () {
      const truncated = 'application';
      final payload = decodePacked(
        contentTypeField: [0, truncated.length, ...utf8.encode(truncated)],
      );

      expect(payload.contentType, isNull);
      expectIntactExcept(payload, SharedFileLinkParams.contentType);
    });

    test('a content type code from a table this build has not grown is '
        'dropped', () {
      final payload = decodePacked(contentTypeField: const [250]);

      expect(payload.contentType, isNull);
      expectIntactExcept(payload, SharedFileLinkParams.contentType);
    });

    // Every id in a payload is 32 bytes, so an id that will not decode to 32
    // bytes cannot travel at all. Each one is dropped on its own, on the way
    // out rather than on the way back in - the only place it can be caught,
    // since by the time it is bytes there is nothing left to be wrong.
    final brokenIdCases = <String, SharedFileLinkPayload Function(String)>{
      SharedFileLinkParams.dataTxId: (id) =>
          fullPayload().copyWith(dataTxId: id),
      SharedFileLinkParams.metadataTxId: (id) =>
          fullPayload().copyWith(metadataTxId: id),
      SharedFileLinkParams.owner: (id) =>
          fullPayload().copyWith(ownerAddress: id),
      SharedFileLinkParams.bundledIn: (id) =>
          fullPayload().copyWith(bundledInTxId: id),
      SharedFileLinkParams.thumbnailTxId: (id) =>
          fullPayload().copyWith(thumbnailTxId: id),
    };

    for (final entry in brokenIdCases.entries) {
      test('a non-canonical `${entry.key}` never reaches the wire', () {
        // `q` is alphabet index 42, which carries bits a 32 byte value does
        // not have, so a strict decoder refuses this id outright.
        final broken = '${dataTxId.substring(0, 42)}q';

        expect(isCanonical32ByteId(broken), isFalse);

        final payload =
            SharedFileLinkPayload.decode(entry.value(broken).encode())!;
        final fields = <String, Object?>{
          SharedFileLinkParams.dataTxId: payload.dataTxId,
          SharedFileLinkParams.metadataTxId: payload.metadataTxId,
          SharedFileLinkParams.owner: payload.ownerAddress,
          SharedFileLinkParams.bundledIn: payload.bundledInTxId,
          SharedFileLinkParams.thumbnailTxId: payload.thumbnailTxId,
        };

        expect(fields[entry.key], isNull);
        expectIntactExcept(payload, entry.key);
      });
    }

    test('a record whose length runs past the end costs the records only', () {
      // A length byte the payload cannot honour. Everything the bitmap already
      // placed is untouched; the records are where the reader stops.
      final payload = decodePacked(
        records: [1, 200, ...rawBytes(bundledInTxId)],
      );

      expect(payload.bundledInTxId, isNull);
      expect(payload.thumbnailTxId, isNull);
      expect(payload.dataTxId, dataTxId);
      expect(payload.metadataTxId, metadataTxId);
      expect(payload.ownerAddress, ownerAddress);
      expect(payload.name, fileName);
      expect(payload.size, fileSize);
      expect(payload.contentType, contentType);
      expect(payload.cipherIv, cipherIv);
      expect(payload.isPinned, isTrue);
      expect(payload.detailsAreHidden, isTrue);
    });

    test('a record of the wrong width is dropped, and the next one is not',
        () {
      final payload = decodePacked(
        records: [
          1, 4, 1, 2, 3, 4, //
          2, 32, ...rawBytes(thumbnailTxId), //
        ],
      );

      expect(payload.bundledInTxId, isNull);
      expect(payload.thumbnailTxId, thumbnailTxId);
      expectIntactExcept(payload, SharedFileLinkParams.bundledIn);
    });

    test('a link where nothing usable survives still parses', () {
      final payload = SharedFileLinkPayload.decode(
        encodeBytes([
          2,
          0x03 | (3 << 2),
          0xff & ~0x0f,
          0, // a zero length size
          0, // a zero length name
          250, // a content type code from no table
          9, 2, 1, 2, // a record nothing knows
        ]),
        key: SharedFileLinkKey.parse(
          'nope',
          source: SharedFileLinkKeySource.query,
        ),
      )!;

      expect(payload.version, 2);
      expect(payload.dataTxId, isNull);
      expect(payload.metadataTxId, isNull);
      expect(payload.ownerAddress, isNull);
      expect(payload.name, isNull);
      expect(payload.size, isNull);
      expect(payload.contentType, isNull);
      expect(payload.cipher, isNull);
      expect(payload.cipherIv, isNull);
      expect(payload.isPinned, isTrue);
      expect(payload.bundledInTxId, isNull);
      expect(payload.thumbnailTxId, isNull);
      expect(payload.detailsAreHidden, isTrue);
      // The key was there and was unusable, which the page must be able to say.
      expect(payload.key.isDamaged, isTrue);
      expect(payload.key.isUsable, isFalse);
    });

    test('empty values read as absent', () {
      final payload = SharedFileLinkPayload.tryParseParameters({
        ...parameters(encodeBytes([2, 0, 0])),
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

  group('SharedFileLinkPayload truncation', () {
    // A link that a chat client cut in half is the reason every field in this
    // format is skippable by something already read: the reader stops at the
    // cut and keeps what came before it, in the order the layout puts it. `dtx`
    // is first because it is the field that starts the download.
    final full = fullPayload().encode();

    test('a payload cut anywhere never throws and never lies', () {
      for (var length = 0; length <= full.length; length++) {
        final payload = SharedFileLinkPayload.decode(full.substring(0, length));

        if (payload == null) {
          continue;
        }

        expect(payload.version, 2);

        // Whatever survived is either right or absent - never a value the
        // sharer did not send.
        final claims = <List<Object?>>[
          [payload.dataTxId, dataTxId],
          [payload.metadataTxId, metadataTxId],
          [payload.ownerAddress, ownerAddress],
          [payload.name, fileName],
          [payload.size, fileSize],
          [payload.contentType, contentType],
          [payload.cipherIv, cipherIv],
          [payload.bundledInTxId, bundledInTxId],
          [payload.thumbnailTxId, thumbnailTxId],
        ];

        for (final claim in claims) {
          expect(
            claim.first,
            anyOf(isNull, claim.last),
            reason: 'cut at $length characters',
          );
        }
      }
    });

    test('a payload cut after the first id still starts the download', () {
      // 3 header bytes and 32 id bytes is 35, and 48 base64url characters are
      // 36 - the first cut that leaves `dtx` whole.
      final payload = SharedFileLinkPayload.decode(full.substring(0, 48))!;

      expect(payload.dataTxId, dataTxId);
      expect(payload.isPinned, isTrue);
      expect(payload.detailsAreHidden, isTrue);
      expect(payload.cipher, Cipher.aes256gcm);
      expect(payload.hasFastPathTarget, isTrue);
      expect(payload.name, isNull);
      expect(payload.thumbnailTxId, isNull);
    });

    test('a payload cut mid-character keeps the bytes before the cut', () {
      // 51 characters is not a whole number of base64 groups, which is what a
      // cut link actually looks like. Whether the trailing bits happen to be
      // decodable or not, at least the 48 character prefix is - and 48
      // characters are 36 bytes, one more than `dtx` needs.
      final payload = SharedFileLinkPayload.decode(full.substring(0, 51))!;

      expect(payload.dataTxId, dataTxId);
      expect(payload.metadataTxId, isNull);
    });

    test('a payload with nothing but a header left is still a payload', () {
      final payload = SharedFileLinkPayload.decode(full.substring(0, 4))!;

      expect(payload.isPinned, isTrue);
      expect(payload.dataTxId, isNull);
    });
  });

  group('SharedFileLinkPayload forward compatibility', () {
    test('a record tag this build does not know is stepped over', () {
      // What a v2.1 link looks like to today's build: a new field between the
      // two it already knows, skipped by its own length byte.
      final payload = decodePacked(
        records: [
          1, 32, ...rawBytes(bundledInTxId), //
          200, 5, 1, 2, 3, 4, 5, //
          2, 32, ...rawBytes(thumbnailTxId), //
        ],
      );

      expectIntactExcept(payload, '');
    });

    test('a record tag this build does not know may be any length', () {
      final payload = decodePacked(
        records: [
          200, 0, //
          1, 32, ...rawBytes(bundledInTxId), //
          201, 255, ...List.filled(255, 7), //
          2, 32, ...rawBytes(thumbnailTxId), //
        ],
      );

      expectIntactExcept(payload, '');
    });

    test('reserved flag bits are ignored rather than read', () {
      final payload = decodePacked(flags: 0x07 | 0xf0);

      expectIntactExcept(payload, '');
    });

    test('the first record of a tag wins over a second', () {
      // A link somebody edited by hand. The second value is no more
      // trustworthy than the first, and showing two is not an option.
      final payload = decodePacked(
        records: [
          1, 32, ...rawBytes(bundledInTxId), //
          1, 32, ...rawBytes(thumbnailTxId), //
          2, 32, ...rawBytes(thumbnailTxId), //
        ],
      );

      expect(payload.bundledInTxId, bundledInTxId);
      expectIntactExcept(payload, '');
    });
  });

  group('SharedFileLinkPayload garbage payloads', () {
    test('a payload that is not base64url at all has no payload', () {
      expect(SharedFileLinkPayload.decode('not a payload!!!'), isNull);
    });

    test('an oversized payload is refused before it is decoded', () {
      final oversized = 'A' * (SharedFileLinkPayload.maxEncodedLength + 1);

      expect(SharedFileLinkPayload.decode(oversized), isNull);
    });

    test('a payload at the size limit is still read', () {
      // Filled to the limit exactly with records nothing knows, which is both
      // the largest thing the decoder will look at and the cheapest way to
      // reach it.
      const limit = SharedFileLinkPayload.maxEncodedLength;
      const limitInBytes = limit ~/ 4 * 3;
      final bytes = <int>[2, 0x01, 0x80];

      while (bytes.length + 257 <= limitInBytes) {
        bytes.addAll([200, 255, ...List.filled(255, 7)]);
      }

      final remaining = limitInBytes - bytes.length;

      if (remaining >= 2) {
        bytes.addAll([201, remaining - 2, ...List.filled(remaining - 2, 7)]);
      }

      final encoded = encodeBytes(bytes);

      expect(encoded, hasLength(limit));
      expect(SharedFileLinkPayload.decode(encoded)?.isPinned, isTrue);
    });

    test('every single character deletion is survivable', () {
      final full = fullPayload().encode();

      for (var index = 0; index < full.length; index++) {
        final damaged = full.substring(0, index) + full.substring(index + 1);

        expect(
          () => SharedFileLinkPayload.decode(damaged),
          returnsNormally,
          reason: 'deleted character $index',
        );
      }
    });

    test('every single character substitution is survivable', () {
      final full = fullPayload().encode();

      for (var index = 0; index < full.length; index++) {
        // One from inside the alphabet and one from outside it: the first is a
        // payload that still decodes and says something else, the second is one
        // that does not decode at all.
        for (final replacement in const ['A', '%']) {
          final damaged = full.substring(0, index) +
              replacement +
              full.substring(index + 1);

          expect(
            () => SharedFileLinkPayload.decode(damaged),
            returnsNormally,
            reason: 'replaced character $index with $replacement',
          );
        }
      }
    });

    test('a payload of nothing but padding characters has no payload', () {
      expect(SharedFileLinkPayload.decode('===='), isNull);
    });
  });

  group('isCanonical32ByteId', () {
    test('accepts every id this schema stores', () {
      for (final id in const [
        dataTxId,
        metadataTxId,
        ownerAddress,
        bundledInTxId,
        thumbnailTxId,
        fileKey,
        otherFileKey,
      ]) {
        expect(isCanonical32ByteId(id), isTrue, reason: id);
        expect(rawBytes(id), hasLength(32), reason: id);
      }
    });

    test('rejects a 43 character id that does not decode to 32 bytes', () {
      // The shape the design plan's examples used to have. `q` is alphabet
      // index 42, which carries bits a 32 byte value does not have.
      expect(
        isCanonical32ByteId('${dataTxId.substring(0, 42)}q'),
        isFalse,
      );
    });

    test('rejects anything that is not 43 base64url characters', () {
      expect(isCanonical32ByteId(''), isFalse);
      expect(isCanonical32ByteId(dataTxId.substring(0, 42)), isFalse);
      expect(isCanonical32ByteId('${dataTxId.substring(0, 42)}!'), isFalse);
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
    final encoded = fullPayload().encode();

    SharedFileLinkKey resolve(String location) =>
        SharedFileLinkKey.resolve(Uri.parse(location));

    test('a fragment key wins over both query sources', () {
      final key = resolve(
        '/file/$fileId/view?${SharedFileLinkParams.payload}=$encoded'
        '&${SharedFileLinkParams.key}=$otherFileKey'
        '&${SharedFileLinkParams.legacyKey}=$otherFileKey'
        '#${SharedFileLinkParams.key}=$fileKey',
      );

      expect(key.source, SharedFileLinkKeySource.fragment);
      expect(key.raw, fileKey);
    });

    test('the v2 key wins over the legacy key', () {
      final key = resolve(
        '/file/$fileId/view?${SharedFileLinkParams.payload}=$encoded'
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
      final key = resolve(
        '/file/$fileId/view?${SharedFileLinkParams.payload}=$encoded',
      );

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
        '/file/$fileId/view?${SharedFileLinkParams.payload}=$encoded'
        '&${SharedFileLinkParams.key}=${fileKey.substring(0, 41)}'
        '&${SharedFileLinkParams.legacyKey}=$otherFileKey',
      );

      expect(key.source, SharedFileLinkKeySource.query);
      expect(key.isDamaged, isTrue);
      expect(key.raw, isNull);
    });

    test('an empty higher source defers to a present lower source', () {
      final key = resolve(
        '/file/$fileId/view?${SharedFileLinkParams.key}='
        '&${SharedFileLinkParams.legacyKey}=$fileKey',
      );

      expect(key.source, SharedFileLinkKeySource.legacyQuery);
      expect(key.raw, fileKey);
    });

    test('a junk fragment does not throw', () {
      final key = resolve('/file/$fileId/view?d=$encoded#not-a-parameter-list');

      expect(key, SharedFileLinkKey.absent);
    });

    test('the key is never part of the payload', () {
      // The payload is one opaque parameter, so the only thing keeping the key
      // out of it is that it is never written there - which is what makes the
      // key independently placeable in a fragment.
      final payload = fullPayload().copyWith(
        key: SharedFileLinkKey.parse(
          fileKey,
          source: SharedFileLinkKeySource.query,
        ),
      );

      expect(payload.encode(), isNot(contains(fileKey)));
      expect(
        SharedFileLinkPayload.decode(payload.encode())!.key,
        SharedFileLinkKey.absent,
      );
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
        SharedFileLinkParams.payload: encodeBytes(
          [2, 0, 0x01, ...rawBytes(dataTxId)],
        ),
      });
    });

    test('writes flags only when set', () {
      const payload = SharedFileLinkPayload(
        isPinned: true,
        detailsAreHidden: true,
      );

      expect(payload.toQueryParameters(), {
        SharedFileLinkParams.payload: encodeBytes([2, 0x03, 0]),
      });
    });

    test('every parameter name it writes is part of the schema', () {
      expect(
        fullPayload().toQueryParameters(includeKey: true).keys,
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

    test('a v2 link is one payload parameter', () {
      final location = buildSharedFileLinkLocation(
        fileId: fileId,
        payload: fullPayload(),
      );

      expect(
        location,
        '/file/$fileId/view?d=${fullPayload().encode()}',
      );
      expect(parse(location), fullPayload());
    });

    test('a name full of URL separators cannot reach the URL', () {
      // The readable schema had to escape these. A packed payload cannot carry
      // them at all: the name is bytes inside base64url, so a `#` in a file
      // name is no longer one character away from ending the query.
      const payload = SharedFileLinkPayload(name: 'a&b=c?d#e.txt');
      final location =
          buildSharedFileLinkLocation(fileId: fileId, payload: payload);

      expect(location.split('?').last, matches(RegExp(r'^d=[A-Za-z0-9_-]+$')));
      expect(parse(location)!.name, 'a&b=c?d#e.txt');
    });

    test('a space in a name never needs escaping', () {
      const payload = SharedFileLinkPayload(name: fileName);
      final location =
          buildSharedFileLinkLocation(fileId: fileId, payload: payload);

      expect(location, isNot(contains('%20')));
      expect(location, isNot(contains('+')));
      expect(parse(location)!.name, fileName);
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
      expect(query, isNot(contains(fileKey)));

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
        '/share/$fileId?d=${payload.encode()}',
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

  group('the encoder writes only what the reader keeps', () {
    /// What a link actually carries, after a full round trip.
    SharedFileLinkPayload roundTrip(SharedFileLinkPayload payload) {
      final location = buildSharedFileLinkLocation(
        fileId: fileId,
        payload: payload,
      );

      return SharedFileLinkPayload.tryParse(Uri.parse(location))!;
    }

    test('an over-long name is shortened rather than spent and discarded', () {
      // The two ends disagreed: `_encodeText` truncates to 255 *bytes*, while
      // `sanitizeName` drops anything over `maxNameLength` *characters* on the
      // way back in. A 150 character name was written into the link and then
      // thrown away by the reader - bytes spent for nothing, and no name shown
      // until the metadata resolved.
      final tooLong = 'a' * (SharedFileLinkPayload.maxNameLength + 30);

      final carried = roundTrip(SharedFileLinkPayload(
        dataTxId: dataTxId,
        name: tooLong,
      )).name;

      expect(carried, isNotNull);
      expect(carried!.length, SharedFileLinkPayload.maxNameLength);
      expect(tooLong.startsWith(carried), isTrue);
    });

    test('a name the reader would reject is never written', () {
      // A right-to-left override cannot be shortened into something
      // acceptable, so it is dropped at the encoder instead of carried to a
      // reader that will drop it.
      final carried = roundTrip(const SharedFileLinkPayload(
        dataTxId: dataTxId,
        name: 'invoice\u202Egpj.exe',
      )).name;

      expect(carried, isNull);
    });

    test('a wide name is shortened on a rune boundary', () {
      // Three bytes per character, so this is over the byte limit as well as
      // the character one, and must not be cut through a rune.
      final wide = '\u65e5' * (SharedFileLinkPayload.maxNameLength + 10);

      final carried = roundTrip(SharedFileLinkPayload(
        dataTxId: dataTxId,
        name: wide,
      )).name;

      expect(carried, isNotNull);
      expect(carried, wide.substring(0, carried!.length));
      expect(carried.contains('\ufffd'), isFalse);
    });
  });

  group('round trips of the example links of §1.3', () {
    // The plan's examples are written on the Phase 3 path route
    // (`/share/{fileId}?d=…`); the schema is transport independent, so these
    // exercise the same payload on the Phase 1 hash route.
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
        name: fileName,
        size: fileSize,
        contentType: contentType,
      ));
    });

    test('private file, keyless', () {
      expectRoundTrip(const SharedFileLinkPayload(
        dataTxId: dataTxId,
        metadataTxId: metadataTxId,
        ownerAddress: ownerAddress,
        name: fileName,
        size: fileSize,
        contentType: contentType,
        cipher: Cipher.aes256gcm,
        cipherIv: cipherIv,
      ));
    });

    test('private file, key in link', () {
      final payload = SharedFileLinkPayload(
        dataTxId: dataTxId,
        metadataTxId: metadataTxId,
        ownerAddress: ownerAddress,
        name: fileName,
        size: fileSize,
        contentType: contentType,
        cipher: Cipher.aes256gcm,
        cipherIv: cipherIv,
        key: SharedFileLinkKey.parse(
          fileKey,
          source: SharedFileLinkKeySource.query,
        ),
      );

      // The key is part of the payload object, so the round trip carries it: on
      // the hash route it rides in the pseudo query, which no server ever sees.
      expectRoundTrip(payload);
    });

    test('pinned to a version, private, name hidden', () {
      expectRoundTrip(const SharedFileLinkPayload(
        isPinned: true,
        detailsAreHidden: true,
        dataTxId: bundledInTxId,
        metadataTxId: thumbnailTxId,
        ownerAddress: ownerAddress,
        size: fileSize,
        cipher: Cipher.aes256ctr,
        cipherIv: cipherIv,
      ));
    });

    test('every field at once', () {
      expectRoundTrip(fullPayload());
    });

    test('generalized viewer hints', () {
      // `/view/{txId}?n=…&ct=…` is a Phase 3 route, and the only route that
      // still spells `n` and `ct` out: it has no payload of its own.
      expectRoundTrip(const SharedFileLinkPayload(
        name: 'talk.mp4',
        contentType: 'video/mp4',
      ));
    });
  });
}
