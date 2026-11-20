import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every read of a private file's data asks [FileKeys]
/// (lib/core/crypto/file_keys.dart) for its key. A private page (version 3)
/// carries file keys without a drive key, so a reader that derives a file key
/// from the drive key itself would not open its files, or worse, would open
/// more than the page shares.
///
/// This fails when new code under lib/ calls `deriveFileKey(` or
/// `getFileKey(`. The places below may, each for its reason, and each only as
/// many times as it does today. When one stops, lower its count; the list
/// only shrinks.
const allowed = <String, ({int calls, String why})>{
  'lib/core/crypto/file_keys.dart': (calls: 1, why: 'the one way to ask'),
  'lib/core/crypto/crypto.dart': (calls: 1, why: 'the derivation itself'),
  'lib/models/daos/drive_dao/drive_dao.dart': (
    calls: 2,
    why: 'getFileKey, which FileKeys calls'
  ),
  // Writes: they encrypt new metadata and already hold the drive key.
  'lib/entities/file_entity.dart': (
    calls: 1,
    why: 'file metadata, encrypted and decrypted with the drive'
  ),
  'lib/blocs/fs_entry_move/fs_entry_move_bloc.dart': (calls: 1, why: 'move'),
  'lib/blocs/fs_entry_rename/fs_entry_rename_cubit.dart': (
    calls: 1,
    why: 'rename'
  ),
  'lib/blocs/hide/hide_bloc.dart': (calls: 1, why: 'hide and unhide'),
  'lib/blocs/fs_entry_license/fs_entry_license_bloc.dart': (
    calls: 1,
    why: 'license'
  ),
  'lib/blocs/pin_file/pin_file_bloc.dart': (calls: 1, why: 'pin'),
  'lib/utils/upload_plan_utils.dart': (calls: 1, why: 'upload'),
};

final _call = RegExp(r'(?<![\w$])(getFileKey|deriveFileKey)\s*\(');

/// Calls in [source], with line comments taken out so a comment that names
/// a function is not a call.
int callsIn(String source) =>
    _call.allMatches(source.replaceAll(RegExp(r'//[^\n]*'), '')).length;

void main() {
  test('file keys are derived only where allowed', () {
    final found = <String, int>{};
    for (final entity in Directory('lib').listSync(recursive: true)) {
      final path = entity.path.replaceAll(r'\', '/');
      if (entity is! File ||
          !path.endsWith('.dart') ||
          path.endsWith('.g.dart')) {
        continue;
      }
      final calls = callsIn(entity.readAsStringSync());
      if (calls > 0) found[path] = calls;
    }

    final problems = <String>[
      for (final MapEntry(key: path, value: calls) in found.entries)
        if (allowed[path] == null)
          '$path derives a file key $calls time(s); ask FileKeys instead'
        else if (calls > allowed[path]!.calls)
          '$path derives a file key $calls times, '
              'more than its ${allowed[path]!.calls}; ask FileKeys instead',
      for (final MapEntry(key: path, value: entry) in allowed.entries)
        if ((found[path] ?? 0) < entry.calls)
          '$path now derives a file key ${found[path] ?? 0} time(s); '
              'lower its count here to match',
    ];
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('the scan finds a call, and skips one in a comment', () {
    expect(callsIn('final k = await dao.getFileKey(id, key);'), 1);
    expect(callsIn('await _crypto.deriveFileKey(driveKey.key, id)'), 1);
    expect(callsIn('// uses deriveFileKey(driveKey, fileId)'), 0);
    expect(callsIn('_getFileKey(fileId: id)'), 0);
  });
}
