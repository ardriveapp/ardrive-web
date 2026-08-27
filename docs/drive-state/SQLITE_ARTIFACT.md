# The drive state artifact as a SQLite file

The D12 counter-proposal to `docs/drive-state/DECISIONS.md` **D1**, built far
enough to be measured against `#2188` rather than argued about.

**Same feature, same drive, same tables.** The artifact carries what D2
settled: the drive, both entry tables, all three revision tables, and licences.
`network_transactions` is regenerated on import; `arns_records` and
`ant_records` do not travel. What changes is only how the rows are carried.

| | `#2188` (D1, JSON) | this branch (D12, SQLite) |
|---|---|---|
| export + import | 3,303 lines | see `lib/drive_state_sqlite/` |
| rows become Dart objects | one object and one `Map` per row, each way | none, either way |
| producer peak at 41,767 files | ~950 MiB from a 263 MiB baseline | SQLite's page cache |
| reader for another client | a spec to reimplement | `node:sqlite`, built in |

Figures from `test/drive_state_sqlite/artifact_scale_test.dart` are in
**Measurements** below.

---

## How it works

Three files, and the SQL is the implementation.

**Export** — `drive_state_artifact_export.dart`

```sql
ATTACH DATABASE '<sink>' AS artifact;
-- the frozen schema, created inside artifact
INSERT INTO artifact.file_revisions (<explicit columns>)
  SELECT <the same columns> FROM main.file_revisions WHERE driveId = ?;
-- one statement per table
INSERT INTO artifact.meta VALUES (...);
DETACH DATABASE artifact;
```

**Import** — `drive_state_artifact_import.dart` — validates everything before
writing anything, then merges in one transaction:

1. `PRAGMA integrity_check`
2. `sqlite_master` must match the frozen schema exactly — no views, no
   triggers, no virtual tables, no indexes, every DDL string identical
3. `meta` must agree with the drive being synced: version, id, owner, privacy,
   entity count, and a range that advances the watermark
4. `INSERT INTO main.x SELECT ... FROM artifact.x`, then rebuild
   `network_transactions`

Every refusal is an enumerated reason and a fallback, never a thrown surprise.
`ArtifactImportRefusal` has ten values and the caller syncs normally on any.

## Two decisions worth a reviewer's attention

**The schema is frozen, and it is not Drift's.** An artifact is a format other
clients read, so copying the app's tables would weld the wire format to
`schemaVersion`. Drift's schema also measured *worst* of every option tried —
10.14 M gzipped against 6.09 M for a frozen schema — because the indexes are
dead weight a reader throws away.

**Rows are copied in, never deleted out.** `artifactProjection` is the only
path into an artifact and it names every column. `profiles` appears nowhere in
the file. This is not a filter to be tested; it is the mechanism — an artifact
is built by selecting into an *empty* database, so an unnamed column cannot
reach one.

The alternative, copying everything and dropping what must not ship, does not
work: `DROP TABLE` leaves the dropped bytes on the freelist unless
`secure_delete` is on, and **it is off in the wasm build the browser runs**
(measured: `0` on wasm, `2` on macOS — `#2196`).

## What is not here

This is a prototype for a decision, not a feature.

- **No encryption, signing, gzip, upload, discovery, sync composition or UI.**
  Everything `#2188` does around the payload is unchanged by the container and
  deliberately out of scope.
- **The browser half is on the other branch.** `ATTACH` inside the sqlite3 WASM
  virtual filesystem is proven in `#2196`, both directions. It is not wired up
  here, because the app's web database is still drift's deprecated sql.js
  backend — migrating to `drift/wasm.dart` is D12's real prerequisite and it is
  not this branch.
- **`ArtifactSink` / `ArtifactSource` are the seam.** A file on the VM and in a
  CLI, a VFS entry in a browser. The exporter does not know which, which is
  what lets a CLI produce an artifact for a drive far too large for a tab.

## Measurements

Both branches' own measurement tests, run on the same machine, at 41,767
files. `#2188`'s figures are from checking out that branch and running
`test/drive_state/drive_state_scale_measurement_test.dart`; they reproduce its
reported sizes exactly (52.16 / 9.55 MiB), which is what makes the comparison
sound.

| | `#2188` (JSON) | this branch (SQLite) | |
|---|---|---|---|
| serialised | 52.16 MiB | **17.70 MiB** | 2.9x smaller |
| gzipped | 9.55 MiB | **5.98 MiB** | 1.6x smaller |
| bytes per entity | 1,306 | **439** | |
| **producer, end to end** | **13,004 ms** | **679 ms** | **19x** |
| — export | 9,111 ms | 267 ms | |
| — encode | 1,274 ms | none | |
| — gzip | 2,619 ms | 412 ms | |
| import, end to end | 7,444 ms | **584 ms** | 12.7x |
| process RSS | 787 MiB baseline, 1,003 MiB peak | 182 MiB baseline, 349 MiB peak | |

**On the producer figure.** `#2188`'s PR reports "seal 4 s", which is its
`jsonEncode` plus `gzip` — 3,893 ms here, matching. Its **export** step is a
separate 9,111 ms that the headline does not include. Comparing like with like
means comparing everything needed to get compressed bytes, which is 13,004 ms
against 679 ms.

**On the RSS figures.** Process-wide, monotonic, on the Dart VM — not a browser
heap, and both include the fixture's own database. The baselines differ because
the two tests build their fixtures differently, so the deltas are the honest
comparison: **+216 MiB** for the JSON path, **+167 MiB** for this one, against a
much lower floor. The JSON path's cost is concentrated in `jsonEncode + utf8`,
which is the step this branch does not have.

**Caveats, both directions.** `#2188`'s fixture carries 43,756 file revisions
(1.05 per entity) to this branch's 41,767 (1.0), and 121 folders to this
branch's 430 — so it moves about 5% more revision rows and this one moves more
folders. Neither fixture has `customJsonMetadata`, `customGQLTags` or licence
rows. Transaction ids are 32 bytes of entropy in both, which matters: an
earlier run of this branch's test reported 1.90 MiB gzipped because the fixture
interpolated counters into them, the same trap `#2188` hit and documented.

Run this branch's with:

```
flutter test test/drive_state_sqlite/artifact_scale_test.dart --run-skipped
```
