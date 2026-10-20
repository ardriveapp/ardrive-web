# Drive state artifact — delivery plan

Tracks the ArFS addition across every repository it touches. The proposal is
`docs/DRIVE_STATE_ARTIFACT.md`; the bound decisions are
`docs/drive-state/DECISIONS.md`.

**Status key:** ✅ merged to the feature branch · 🔨 in flight · ⬜ not started ·
🔒 blocked on a human decision

**Status, 2026-10-20.** The web app's part is on `dev` (#2197, merged
2026-10-16, then #2267 to #2271) and reads and publishes artifacts on staging.
Production has both flags off. The spec is in review as ar-io/docs #192.
Stream B is in review: ardrive-core-js #288 (reading, on by default, and
producing), ardrive-cli #378 (`create-snapshot` publishes artifacts,
`snapshot-info`), ArDrive desktop #2 (pins core-js), and this repo's golden
fixtures and cross test, #2297. Decisions of 2026-10-20: reading on by default
in core-js and the CLI; the CLI's `create-snapshot` replaces JSON snapshots;
licence details are not produced, since readers read each file's licence from
its `licenseTxId`.

---

## Findings that shape the downstream work

**Corrected.** An earlier revision of this plan claimed `ardrive-core-js` had no
snapshot support and that a CLI comment referencing `parseSnapshotData` was
stale. Both were wrong — read from a checkout sitting on an old feature branch
rather than `origin/master`. The error is recorded rather than quietly edited
out, because it is the same stale-checkout failure the agentic framework warns
about, and it made the downstream work look larger and lonelier than it is.

What `origin/master` actually has:

- **A complete `src/snapshots/` module** (16 files): `range`, `height_range`,
  `snapshot_obscuring`, `drive_history_composite`, `snapshot_query`,
  `snapshot_data`, `snapshot_tags`, `snapshot_types`.
- **`parseSnapshotData` is real and in use** — `src/arfs/arfsdao_anonymous.ts`
  reads snapshot bodies through it. The CLI comment attributing the body shape
  to it is accurate.
- The module deliberately mirrors this app's `lib/utils/snapshots/`: the same
  `Range` / `HeightRange` / obscuring / composite concepts, under the same
  names.

Three consequences, all favourable:

1. **The composition machinery already exists.** A drive-state artifact is one
   more obscuring range in core-js exactly as it is here, so §3 is mirroring a
   proven structure rather than inventing one.
2. **The read path is the model to copy.** `parseSnapshotData` →
   `arfsdao_anonymous` is precisely the seam a drive-state reader slots beside.
3. **One real gap remains:** `src/snapshots/index.ts` states these are *"NOT yet
   wired into the live listing path — that integration (composite merge, entity
   cache) is a later phase."* So core-js can parse and compose snapshots but does
   not yet use them when listing a drive. Drive-state should not overtake that;
   it should land behind or alongside the same integration, or it will be a
   reader nothing calls.

Note `entityTypeValues` (`src/types/type_guards.ts`) still lists only
`drive | file | folder | drive-signature` — snapshots are identified by their
own `snapshot_tags.ts` constants instead. Either convention works for
`drive-state`; matching `snapshot_tags.ts` keeps rollup formats consistent with
each other.

## 1. ardrive-web — the reference implementation

