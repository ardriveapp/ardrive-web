# Sync: skipped entities and why they can be lost permanently

Status: design note for a follow-up PR. Nothing here is implemented yet.

This note exists because of a bug found while making sync read from a single
gateway (PE-9203). The bug **predates that change** and is invisible unless you
go looking for it, so it is written down here in full.

---

## 1. The pre-existing silent drop

When a sync cannot read an entity's metadata, that entity is dropped from the
user's local drive state, silently, and in the common case permanently. There is
no error surfaced, no retry across sessions, and no record that anything is
missing.

### Evidence

**A failed read becomes empty bytes, not an error.**
`ArweaveService._getEntityData` (`lib/services/arweave/arweave_service.dart`)
historically ended with:

```dart
return getEntityDataFromNetwork(txId: txId).catchError((e) {
  logger.e('Failed to get entity data from network', e);
  return Uint8List(0);          // <-- failure becomes empty bytes
});
```

**The empty bytes then fail to parse, and the parse error is swallowed.**
In `createDriveEntityHistoryFromTransactions`, `FileEntity.fromTransaction(tx,
Uint8List(0), ...)` throws `EntityTransactionParseException`, which is caught by
the `on EntityTransactionParseException` handler and logged at warning level.
The entity is never added to `blockHistory`, so it never reaches the database.

**The drive's watermark advances anyway.**
`_parseDriveTransactionsIntoDatabaseEntities`
(`lib/sync/domain/repositories/sync_repository.dart`) writes
`lastBlockHeight: Value(currentBlockHeight)` — both in the empty-transactions
branch and in `endOfBatchCallback` — with no knowledge that anything was
dropped. The next sync therefore starts *after* the block containing the item it
failed to read.

**The look-back only helps within a session boundary.**
`_calculateSyncLastBlockHeight` rewinds by `kBlockHeightLookBack`
(`lib/sync/constants.dart`, currently 240 blocks ≈ 2 hours) — but only when
`_lastSync == null`:

```dart
int _calculateSyncLastBlockHeight(int lastBlockHeight) {
  if (_lastSync != null) {
    return lastBlockHeight;                                   // no rewind
  }
  return max(lastBlockHeight - kBlockHeightLookBack, 0);      // rewind
}
```

`_lastSync` is a plain in-memory `DateTime?` on `_SyncRepository`. It is never
persisted. So the rewind happens once per app session and covers only the last
~2 hours of chain history.

### What that means in practice

| Situation | Recovered? |
|---|---|
| Item dropped, another sync runs in the same session | No — `_lastSync != null`, no rewind |
| Item dropped, app restarted within ~2h of that block | Yes — first sync of the session rewinds 240 blocks |
| Item dropped, app restarted more than ~2h later | **No — lost until a deep sync** |
| User triggers a deep sync | Yes — `syncDeep` passes `lastBlockHeight: 0` |

Deep sync is the only reliable recovery, it is user-initiated, and nothing tells
the user they need it. A file uploaded from another device can therefore be
missing from this device indefinitely while the UI looks perfectly healthy.

### What PE-9203 changed about this

PE-9203 did not introduce this, but it does raise how often it fires. Sync reads
went from a 4-attempt waterfall (configured gateway + 2 GAR gateways +
arweave.net) to 2 attempts against the configured gateway only. Fewer attempts
means more skips.

What PE-9203 *added* is the record: skipped transaction ids are now collected
and reported instead of being logged and forgotten.

- `DriveEntityHistory.skippedTxIds` carries them out of `ArweaveService`.
- `_SyncRepository._skippedEntityTxIdsByDrive` accumulates them per drive.
- `SyncProgress.skippedEntityCount` / `.skippedEntityTxIdsByDrive` report them.
- `SyncCubit.lastSyncSkippedEntityTxIdsByDrive` retains them after the run.

That record is **in-memory only**. It dies with the process, which is exactly
the gap this note proposes to close.

---

## 2. Proposal: `sync_failed_entities`

### Why a table, and not the watermark

The tempting zero-schema fix is to clamp the watermark: on failure, don't
advance `drives.lastBlockHeight` past the oldest failed item's block height.
It uses an already-persisted field and guarantees a retry.

