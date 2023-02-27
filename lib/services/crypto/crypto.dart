import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';

export 'ciphers.dart';
export 'entities.dart';
export 'keys.dart';
export 'stream_aes.dart';

final sha256 = Sha256();

/// Returns a [SecretBox] that is compatible with our past use of AES-GCM where the cipher text
/// was appended with the MAC and the nonce was stored separately.
SecretBox secretBoxFromDataWithGcmMacConcatenation(
  Uint8List data, {
  int macByteLength = 16,
  required Uint8List nonce,
}) =>
    SecretBox(
      Uint8List.sublistView(data, 0, data.lengthInBytes - macByteLength),
      mac: Mac(Uint8List.sublistView(data, data.lengthInBytes - macByteLength)),
      nonce: nonce,
    );
