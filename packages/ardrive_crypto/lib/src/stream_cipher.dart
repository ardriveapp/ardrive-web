import 'dart:async';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:flutter/material.dart';

class CipherStreamRes {
  final Uint8List nonce;
  final Stream<Uint8List> stream;

  CipherStreamRes(this.nonce, this.stream);
}

class CipherStreamGenRes {
  final Uint8List nonce;
  final DataStreamGenerator streamGenerator;

  CipherStreamGenRes(this.nonce, this.streamGenerator);
}

abstract class CipherStream {
  @protected
  FutureOr<Uint8List> generateNonce();
}

mixin EncryptStream implements CipherStream {
  @protected
  StreamTransformer<Uint8List, Uint8List> encryptTransformer(
    Uint8List nonce,
    int streamLength,
  );

  FutureOr<CipherStreamRes> encryptStream(
    Stream<Uint8List> plaintextStream,
    int streamLength,
  ) async {
    final nonce = await generateNonce();
    final streamCipher =
        plaintextStream.transform(encryptTransformer(nonce, streamLength));

    return CipherStreamRes(nonce, streamCipher);
  }

  FutureOr<CipherStreamGenRes> encryptStreamGenerator(
    DataStreamGenerator plaintextStreamGenerator,
    int streamLength,
  ) async {
    final nonce = await generateNonce();
    dataStreamGenerator() => plaintextStreamGenerator()
        .transform(encryptTransformer(nonce, streamLength));

    return CipherStreamGenRes(nonce, dataStreamGenerator);
  }
}

mixin DecryptStream implements CipherStream {
  /// [startOffsetBytes] is the offset into the whole ciphertext that the
  /// stream being transformed starts at. It must be aligned to the cipher's
  /// block size; implementations reject anything else.
  @protected
  StreamTransformer<Uint8List, Uint8List> decryptTransformer(
    Uint8List nonce,
    int fileSize, {
    int startOffsetBytes = 0,
  });

  /// Decrypts [plaintextStream] (in truth, the ciphertext stream).
  ///
  /// Pass [startOffsetBytes] to decrypt a stream that begins partway into the
  /// data — a resumed or ranged download. The default, `0`, decrypts from the
  /// beginning.
  FutureOr<CipherStreamRes> decryptStream(
    Uint8List nonce,
    Stream<Uint8List> plaintextStream,
    int streamLength, {
    int startOffsetBytes = 0,
  }) async {
    final streamCipher = plaintextStream.transform(decryptTransformer(
      nonce,
      streamLength,
      startOffsetBytes: startOffsetBytes,
    ));

    return CipherStreamRes(nonce, streamCipher);
  }

  FutureOr<CipherStreamGenRes> decryptStreamGenerator(
    Uint8List nonce,
    DataStreamGenerator plaintextStreamGenerator,
    int streamLength, {
    int startOffsetBytes = 0,
  }) async {
    dataStreamGenerator() => plaintextStreamGenerator().transform(
          decryptTransformer(
            nonce,
            streamLength,
            startOffsetBytes: startOffsetBytes,
          ),
        );

    return CipherStreamGenRes(nonce, dataStreamGenerator);
  }
}
