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

abstract class EncryptStream implements CipherStream {
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
    final streamCipher = plaintextStream
      .transform(encryptTransformer(nonce, streamLength));
    
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

abstract class DecryptStream implements CipherStream {
  @protected
  StreamTransformer<Uint8List, Uint8List> decryptTransformer(
    Uint8List nonce,
    int streamLength,
  );

  FutureOr<CipherStreamRes> decryptStream(
    Uint8List nonce,
    Stream<Uint8List> plaintextStream,
    int streamLength,
  ) async {
    final streamCipher = plaintextStream
      .transform(decryptTransformer(nonce, streamLength));
    
    return CipherStreamRes(nonce, streamCipher);
  }

  FutureOr<CipherStreamGenRes> decryptStreamGenerator(
    Uint8List nonce,
    DataStreamGenerator plaintextStreamGenerator,
    int streamLength,
  ) async {
    dataStreamGenerator() => plaintextStreamGenerator()
      .transform(decryptTransformer(nonce, streamLength));
    
    return CipherStreamGenRes(nonce, dataStreamGenerator);
  }
}
