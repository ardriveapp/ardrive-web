# Making sync progressively readable

The last hurdle: a sync that you can read *through* rather than wait out.
Planned as a stack, smallest and safest first, so each PR is shippable alone
and the risky one is last.

## First, a correction worth making up front

Two things got merged in conversation and they are not the same:

- **Reading during a sync** — the subject of this plan. Genuinely blocked
  today, and the work is in `DriveDetailCubit`, not in the sync engine.
- **Syncing 4 of 10 drives at once** — *already possible in the engine*.
  `startSync(driveIdsToRetry: [...])` filters `allDrives()` to that set and
  walks them concurrently (`Future.wait`, `eagerError: false`). The parameter
  is named for its only caller, Retry Failed; it is a general subset filter.
  What is missing is a way to *choose* the four, which is selection UI, not
  engine work.

They are separate PRs because they are separate problems. Doing the second
does not require touching sync at all.

## What actually blocks reading today

Four holds, all of them `await _syncCubit.waitCurrentSync()`, all gated on
`SyncCubit.syncTouchesDrive`:

| Where | Fires when | Effect |
|---|---|---|
| `DriveDetailCubit` constructor | first load of a drive | the drive will not open |
| `changeDrive`, drive absent locally | deep link to an undiscovered drive | waits for discovery |
| `openFolder` | every navigation | the folder will not open |
| the folder subscription's callback | **every Drift tick** | no updates land |

And `syncTouchesDrive` is:

```dart
(state is SyncInProgress || state is SyncLoadingDrives) &&
    (syncingDriveId == null || syncingDriveId == driveId)
```

`syncingDriveId` is null for an all-drives sync, so an all-drives sync counts
as writing every drive — which is why it blocks everything.

The load-bearing one is the fourth. Without it a background sync redraws the
file list under the reader on every batch. It is not there for correctness:
each batch commits in its own transaction, so a read mid-sync gets consistent
data, just less of it than it will eventually have.

## The stack

### PR 1 — A finished drive stops counting as busy

The smallest useful change, and it needs no new state: `SyncProgress` already
carries `syncedDriveIds`, appended per drive on the success path only, live
during the run.

- Expose it from `SyncCubit` beside `syncingDriveId`.
- `syncTouchesDrive` consults it: a drive whose walk has finished is not being
  written by this sync any more.

Unblocks the case that reads worst today — an all-drives sync of ten drives
where the first finished a minute ago and still cannot be opened.

**The caveat that must be handled, not ignored:** two phases run *after* every
drive walk. `createGhosts` writes from `_ghostFolders`, accumulated across
drives, and transaction statuses are updated at the end. So "walked" is not
"nothing will touch this again". Both are additive row writes that arrive
through the Drift stream, so a reader sees them appear rather than sees
anything wrong — but the doc comment on `syncTouchesDrive` must say this
plainly, because the name will otherwise be read as a stronger guarantee than
it gives.

Testable without the engine: `syncTouchesDrive` is static and pure.

### PR 2 — A drive being read is never blanked, and fills in as it goes

Replace the subscription's hold with a throttle.

- The callback stops awaiting the sync and instead coalesces Drift ticks -
  one redraw every N hundred ms rather than one per batch.
- It emits *contents*, never a loading state, while a drive is on screen. That
  half is already true as of the "folder click keeps the drive" change; this
  makes it true of updates as well as navigation.

Result: opening a syncing drive shows it filling in, which is the single most
convincing thing this project can show a user who has waited years for it.

**Measure the throttle, do not guess it.** An earlier attempt at a publish
throttle in this area was reverted for being unmeasured. The number to watch
is redraws per second on a drive with thousands of revisions.

### PR 3 — Navigate freely mid-sync

Drop `openFolder`'s wait for a drive that is already in the local database.
Keep it only in `changeDrive`'s discovery path, where the drive genuinely is
not there yet and only a sync will produce it.

Do this **after** PR 2, not before: without the throttle, free navigation
during a sync means a folder that redraws on every batch.

### PR 4 — Sync the four you care about

No engine work. Rename `driveIdsToRetry` to what it is (`driveIds`), keep the
old name as a deprecated alias if anything outside this repo passes it, and
build the selection:

- Row checkboxes on Your Drives, and a "Sync selected (4)" action.
- The existing `Sync All Drives` becomes the no-selection case of the same
  control.

Note the standing decision this does **not** overturn: one sync run at a time,
no queuing. Four drives in one run is one run. Pressing sync while a run is
going is still refused, not queued.

### PR 5 — Recoverable, and able to say what it recovered

The pieces exist and do not add up to a story yet:

- `lastBlockHeight` per drive makes every drive independently resumable - a
  re-run continues rather than restarts.
- `SyncCancellationToken` can stop a run.
- `SyncCompleteWithErrors.failedDriveIds` knows which drives failed.
- `syncedDriveIds` knows which succeeded.

What is missing is the sentence that uses them: **"7 of 10 read. 3 could not be
reached — sync those three."** One action, targeting exactly the failures,
which PR 4's subset filter already implements. A sync interrupted by a closed
tab should read the same way on the next launch, from the watermarks alone.

This is the PR that turns "sync failed, try again" into something a person can
act on, and it is cheap once 1 and 4 exist.

## Order, and why

1 and 4 are independent of each other and of the rest; either can go first.
2 must precede 3. 5 wants 1 and 4 done.

The risk is concentrated in 2 and 3, which is why they sit in the middle with
a shippable PR either side: if 2 measures badly, 1, 4 and 5 still stand on
their own and the app is better than it is today.

## What "professional grade" means here, concretely

Not more spinners. Four properties, in the order a user notices them:

1. **It never lies.** A dash is not a zero; "synced" is not claimed for a drive
   that failed; a figure that cannot move is not shown as a percentage. This is
   already true and must survive the work above.
2. **It never takes the app away.** No scrim, no modal, no losing your place.
   True today except for the holds this plan removes.
3. **It fills in rather than finishing.** The difference between a progress bar
   and a drive that visibly becomes useful is PR 2.
4. **A failure names itself and offers exactly the retry that fixes it.** PR 5.
