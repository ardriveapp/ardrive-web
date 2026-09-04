# Login to Synced

Every step from the moment a wallet is supplied to the moment a sync reports itself
complete, and which ones actually block the user.

Traced from `ardrive_auth.dart`, `app_router_delegate.dart`, `sync_cubit.dart`,
`sync_repository.dart` and `arweave_service.dart`.

## The short answer

- **Password validation blocks login** (step 2) and costs a network round trip plus a
  key derivation — but only if the wallet owns at least one private drive.
- **The drive list blocks the drives page** (steps 11–14). Nothing else in the app waits
  on it.
- **Unlocking private drives is serial** (step 13) — one signature read, one key
  derivation and one decrypt per private drive, no pooling. This is the pause after the
  fetch count reaches its total.
- **The full sync blocks nothing.** No scrim; the app stays usable throughout, and
  opening a drive waits only for a sync that could be writing *that* drive.
- **By default there is no full sync on login at all.** `syncAllDrivesOnLogin` ships
  `false`. Steps 17–27 run only if it was turned on, or if an upload is still unconfirmed.
- **Every ARNS lookup is fire-and-forget.** The primary name at login and both ANT record
  passes during sync are started and never awaited, so ARNS being slow or unreachable
  cannot delay or fail either.

Legend: **[blocks]** the user waits · **[bg]** background · **[net]** network ·
**[local]** local only.

## A. Authenticate — `ardrive_auth.dart`

Nothing about sync has started. The user is at the login screen.

1. **A wallet is supplied.** **[blocks]**
   JWK keyfile, ArConnect, Ethereum or Solana. The extension wallets prompt, and the
   browser may briefly treat the tab as unfocused — which is why the sync that follows
   passes `skipTabVisibilityCheck: true`.

2. **The password is proved against a real private drive.** **[blocks] [net]**
   `_validateUser` finds the first *private* drive transaction, reads its
   `DriveSignature` from the gateway, derives a drive key and decrypts the drive entity.
   Failure means a wrong password. Skipped entirely for a wallet with no private drives,
   which is why login speed differs so much between accounts.

3. **The user record is written.** **[blocks] [local]**
   `_addUser` on first login, `getUser` on unlock.

4. **Balance, biometrics, secure storage.** **[bg]**
   `_updateBalance()` is not awaited. The password reaches secure storage only if
   biometrics are enabled.

5. **The auth stream emits.** **[bg]**
   `_userStreamController.add(user)`. Everything downstream hangs off this.

6. **The wallet's ARNS primary name is looked up.** **[bg] [net]**
   `ProfileNameBloc` (wired in `main.dart`) asks `ARNSRepository.getPrimaryName` so the
   profile card can show a name instead of an address. Nothing waits on it; the card
   shows the truncated address until it answers, and keeps showing it if it never does.

## B. Land — `app_router_delegate.dart`, `sync_cubit.dart`

The screen is decided before any drive data exists.

7. **`ProfileCubit` reaches `ProfileLoggedIn`.** **[bg]**

8. **The router lands on the drives list.** **[bg]**
   Its profile listener clears `signingIn` and, when there is no deep link to honour,
   sets `showingDrivesList = true`. A drive or folder link is honoured instead.

9. **`SyncCubit` is constructed in `SyncLoadingDrives`.** **[bg]**
   Deliberately, not `SyncIdle`: anything calling `waitCurrentSync()` before the first
   state arrives would otherwise race past it. `SyncLoadingDrives` counts as finished for
   that wait, so a metadata refresh never blocks the app.

10. **The sync-on-login preference is read.** **[local]**
   `syncAllDrivesOnLogin`, which ships `false`. A throw falls back to `false` rather than
   stranding the login on "Loading your drives…".

## C. Refresh the drive list — runs on both paths

Happens whether or not the user syncs on login. Not syncing must not mean not noticing
drives: one created or renamed elsewhere still appears.

11. **Every drive transaction for the wallet is listed.** **[blocks the drives page] [net]**
    `getUniqueUserDriveEntityTxs` — a paginated GraphQL walk. Until it returns the total
    is unknown and the page says only "Loading your drives…".

12. **Each drive's metadata is fetched, pooled.** **[blocks the drives page] [net]**
    Says: `Loading your drives... 3 of 12`.
    Concurrency is `maxConcurrentDataFetches` (5). The total is known before any of it
    starts, which is what makes the count honest.

13. **Private drives are unlocked, one at a time.** **[blocks the drives page] [net]**
    Says: `Unlocking your private drives... 2 of 5`.
    Per private drive: read its `DriveSignature` from the gateway, derive the key against
    the wallet, decrypt the metadata. **Serial, not pooled** — the long pause after the
    fetch count hits its total, scaling with how many private drives are owned. Public
    drives just parse. A drive whose signature cannot be read is dropped from this pass
    and picked up on the next, rather than failing the whole login.

