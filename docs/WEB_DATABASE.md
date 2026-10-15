# The web database: SQLite on OPFS in a dedicated worker

Status: plan, 2026-10-15. Decided by measurement (below), to be built on
`PE-9205-drive-state-sqlite` before #2197 ships, so every web user migrates
once.

## Why

#2197 moves the web database off sql.js to SQLite in wasm, on the page's main
thread, saved to IndexedDB block by block (`IndexedDbFileSystem`, package
`sqlite3` 2.4.2). It works, and it is slow: every large write freezes the UI
while it runs, then keeps writing to IndexedDB for seconds afterwards, and the
whole database is read into memory on every start. That migration has not
shipped (#2264 only removed an unused wasm file), so the target can still
change.

## What was measured

Release builds (dart2js), the app's real schema through the app's own
`Database` class, Chromium 151 and Firefox 131 headless, 2026-10-15. "Write"
is the rows a 41,767-file drive state import lands, in one transaction.

| | Chromium | Firefox |
|---|---|---|
| **Write, worker + OPFS** | **0.63 s**, saved at commit | **5.4 s**, saved at commit |
| Write, #2197 as is | 15.5 s, then 7.4 s more to save | 15.4 s, then 16.8 s more |
| **Reopen, worker + OPFS** | **0.08 s** | **0.12 s** |
| Reopen, #2197 as is | 3.5 s | 3.2 s |
| One standalone insert | 3.3 ms (today 10.6 ms) | 8.5 ms (today 10.5 ms) |
| One select | 0.16 ms (today 0.02 ms) | 0.70 ms (today 0.02 ms) |
| 3,000 single inserts in one transaction | 485 ms (today 28 ms) | 2,312 ms (today 40 ms) |
| Live query fires after an insert | 28 ms | 33 ms |

Also established:

- **Crash safety.** The worker was killed inside a real 41,767-row transaction
  at 100, 250, 300, 400 ms and 3 s: the database came back with no rows and
  passed `PRAGMA integrity_check`. Killed at 550 ms, just after the commit, it
  came back with all of them. Never torn: the rollback journal lives in OPFS
  beside the database and `xSync` flushes it.
- **Artifacts work.** A file path the OPFS filesystem does not own goes to its
  in-memory filesystem, so an artifact built by `ATTACH` in the worker can be
  read out (export), and one handed in can be attached (import), and both are
  freed by a delete.
- **A second tab is refused cleanly** (`NoModificationAllowedError` from
  `createSyncAccessHandle`), and can still read the database file directly
  from the page.
- **Rejected alternatives.** Drift 2.16's own OPFS needs cross-origin
  isolation headers on Chrome. Served with them, the app's audio and video
  previews failed (`require-corp`: gateways send no CORP header) and Stripe's
  card field never rendered (either COEP mode), and the app is also served
  from AR.IO gateways, where headers cannot be set. Drift's IndexedDB shared
  worker lost a committed write when the browser closed soon after. Newer
  drift (2.33 and later) needs Dart 3.10, a Flutter upgrade, and adds no
  header-free OPFS mode for Chrome.

The one cost is a round trip per statement (about 0.15 ms in Chromium, 0.7 ms
in Firefox). The bulk paths do not pay it: sync writes through `batch()`, one
round trip per batch, and the artifact import is a handful of statements.
Code that issues thousands of separate statements does pay it, and §6 finds
and fixes those before this ships.

## 1. Architecture

```
 page (Flutter, main thread)                 dedicated worker (db_worker.js)
 ┌──────────────────────────────┐            ┌──────────────────────────────────┐
 │ Database(remote(port))       │◄─ drift ──►│ DriftServer                      │
 │   every DAO, stream, migration│  protocol  │   WasmDatabase(sqlite3, '/database')
 │                              │            │ SimpleOpfsFileSystem             │
 │ artifact sink / source       │◄─ files ──►│   OPFS: ardrive-db/<name>/       │
 │   (put, read, delete)        │  requests  │     database, journal, meta      │
 └──────────────────────────────┘            │   anything else: in memory       │
                                             └──────────────────────────────────┘
```

- **`web/db_worker.dart`**, compiled to `db_worker.js` with `dart compile js
  -O4`, served beside `sqlite3.wasm`. Plain Dart: drift, sqlite3, nothing from
  Flutter. It owns SQLite, the OPFS files and a `DriftServer`. Besides the
  drift port it answers four requests: `open`, `putFile`, `readFile`,
  `deleteFile`, the last three only for in-memory paths.
- **`lib/models/database/web.dart`** spawns the worker, opens it, and returns
  `remote(port)` as the executor. `Database`, every DAO and every migration
  run unchanged.
- **The OPFS directory is `ardrive-db/ardrive`.** Three files: `database`,
  `journal`, `meta`.

## 2. Which tab writes

One tab writes. The rest get a read-only session copy, which is what #2197
already gives them.

1. The tab takes the `ardrive-database` Web Lock (`claimWriterLock`, as now).
2. The lock holder opens OPFS in its worker. A refusal from OPFS
   (`NoModificationAllowedError`) also means another tab holds it, whatever
   the lock said: the file system is the authority, the lock the courtesy.
3. Any other tab reads the `database` file directly from OPFS, runs
   `PRAGMA integrity_check` on the copy, and opens it in its own worker on the
   in-memory filesystem. A copy read during a commit can be torn, so a failed
   check retries, three times, then the tab starts with an empty session
   database and the existing "open in another tab" notice. Writes in a reader
   tab are lost on close, as now.

## 3. When OPFS is not there

The worker reports why it could not open: no OPFS (older Safari, Firefox
private windows), no worker script (a dev build without it), or an error.
Then:

- **OPFS never held this user's database** (no `ardrive-db` directory): use
  #2197's main-thread IndexedDB path, unchanged. It is built and tested, and
  it is today's behaviour plus the sql.js migration.
- **OPFS holds a database but did not open:** do not fall back to IndexedDB,
  which holds an older copy or nothing, and writing there would split the
  user's data. Open a read-only session copy as a second tab would, and log
  the reason.

## 4. Migration

On the first open, the OPFS `database` file is empty and `meta` carries no
migrated mark. In the worker, before SQLite opens the file:

1. **#2197's store** (`IndexedDbFileSystem` `ardrive_sqlite3`, `/db.sqlite`),
   if it exists. Only preview and staging testers have one.
2. **The sql.js store** (`DriftWebStorage` `db`), which every production user
   has.
3. Neither: a fresh database.

The page reads the bytes (both stores are IndexedDB, reachable from the page)
and hands them to the worker. The worker refuses anything that is not a SQLite
file or fails `PRAGMA quick_check` (the checks #2197 already has), writes the
bytes to `database`, flushes, then marks `meta`. A failure before the mark
leaves OPFS empty and the old store untouched, so the next start tries again.
The old stores are left in place, so a rollback build still finds them;
deleting them is a later release's job.

## 5. Artifacts

The web `ArtifactSink` and `ArtifactSource` become requests to the worker:

- **Export:** the sink is an in-memory path in the worker; the export
  `ATTACH`es it as before; `read()` is a `readFile`; `dispose()` a
  `deleteFile`.
- **Import:** the source is a `putFile` of the received bytes; the importer
  attaches its path as before; `dispose()` deletes it.

Nothing about the drive state format or the importer's checks changes.
On the IndexedDB fallback the existing implementations stay.

## 6. The round-trip audit

Find every path that issues many separate statements and batch it where it
matters. Known so far: sync writes are batched. To check: `getFolderTree`
(recursive, one query per folder), drive deletion, upload bookkeeping per
file, licence and ArNS lookups per file, the confirmation pass. The gate: no
measured flow slower than #2197 as is, in Chromium or Firefox.

## 7. Build

- CI (`pr.yaml`, `staging.yaml`, `production.yaml`) compiles the worker after
  `flutter build web` into `build/web/db_worker.js`.
- Locally `scr setup` compiles it into `web/db_worker.js` (git-ignored), so
  `flutter run -d chrome` serves it. Without it the app takes the IndexedDB
  fallback, so a missing step never breaks a developer.
- `tool/browser_tests.sh` compiles it before serving.

## 8. Tests

**Browser tests** (CI, headless Chromium):

- open through the worker; create and upgrade the schema from version 29;
  read, write, delete;
- live queries refresh across the worker, for drift's batch API and for
  `customUpdate` with named tables;
- artifact export and import through the worker, files freed afterwards;
- migration from sql.js bytes, from #2197's store, with neither, with a
  corrupt store, and run twice;
- a second tab gets a refusal and a sound copy;
- a worker killed inside a transaction leaves a sound database;
- the fallback: no worker script, and no OPFS, both open on IndexedDB;
- logout clears the database.

**Release builds with the demo wallet**, Chromium and Firefox: login, an
ordinary sync of several drives timed against #2197 as is, an artifact import
and a publish, a reload, two tabs, logout and login again, the 41,767-file
benchmark.

**Safari:** by hand, on a Mac. The WebKit test browser needs system libraries
this machine lacks.

## 9. Order of work

1. The worker and the page side (§1), behind the fallback (§3), browser tests
   for open, read, write, live queries.
2. Migration (§4) with its tests.
3. Artifacts through the worker (§5).
4. Second tab (§2) and crash tests.
5. The round-trip audit (§6) with measurements.
6. Build wiring (§7), the full suite, release-build e2e with the demo wallet,
   then Safari by hand.