| | Item | Status |
|---|---|---|
| 1.1 | Export one drive's current state; key material excluded by construction; schema-drift guard | ✅ |
| 1.2 | Envelope: gzip → AES-GCM (private only), and the inverse. The inner signed data item was removed by D16 | ✅ |
| 1.3 | ArFS entity + tags (§3.2) | ✅ |
| 1.4 | Discovery by GraphQL, owner-filtered, behind an interface | ✅ |
| 1.5 | Enumerated outcome vocabulary (§7) | ✅ |
| 1.6 | Import + merge, validate-before-write, watermark from the payload's coverage claim (the `Block-End` tag is cross-checked against it, never believed on its own) | ✅ |
| 1.7 | Sync composition behind an `AppConfig` flag defaulting to false | ✅ |
| 1.8 | Creation service + confirmation UI | ✅ |
| 1.8a | **Carry revisions, licences and derived `network_transactions`** (D2 reversal). Entry rows alone render an empty drive: `filesInFolderWithLicenseAndRevisionTransactions` INNER JOINs `network_transactions` through the newest `file_revisions` row, so a restored drive with no revisions shows zero files | ✅ |
| 1.8b | **A publish path and an app entry point.** A real Turbo/L1 uploader behind the `DriveStateUploader` seam, cost shown before the click, and a flag-gated item in the new button — until this lands the modal has no caller and the uploader publishes nothing | ✅ |
| 1.9 | Independent QA gate — an agent that wrote none of it | ✅ 10 findings, all closed |
| 1.10 | Adversarial audit of every layer, findings ranked and re-verified | ✅ |
| 1.14 | **Measured at production scale.** Export, seal, import and render at 41,767 files; sizes, timings and the producer's memory peak recorded in §1.1/§2.3 and reproducible from `drive_state_scale_measurement_test.dart` | ✅ |
| 1.15 | **Composition with snapshots.** Artifact, snapshots and GraphQL proven to cover the range once, including a snapshot straddling `Block-End` | ✅ |
| 1.16 | Localisation — every string the feature adds is hardcoded English by decision, pending a single `.arb` pass across all six locales at ship time | ⬜ ship-time |
| 1.17 | 🔨 The imported-artifact record is persisted on the drive row (D19), so a restart no longer re-downloads and re-imports. The sync skip ledger (`SYNC_SKIPPED_ENTITY_PERSISTENCE.md`) is still in memory, so a restart forgets one refusal | ⬜ skip ledger |
| 1.18 | ✅ **Import speed (D18).** The bulk tables are copied by SQLite, not through Dart: 5.4 s to 2.1 s at 41,767 files on the VM; in an optimised browser build 0.93 s to 0.43 s at 3,000 files and 26.8 s to 19.2 s at 41,767, where the rest is the web database's storage layer. Behaviour proved identical by a twelve-scenario table-by-table harness, and concurrent imports no longer collide on one attach name | ✅ |
| 1.19 | **The web database's storage.** Measured 2026-10-15, below. SQLite on OPFS in a dedicated worker, built in #2197 (`a0b6416f0`), so every user migrates once. See `docs/WEB_DATABASE.md` | ✅ |
| 1.11 | Export views replacing the typed projection (D7 deferral — needs a schema migration) | 🔒 |
| 1.12 | ArNS discovery (D6 deferral — needs an undername convention) | 🔒 |
| 1.13 | Execute an upload | ✅ by a human, 2026-10-15: `xk_N9vGYgTuLUgyWlVbdHCkl_js_Bo35M2miM6porK4` (rehearsal below). Every further upload stays human only, because it costs money and publishes permanently |

## End-to-end review, 2026-10-14

A pass over the whole feature, every premise checked against code or a live
gateway. Fixed items are in #2197; open ones are owned below.