14. **The drives table is written.** **[local]**
    `_driveDao.updateUserDrives`. The sidebar and drives list populate here — name,
    privacy and last-synced time. Contents are still unknown.

## D. Decide whether to sync at all

15. **Sync-on-login enabled → a full sync starts immediately.** **[bg]**
    `startSync(trigger: background)`, un-awaited. Phase C runs inside it rather than
    before it.

16. **Disabled (the default) → one local question.** **[local]**
    `hasPendingTransactions()`. An upload that has not been confirmed is the only thing a
    sync still owes, and nothing but a sync resolves it. No network request.
    **If nothing is pending it stops here and says nothing** — ordinary idle, Resync in
    the top bar, and each drive opens on its own "Drive Not Synced" card. The silence is
    the feature.

## E. The full sync — only if D said so

Nothing here blocks the app. No scrim; navigation, opening drives and uploading all work
throughout.

17. **The wallet's ANT records are refreshed.** **[bg] [net]**
    `getAntRecordsForWallet(update: true)` fires at the top of the sync and is
    **deliberately not awaited** — its `catchError` swallows a failure and the sync
    carries on. ARNS being unreachable never fails or delays a sync.

18. **Connecting to the network.** **[net]**
    `getCurrentBlockHeight()`, with retry. Everything below is measured against it.

19. **Checking for changes.** **[net]**
    `probeActiveDriveIds` — one query asking which drives have had activity since their
    own last block height, so untouched drives are skipped. Never-synced drives are always
    included and never poison the probe's floor.

20. **Downloading drive snapshots.** **[net]**
    Batched per owner — one query per owner, not per drive. A snapshot lets the walk skip
    history it would otherwise read transaction by transaction.

21. **Reading the drive history.** **[net]**
    Says: `Reading 340 files...`.
    The long pole by a wide margin. Drives run concurrently; within a drive the history
    arrives in chunks, and each chunk is fetched in batches of `200 ÷ drives remaining` at
    concurrency 5. **One HTTP request per revision.** A drive with thousands of revisions
    spends minutes here.

22. **Revisions are written, one transaction per batch.** **[local]**
    Revisions insert, entries refresh, the drive record updates — all inside a single
    `runTransaction`. Entity counts are staged and promoted only on commit, so a rollback
    cannot inflate "N items changed".

23. **The block-height cursor advances.** **[local]**
    `lastBlockHeight` is written when the walk reaches the last page. **This is what makes
    the next sync incremental** — the single most consequential write in the sequence, and
    the reason a second sync is fast.

24. **Creating ghost folders.** **[local]**
    Folders referenced by files whose own metadata was never found. A normal state, not
    corruption.

25. **Updating transaction statuses.** **[net]**
    Already-confirmed ids are read locally and skipped; the rest go to the gateway in
    pages of 5000. For most wallets that is a single round trip — which is why the bar
    reports one step here and then waits.

26. **Files with assigned ARNS names are recorded.** **[bg] [net]**
    `waitForARNSRecordsToUpdate().then(saveAllFilesWithAssignedNames)` — started here and
    **not awaited either**, so the sync can report itself complete while ARNS is still
    settling. A file's assigned name may therefore appear a moment after the sync ends.

27. **Completing sync.** **[local]**
    The hidden-items flag and preferences are written, then `SyncComplete` is emitted with
    what changed. The run is recorded in the sync history and each drive's last-synced time
    is saved.

## What waits on what

| This | Waits for | Notes |
|---|---|---|
| The login screen | Steps 1–3 | Step 2 is the network round trip, and only for wallets with a private drive. |
| The drives list page | Steps 11–14 | Via `waitForDriveListRefresh()` — the one caller that needs it, so an empty table is never reported as "you have no drives". |
| Opening a drive | Only a sync writing *that* drive | `SyncCubit.syncTouchesDrive`. A single-drive sync of B does not block opening A. |
| Attaching a drive | The current sync, then its own | Retries once if refused, so an attached drive is not left unsynced in silence. |
| A file shared into the app | The sync reaching any terminal state | Not `SyncIdle` specifically — a sync that ended with one failed drive still releases it. |
| The rest of the app | Nothing | No scrim, no modal. |
| ARNS names | Nothing waits on them | Primary name at login and both ANT passes during sync are started and never awaited; failures are swallowed. |

Step numbering is order of execution, not of importance: step 23 matters most and is
nearly invisible.
