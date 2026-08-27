# D12 prototype — `ATTACH` in the browser

The SQLite-file proposal for the drive state artifact (D12, proposed against
`#2187`) rests on two claims that nobody had executed. This is the executable
form of both.

```
tool/drive_state_prototype.sh
```

**Both hold.** The pipeline in `test/drive_state_prototype/artifact_pipeline.dart`
is the same SQL on both platforms, and both run it green.

| | vm/ffi | web/wasm (Chrome) |
|---|---|---|
| tests | 13 pass | 14 pass |
| SQLite | 3.45.1 | 3.45.1 |
| 20,000 rows → artifact | 3,194,880 B | 3,162,112 B |
| build | 33 ms | 428 ms |
| import | 47 ms | 418 ms |

For scale, the shipped JSON path measures 4 s to seal and 9 s to import at
41,767 files (`#2188`). This prototype does about 20,000 rows in 0.43 s each
way in a browser — but see **What this does not prove**, because the two are
not measuring the same work.

---

## The two claims

**Case 1, the producer.** `ATTACH` an empty database, build the frozen schema
in it, copy one drive's rows in through an explicit column projection,
`DETACH`, and read the bytes back out. Proven on both platforms. On web the
attached database is a real, separate entry in the virtual filesystem — the
test asserts its first sixteen bytes are `SQLite format 3`.

**Case 2, the consumer.** Put received bytes in the filesystem, `ATTACH` them,
refuse anything that is not the exact agreed shape, then merge with
`INSERT INTO main.x SELECT … FROM artifact.x`. Proven on both platforms. No
row becomes a Dart object at any point in either direction.

The read gate refuses all six cases it is given: a view, a trigger, an extra
table, an entity count that disagrees with the body, a foreign drive id, and an
unimplemented version. Each is checked before anything is written, and the test
asserts the target database is still empty after the refusal.

---

## Three findings that were not the question

### 1. The app's web database is not a WASM VFS at all

`lib/models/database/web.dart` opens `WebDatabase.withStorage(...)` from
`package:drift/web.dart` — the **deprecated sql.js backend**, which keeps the
database in memory and persists a serialised copy to IndexedDB. That is what
`web/sql-wasm.wasm` and `web/js/sql-wasm.js` are, and `web/index.html:332`
loads them on every page load.

So the phrase "Drift's WASM VFS" in the D12 write-up describes something this
app does not currently run. **Adopting D12 means migrating the web database
layer from `drift/web.dart` to `drift/wasm.dart` first.** That is real work
this proposal did not account for, and it should be costed before D12 is
accepted — though it is work worth doing regardless, since the backend in use
is deprecated.

This prototype therefore proves the claims against `package:sqlite3/wasm.dart`
directly, not through Drift.

### 2. `web/sqlite3.wasm` is dead weight, and is broken anyway

The repository vendors `web/sqlite3.wasm` (1,348,108 bytes) and `web/worker.js`.
Nothing references either — not `index.html`, not `lib/`. They look like the
remains of an abandoned migration to `drift/wasm.dart`.

The file also cannot be loaded by the resolved `sqlite3: 2.4.2`:

```
LinkError: WebAssembly.instantiate(): Import #0 "dart" "fs_delete":
function import requires a callable
```

It is built against a different ABI. The prototype fetches the matching
`sqlite3.wasm` (697,758 bytes) from the `sqlite3.dart` release that matches
`pubspec.lock`. Removing the two stale files is a separate, easy cleanup worth
about 1.3 MB in the deployed build.

### 3. `secure_delete` differs between the platforms, and web is the unsafe one

D12 argues the artifact must be **built up** — copy wanted rows into an empty
database — rather than **torn down** — copy everything, then delete what must
not ship. The stated reason was that `DROP TABLE` leaves the dropped bytes on
the freelist.

Measured, that is true **only when `secure_delete` is off**, and the default is
not the same everywhere:

| build | `PRAGMA secure_delete` | tear-down result |
|---|---|---|
| vm/ffi (macOS) | `2` (fast) | secret **not** recoverable |
| web/wasm | `0` (off) | secret **recoverable in the file** |

So the original claim was too strong as stated — and the platform where it does
hold is the browser, which is where the producer runs. The conclusion survives
and the reasoning improves: the safety of tear-down is not a property of our
code but of whichever SQLite build the client happens to link, and that is not
an acceptable thing to have standing between a user's wallet ciphertext and a
permanent public upload. Building up removes the question.

The suite asserts the leak under an explicit `PRAGMA secure_delete = 0` on both
platforms, and prints each platform's default rather than depending on it.

---

## What this does not prove

Stated plainly, because the numbers above are easy to over-read.

- **Nothing about Drift.** The prototype drives `package:sqlite3` directly. It
  does not use `WasmDatabase`, and it does not touch the sql.js backend the app
  actually runs on web today. Finding 1 is the gap.
- **Nothing about OPFS.** The browser run uses `InMemoryFileSystem`, so the
  whole artifact is in memory. Bounded producer memory for a very large drive
  is exactly what an OPFS-backed VFS would buy, and it is untested here.
- **No memory measurement.** A browser test cannot take one. The claim that no
  row becomes a Dart object is a property of the code, readable in
  `artifact_pipeline.dart`; it is not a measurement.
- **Not comparable to the `#2188` figures.** 20,000 synthetic rows of one table
  against 41,767 files across seven sections, with different columns. The
  timings show the pipeline is not pathological, not that it is 20× faster.
- **No encryption, signature, gzip or upload.** Everything downstream of
  `build → …` in D12 is out of scope here.
- **The projection is illustrative.** `artifactProjection` names a realistic
  subset of columns, not the real seven-section set from D2.

---

## Layout

| file | what it is |
|---|---|
| `test/drive_state_prototype/artifact_pipeline.dart` | the pipeline, as SQL, platform-agnostic |
| `test/drive_state_prototype/prototype_suite.dart` | the assertions, written once, run on both platforms |
| `test/drive_state_prototype/attach_vm_test.dart` | VM entry point |
| `test/drive_state_prototype/attach_web_test.dart` | browser entry point |
| `tool/drive_state_prototype.sh` | fetches the matching wasm, serves it, runs both |

None of it imports application code, and none of it is wired into the app.
`flutter test` picks up the VM half; the browser half needs the script, because
`flutter test --platform chrome` serves only the compiled test bundle and not
the package's own files.
