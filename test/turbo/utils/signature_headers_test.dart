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
}
