import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:ardrive_crypto/ardrive_crypto.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart' as ar_utils;
import 'package:flutter_test/flutter_test.dart';

/// Real crypto end to end: a real RSA-4096 key signs a real ANS-104 data item
/// (deep hash + RSA-PSS, via `package:arweave`), and the verifier re-derives
/// that hash from the data as it streams. Nothing here is mocked — a wrong
/// hash, a wrong tag encoding or a wrong field order fails the test.
void main() {
  late Wallet wallet;
  late String owner;

  // ~300 KiB, enough to arrive in many chunks.
  final data = _pseudoRandomBytes(300 * 1024, seed: 1337);
  const tags = [
    DataItemTag('Content-Type', 'application/octet-stream'),
    DataItemTag('Cipher', 'AES256-CTR'),
    DataItemTag('Cipher-IV', 'qq6i7g4dJ+ZQR5cE'),
    DataItemTag('App-Name', 'ArDrive-App'),
  ];

  // A second, tiny item for the tests that would otherwise push 300 KiB
  // through the verifier one byte at a time.
  final smallData = _pseudoRandomBytes(3000, seed: 7);

  late DataItem signedDataItem;
  late DataItem signedSmallDataItem;

  setUpAll(() async {
    wallet = Wallet.fromJwk(json.decode(_testWalletJwk));
    owner = await wallet.getOwner();

    signedDataItem = DataItem.withBlobData(owner: owner, data: data);
    signedSmallDataItem = DataItem.withBlobData(owner: owner, data: smallData);
    for (final tag in tags) {
      signedDataItem.addTag(tag.name, tag.value);
      signedSmallDataItem.addTag(tag.name, tag.value);
    }
    await signedDataItem.sign(ArweaveSigner(wallet));
    await signedSmallDataItem.sign(ArweaveSigner(wallet));
  });

  StreamedDataItemVerifier newVerifier({
    String? dataItemId,
    String? signature,
    String? ownerOverride,
    List<DataItemTag>? tagsOverride,
  }) {
    return StreamedDataItemVerifier(
      dataItemId: dataItemId ?? signedDataItem.id,
      owner: ownerOverride ?? owner,
      signature: signature ?? signedDataItem.signature,
      tags: tagsOverride ?? tags,
    );
  }

  group('verified', () {
    test('accepts a correctly signed data item fed chunk by chunk', () async {
      final verifier = newVerifier();

      for (final chunk in _split(data, 64 * 1024)) {
        await verifier.addChunk(chunk);
      }
      final result = await verifier.finish();

      expect(result.verdict, DataItemIntegrityVerdict.verified);
      expect(result.isVerified, isTrue);
      expect(result.reason, isNull);
      expect(result.bytesHashed, data.length);
    });

    test('accepts data whatever the chunk boundaries are', () async {
      for (final chunkSize in [17, 4096, data.length]) {
        final verifier = newVerifier();
        for (final chunk in _split(data, chunkSize)) {
          await verifier.addChunk(chunk);
        }

        final result = await verifier.finish();
        expect(
          result.verdict,
          DataItemIntegrityVerdict.verified,
          reason: 'chunked at $chunkSize',
        );
      }
    });

    test('accepts data fed one byte at a time', () async {
      final verifier = StreamedDataItemVerifier(
        dataItemId: signedSmallDataItem.id,
        owner: owner,
        signature: signedSmallDataItem.signature,
        tags: tags,
      );

      for (final chunk in _split(smallData, 1)) {
        await verifier.addChunk(chunk);
      }

      final result = await verifier.finish();
      expect(result.verdict, DataItemIntegrityVerdict.verified);
      expect(result.bytesHashed, smallData.length);
    });

    test('tap() passes the bytes through untouched', () async {
      final verifier = newVerifier();

      final seen = <int>[];
      await for (final chunk in verifier.tap(_streamOf(data, 32 * 1024))) {
        seen.addAll(chunk);
      }

      expect(Uint8List.fromList(seen), data);
      expect((await verifier.finish()).isVerified, isTrue);
    });

    test('finish() is idempotent', () async {
      final verifier = newVerifier();
      await verifier.addChunk(data);

      final first = await verifier.finish();
      final second = await verifier.finish();

      expect(identical(first, second), isTrue);
      expect(second.isVerified, isTrue);
      expect(verifier.isVerifying, isFalse);
    });
  });

  group('failed', () {
    test('rejects a single flipped byte', () async {
      final tampered = Uint8List.fromList(data);
      tampered[123456] = tampered[123456] ^ 0x01;

      final verifier = newVerifier();
      for (final chunk in _split(tampered, 64 * 1024)) {
        await verifier.addChunk(chunk);
      }
      final result = await verifier.finish();

      expect(result.verdict, DataItemIntegrityVerdict.failed);
      expect(result.isFailed, isTrue);
      expect(result.reason, isNotNull);
    });

    test('rejects truncated data', () async {
      final verifier = newVerifier();
      await verifier.addChunk(Uint8List.sublistView(data, 0, data.length - 16));

      expect((await verifier.finish()).verdict, DataItemIntegrityVerdict.failed);
    });

    test('rejects data with extra bytes appended', () async {
      final verifier = newVerifier();
      await verifier.addChunk(data);
      await verifier.addChunk(Uint8List.fromList([0, 1, 2, 3]));

      expect((await verifier.finish()).verdict, DataItemIntegrityVerdict.failed);
    });

    test('rejects an id that does not match the signature', () async {
      final verifier = newVerifier(
        dataItemId: ar_utils.encodeBytesToBase64(
          _pseudoRandomBytes(32, seed: 9),
        ),
      );
      await verifier.addChunk(data);

      expect((await verifier.finish()).verdict, DataItemIntegrityVerdict.failed);
    });

    test('rejects tampered tags', () async {
      final verifier = newVerifier(
        tagsOverride: const [
          DataItemTag('Content-Type', 'application/octet-stream'),
          DataItemTag('Cipher', 'AES256-GCM'), // was AES256-CTR
          DataItemTag('Cipher-IV', 'qq6i7g4dJ+ZQR5cE'),
          DataItemTag('App-Name', 'ArDrive-App'),
        ],
      );
      await verifier.addChunk(data);

      expect((await verifier.finish()).verdict, DataItemIntegrityVerdict.failed);
    });

    test('rejects a signature that does not belong to the owner', () async {
      // The real modulus with its last bit flipped: still a well formed 4096
      // bit RSA key, just not the one that signed this item.
      final otherOwnerBytes =
          Uint8List.fromList(ar_utils.decodeBase64ToBytes(owner));
      otherOwnerBytes[otherOwnerBytes.length - 1] ^= 0x01;

      final verifier = newVerifier(
        ownerOverride: ar_utils.encodeBytesToBase64(otherOwnerBytes),
      );
      await verifier.addChunk(data);

      final result = await verifier.finish();
      expect(result.verdict, DataItemIntegrityVerdict.failed);
    });
  });

  group('notVerified — the cases we cannot know about', () {
    test('a resumed download reports notVerified, not a failure', () async {
      final verifier = newVerifier();

      // The first half was written by a previous, now dead, download.
      await verifier.addChunk(Uint8List.sublistView(data, 0, 128 * 1024));
      verifier.markUnverifiable('Download was resumed');

      // The rest of the (perfectly good) file streams in.
      await verifier.addChunk(Uint8List.sublistView(data, 128 * 1024));

      final result = await verifier.finish();
      expect(result.verdict, DataItemIntegrityVerdict.notVerified);
      expect(result.isNotVerified, isTrue);
      expect(result.reason, 'Download was resumed');
      expect(verifier.isVerifying, isFalse);
    });

    test('marking unverifiable wins even when the data is perfect', () async {
      final verifier = newVerifier();
      await verifier.addChunk(data);
      verifier.markUnverifiable('Hash context lost');

      expect(
        (await verifier.finish()).verdict,
        DataItemIntegrityVerdict.notVerified,
      );
    });

    test('the unavailable verifier accepts chunks and reports notVerified',
        () async {
      final verifier =
          StreamedDataItemVerifier.unavailable('No signature in GraphQL');

      await verifier.addChunk(data);
      final result = await verifier.finish();

      expect(result.verdict, DataItemIntegrityVerdict.notVerified);
      expect(result.reason, 'No signature in GraphQL');
      expect(verifier.isVerifying, isFalse);
    });

    test('a non-Arweave signature type is notVerified, never failed', () async {
      // An Ethereum-signed data item: 65 byte owner and signature.
      final verifier = StreamedDataItemVerifier(
        dataItemId: signedDataItem.id,
        owner: ar_utils.encodeBytesToBase64(_pseudoRandomBytes(65, seed: 11)),
        signature:
            ar_utils.encodeBytesToBase64(_pseudoRandomBytes(65, seed: 12)),
        tags: tags,
      );

      // Feeding must not hang even though nothing is consuming the chunks.
      for (final chunk in _split(data, 64 * 1024)) {
        await verifier.addChunk(chunk);
      }

      final result = await verifier.finish();
      expect(result.verdict, DataItemIntegrityVerdict.notVerified);
      expect(result.reason, contains('Unsupported signature type'));
    });

    test('missing owner or signature is notVerified', () async {
      for (final verifier in [
        StreamedDataItemVerifier(
          dataItemId: signedDataItem.id,
          owner: '',
          signature: signedDataItem.signature,
        ),
        StreamedDataItemVerifier(
          dataItemId: signedDataItem.id,
          owner: owner,
          signature: '',
        ),
        StreamedDataItemVerifier(
          dataItemId: '',
          owner: owner,
          signature: signedDataItem.signature,
        ),
      ]) {
        await verifier.addChunk(data);
        expect(
          (await verifier.finish()).verdict,
          DataItemIntegrityVerdict.notVerified,
        );
      }
    });

    test('malformed base64 in the signature is notVerified', () async {
      final verifier = newVerifier(signature: 'not base64 !!!!');
      await verifier.addChunk(data);

      final result = await verifier.finish();
      expect(result.verdict, DataItemIntegrityVerdict.notVerified);
    });
  });

  test('the verdict does not depend on the order chunks are added in, only '
      'on their content', () async {
    final forwards = newVerifier();
    for (final chunk in _split(data, 100 * 1024)) {
      await forwards.addChunk(chunk);
    }

    final shuffled = newVerifier();
    final chunks = _split(data, 100 * 1024).toList();
    for (final chunk in chunks.reversed) {
      await shuffled.addChunk(chunk);
    }

    expect((await forwards.finish()).isVerified, isTrue);
    expect((await shuffled.finish()).isFailed, isTrue);
  });
}

