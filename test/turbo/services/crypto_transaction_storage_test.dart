import 'package:ardrive/turbo/services/crypto_transaction_storage.dart';
import 'package:ardrive/turbo/topup/models/session_lock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Another browser tab writes the same localStorage behind this tab's
/// SharedPreferences cache. Reads must see what it wrote.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const lockKey = 'flutter.ardrive_topup_session_lock';
  late CryptoTransactionStorage storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    storage = CryptoTransactionStorage(prefs);
  });

  // Swapping the mock store changes what the platform holds without touching
  // this tab's cache: what another tab's write looks like.
  void otherTabWrites(String state) => SharedPreferences.setMockInitialValues({
        lockKey: CryptoTopupSessionLock.create(tabId: 'other-tab', state: state)
            .toJsonString(),
      });

  test('a lock another tab wrote since is seen', () async {
    expect(await storage.getSessionLock(), isNull);

    otherTabWrites('processing');

    final lock = await storage.getSessionLock();
    expect(lock?.tabId, 'other-tab');
    expect(lock?.state, 'processing');
  });

  test('a lock another tab removed since is gone', () async {
    otherTabWrites('processing');
    expect(await storage.getSessionLock(), isNotNull);

    SharedPreferences.setMockInitialValues({});

    expect(await storage.getSessionLock(), isNull);
  });

  test('acquiring does not overwrite a lock another tab wrote since', () async {
    expect(await storage.getSessionLock(), isNull);
    otherTabWrites('token_selection');

    expect(await storage.acquireSessionLock('token_selection'), isFalse);
    expect((await storage.getSessionLock())?.tabId, 'other-tab');
  });
}
