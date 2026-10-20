/// One artifact attached at a time.
library;

import 'package:drift/drift.dart';
import 'package:synchronized/synchronized.dart';

/// Held from `ATTACH` to `DETACH` by every export.
///
/// An export attaches its artifact as `artifact` on the app's one connection,
/// and a second `ATTACH` under a name in use fails. On the web that was easy
/// to reach: a snapshot modal closed mid-export left its export running, and
/// the next one opened collided with it ("database artifact is already in
/// use"). With the lock the second waits for the first. The importer needs no
/// lock: it attaches each artifact under a name of its own.
final artifactAttachLock = Lock();

/// Detaches an `artifact` a failed run left attached, so the next `ATTACH`
/// does not fail on it. Only ever called under [artifactAttachLock], where an
/// attached `artifact` cannot belong to a run still in progress.
Future<void> detachLeftoverArtifact(GeneratedDatabase db) async {
  final attached = await db.customSelect('PRAGMA database_list').get();
  if (attached.any((row) => row.read<String>('name') == 'artifact')) {
    await db.customStatement('DETACH DATABASE artifact');
  }
}