| | Finding | Status |
|---|---|---|
| R1 | **A failed upload arrived as a confirmed file.** Every regenerated transaction landed `confirmed`, and the confirmation pass never revisits those | ✅ D15, format `0.2` |
| R2 | Ethereum and Solana sign-ins | ✅ not a gap: both derive an Arweave wallet from a seed phrase (`login_bloc.dart`), and it owns and signs the drive |
| R3 | **Which signature is the artifact's proof of authorship.** The upload's owner, as for every ArFS entity; the inner signature is gone. See below | ✅ D16 |
| R4 | 🔨 `meta.producer` now carries the building client and version (D17); the reader-side refusal list and the spec's versioning policy remain. **No way to disown a buggy producer.** A reader tries the next artifact only when one fails a check; a valid but wrong one is adopted by every client. Artifacts carry `App-Version`, so a reader-side refusal list (config) plus a versioning policy in the spec closes it | ⬜ spec + reader |
| R5 | ✅ **`path` and `isGhost` no longer travel; the rest are chain facts.** `thumbnail`, `importSource`, `originalOwner`, `fallbackTxId` and `assignedNames` are fields of the file's ArFS metadata, so they stay; `action` stays as derived and informational. Original finding: **app-internal columns in the format**: `path`, `isGhost`, `thumbnail`, `importSource`, `action`, `fallbackTxId`, `assignedNames`. Ghost and placeholder rows are already filtered out (`artifactChainOnlyPredicate`); the columns themselves need a protocol-or-drop call in 2.3 before the first publish | ✅ D17; specified in ar-io/docs #192 |
| R6 | **Library pages could not verify what they read by range**, since a signature covered the whole payload | ✅ resolved by D16: a range read is trusted exactly as much as a full one |
| R7 | **No rollout plan.** Flags exist, but a flag change reaches a user only with a `configVersion` bump and a reload, so there is no fast off switch, and outcomes are only logged | ⬜ below |
| R8 | Stream B order: with snapshots retiring, core-js may wire artifacts before finishing its own snapshot wiring | ⬜ B1.3 |

### Decided: the upload's owner proves authorship (R3, D16)

The payload was signed **inside** the uploaded data item, as well as by the
upload itself. The outer signature is real, but readers cannot check it
with the gateways in service. Measured on ardrive.net and turbo-gateway.com
for a Turbo-bundled data item: no `X-Arweave-Signature` or `X-Arweave-Owner`
headers, and GraphQL returns `"signature": "<not-found>"` and
`"owner": { "key": "<not-found>" }`. Release 75 can send those headers, but
for a bundled item only with `WRITE_ANS104_DATA_ITEM_DB_SIGNATURES=true`,
which defaults to `false`.

Phil chose to drop the inner signature on 2026-10-14: it bought nothing
serious, innovative or revenue-bearing. The options as weighed:

- **Keep the inner signature.** The bytes prove their author however they
  were found, including through an ArNS name. Costs: Wander signs through the
  deprecated `arweaveWallet.signature()` with `saltLength: 0`, which no test
  covers yet; core-js and the CLI must implement data item verification; and
  R6 stands.
- **Drop it.** Authorship is the owner GraphQL reports for the upload, which
  is how every ArFS entity is trusted today; a private drive's artifact is
  still authenticated by AES-GCM under the drive key. Costs: a name-discovered
  artifact needs one owner lookup, and a public drive's artifact is as
  trustworthy as the gateway, no more.

Removed in #2197 before the first publish, under format `0.2`.

### Open decision: carry the entry tables, or derive them (R9)

`folder_entries` and `file_entries` repeat the newest revision of each item.
Measured on a realistic 3,000-file artifact, they are 42% of the file, and
dropping them saves 42% even after gzip, because each entry row sits too far
from its revision for gzip's window to see the repeat. At 41,767 files that is
about 26 MiB down to 15 MiB uncompressed, or about 10.5 MiB down to 6 MiB on
the wire.

**Keep them (recommended).**

- The artifact stays drop-in: current state is a table a Library page, core-js
  or any SQLite tool reads directly, which is the property Ariel built the
  SQLite container for.
- Nothing about current state has to be specified as a derivation, and nothing
  on the import path changes.
- The saving only matters for the largest drives, and there it is about 4 MiB
  per publish, against an artifact that exists to replace tens of thousands of
  metadata fetches.

**Derive them.**

- 42% less to upload, store and download, every publish.
- One source of truth inside the file, so an entry cannot disagree with its
  revisions.
- But the derivation (newest revision by `dateCreated`, how ties break, which
  revision supplies `dateCreated` and `lastUpdated`) becomes protocol every
  reader must reproduce exactly, on the sync path, and every reader that wants
  current state runs a newest-per-item query over a table with no indexes.

**Risk if it is wrong either way.** Keeping them and later wanting the saving
means a major version: readers depend on the tables. Deriving them and getting
the rule subtly different from sync shows users the wrong name or folder for a
renamed or moved item, permanently per artifact. The first is a cost; the
second is a correctness failure on the path that must not have one.

