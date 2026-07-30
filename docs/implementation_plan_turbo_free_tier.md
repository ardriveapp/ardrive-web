# Turbo Free-Tier Restriction — ArDrive Client Implementation Plan

## Policy (PE-9132)

- Each wallet receives a **10 MiB free pool**.
- An upload is free-eligible only when the data item is **≤ 105 KiB (107,520 bytes)** AND the pool has remaining room. Eligible items draw down the pool by their size. ArFS metadata items (~1–2 KiB: renames, moves, creates, hides, pins, license assertions, bulk-import entries, thumbnails metadata) draw from the same pool.
- When the pool is exhausted, **every** upload is paid — including metadata operations. Purchasing credits does **not** replenish the pool; free and credits are independent.
- Reset cadence (monthly vs lifetime) is server policy; the client must treat remaining-free as **server-reported state**, never a client-side computation.

## Current client reality (verified inventory, July 2026)

"Free" today is a client-side guess: anything under `allowedDataItemSizeForTurbo`
(100,000 bytes; `assets/config/*.json:12`) is posted to `POST /v1/tx` with **no
cost check, no payment header, no quota awareness** (`lib/turbo/services/upload_service.dart:59-106`).

**Fifteen operation paths post silently on this assumption** (all wallet-signed,
none has payment UI):

| Op | Post site |
|---|---|
| File/folder rename | `lib/blocs/fs_entry_rename/fs_entry_rename_cubit.dart:176/:101` |
| Drive rename | `lib/blocs/drive_rename/drive_rename_cubit.dart:71` |
| Move (per item!) | `lib/blocs/fs_entry_move/fs_entry_move_bloc.dart:275` |
| Hide/unhide | `lib/blocs/hide/hide_bloc.dart:330` |
| Folder create | `lib/blocs/folder_create/folder_create_cubit.dart:85` |
| Drive create (+root folder) | `lib/blocs/drive_create/drive_create_cubit.dart:134` |
| Pin file | `lib/blocs/pin_file/pin_file_bloc.dart:337` |
| License assertion (2/file×rev) | `lib/blocs/fs_entry_license/fs_entry_license_bloc.dart:320` |
| Ghost fixer | `lib/blocs/ghost_fixer/ghost_fixer_cubit.dart:141` |
| ArNS name revision | `lib/arns/domain/arns_repository.dart:196` |
| Thumbnail metadata | `lib/drive_explorer/thumbnail/repository/thumbnail_repository.dart:210` |
| Private-drive migration | `lib/shared/blocs/private_drive_migration/private_drive_migration_bloc.dart:134` |
| Bulk import folder meta (per folder) | `lib/core/arfs/use_cases/upload_folder_metadata.dart:81` |
| Bulk import file meta (per file) | `lib/core/arfs/use_cases/upload_file_metadata.dart:80` |
| Snapshot create (has payment UI already) | `lib/blocs/create_snapshot/create_snapshot_cubit.dart:693` |

**Known failure behavior on payment rejection today** (nothing decodes 402/429):

- Rename: progress dialog never dismisses (`fs_entry_rename_form.dart:76-137` has no failure case).
- Move: no failure state at all (`fs_entry_move_state.dart`), progress dialog hangs; **DB commits BEFORE the network post** (`fs_entry_move_bloc.dart:261-279`) → local state diverges from chain on rejection.
- Chunked uploader retries any failure **8×** including payment rejections (`packages/ardrive_uploader/lib/src/turbo_upload_service.dart:28,99-100`).
- App-side `TurboUploadService._handleException` special-cases only 408 (`upload_service.dart:108-129`); everything else becomes a generic `Exception`.
- No quota/allowance API is consumed anywhere; balance response (`payment_service.dart:77`) has no free-tier fields today.

## Budget math (why per-op UX must be silent)

- Metadata op ≈ 2 KiB → the 10 MiB pool covers ~5,000 metadata operations.
- A single 105 KiB file consumes ~50 metadata-ops worth of pool; ~97 max-size files exhaust the pool.
- Bulk import of a 1,000-file manifest ≈ 2 MiB of pool in one click. Folder
  uploads of many small files can exhaust the pool in one action.
- Conclusion: prompting per metadata op is unacceptable (dust); prompting per
  BURST (bulk import, folder upload) with a pool-aware preflight is required.

## Phase 1 — Failure honesty (policy-independent; build first, no server dependency)

1. **Typed payment errors.** In both TurboUploadServices: decode HTTP 402 (and
   distinguish free-exhausted vs insufficient-credits when the server provides a
   reason code) into `TurboPaymentRequiredException`; decode 429 into a typed
   rate-limit error. Exclude both from blind retry (`retryIf`).
2. **Fix the stuck dialogs.** Add failure states + dialog handling for Rename
   (both file/folder) and Move; generic message now, payment-specific once
   Phase 2 lands.
