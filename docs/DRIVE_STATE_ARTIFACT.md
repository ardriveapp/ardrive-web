# The drive state artifact

A published, encrypted, parsed-state blob that a client imports in bulk instead
of replaying a drive's history entity by entity.

**Additive.** Snapshots remain an ArFS interchange format and the fallback. A
client that does not understand a state artifact, or cannot decrypt one, syncs
exactly as it does today.

**The governing principle: this is a cache, and every failure is a fallback.**
Unknown version, failed decryption, failed integrity check, missing tag,
unexpected row - each means *ignore the artifact and sync normally*, never
*fail the drive*. That single rule is what makes the addition foolproof: the
worst outcome of anything going wrong is today's performance.

---

## 1. Why

Sync is slow on large drives, and the cost is not the download.

Consuming a snapshot costs, **per entity**: one AES decryption
(`file_entity.dart:117`, inside `FileEntity.fromTransaction`), one JSON parse,
one database insert. On a 42k-item drive that is ~42,000 of each — the ~80
seconds of `Processing chunk of 1000 transactions` observed in a real sync.

A state artifact costs **one** decryption and a bulk insert.

### Measured size

| | on disk | gzipped |
|---|---|---|
| State artifact (42k files) | **31.31 MiB** | **6.41 MiB** |
| Snapshot `z78YIh…` (same drive) | 43.92 MiB | ~11.37 MiB |
| | 1.40× smaller | 1.77× smaller |

The artifact figure is from a Drift database built with 42,000 file entries,
revisions and network transactions, `VACUUM`ed and weighed — a model of the
drive, not an export of the user's own database, and with one revision per
file. The snapshot figures are the real transaction: 43.92 MiB on chain, and
3.86× gzip measured on a 200 KB sample of it.

Size is the smaller win. The snapshot carries full GQL nodes with tags repeated
per entity and base64-inflated metadata, which is why it loses even though JSON
compresses better in ratio terms.

### Producing it is cheap, which is the real inversion

A snapshot stores chain data, so producing one **re-reads the chain**: ~420
paginated GraphQL queries plus ~42,000 metadata fetches for this drive, which
does not complete on a throttled connection (see
`SNAPSHOT_CREATION_FROM_SNAPSHOTS.md`).

A state artifact is already sitting in the local database. Producing it is
export → encrypt → upload. No GraphQL walk, no per-entity fetches.

---

## 2. Security

### 2.1 Export, never dump — the rule everything else depends on

The local database holds key material:

```
profiles.encryptedWallet        the Arweave wallet, encrypted with a
                                password-derived key
profiles.keySalt                the salt that key is derived with
profiles.encryptedPublicKey
drives.encryptedKey             the drive key, wrapped in the profile key
drives.keyEncryptionIv
```

Serialising the database would publish these **permanently and publicly**.
Note that `encryptedWallet` and `keySalt` together are a complete offline
attack package: ciphertext and the salt needed to derive candidate keys from
guessed passwords, with unlimited time to try. Arweave has no delete. This is the single failure that would make the feature harmful rather
than merely wrong.

Therefore the exporter must be **structurally unable** to read them, not merely
instructed not to:

- Define **export views** in the schema that name only exportable columns, and
  let the exporter query *views only*, never tables. The schema has no views
  today, so this is additive.
- A view lists columns explicitly, so a later migration adding a sensitive
  column to `drives` does not reach the export. That is the realistic failure
  this defends against: not this design being wrong today, but a future
  migration quietly widening what an exporter sees. `schemaVersion` is 29 and
  moves regularly.
- `profiles` has no export view at all. `drives`' view omits `encryptedKey`,
  `driveKeyGenerated` and `keyEncryptionIv`.
- A test still asserts the views against the live schema, but as a second line
  rather than the only one.

Separating key material into its own store was considered and rejected for now:
it would migrate `encryptedWallet`, `keySalt`, `encryptedKey` and
`keyEncryptionIv` out of a live database whose migration fixtures are stale at
v19, with "user loses wallet access" as the failure mode, and it would still
leave one drive being exported from a database holding all of them. Worth doing
on its own security merits - browser storage is readable by any XSS in the
origin - but as separate hardening work, not as a dependency of this.