Revisit if publishing cost becomes a real complaint for large drives, with a
parity test (export, strip, derive, compare exactly on hidden, moved, renamed
and multi-revision items) written before the change.

### The web database's storage (1.19), measured

#2197 moves the web database from sql.js to SQLite in wasm on the main thread,
saved block by block to IndexedDB (package:sqlite3 2.4.2 `IndexedDbFileSystem`).
That migration has not shipped (#2264 only removed an unused wasm file), so the
target can still change and every user migrate once.

Release builds (dart2js), the app's real schema, the rows a 41,767-file import
writes in one transaction, 2026-10-15:

| Browser | Storage | Committed | Saved | Reopen |
|---|---|---|---|---|
| Chromium 151 | #2197 as is (main thread, IndexedDB) | 15.5 s | +7.4 s after | 3.5 s |
| Chromium 151 | drift 2.16 shared worker, IndexedDB | 14.6 s | up to ~30 s after; lost if the tab closes sooner | 3.7 s |
| Chromium 151 | drift 2.16 OPFS (`opfsLocks`), needs COOP/COEP | 1.8 s | at commit | 0.25 s |
| Chromium 151 | **OPFS in a dedicated worker, no headers** | **0.69 s** | at commit | 0.06 s |
| Firefox 131 | #2197 as is | 15.4 s | +16.8 s after | 3.2 s |
| Firefox 131 | drift 2.16 OPFS (`opfsShared`), no headers | 3.5 s | at commit | 0.9 s |
| Firefox 131 | **OPFS in a dedicated worker, no headers** | 5.5 s | at commit | 0.07 s |

Safari/WebKit was not measured: its test browser needs system libraries this
machine lacks.

**The headers break the app.** Served with `Cross-Origin-Opener-Policy:
same-origin`, the demo wallet logged in, synced, and showed gateway images and
thumbnails, but:

- with `Cross-Origin-Embedder-Policy: require-corp`, audio (and so video)
  previews fail: gateways send no `Cross-Origin-Resource-Policy` header;
- with either `require-corp` or `credentialless`, Stripe's iframes are blocked
  and the card field does not render, so card top-ups break;
- the app is also served from AR.IO gateways, where headers cannot be set.

So drift's built-in OPFS needs headers on Chrome and is out. OPFS from a
dedicated worker needs none and was the fastest measured. Its costs: drift
2.16 has no such mode, so the worker is ours (drift's remote protocol on the
main side); `SimpleOpfsFileSystem` holds only the database and its journal,
so a received artifact is attached from an in-memory filesystem in the same
worker; and an OPFS file takes one writer, so a second tab needs the
read-only copy #2197 already builds for that case. Newer drift (2.33 and
later, Dart 3.10, so a Flutter upgrade) fixes IndexedDB persistence and adds
an IndexedDB-to-OPFS mover, but not a header-free OPFS mode for Chrome.

### Rollout (R7)

1. ✅ Read artifacts on staging (`enableSyncFromDriveState`), with a
   `configVersion` bump (`staging.json`, `configVersion` 4).
2. ⬜ Read in production, the same way.
3. 🔨 Publish on staging: done with the demo wallet; Wander not yet.
4. ⬜ Publish in production.

Each step records the import outcomes (§7) and the migration result, so a
step is judged on numbers rather than on the absence of complaints.

**Rehearsal, 2026-10-15, before step 1.** A release build of #2197 with the
staging config and both flags on, the demo wallet (21 drives), headless
Chromium. One drive, My Private Drive (`8d81a9db-…`), end to end:

| Step | Result |
|---|---|
| Ordinary GraphQL sync, no artifact on chain | `outcome=none-found`; 20.8 s |
| Publish | 792 entities, 174.22 KiB sealed (AES256-GCM), 0.0023 Credits; `xk_N9vGYgTuLUgyWlVbdHCkl_js_Bo35M2miM6porK4`, indexed at once with the expected tags |
| Fresh client (logout), sync | `outcome=used`, 791 entities, decrypt and checks 59 ms, merge 27 ms; the sync took 40.8 s, of which 39.8 s was the gateway's first answer for the unbundled item, a few minutes after the upload (later reads: 0.2 s) |
| Reload, sync again | skipped as already imported (D19) without a download; the sync took 0.93 s |
| Parity | 773 files, 9.58 GiB in the drives list after the import and after a GraphQL-only sync on a fresh client |

