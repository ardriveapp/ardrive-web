import 'dart:async';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:ardrive/turbo/utils/get_signature_headers_for_turbo.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_utils/utils.dart';

void main() {
  test('signed headers are reused until the session is cleared', () async {
    final manager = TurboSignatureHeadersManager.getInstance(
      tabVisibility: TabVisibilitySingleton(),
    );
    final wallet = getTestWallet();
    addTearDown(TurboSignatureHeadersManager.clearSession);

    final first = await manager.getSignatureHeaders(wallet: wallet);
    final again = await manager.getSignatureHeaders(wallet: wallet);
    expect(again['x-nonce'], first['x-nonce']);

    // Sign-out: the next read signs afresh.
    TurboSignatureHeadersManager.clearSession();
    final afterSignOut = await manager.getSignatureHeaders(wallet: wallet);
    expect(afterSignOut['x-nonce'], isNot(first['x-nonce']));

    // A refusal from Turbo: the same.
    manager.clearCache();
    final afterRefusal = await manager.getSignatureHeaders(wallet: wallet);
    expect(afterRefusal['x-nonce'], isNot(afterSignOut['x-nonce']));
  });

  test('a signature still being made at sign-out is not cached after it',
      () async {
    final manager = TurboSignatureHeadersManager.getInstance(
      tabVisibility: TabVisibilitySingleton(),
    );
    addTearDown(TurboSignatureHeadersManager.clearSession);
    final real = getTestWallet();
    final release = Completer<void>();
    final wallet = _SlowWallet(real, release.future);

    final pending = manager.getSignatureHeaders(wallet: wallet);
    await Future<void>.delayed(Duration.zero);
    TurboSignatureHeadersManager.clearSession();
    release.complete();
    final inFlight = await pending;

    // The caller that asked still gets its headers...
    expect(inFlight['x-nonce'], isNotNull);
    // ...but they were not put back in the cache.
    final next = await manager.getSignatureHeaders(wallet: real);
    expect(next['x-nonce'], isNot(inFlight['x-nonce']));
  });
}

class _SlowWallet extends Wallet {
  _SlowWallet(this._real, this._gate) : super();

  final Wallet _real;
  final Future<void> _gate;

  @override
  Future<String> getAddress() => _real.getAddress();

  @override
  Future<String> getOwner() => _real.getOwner();

  @override
  Future<Uint8List> sign(Uint8List message, [String? hashAlgorithm]) async {
    await _gate;
    return _real.sign(message);
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