### 2.2 Authenticated encryption, and the 100 MiB cliff

Encrypt with the drive key, as ArFS encrypts everything else.

`maxSizeSupportedByGCMEncryption` is **100 MiB**
(`packages/ardrive_uploader/lib/src/constants.dart`); above it the codebase
falls back to AES-CTR, which is **unauthenticated**. For file data that is a
considered trade. For state a client imports wholesale it is not: a flipped bit
becomes silently wrong local state rather than visibly corrupt bytes.

The artifact must stay authenticated. Options, in order of preference:

1. Cap the artifact below the GCM boundary and split larger drives into parts,
   each authenticated, with a manifest listing them.
2. Keep one blob and add a separate MAC over the ciphertext.

At 31 MiB for 42k files, the boundary sits somewhere near 130k files. It will be
reached.

### 2.3 Do not hand an untrusted file to SQLite

Opening an attacker-controlled SQLite file exercises a parser with a history of
malformed-database CVEs. The artifact should therefore be a **serialisation of
parsed rows**, not a `.db` file — read with ordinary deserialisation and
inserted through the normal DAO path.

This also removes the schema-welding problem: a row format the client maps onto
whatever `schemaVersion` it runs, rather than a database file that only one
version can open. Two independent reasons for the same decision.

### 2.4 Trust, authorship and replay

- **Owner only.** Discovery filters on `owners: [ownerAddress]`, exactly as the
  snapshot query does today. An artifact from any other address is ignored.
- **Newest wins**, by the coverage tags in §3 — not by arrival order.
- **Rollback resistance.** A client must not accept an artifact covering *less*
  than what it has already synced; a stale artifact is a no-op, not a regression.
- **Decryption failure is not a fallback failure.** A drive key that cannot open
  an artifact means skip it and sync normally. It must never be reported as a
  corrupt drive.
- **Residual risk.** The owner's own client publishes whatever local state it
  has. A snapshot's entries can in principle be checked against chain because
  each carries its original `gqlNode`; exported rows cannot. This is the same
  trust as `SNAPSHOT_CREATION_FROM_SNAPSHOTS.md` §"the correctness question",
  one step further from the chain — and it is why the artifact is a cache, never
  the only copy.

### 2.5 Public drives

A public drive has no drive key, so its artifact would be plaintext. The
contents are already public, but a single blob enumerating every name, size and
relationship is materially more useful to an adversary than the same facts
scattered across transactions.

Options: publish plaintext (accepting the aggregation), encrypt to a key derived
from the drive id (obfuscation only, not a security boundary), or support the
artifact for private drives only in v1. **Recommend v1 private-only** — the
performance problem is worst there, because public drives skip the 42,000
decryptions entirely.

---

## 3. The ArFS entity

Specified to match the conventions the Snapshot entity already uses in
`ar-io-docs/content/build/advanced/arfs/entity-types.mdx`, so it reads as one
more entity type rather than a bolt-on.

### Tags

```
Drive-Id:       "<drive uuid this state belongs to>"
Entity-Type:    "drive-state"
Drive-State-Id: "<uuid of this drive-state entity>"
State-Version:  "1"
Block-Start:    "<minimum block height accounted for, eg 0>"
Block-End:      "<maximum block height accounted for, eg 1814228>"
Cipher:         "AES256-GCM"          (private drives)
Cipher-IV:      "<12 byte IV as Base64>"
```

`Drive-State-Id` mirrors `Snapshot-Id`; `Block-Start`/`Block-End` carry the same
meaning they do for a snapshot, and `Cipher`/`Cipher-IV` follow
`arfs/privacy.mdx` unchanged - AES256-GCM with a 12 byte IV, the parameter
Base64 encoded in the tag.

`Block-End` is what makes it composable with everything already built: a client
imports the artifact, then covers `(Block-End → current]` from snapshots and
GraphQL - the same range arithmetic `HeightRange.difference` already performs.

