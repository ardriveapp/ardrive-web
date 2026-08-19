# Drive state artifact — delivery plan

Tracks the ArFS addition across every repository it touches. The proposal is
`docs/DRIVE_STATE_ARTIFACT.md`; the bound decisions are
`docs/drive-state/DECISIONS.md`.

**Status key:** ✅ merged to the feature branch · 🔨 in flight · ⬜ not started ·
🔒 blocked on a human decision

---

## Findings that shape the downstream work

Two things checked in the sibling repositories, both of which change the plan
from what the proposal assumed:

**1. `ardrive-core-js` has no snapshot support at all.** Its `entityTypeValues`
(`src/types/type_guards.ts:7`) is `drive | file | folder | drive-signature` —
there is no `snapshot`, and no `parseSnapshotData` anywhere in the source. So
adding `drive-state` there is not "one more rollup format beside snapshots"; it
would be the **first** rollup artifact core-js can read. That is a larger piece
of work than the proposal's §8 implied, and it is also the higher-value one:
core-js is what every non-web client builds drive state through.

**2. The CLI creates snapshots through its own utility**
(`src/utils/snapshots/create_snapshot.ts`), not through core-js. A comment in
`src/commands/create_snapshot.ts:74` says the body shape is "dictated by
core-js's own `parseSnapshotData`" — **that function does not exist in
core-js**. The comment is stale or aspirational, and anyone reasoning from it
would be misled. Worth correcting regardless of this feature.

Consequence: the CLI can *produce* a rollup that nothing in core-js can
*consume*. The drive-state work should not repeat that split — the reader
belongs in core-js, where every client can reach it.

---

## 1. ardrive-web — the reference implementation

| | Item | Status |
|---|---|---|
| 1.1 | Export one drive's current state; key material excluded by construction; schema-drift guard | ✅ |
| 1.2 | Envelope: gzip → signed ANS-104 data item → AES-GCM, and the inverse | ✅ |
| 1.3 | ArFS entity + tags (§3.2) | ✅ |
| 1.4 | Discovery by GraphQL, owner-filtered, behind an interface | ✅ |
| 1.5 | Enumerated outcome vocabulary (§7) | ✅ |
| 1.6 | Import + merge, validate-before-write, watermark from `Block-End` | ✅ |
| 1.7 | Sync composition behind an `AppConfig` flag defaulting to false | 🔨 |
| 1.8 | Creation service + confirmation UI, stopping short of upload | 🔨 |
| 1.9 | Independent QA gate — an agent that wrote none of it | ⬜ |
| 1.10 | Adversarial audit of every layer, findings ranked and re-verified | 🔨 |
| 1.11 | Export views replacing the typed projection (D7 deferral — needs a schema migration) | 🔒 |
| 1.12 | ArNS discovery (D6 deferral — needs an undername convention) | 🔒 |
| 1.13 | Execute an upload | 🔒 human only — costs money, publishes permanently |

## 2. ar-io-docs — the specification

A new entity type is not real until it is specified here.

| | Item | Status |
|---|---|---|
| 2.1 | **Correct the Snapshot spec**: the metadata field is `jsonMetadata`, not `dataJson`, in both prose and the JSON example (`content/build/advanced/arfs/entity-types.mdx`). Independent of this feature and live today — an implementer following the docs reads no metadata from any snapshot | ⬜ ship first, on its own |
| 2.2 | `entity-types.mdx` — a `## Drive State` section beside `## Snapshot`, with `### Drive State Entity Tags` and `### Drive State Entity Data` | ⬜ |
| 2.3 | `data-model.mdx` — where the artifact sits relative to drives, snapshots and entities | ⬜ |
| 2.4 | `reading-data.mdx` — the read order (artifact → snapshots → GraphQL) and the rule that every failure falls back rather than fails | ⬜ |
| 2.5 | `privacy.mdx` — signed and encrypted with the **drive** key as one unit, unlike a snapshot's per-entity ciphertext; and that a snapshot of a private drive is *not* encrypted, which is not currently stated anywhere | ⬜ |

2.5 is worth its own line: the fact that snapshots publish a private drive's
entire structure in plaintext is true today, undocumented, and something
implementers should know irrespective of this addition.

## 3. ardrive-core-js — the reader every other client inherits

| | Item | Status |
|---|---|---|
| 3.1 | Add `DRIVE_STATE: 'drive-state'` to `entityTypeValues` (`src/types/type_guards.ts`) | ⬜ |
| 3.2 | Envelope reader: decrypt → parse data item → verify signature → gunzip → sections. Must match ardrive-web byte for byte | ⬜ |
| 3.3 | Section deserialisation to core-js's own entity types — **not** a port of this app's column names (proposal §8) | ⬜ |
| 3.4 | Discovery by GraphQL, owner-filtered | ⬜ |
| 3.5 | Compose into the existing listing path so a client covers `Block-End → head` by GraphQL | ⬜ |
| 3.6 | Cross-implementation test: an artifact produced by ardrive-web opens in core-js and yields identical entities | ⬜ **the acceptance test for the whole feature** |

3.6 is the one that matters. Until an artifact written by one implementation is
read by another, "cross-client format" is an assertion, not a fact.

## 4. ardrive-cli — production where bandwidth exists

| | Item | Status |
|---|---|---|
| 4.1 | `ardrive create-drive-state` — produce and upload an artifact. The CLI is the better producer for a large drive: real bandwidth, no browser connection limits | ⬜ |
| 4.2 | Route it through core-js rather than a CLI-local utility, so the split described above is not repeated | ⬜ |
| 4.3 | `--dry-run` that prepares and reports size without uploading, mirroring the existing snapshot command's flag | ⬜ |
| 4.4 | Correct the stale `parseSnapshotData` comment (`src/commands/create_snapshot.ts:74`) | ⬜ |

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

**Across repositories** — 3.6: an artifact produced by one implementation, read
by another, yielding identical entities. Nothing else proves the format.

**Before anything is published** — a human. The loop never uploads.

---

## Sequencing

1. **2.1 alone, now.** The `dataJson` correction is a live bug against every
   snapshot on chain and has nothing to do with this feature. It should not wait
   behind a proposal, and should not ride in on a feature PR.
2. **Finish ardrive-web** (1.7–1.10), so the reference implementation is real
   and reviewed before anything is specified as protocol.
3. **Specify** (2.2–2.5) from the implementation that exists, not from intent —
   the `dataJson` divergence is what happens when those drift apart.
4. **core-js** (3.1–3.6), ending at the cross-implementation test.
5. **CLI** (4.1–4.4) once core-js can do the work.
6. **Then** the deferrals: export views (1.11), ArNS (1.12), incremental
   artifacts, public drives.

The human decisions on the critical path — the format's names before anything
is published, and the first upload — are 🔒 and stay that way.
