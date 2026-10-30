@Tags(['measurement'])
library;

import 'dart:io';

import 'package:ardrive/models/models.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:test/test.dart';

/// What `secure_delete` costs: the delete-heavy paths, timed with it off and
/// on, on a drive the size of the 41,767-file benchmark.
///
///   flutter test test/models/database/secure_delete_cost_test.dart \
///     --run-skipped --tags=measurement
void main() {
  const files = 41767;

  Future<Duration> time(Future<void> Function() body) async {
    final watch = Stopwatch()..start();
    await body();
    return watch.elapsed;
  }

  Future<Map<String, Duration>> run(bool secure) async {
    final dir = Directory.systemTemp.createTempSync('secure_delete_cost');
    try {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final db = Database(NativeDatabase(File('${dir.path}/db.sqlite')));
      await db
          .customStatement('PRAGMA secure_delete = ${secure ? 'ON' : 'OFF'}');
      await db.batch((b) {
        for (var i = 0; i < files; i++) {
          b.insert(
            db.fileEntries,
            FileEntriesCompanion.insert(
              id: 'file-$i',
              driveId: 'drive',
              parentFolderId: 'root',
              name: 'a file name that is about as long as most $i.jpg',
              dataTxId: 'data-tx-$i-padding-padding-padding-padding',
              size: i,
              lastModifiedDate: DateTime(2026),
              path: '/root/a file name $i.jpg',
              dataContentType: const Value('image/jpeg'),
            ),
          );
        }
      });
      final results = <String, Duration>{};
      results['delete 10% of the files'] = await time(() async {
        await db.customStatement(
            'DELETE FROM file_entries WHERE CAST(substr(id, 6) AS INTEGER) % 10 = 0');
      });
      results['delete the rest (a drive, or sign-out)'] =
          await time(() => db.delete(db.fileEntries).go());
      results['VACUUM afterwards'] = await time(() => db.vacuum());
      await db.close();
      return results;
    } finally {
      dir.deleteSync(recursive: true);
    }
  }

  test('secure_delete off and on', () async {
    final off = await run(false);
    final on = await run(true);
    for (final step in off.keys) {
      // ignore: avoid_print
      print('$step: off ${off[step]!.inMilliseconds} ms, '
          'on ${on[step]!.inMilliseconds} ms');
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