Two things to watch at step 1: the first read of a newly published artifact
can wait on the gateway, and the profile card's totals are computed once per
session, so they can show a figure from partway through a sync (397 files and
3.7 MB here, against 773 and 9.58 GiB in the drives list). The second predates
this feature.

---

## 2. ar-io-docs: the specification

The spec is written from the implementation that exists, and it is the contract
Stream B builds against. Stream B does not start development until 2.2 to 2.8
are merged, because a second implementation written from the web app's code
instead of the spec would only prove that the two codebases agree.

| | Item | Status |
|---|---|---|
| 2.1 | **Correct the Snapshot spec**: `jsonMetadata`, not `dataJson`; `txSnapshot`, not `tsSnapshot`; a sibling of `gqlNode`; a nullable string | ✅ ar-io-docs #137 |
| 2.2 | `entity-types.mdx`: a `## Drive State` section beside `## Snapshot`, with its tags (`Entity-Type: drive-state`, `Drive-Id`, `Drive-State-Id`, `State-Version`, `Entity-Count`, `Block-Start`, `Block-End`, `Cipher`, `Cipher-IV`) and the rule that a `Content-Encoding` tag is never set | 🔨 ar-io/docs #192 |
| 2.3 | **The payload, normatively**: the SQLite tables, columns, types and `meta` keys a producer must write and a reader may rely on, with what is excluded by construction (every key). A second producer cannot be written without this. The DDL in the PR is generated from `drive_state_artifact_schema.dart` | 🔨 ar-io/docs #192 |
| 2.4 | **The envelope, normatively**: serialise, optional gzip, AES256-GCM with the drive key for a private drive. Authorship is the upload's owner (D16). The coverage claim, and the rule that the indexer-reported `Block-Start` / `Block-End` tags are checked against it before a watermark is adopted | 🔨 ar-io/docs #192 |
| 2.5 | **The encoding rule** (D13, decided below): a reader accepts both encodings and tells them apart by the first bytes of the payload | 🔨 ar-io/docs #192 |
| 2.6 | `reading-data.mdx`: the read order (artifact, then snapshots, then GraphQL) and the rule that every failure falls back rather than fails | 🔨 ar-io/docs #192 |
| 2.7 | `privacy.mdx`: one ciphertext under the **drive** key, unlike a snapshot's per-entity ciphertext; and that a snapshot of a private drive publishes its structure in plaintext, which is not stated anywhere | 🔨 ar-io/docs #192 |
| 2.8 | Snapshots: marked as superseded for new drives (D-30). Existing snapshots stay readable for ever, and a reader keeps reading them | ⬜ 🔒 D-30 |
| 2.9 | Whether this addition bumps the ArFS version (0.15 today). A reader that ignores an unknown entity type is unaffected either way | ⬜ 🔒 naming |

2.7 is worth its own line: the fact that snapshots publish a private drive's
entire structure in plaintext is true today, undocumented, and something
implementers should know irrespective of this addition.

### D13, the compression threshold (decided 2026-10-14)

**Decided: the threshold is a producer setting, not part of the format. One
thing is fixed permanently: every reader accepts both encodings.**

Three facts decide it:

1. **A private artifact can never be range-read.** It is encrypted as one unit,
   so it is always compressed and the threshold never applies to it.
2. **Only a public artifact served by a Library page gains from identity**, and
   Library pages do not exist yet. Until they do, identity costs about three
   times the upload (17.70 MiB against 5.98 at 41,767 files) and buys nothing.
