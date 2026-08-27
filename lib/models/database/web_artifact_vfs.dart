/// The one SQLite instance the web build runs, shared by the app database and
/// by drive state artifacts.
///
/// `ATTACH` requires both databases to live inside the same SQLite instance,
/// so an artifact cannot be built beside the app's database — it has to be
/// built *in* it. That makes this holder the seam: [openConnection] fills it
/// in when the database opens, and the artifact sink reads it back.
///
/// It is a global because the thing it holds is genuinely global — there is
/// one sqlite3 module per page — and passing it through every layer between
/// the database and the artifact would be threading a singleton by hand.
library;

import 'package:sqlite3/wasm.dart';

/// The loaded module and the filesystem its databases live on, or null before
/// the database has been opened.
({WasmSqlite3 sqlite3, VirtualFileSystem vfs})? webSqlite;