Uint8List _pseudoRandomBytes(int length, {required int seed}) {
  final random = Random(seed);
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}

Iterable<Uint8List> _split(Uint8List data, int chunkSize) sync* {
  for (var i = 0; i < data.length; i += chunkSize) {
    yield Uint8List.sublistView(data, i, min(i + chunkSize, data.length));
  }
}

Stream<Uint8List> _streamOf(Uint8List data, int chunkSize) async* {
  for (final chunk in _split(data, chunkSize)) {
    yield chunk;
  }
}

/// A throwaway RSA-4096 key. This is the same key the app's own test suite
/// uses (`test/test_utils/utils.dart`); it protects nothing.
const _testWalletJwk = '''
  {
    "kty": "RSA",
    "e": "AQAB",
    "n": "kmM4O08BJB85RbxfQ2nkka9VNO6Czm2Tc_IGQNYCTSXRzOc6W9bHRrlZ_eDhWO0OdfaRalgLeuYCXx9DV-n1djeerKHdFo2ZAjRv5WjL_b4IxbQnPFnHOSNHVg49yp7CUWUgDQOKtylt3x0YENIW37RQPZJ-Fvyk7Z0jvibj2iZ0K3K8yNenJ4mWswyQdyPaJcbP6AMWvUWT62giWHa3lDgBZNhXqakkYdoaM157kRUfrZDRSWXbilr-4f40PQF1DV5YSj81Fl72N7j30r0vL1yoj0bZn74WRquQ5j3QsiAA-SzhAxpecWniljj1wvZlyIgJpCYCvCrKZCcCq_JW1nYP6to5YM3fAqcYRadbTNdQ3oH0Sjy8vyvLYNe48Ur_TFTTAwZxJV70BgZfkJ00BxiNTb8EhSchejabeExUkCNlOrQsCHDxOig-WXOrjX5fb4NeR3jedeYWbhN922ORLuEwVLeyjc7hBfQXU2-mYraFAVTc0QST201P7rRu-UGtZ4gRavFuOvAyYrMimFVW9dTwTrcYXFK2zKCEv2aRRQAHZanKjBv0Xq9m3BqvxKy-_3Cj1O6ft7FT21drPoDRDzfnkyOeUjlXzRJzn-iQ0nqgHAQr9WBWPzLEcaTFpw3KmwDYHW_6JOkUWDyMW9anuS8cyqt_2O29SK_rHHuucD8",
    "d": "Bq6C13vknF6Ln1MrKI3Ilq-83IuSvQpe7NRAuT69u7i8sv4XwsHOJAV7qpGvp37NXT5R1G3ehEZ6qoSxJbcN4IVrQMKq5mMiCY6DBv5C6fHZGoNZE2gxXV7uydf8I1Vnnw4xYIj5oyC_5nSJlFAc3U-MAcbkfJuvrhGxLVGsrqHmjoqQPGG_hTxCjuAOlOBs-9cmWTujbm1-OyjaAQwfTbXYbUy7hC1TCE05SxLPmTUwaJxY8AXJigpbYqjpWsc15HjRlv38A44tEnIwHjHda_3JpmbSsffSslRej2vPCCgSPHHyLeO437Nc7DraogKStugisRfhoe89yY4QSBVXbtvWJeF1LxPtg8uPtfoKt3wdnGWKaLDqYNDeA3AckbKrPp50kHEMR7hnNHq3lAoMAXTz8BbI_Czo5n9-f9DQpvJC8kpM7gCGG8DptA2nTPuQG02MOx7AsEE99EN8ltD_dA0l0MgG7CDsaQC5IPMHcRs1wyvZMBGA8fvZdURiVv9YSnCddndXjBJuetf5KdES-1EmrSLzo5hobQbkc7dkHMS5dmLm5YtK-aLYXZi31nRIGkA1UfZhf2TtfRxP6uKlRT106EtDX1rT3RgsLqg06y_xoS4SFQ6u-8wHqgbIHBmKdsWVtBkC4SGUlYDPgrJe2V9CaPFAcoSDFK1D_IPvU2U",
    "p": "zhyauK0ISMg9Wk7iZK2ifW2cj5KSr-_k_Em0nfUrtsaKp0iXOsCKxOH__zcAVj7oLxaEP2l8i2Pdi7CzhVRiqrjgVwA1JuLPgxtryuVqwRCYbO_Y_2Xutk404iKmDX6_LQ7BeIzUI8GD6rQCeLq1HBd3Yvok9bPvbbMZjFtUmBf_Kfb0cYP8tewMmV_USGpqwJXdB_4aHF6qBrZBtd1KLoO1E7MNkAPk7pbiA1-KO2Xa6oY6fy2pztNe1MO7tz_QywqlDdymfhnpk41arY3A6US-ZFXOinqXKdh9uEfxiyZwzaLMNWVKEaWxRxbqSUOLV3uZS05N6B2ZqvOp2h9Csw",
    "q": "tdHmYcbJpZ0U27d_j0YvUeb6sdcuFLg2vmDgKwUamC5_vvV41LSm8LIkLuY2DAN5MKg6-HTWetKWQhgbCIbubLtX5164MFrES1YVZI-aggrYohhH8MRn_hwMZZQndv9H07WUVgQ1GZ2ZDvhO7XxPDIXyBNQ46x6V1AikHtyTmqARjgrkgs-1XN55S9rhcffixOlJ-egIDPVei_Z6YNdSpLlhtiqHOp_lX37mrPSYGxjgIZVxevpPgBhVFlnAMqC2iRd87XupmWgiluSos8I7i1VESBzwlFZGk5hRb8och4zwmDBDwx65XWngg6LneSXTWcKjKKGM2NnX7wHrZBuyRQ",
    "dp": "Gfo49fW5CZNTSEKQ_id0R2K9TMsoecw-jB2uCgqQi-TSLOtVRC5oTxA896my_SvIj8bCvEtLSzY3AhgvSCqulN3gSJbaHCCSDvAx0czAe7zfuTsxml76izeoKqg7TZAgAEnP0KXPRwJo4ff2J8lAcl3yyiLE7cLT9nuQSMRqERFVM7DQdk4wV618mQge9VGUStmYlh1MpS65N0dZWNafNuWauPTkTLZw8DFMIyizf3EC-nQYg1b6A_tYBHD3A82jPzQEQY8B3PrfGZ3DRASNv9jONk8qTQHOc5O5pLRMmUErDn_qRQCTKU483bzhooJE2a3WUEt6Pjsc1xMG4Vr3SQ",
    "dq": "cCVai36Yi-06m1cwd8fbkhH9GUpXIvKI2Z5ZRk-smqc7piY0dEZFHftS9BaMyZYu3wM09GDklfdkNLo3mmfXkftv-cbjpvelUa50HYWx0HouKrT9UpVia0sTnmfme7BztjKunuuTcQxTBvfDfxoIi_nmUHIx9Vv1IEaALITzChGnIky3q7O_8ttKR65nFevG1JvsRBeJN6z0tzG9RBQr5mxtx3Wt2Uwcp21XjOCFHVmXjT9nMmpINQNNIC8VrGSSkjaJmNWIw5WGmDnLkKzCG2vpZO1suqIIgCsYN_Ka7ETTdZt3gFdoECUpFSiay4-4MAospvgWLv8XAFXXwfSPXQ",
    "qi": "n-R81MpbwfWfqRSVgD8nDk7D8zlJ-tpMaojfTwNNqDt34Cr-BpMjxaQyEfMnzOd2dY4OV0rKhd29DIuwFEb2UERHdVWF3gM8f2byYGj4357CRkiwq6I050bUxd1ODgAXjVGNpOK_fmaNHDWfe5v3wVIcCmwH0mJxEu9kuz7fr9TJNxGJBGUphpGS6NQZDCbDXg9-FPafMeNV-Jdo0NQaKMwm8uZyW7YGSNpUXYnksrWt4Fa-B9H2KoC4PPSWESPxNooXdxK7Y0J1KbzNyrUmOl4dT6p_oFKcU-1unuDCZ11e6EmMKyUGjpDzTIAZ2XxmyWUJ06yzEw7oLo8noiCE_Q"
  }''';
