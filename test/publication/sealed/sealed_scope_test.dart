import 'package:ardrive/publication/domain/sealed/seal_codec.dart';
import 'package:test/test.dart';

const _folder = 'b0b0b0b0-0000-4000-8000-000000000002';
const _scopeRule = "the sealed scope must be the page's scope";

/// What [readSealedBlock] says of [scope] in a block for a page of
/// [pageScope]: the scope rule's message, or null when it got past it.
String? _scopeError(Map<String, dynamic> scope, Map pageScope) {
  try {
    readSealedBlock({'v': sealedVersion, 'scope': scope}, {'scope': pageScope});
  } on SealError catch (e) {
    return e.message == _scopeRule ? e.message : null;
  }
  return null;
}

void main() {
  test('a sealed scope with no type, or one unknown, is refused', () {
    const drive = {'type': 'drive'};
    expect(_scopeError({}, drive), _scopeRule);
    expect(_scopeError({'type': 'unknown'}, drive), _scopeRule);
    expect(_scopeError({'type': 'folder', 'folderId': _folder}, drive),
        _scopeRule);
  });

  test('the same scope gets past the scope rule', () {
    expect(_scopeError({'type': 'drive'}, {'type': 'drive'}), isNull);
    const folder = {'type': 'folder', 'folderId': _folder};
    expect(_scopeError({...folder}, folder), isNull);
    expect(_scopeError({'type': 'folder', 'folderId': 'c$_folder'}, folder),
        _scopeRule);
    expect(_scopeError({'type': 'drive'}, folder), _scopeRule);
  });
}
