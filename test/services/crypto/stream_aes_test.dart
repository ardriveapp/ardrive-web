// Fails to compile when testing on chrome
@TestOn('vm')

import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/services/crypto/stream_aes.dart';
import 'package:async/async.dart';
import 'package:cryptography/cryptography.dart';
import 'package:test/test.dart';

import 'stream_aes_test_helpers.dart';

const _aes256KeyLengthBytes = 32;
const _aesNonceLengthBytes = 12;

final _testKey = sequentialBytes(_aes256KeyLengthBytes);

const _testDataLength = 123 * 1024 + 123;
final _testData = sequentialBytes(_testDataLength);
Stream<Uint8List> _testDataStreamGen() => 
  bufferToStream(_testData, chunkSize: 12 * 1024 + 321);

main() {
  late final AesCtrStream ctr;
  late final AesGcmStream gcm;

  setUpAll(() async {
    ctr = await AesCtrStream.fromKeyData(_testKey);
    gcm = await AesGcmStream.fromKeyData(_testKey);
  });

  group('parity with reference', () {
    final ctrRef = AesCtr.with256bits(macAlgorithm: MacAlgorithm.empty);
    Future<Uint8List> ctrEncRefGen(Uint8List nonce) async => (await ctrRef.encrypt(
      _testData,
      secretKey: SecretKey(_testKey),
      nonce: nonce,
    )).concatenation(nonce: false, mac: false);

    final gcmRef = AesGcm.with256bits(nonceLength: _aesNonceLengthBytes);
    Future<Uint8List> gcmEncRefGen(Uint8List nonce) async => (await gcmRef.encrypt(
      _testData,
      secretKey: SecretKey(_testKey),
      nonce: nonce,
    )).concatenation(nonce: false, mac: true);

    test('GCM streamGen/reference decrypt parity', () async {
      final nonce = await gcm.generateNonce();
      final gcmEncRef = await gcmEncRefGen(nonce);
      gcmRefStreamGen() => bufferToStream(gcmEncRef, chunkSize: 1);
      
      final dataGcmDec = await gcm.decryptStreamGenerator(nonce, gcmRefStreamGen, gcmEncRef.length);
      expect(collectBytes(dataGcmDec.streamGenerator()), completion(equals(_testData)));
    });

    test('CTR streamGen/reference encrypt/decrypt parity', () async {
      final ctrEncRes = await ctr.encryptStreamGenerator(_testDataStreamGen, _testDataLength);
      final ctrEncRef = await ctrEncRefGen(ctrEncRes.nonce);
      expect(collectBytes(ctrEncRes.streamGenerator()), completion(equals(ctrEncRef)));

      final dataCtrDec = await ctr.decryptStreamGenerator(ctrEncRes.nonce, ctrEncRes.streamGenerator, _testData.length);
      expect(collectBytes(dataCtrDec.streamGenerator()), completion(equals(_testData)));
    });
  });
}