3. **D13's earlier form, a `meta` flag, cannot work.** `meta` is inside the
   compressed bytes, so a reader would have to decompress to learn whether to
   decompress. The bytes already answer the question: a gzip stream starts with
   `1f 8b`, a SQLite file with `SQLite format 3\0`. The bytes carry the answer,
   so no tag is needed and none can lie about it.

So:

- **Readers, from the first release, in every implementation:** check the
  owner, decrypt if private, then sniff. gzip is inflated with the existing bound; SQLite is
  read as is; anything else is refused. The web reader does this as of #2197,
  before any artifact is published.
- **Producers, until Library pages ship:** always gzip, as the code does now.
- **Producers, when Library pages ship:** a public artifact is published
  identity above a size measured with the real page, not chosen now. 16 MiB of
  SQLite (about 26,000 files at 640 B each) is the proposed starting point to
  test against, since below it a whole fetch is a few seconds on an ordinary
  connection and a cold gateway fetches the whole object anyway (§4.5).

The permanent choice is per artifact, as before. What changes is that the
number stays adjustable, because no reader depends on it.

---

## Stream B: ardrive-core-js and ardrive-cli

A separate stream with its own design, development and test phases, run after
the spec (§2) is merged. The goal: core-js **reads** artifacts during drive
sync and **produces** them, and the CLI exposes both, so any ArDrive client can
open a drive from one artifact and any client can publish one.

core-js is the implementation; the CLI is a thin surface over it. Nothing about
the format lives in the CLI.

### B1. Design

Exit: a design doc in ardrive-core-js, reviewed by someone who wrote none of
it, answering every row.

