# Building a snapshot from the snapshots you already have

## The problem, measured

Creating a snapshot of a 40k-item drive re-reads the entire drive from the
network, even immediately after a sync that just read the same data.

For drive `0a36156c…` (~42,000 transactions):

| Work | Count |
|---|---|
| `DriveEntityHistoryWithoutEntityTypeFilter` pages (`first: 100`) | ~420 |
| Individual metadata fetches (`_arweave.dataFromTxId`) | ~42,000 |
| Of those served from cache | ≤ 550 |

`CreateSnapshotCubit` walks blocks `0 → current` over GraphQL
(`create_snapshot_cubit.dart:239`), then for every transaction calls
`_jsonMetadataOfTxId` (`:610`), which checks `MetadataCache` and otherwise goes
to the gateway. `MetadataCache` holds `defaultMaxEntries = 550`
(`metadata_cache.dart:6`) with `evictionPolicy: null`, so on a drive this size
it covers ~1.3% and then logs *"Metadata cache is now full and will not accept
new entries"*.

On a throttled connection this does not finish.

## Why it is redundant

The sync that just ran read 41,767 of those entities' metadata **out of the
drive's existing snapshots** and then discarded it:

- `SnapshotItemOnChain.dispose(driveId)` clears the per-drive cache when the
  drive's sync ends.
- `getDataForTxId` is `getAndRemove` — destructive, so it is one-shot even
  before disposal.
- `_jsonMetadataOfTxId` never consults that cache at all. It knows only the
  550-entry store and the network.

Meanwhile the existing snapshots hold, verbatim, exactly what a new snapshot
needs.

## What a snapshot entry is, and what we hold

A snapshot body is `{"txSnapshots": [{gqlNode, jsonMetadata}, …]}`.

| Field | Where it can come from |
|---|---|
| `gqlNode` — id, owner, bundledIn, block, tags | an existing snapshot ✅ · GraphQL ✅ · **local DB ❌** |
| `jsonMetadata` — raw entity bytes (base64 when private) | an existing snapshot ✅ · gateway ✅ · **local DB ❌** |

The local database stores *parsed* revisions — name, size, `dataTxId`,
`metadataTxId`, plus `customJsonMetadata`/`customGQLTags`. It does not keep the
raw metadata bytes, nor a complete GQL node. **A snapshot cannot be rebuilt
from the database**, and attempting to reconstruct one would be lossy.

That is the important constraint: the source must be existing snapshots, not
local state.

## Design

A new snapshot covering `[0 → current]` is assembled as:

1. **`[0 → previousSnapshot.blockEnd]`** — copied verbatim from the existing
   snapshot bodies. No GraphQL, no metadata fetches.
2. **`(previousSnapshot.blockEnd → current]`** — the existing path: GraphQL for
   the range, then a metadata fetch per transaction.

For this drive that is **261 transactions fetched instead of ~42,000**, and one
44 MiB download the app may already be holding. The ratio improves every time a
snapshot is taken, rather than degrading.

Entries are copied, not re-derived, so fidelity is not a question: the bytes
that go into the new snapshot are the bytes that came off chain.

## The correctness question

*"If you have an improperly synced drive, you can end up with a bad snapshot."*

Correct, and it is the reason this design sources from **snapshots** rather than
from the local database. The two failure modes are different:

- **Local DB as the source** — inherits every silent drop in
  `docs/SYNC_SKIPPED_ENTITY_PERSISTENCE.md`. A metadata read that failed during
  sync leaves an entity missing locally while the watermark advances, so the
  snapshot would bake that gap in permanently and on chain. **Rejected.**
- **Existing snapshots as the source** — inherits only what the previous
  snapshot contained. That snapshot is immutable, on chain, and is *already*
  trusted for exactly this range on every sync. The new snapshot is no more
  trusted than the one it descends from.

Residual risk: a defective ancestor snapshot propagates forward. Mitigations,
in increasing cost:

1. **Range assertion (cheap).** The copied entries must cover the ancestor's
   claimed `Block-Start … Block-End` with no interior gap. Fails loudly rather
   than writing a short snapshot.
2. **Count check (moderate).** One id-only GraphQL pagination over the ancestor
   range, comparing counts. Catches a truncated ancestor without fetching any
   metadata.
3. **Full rebuild (expensive).** Today's behaviour, kept as an explicit
   "rebuild from chain" option for when an ancestor is suspect.

Default to 1, offer 3. 2 is worth measuring before committing to it.

## Phases

**Phase 1 — make the metadata survive.**
`getDataForTxId` stops being destructive (or gains a non-consuming read), and
the per-drive cache becomes retainable past `dispose` when a snapshot creation
is pending. Nothing user-visible; it only stops throwing away what was read.

**Phase 2 — source the covered range from ancestors.**
`SnapshotItemToBeCreated` takes entries for `[0 → ancestorEnd]` from ancestor
snapshot bodies, and drives GraphQL only for the tail. Includes the range
assertion.

**Phase 3 — the escape hatch.**
Expose "rebuild from chain" for a suspect ancestor, which is the current code
path unchanged.

**Phase 4 — the modal.**
Progress currently counts transactions processed. With most entries copied, the
meaningful units become "copied from existing snapshots" and "fetched for the
new range". Also the point at which the dialog's structure gets revisited.

## Notes

- Ancestor snapshots record prior snapshot transactions as
  `TxSnapshot(gqlNode: node, jsonMetadata: null)` (`_isSnapshotTx`). Copying is
  verbatim, so this needs no special handling — but a rebuild must not treat a
  null `jsonMetadata` as a fetch failure.
- Overlapping ancestors already compose through the `obscuredBy` accumulator in
  `SnapshotItem.instantiateAll`; the copy path should reuse it rather than
  inventing a second dedup.
- `MetadataCache`'s 550-entry cap is not worth raising: it is
  SharedPreferences-backed, and `put` carries a `FIXME` about not checking
  quota. Copying from snapshots removes the need for it on this path.
