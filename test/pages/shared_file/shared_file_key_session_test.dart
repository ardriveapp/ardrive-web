import 'package:ardrive/pages/shared_file/shared_file_key_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_html/html.dart' as html;

/// Where a recipient's access key is actually kept.
///
/// Every widget test of the locked gate injects
/// `SessionKeyValueStore.inMemory` - the right seam for a widget test, and a
/// statement about nothing at all: with a store handed in, the branch that
/// picks the *real* one never runs. This file builds a [SharedFileKeySession]
/// the way `SharedFilePage` does, with no `store` argument, and then looks at
/// the browser storages underneath it.
///
/// The distinction is the whole point of the class. `sessionStorage` is scoped
/// to one tab and is gone when that tab closes. `localStorage` - which is what
/// `shared_preferences` is on the web, so it is one word away at every call
/// site - survives the tab, survives sign-out, and is readable by every page on
/// the origin, including whoever uses the machine next.
///
/// `universal_html`'s `window` is an in-memory simulation off the web, so both
/// storages exist and stay distinguishable in a VM test.
void main() {
  const fileId = 'file-id';

  // 43 base64url characters whose last character carries no stray bits - the
  // shape `SharedFileLinkKey.isWellFormed` accepts.
  const wellFormedKey = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopQ';

  final storageKey = SharedFileKeySession.storageKey(fileId);

  setUp(() {
    html.window.sessionStorage.clear();
    html.window.localStorage.clear();
  });

  test('the default store is sessionStorage, and localStorage stays empty',
      () async {
    // No `store`: exactly what the page constructs.
    final session = SharedFileKeySession();

    await session.remember(fileId, wellFormedKey);

    expect(html.window.sessionStorage[storageKey], wellFormedKey);
    expect(
      html.window.localStorage,
      isEmpty,
      reason: 'a key in localStorage outlives the tab that was given it and '
          'is readable by every other tab on this origin',
    );

    // And it is the same store the read comes back out of.
    expect(await session.read(fileId), wellFormedKey);
  });

  test('forgetting a key removes it from the tab', () async {
    final session = SharedFileKeySession();

    await session.remember(fileId, wellFormedKey);
    await session.forget(fileId);

    expect(html.window.sessionStorage, isEmpty);
    expect(await session.read(fileId), isNull);
  });

  test('a key that is not well formed is never written at all', () async {
    final session = SharedFileKeySession();

    await session.remember(fileId, 'not-a-key');

    expect(html.window.sessionStorage, isEmpty);
    expect(html.window.localStorage, isEmpty);
  });
}