**Unknown `State-Version` must be inert**, not an error. An older client sees a
transaction whose `Entity-Type` it does not query for and syncs from snapshots,
unaware anything was offered.

### Data

The body is the encrypted serialisation of one drive's exported rows. For a
private drive it is encrypted with the drive key under the `Cipher`/`Cipher-IV`
above - **one** encryption over the whole body, which is the entire performance
point, as against a snapshot's per-entity ciphertext.

The row format is deliberately **not** Drift's schema (§5), and is versioned by
`State-Version` so it can change without stranding published artifacts.

### A warning from the existing spec

While writing this, a divergence surfaced between the Snapshot spec and every
snapshot on chain:

| | field |
|---|---|
| `entity-types.mdx`, prose and JSON example | `dataJson` |
| `snapshot_types.dart:18`, `snapshot_item.dart:311` | `jsonMetadata` |
| Real snapshot `z78YIh…` (200 KB sample) | `jsonMetadata` ×189, `dataJson` ×0 |

An implementer following the published spec would read no metadata from any
snapshot and silently fall back to fetching every transaction individually -
precisely the pathology this document exists to remove. It should be corrected
independently of this work (§7).

The lesson for this entity: **the spec, the implementation and a real artifact
must be checked against each other**, not assumed to agree.

---

## 4. Impact on sync

The artifact slots in ahead of snapshots, as one more source in the existing
composition:

```
1. state artifact   [0 → Block-End]        bulk import, one decryption
2. snapshots        (Block-End → newest]   existing path
3. GraphQL          (newest → current]     existing path
```

Concretely:

- **`SyncRepository`** gains an artifact lookup before the snapshot prefetch. It
  is one query and, on a hit, replaces the snapshot phase for that range.
- **`HeightRange`/`obscuredBy` need no change.** The accumulator in
  `SnapshotItem.instantiateAll` already composes ranges from multiple sources;
  the artifact is one more obscuring range.
- **Import is a merge, not a replace.** The database holds every drive and
  profile. Import into a sandbox, validate, then merge one drive's rows,
  reconciling against any locally-newer revision rather than clobbering it.
- **The watermark rule is unchanged and matters more.** Sync advances
  `lastBlockHeight` regardless of skipped entities
  (`SYNC_SKIPPED_ENTITY_PERSISTENCE.md`), so an artifact must not be produced
  from a drive whose sync reported skips. Publishing gaps into an immutable
  artifact is exactly the failure that document describes, made permanent.
- **Instrumentation already exists.** The `[snapshot]` log lines added in #2184
  report where entity metadata came from; the artifact path should report itself
  the same way, so a sync that used one is legible.

---

## 5. Impact on ardrive-core-js and the CLI

*Reasoned from the protocol boundary; those repositories were not read.*

- **Nothing breaks.** The artifact is a transaction with an `Entity-Type` no
  existing client queries for. Clients that do not know it continue to read
  snapshots, which continue to be produced.
- **Core would need three things to participate**: the envelope and row format,
  the drive-key decryption path (which it already has), and the merge rules.
  Reading is strictly simpler than writing.
- **The CLI is the more interesting producer, not consumer.** It runs on
  machines with real bandwidth and no browser connection limits, so
  `ardrive create-drive-state` is a better place to generate artifacts for a
  large drive than a browser tab is.
- **Row format must not be Drift's schema.** If the wire format mirrors
  `schemaVersion`, every other implementation inherits this app's migration
  history. Define it as its own thing, mapped on both sides.
- **Version negotiation is the whole compatibility story.** One tag, and the
  rule that unknown versions are ignored rather than rejected.

---

## 6. ArNS as the discovery mechanism

Finding the newest artifact by GraphQL means a query per drive per sync, on
gateways that already rate limit
(`arweave-net-rate-limited`, and turbo-gateway throttling under sync load).

The app can already point a name at an arbitrary transaction —
`ArnsRepository.setUndernamesToFile` calls `_sdk.setUndername(jwtString:,
domain:, txId:, undername:)` today for files. The same call points an undername
at the newest artifact:

