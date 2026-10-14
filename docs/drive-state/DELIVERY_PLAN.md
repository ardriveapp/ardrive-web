# Drive state artifact — delivery plan

Tracks the ArFS addition across every repository it touches. The proposal is
`docs/DRIVE_STATE_ARTIFACT.md`; the bound decisions are
`docs/drive-state/DECISIONS.md`.

**Status key:** ✅ merged to the feature branch · 🔨 in flight · ⬜ not started ·
🔒 blocked on a human decision

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
| 1.2 | Envelope: gzip → signed ANS-104 data item → AES-GCM, and the inverse | ✅ |
| 1.3 | ArFS entity + tags (§3.2) | ✅ |
| 1.4 | Discovery by GraphQL, owner-filtered, behind an interface | ✅ |
| 1.5 | Enumerated outcome vocabulary (§7) | ✅ |
| 1.6 | Import + merge, validate-before-write, watermark from the payload's **signed** coverage claim (the `Block-End` tag is cross-checked against it, never believed on its own) | ✅ |
| 1.7 | Sync composition behind an `AppConfig` flag defaulting to false | ✅ |
| 1.8 | Creation service + confirmation UI | ✅ |
| 1.8a | **Carry revisions, licences and derived `network_transactions`** (D2 reversal). Entry rows alone render an empty drive: `filesInFolderWithLicenseAndRevisionTransactions` INNER JOINs `network_transactions` through the newest `file_revisions` row, so a restored drive with no revisions shows zero files | ✅ |
| 1.8b | **A publish path and an app entry point.** A real Turbo/L1 uploader behind the `DriveStateUploader` seam, cost shown before the click, and a flag-gated item in the new button — until this lands the modal has no caller and the uploader publishes nothing | ✅ |
| 1.9 | Independent QA gate — an agent that wrote none of it | ✅ 10 findings, all closed |
| 1.10 | Adversarial audit of every layer, findings ranked and re-verified | ✅ |
| 1.14 | **Measured at production scale.** Export, seal, import and render at 41,767 files; sizes, timings and the producer's memory peak recorded in §1.1/§2.3 and reproducible from `drive_state_scale_measurement_test.dart` | ✅ |
| 1.15 | **Composition with snapshots.** Artifact, snapshots and GraphQL proven to cover the range once, including a snapshot straddling `Block-End` | ✅ |
| 1.16 | Localisation — every string the feature adds is hardcoded English by decision, pending a single `.arb` pass across all six locales at ship time | ⬜ ship-time |
| 1.17 | Persist the sync skip ledger and the imported-artifact record across sessions (`SYNC_SKIPPED_ENTITY_PERSISTENCE.md`); both are in-memory today, so a restart re-pays one import and forgets one refusal | ⬜ |
| 1.11 | Export views replacing the typed projection (D7 deferral — needs a schema migration) | 🔒 |
| 1.12 | ArNS discovery (D6 deferral — needs an undername convention) | 🔒 |
| 1.13 | Execute an upload | 🔒 human only — costs money, publishes permanently |

## 2. ar-io-docs: the specification

The spec is written from the implementation that exists, and it is the contract
Stream B builds against. Stream B does not start development until 2.2 to 2.8
are merged, because a second implementation written from the web app's code
instead of the spec would only prove that the two codebases agree.

| | Item | Status |
|---|---|---|
| 2.1 | **Correct the Snapshot spec**: `jsonMetadata`, not `dataJson`; `txSnapshot`, not `tsSnapshot`; a sibling of `gqlNode`; a nullable string | ✅ ar-io-docs #137 |
| 2.2 | `entity-types.mdx`: a `## Drive State` section beside `## Snapshot`, with its tags (`Entity-Type: drive-state`, `Drive-Id`, `Drive-State-Id`, `State-Version`, `Entity-Count`, `Block-Start`, `Block-End`, `Cipher`, `Cipher-IV`) and the rule that a `Content-Encoding` tag is never set | ⬜ |
| 2.3 | **The payload, normatively**: the SQLite tables, columns, types and `meta` keys a producer must write and a reader may rely on, with what is excluded by construction (every key). A second producer cannot be written without this, and today it exists only as `drive_state_artifact_schema.dart` | ⬜ |
| 2.4 | **The envelope, normatively**: serialise, optional gzip, sign as an ANS-104 data item, AES256-GCM with the drive key for a private drive. The signed coverage claim, and the rule that the unsigned `Block-Start` / `Block-End` tags are checked against it before a watermark is adopted | ⬜ |
| 2.5 | **The encoding rule** (D13, decided below): a reader accepts both encodings and tells them apart by the first bytes of the signed payload | ⬜ |
| 2.6 | `reading-data.mdx`: the read order (artifact, then snapshots, then GraphQL) and the rule that every failure falls back rather than fails | ⬜ |
| 2.7 | `privacy.mdx`: one ciphertext under the **drive** key, unlike a snapshot's per-entity ciphertext; and that a snapshot of a private drive publishes its structure in plaintext, which is not stated anywhere | ⬜ |
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
   `1f 8b`, a SQLite file with `SQLite format 3\0`. Both are inside the
   signature, so the answer cannot be forged, and no tag is needed.

So:

- **Readers, from the first release, in every implementation:** verify the
  signature, then sniff. gzip is inflated with the existing bound; SQLite is
  read as is; anything else is refused. The web reader does this as of #2197,
  before any artifact is published.
- **Producers, until Library pages ship:** always gzip, as the code does now.
- **Producers, when Library pages ship:** a public artifact is published
  identity above a size measured with the real page, not chosen now. 16 MiB of
  SQLite (about 24,000 files at 705 B each) is the proposed starting point to
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
| B2.1 | Tags, types and GraphQL discovery, owner-filtered | ⬜ |
| B2.2 | Envelope reader: decrypt, parse the data item, verify the signature, sniff the encoding, inflate with a bound, open the SQLite | ⬜ |
| B2.3 | Payload reader into core-js's own entity types, not a port of the web app's column names, including the coverage check against the tags | ⬜ |
| B2.4 | Wire the reader into drive listing and sync (B1.3, B1.4), behind an option that defaults off until B3 passes | ⬜ |
| B2.5 | Producer: build the SQLite to the spec's schema (2.3), seal it (2.4), and refuse on any gap | ⬜ |
| B2.6 | CLI: `ardrive create-drive-state` (with `--dry-run`) and an option on drive listing and sync to use artifacts | ⬜ |
| B2.7 | CLI docs in ar-io-docs, beside the snapshot command | ⬜ |

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

1. **Finish ardrive-web** (#2197), including the two-encoding reader (D13
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
