/// The browser.
///
/// **Not yet supported, and the reason is specific.** `ATTACH` needs both
/// databases inside the same SQLite instance, and the app's web database is
/// drift's sql.js backend. `SqlJsDatabase` exposes `export()`, which returns
/// `main` — there is no way to read an *attached* database's bytes back out,
/// and drift surfaces no filesystem.
///
/// The sqlite3 WASM path does have one: `InMemoryFileSystem.fileData` is a
/// readable map, which is what makes both directions work in
/// `test/drive_state_prototype` (PR #2196). Reaching it means moving the app's
/// web database from `drift/web.dart` to `drift/wasm.dart` — deprecated
/// backend to current one — which is its own piece of work.
///
/// Until then this returns false rather than throwing at an awkward moment, so
/// a user on the web build is told the platform cannot do it yet instead of
/// watching a publish fail halfway.
library;

import 'package:ardrive/drive_state_sqlite/artifact_sink.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_export.dart';
import 'package:ardrive/drive_state_sqlite/drive_state_artifact_import.dart';

bool get artifactSinkSupported => false;

Future<ArtifactSink> createArtifactSink(String label) => throw
    ArtifactSinkUnsupported(
  'the web database is drift/web.dart (sql.js), which cannot read an attached '
  'database back out. Needs the drift/wasm.dart migration.',
);

Future<ArtifactSource> createArtifactSource(String label, List<int> bytes) =>
    throw ArtifactSinkUnsupported(
  'the web database is drift/web.dart (sql.js), which cannot attach a received '
  'database. Needs the drift/wasm.dart migration.',
);