```
state_<driveId>.myname  →  latest drive-state tx id
```

What this buys:

- **One name resolution instead of a paginated query**, and a stable address
  that does not change when the artifact does.
- **A publish step that is already implemented.** Assigning a name to a
  transaction is existing, tested plumbing, not new protocol.
- **A sharing story.** A recipient given a name and a drive key can resolve and
  import a large shared drive without walking its history — the case where
  today's experience is worst.

Caveats, and they are real:

- **ArNS is optional.** Most users have no name. It is an accelerator on top of
  GraphQL discovery, never the only path.
- **Updating a record costs a transaction** and takes time to propagate. Rapid
  re-publishing would be expensive and would lag; artifacts should be produced
  on a cadence, not per change.
- **A name is a mutable pointer**, which is a different trust object from an
  immutable transaction. Resolution gives a tx id; the ownership and coverage
  checks in §2.4 still apply to whatever it points at. A compromised ArNS record
  must not be able to convince a client to import a hostile artifact — owner
  filtering is what prevents that, not the name.

---

## 7. Documentation

ArFS is specified in the sibling repository `ar-io-docs`. A new entity type is
not real until it is documented there, and the divergence found in §3 shows what
happens when the spec and the implementation drift apart.

**New, in `content/build/advanced/arfs/`:**

- `entity-types.mdx` — a `## Drive State` section beside `## Snapshot`, with
  `### Drive State Entity Tags` and `### Drive State Entity Data`, matching the
  shape those Snapshot sections already use.
- `data-model.mdx` — where the artifact sits relative to drives, snapshots and
  entities.
- `reading-data.mdx` — the read order: drive state, then snapshots, then
  GraphQL, and the rule that any failure falls back rather than fails.
- `privacy.mdx` — that the body is encrypted with the **drive** key as a single
  unit, unlike a snapshot's per-entity ciphertext, and that public drives are
  out of scope for v1 (§2.5).

**Correction, independent of this work:**

- `entity-types.mdx` — the Snapshot data field is `jsonMetadata`, not
  `dataJson`, in both the prose and the JSON example (§3). This is a live bug
  against every snapshot on chain and should be fixed on its own, not bundled
  into a new-feature change.

**Not documentation, but part of the same story:** ardrive-core-js and the CLI
need the row format and the read order before they can participate (§5).

---

## 8. Open questions

1. **Row format.** Its own compact serialisation, or something existing? It has
   to be readable by Dart and TypeScript, stable across `schemaVersion`, and
   cheap to insert in bulk.
2. **Production trigger.** On demand, after a full clean sync, or on a cadence?
   Coupled to §4's rule that a sync reporting skipped entities must not produce
   one.
3. **Who pays.** It is an upload — Turbo credits or AR, on a drive the user may
   not be actively changing.
4. **Revision depth.** Full history, or current state plus a pointer to
   snapshots for older revisions? Current-state-only is much smaller and covers
   what the explorer shows; history matters for the activity view.
5. **Multi-part authentication** above the GCM boundary (§2.2): manifest of
   authenticated parts, or one blob with a separate MAC.
6. **Public drives** — the §2.5 decision.

---

## 9. Relationship to the other snapshot work

- `SNAPSHOT_CREATION_FROM_SNAPSHOTS.md` makes *producing snapshots* affordable
  by sourcing the covered range from ancestors rather than the chain.
- **Incremental snapshots** — every snapshot on the measured drive has
  `Block-Start: 0` and re-encodes the whole history, because
  `create_snapshot_cubit.dart:225` defaults to `Range(start: 0, …)` even though
  line 221 already honours an arbitrary start. Starting where the last one ended
  would make production cheap without any new artifact at all, and is the
  smallest of the three changes.
- **This document** makes *consuming* cheap, and is the only one of the three
  that removes the 42,000 per-entity decryptions.

They are complementary and independently shippable. If only one is built,
incremental snapshots is the cheapest; this one is the largest change and the
biggest win.