3. **Move: post-then-commit.** Reorder `fs_entry_move_bloc` so network posts
   succeed before DB writes commit (or wrap in a rollback) — fixes the
   divergence bug independent of any free-tier change.
4. **Tests:** unit tests for error decoding; bloc tests for rename/move failure
   states; regression test that a 402 is not retried.

## DECISION (2026-07-15, after review with Turbo team)

Phase 1 green-lit. The balance-endpoint remaining-free dependency and the
dynamic pool meter are DROPPED: no pool tracking client-side. Instead:
- **Static free-tier messaging** — when a post is rejected with 402, show a
  static explanation ("free allowance is used up — add Credits") with the
  top-up path. No live "X MiB remaining" anywhere.
- **`maxItemBytes` from `GET /v1/info`** is kept as the server-driven
  per-item eligibility threshold (implemented:
  `TurboUploadService.maxFreeItemSizeBytes`, fetched once at construction,
  config value as fallback). Follow-up: consume it in
  `UploadPaymentEvaluator` in place of `allowedDataItemSizeForTurbo`.
- Typed-402 handling everywhere (Phase 1) is the backbone of the UX.

The original Phase 2/3 below is retained for reference but is NOT the
current plan; only the pieces named above survive.

## Phase 2 — Pool-aware eligibility (SUPERSEDED by decision above)

**Server asks (blockers for this phase, not Phase 1):**
- Remaining-free bytes (+ reset timestamp if any) on the existing balance
  endpoint (`GET /v1/account/balance/arweave`) — client already polls it.
- Deterministic 402 with machine-readable reason: `free_exhausted` |
  `insufficient_credits`.
- Confirm per-item eligibility threshold (105 KiB) is queryable or stable.

**Client work:**
1. **`TurboConditionsService`** (new, `lib/turbo/`): caches
   `{creditBalance, freeRemainingBytes, freeItemLimit=107520}`; refreshed on
   login, after every upload, and immediately on any 402. Single source of
   truth; all "is this free?" questions go here.
2. **Retire the client-side constant as authority.** `allowedDataItemSizeForTurbo`
   (100 KB) becomes the fallback for the item-size gate only (bump to 107,520);
   eligibility = size-gate AND `freeRemainingBytes >= itemSize`.
3. **Decision ladder for every post** (file uploads AND all 15 metadata paths):
   - free-covered → post silently (pool decremented server-side; client
     decrements optimistically, reconciles on next balance poll)
   - credits cover it → post silently for dust-sized metadata; show cost line
     for user-perceivable sizes (uploads keep existing payment UI)
   - neither → pre-flight prompt with top-up flow (replaces today's hang)
   - server 402 anyway (stale cache) → typed error → refresh conditions → one
     honest dialog, never blind retry
4. **Payment evaluator changes** (`lib/core/upload/uploader.dart:379-382,
   :464-476, :534-564`; `upload_payment_method_bloc.dart:111-137`):
   `isFreeUploadPossibleUsingTurbo` must consult the conditions service, not
   just size. Multi-file: free only if the whole plan fits remaining pool;
   otherwise split display (N free / M paid) or fall to paid entirely
   (simpler v1: all-or-nothing per upload plan).
5. **Burst preflight.** Bulk import (`bulk_import_files.dart`) and folder
   uploads estimate total bytes against the pool up front: "This import needs
   2.1 MiB; you have 0.8 MiB free — the rest uses ~0.0004 credits
   [Continue] [Top up]". On mid-burst exhaustion: pause-and-resume, not
   fail-halfway (bulk import's failure tracking is the foundation).

## Phase 3 — Surfacing (UX)

- FREE badge (`upload_form.dart:1937-1948`, `create_snapshot_dialog.dart:431`)
  becomes dynamic: "Free — X MiB left" / absent when exhausted.
- Pool meter + low-pool nudge in the profile card next to credits
  (`profile_card.dart:568-592` area); "free used up — everything now uses
  credits" one-time notice on the free→paid transition.
- Onboarding guard: drive-create is a new wallet's first action (~2 KiB). With
  a fresh 10 MiB pool this always succeeds; the dead-end only exists for
  exhausted wallets — those get the pre-flight prompt, never a hang.

## Explicit non-goals / accepted

- No client-side enforcement (abusers bypass the app; enforcement is Turbo's).
  Client goals: honest UX for legitimate users + never amplifying rejected
  load (no 402 retries).
- No hardcoded reset cadence; display whatever the server reports.
- L1 (direct Arweave) fallback for metadata ops remains available where it
  exists today (rows 1–10, 13–14) for users who prefer paying AR — unchanged.

## Sequencing

Phase 1 is unblocked today and ships value regardless of policy timing.
Phase 2 blocks on the two server asks. Phase 3 rides Phase 2. Estimated:
Phase 1 ≈ 2–4 days incl. tests; Phase 2 ≈ 1 week client-side once the API
contract exists; Phase 3 ≈ 2–3 days.