It was rejected because it is unbounded. A genuinely dead transaction pins the
drive's watermark forever, so every subsequent sync re-queries from that height
— a compounding regression on the exact path PE-9203 exists to speed up. It also
cannot answer "which items failed" (only "something failed at or after block
N"), and it distorts snapshot range maths, since `HeightRange.difference`
derives the GQL sub-ranges from that same watermark.

Distinguishing "transient" from "permanently unavailable" needs attempt history.
Attempt history needs persistence. Hence a table.

### Schema

```sql
CREATE TABLE sync_failed_entities (
    txId TEXT NOT NULL PRIMARY KEY,
    driveId TEXT NOT NULL,
    blockHeight INTEGER NOT NULL,
    attempts INTEGER NOT NULL DEFAULT 1,
    lastAttempt DATETIME NOT NULL,
    lastError TEXT,
    isTerminal BOOLEAN NOT NULL DEFAULT FALSE
) As SyncFailedEntity;

CREATE INDEX idx_sync_failed_entities_drive ON sync_failed_entities(driveId);
```

Migration cost is small and mechanical:

- add `lib/models/tables/sync_failed_entities.drift`, import it from `all.drift`
  and from the `@DriftDatabase(include: {...})` set in `database.dart`
- bump `schemaVersion` 29 → 30
- add `if (from < 30) { await m.createTable(syncFailedEntities); }`, matching the
  existing style of the v19 and v21 migration blocks
- run `flutter pub run build_runner build --delete-conflicting-outputs`

The pre-push hook (`lefthook/database_checker.sh`) only asserts that
`schemaVersion` increased when `lib/models/tables` changed. It does **not**
require a `drift_schemas/` JSON export — that directory is stale (last export
v19 against a live schemaVersion of 29), so no export is needed.

### Retry: re-query the block, not the transaction

To re-apply a recovered item we need its full GQL node (tags, block, owner) for
`createDriveEntityHistoryFromTransactions`. A bare transaction id is not enough,
and there is no existing query returning `...TransactionCommon` by ids —
`InfoOfTransactionsToBePinned` takes `ids:` but returns a narrower shape.

Rather than add a GraphQL query and another generated-code surface, **store the
failed item's block height and union it back into the range that sync already
queries.** `_syncDrive` builds `totalRangeToQueryFor` as a multi-segment
`HeightRange`:

```dart
final totalRangeToQueryFor = HeightRange(
  rangeSegments: [
    Range(start: lastBlockHeight, end: currentBlockHeight),
  ],
);
```

Adding `Range(start: h, end: h)` for each due failed height makes the normal
`DriveEntityHistory` query re-yield the failed transaction with all its tags, at
the cost of re-reading a few cheap siblings in the same block. No new query, no
new codegen beyond the table.

Sketch:

```dart
final dueHeights = await _driveDao.dueFailedEntityHeights(drive.id);
final totalRangeToQueryFor = HeightRange(
  rangeSegments: [
    Range(start: lastBlockHeight, end: currentBlockHeight),
    ...dueHeights.map((h) => Range(start: h, end: h)),
  ],
);
```

`HeightRange.union` already normalises overlaps, so heights inside the primary
range cost nothing extra.

### Backoff policy

Retries are driven by the table, not by block height, so they are independent of
the 240-block look-back window.

| Failure kind | Behaviour |
|---|---|
| `TransactionNotFound` (404) | Record with `isTerminal = true`. Never auto-retried — consistent with the fast-fail-on-404 stance in `SnapshotValidationService`. The row remains for the UI, and a deep sync clears it. |
| Transient (timeout, 5xx, network) | Retried at the start of the next sync for that drive, subject to backoff. |

Backoff keyed on `attempts`, evaluated against `lastAttempt`:

| attempts | earliest next retry |
|---|---|
| 1 | next sync |
| 2 | +5 minutes |
| 3 | +1 hour |
| 4 | +6 hours |
| 5 | stop; mark `isTerminal` |

One integer, one timestamp, and a constant list of durations. No queue, no
isolate, no scheduler. The retry pass is: load the drive's due rows, union their
heights into the query range, let the existing path re-read them, then delete
the rows that succeeded and bump `attempts` on those that did not.

### Lifecycle

- **Write** on a failed metadata read, keyed by `txId` (upsert, incrementing
  `attempts`).
- **Delete** as soon as that `txId` parses successfully in any later sync.
- **Clear per drive** on deep sync, which re-reads from block 0 anyway.
- **Never block a sync.** A failed retry is still just a skip.

---

## 3. Follow-on work this unlocks

1. **"Failed files" UI.** Design is pending. The data is already exposed
   in-memory via `SyncProgress.skippedEntityTxIdsByDrive` and
   `SyncCubit.lastSyncSkippedEntityTxIdsByDrive`; the table makes it durable and
   makes a per-drive count queryable without a sync having just run.
2. **Automatic recovery**, removing the need for a user to know that deep sync
   exists.
3. **Telemetry on skip rate**, which is the measurement needed before raising
   `maxConcurrentDataFetches` (deliberately left at 5 in PE-9203 so that the
   scheduling change and the request-rate change can be evaluated separately).

## 4. Related code

| Concern | Location |
|---|---|
| Failed read → `null` | `ArweaveService._getEntityData` |
| Parse error swallowed | `ArweaveService.createDriveEntityHistoryFromTransactions` |
| Watermark advance | `_SyncRepository._parseDriveTransactionsIntoDatabaseEntities` |
| Look-back rewind | `_SyncRepository._calculateSyncLastBlockHeight` |
| Look-back constant | `kBlockHeightLookBack`, `lib/sync/constants.dart` |
| Deep sync reset | `_SyncRepository.syncAllDrives`, `syncDeep ? 0 : ...` |
| Sync read path | `DataGatewayFallback.fetchDataForSync` |
| In-memory skip record | `SyncProgress`, `SyncCubit` |
| Range machinery | `lib/utils/snapshots/height_range.dart` |