| | Question | Notes |
|---|---|---|
| B1.1 | **The SQLite engine** | Must run on Node 18 (both packages' `engines`), with no native build for the CLI's install. `sql.js` (WebAssembly) meets both; `better-sqlite3` is native; `node:sqlite` needs Node 22. Also decides whether core-js can produce in a browser |
| B1.2 | **Module layout** | `src/drive_state/` beside `src/snapshots/`, mirroring its files: tags, types, query, data, plus envelope and producer |
| B1.3 | **Where the reader joins sync** | Beside `parseSnapshotData` in `arfsdao_anonymous`, composed with `snapshot_obscuring`, `height_range` and `drive_history_composite`. Not a second range mechanism. Sequenced with core-js's own pending snapshot wiring (`src/snapshots/index.ts`: not yet in the live listing path) |
| B1.4 | **The CLI's metadata cache** | How an imported artifact populates the persistent ArFS entity cache, and how the watermark is stored so the next run continues from `Block-End` |
| B1.5 | **Producer inputs** | core-js has no local database, so the producer builds from a fresh full listing of the drive. Define the coverage claim it can honestly sign, and refuse to publish over a gap, the same rule as the web app |
| B1.6 | **Private drives** | Drive key derivation for every identity type the CLI supports, and the guarantee that no key material reaches the payload |
| B1.7 | **Failure vocabulary** | The same enumerated outcomes as the web app (§7 of the proposal), mapped to core-js errors, so a failure in either client means the same thing |
| B1.8 | **Upload path** | Turbo and L1 through core-js's existing uploaders, cost reported before upload, `--dry-run` |

### B2. Develop

| | Item | Status |
|---|---|---|
| B2.1 | Tags, types and GraphQL discovery, owner-filtered | 🔨 core-js #288 |
| B2.2 | Envelope reader: check the upload's owner, decrypt (private), sniff the encoding, inflate with a bound, open the SQLite through the read gate | 🔨 core-js #288 |
| B2.3 | Payload reader into core-js's own entity types, not a port of the web app's column names, including the coverage check against the tags | 🔨 core-js #288 |
| B2.4 | Wire the reader into drive listing and sync (B1.3, B1.4), behind an option. Decided 2026-10-20: on by default | 🔨 core-js #288 |
| B2.5 | Producer: build the SQLite to the spec's schema (2.3), seal it (2.4), and refuse on any gap | 🔨 core-js #288 |
| B2.6 | CLI: `ardrive create-snapshot` publishes artifacts (with `--dry-run`), and listing uses them. Decided 2026-10-20: the existing command, not a new one | 🔨 cli #378 |
| B2.7 | CLI docs in ar-io-docs, beside the snapshot command | 🔨 generated from the CLI README in #378 |

### B3. Test

Exit: every row green in CI, and a reviewer who wrote none of it has signed off.

| | Test | What it proves |
|---|---|---|
| B3.1 | Per-layer unit tests, with every integrity guard mutation-checked | A guard whose removal no test notices is not a guard |
| B3.2 | **Web produces, core-js reads**: identical entities | The format is real, not two codebases agreeing with themselves |
| B3.3 | **core-js produces, web reads**: identical entities | The same, in the direction that makes the CLI a trustworthy producer |
| B3.4 | Golden fixtures checked into both repos: a public and a private artifact, gzip and identity, plus one of each malformed kind | Each repo catches drift without needing the other's toolchain |
| B3.5 | Composition: artifact plus snapshots plus GraphQL cover the range once, including a snapshot straddling `Block-End` | No entity is lost or doubled |
| B3.6 | Hostile inputs: forged coverage tags, a wrong owner, a wrong drive, a gzip bomb, truncated data | Every one falls back to GraphQL and none is adopted |
| B3.7 | Scale: a drive of at least 40,000 files, read and produced, with time and memory recorded | The CLI is the better producer for large drives only if that is measured |
| B3.8 | End to end on a real gateway with a test wallet, never a production upload in CI | The whole path, once, by a human |

**Results, 2026-10-20** (core-js #288, web #2297):

| | Result |
|---|---|
| B3.1 | 100 core-js unit tests across the envelope, reader, entities, discovery, source, listing, producer and sync |
| B3.2 | core-js reaches this app's importer outcome on all 43 golden fixtures, and reads the same rows from every one it uses |
| B3.3 | This app imports core-js's artifacts with identical folder and file rows; so do two mainnet drives core-js built (5 and 544 entities) |
| B3.4 | `test/fixtures/drive_state/` here, copied to core-js `tests/fixtures/drive_state/` |
| B3.5 | core-js tests: base plus later revisions, a newer copy kept against a lagging gateway, a file moved out of a folder |
| B3.6 | Fixtures for each: coverage, owner, drive, gzip bomb, truncated and tampered ciphertext |
| B3.7 | 41,767 files, private, Node 18: read 1.9 s plus 0.95 s to entities, 208 MiB; build and seal 3.4 s, 255 MiB. Within every target |
| B3.8 | Not yet: reads and a `--dry-run` publish ran on mainnet with no spend; one real publish by a person remains |


---

## Verification strategy

Scaled to the risk, which is that the output is immutable and permanent.

**Per layer** — behavioural tests, and mutation-check anything that enforces a
security or integrity property. A test that still passes when the guard is
removed is not a test. This has already caught real defects: an always-true
signature verifier, a removed size guard, a `>=`/`>` boundary, an ignored owner
check.

**Per merge** — the full suite, never the touched files. Two branches green
individually can be wrong together, which has already happened once here (a
stale enum case that neither branch's own gate could see).

**Per repository** — an independent reviewer who wrote none of the code.

**Across repositories**: B3.2 and B3.3, an artifact produced by one
implementation, read by another, yielding identical entities. Nothing else proves the format.

**Before anything is published** — a human. The loop never uploads.

---

## Sequencing

1. ✅ **Finish ardrive-web** (#2197), including the two-encoding reader (D13
   above) so no published artifact can outrun its readers.
2. **Specify** (2.2 to 2.9) from the implementation that exists, not from
   intent: the `dataJson` divergence is what happens when those drift apart.
3. **Stream B**: design (B1), then develop (B2), then test (B3). The cross
   tests B3.2 and B3.3 gate it; nothing ships in core-js or the CLI until both
   directions pass.
4. **Then** the deferrals: export views (1.11), ArNS (1.12), incremental
   artifacts, Library pages and the identity threshold.

The human decisions on the critical path, the format's names before anything
is published and the first upload, are 🔒 and stay that way.
