# The drive state artifact

A published, encrypted, signed blob of a drive's parsed state, which a client
imports in bulk instead of replaying the drive's history entity by entity.

**Additive.** Snapshots remain an ArFS interchange format and the fallback. A
client that does not understand a state artifact, cannot decrypt one, or never
finds one syncs exactly as it does today.

**The governing principle: this is a cache, and every failure is a fallback.**
Unknown version, failed signature, failed decryption, failed integrity check, an
unexpected section — each means *ignore the artifact and sync normally*, never
*fail the drive*. The worst outcome of anything going wrong is today's
behaviour. Every design decision below follows from that.

---

## 1. The case

Three arguments, in increasing order of how much they matter.

### 1.1 Size — the weakest of the three

| | on disk | gzipped |
|---|---|---|
| State artifact | **34.63 MiB** | **6.65 MiB** |
| Snapshot `z78YIh…` | 43.92 MiB | 11.37 MiB |
| | 1.27× smaller | 1.71× smaller |

Modelled on the real drive: 41,767 transactions, 98.4% files / 1.1% folders /
0.5% drive, `bundledIn` populated (present on 188 of 189 sampled nodes), one
revision per entity. Built with Drift, `VACUUM`ed, weighed.

The model is anchored at one end: the same sample gives 1058 bytes per snapshot
entry, and 1058 × 41,767 = 44.2 MiB against the snapshot's real 43.92 MiB — a
0.6% error, so the sample is representative.

**Known omissions, all of which would move the number up**: no
`customJsonMetadata`/`customGQLTags` (the real nodes carry 11 tags, exactly the
standard ArFS set, so these appear genuinely absent), no license or ArNS rows,
and one revision per file. More revisions inflate both sides — a snapshot holds
one entry per transaction, the database one row per revision — so the ratio
should hold.

A 1.27× win on disk is modest. This is not the reason to build it.

### 1.2 Work — the actual reason

Reading a snapshot costs, **per entity**: one AES decryption
(`file_entity.dart:117`, inside `FileEntity.fromTransaction`), one JSON parse,
one insert. Private file metadata is encrypted with a per-file key, so the
decryption is unavoidable and individual.

On this drive that is ~41,000 of each — the ~80 seconds of `Processing chunk of
1000 transactions` visible in a real sync log.

An artifact costs **one** decryption and a bulk insert.

Producing one is cheap in the way snapshots are not. A snapshot stores chain
data, so producing it re-reads the chain: ~420 paginated GraphQL queries plus
~42,000 metadata fetches for this drive, which does not complete on a throttled
connection (`SNAPSHOT_CREATION_FROM_SNAPSHOTS.md`). An artifact is already in
the local database — export, sign, compress, encrypt, upload.

### 1.3 Privacy — an improvement, not a cost

**A snapshot of a private drive is not encrypted.** Its `Content-Type` is
`application/json` and it carries no `Cipher` tag; only the per-entity metadata
values inside are ciphertext. Taken from a real private drive's snapshot:

```
Entity-Type        file
Drive-Id           0a36156c-6274-41a2-87b0-372f4da7f568
File-Id            af4c1dc3-7aab-4250-8209-4bcfa52b0089
Parent-Folder-Id   f904fef9-73cd-48b4-9087-00afb445bb4b
Unix-Time          1639422086
jsonMetadata       DzvFP9VWdSbznuhbtRNT2g0QKnwx…   ← the only encrypted part
```

Anyone can therefore read a private drive's entire *shape* from its snapshot:
how many entities exist, every file and folder id, the parent of each, and when
each was written. Only names, sizes and content types are hidden.

A fully encrypted artifact leaks none of that — `Drive-Id`, a block range, and a
size. **Strictly less exposure than the status quo.**

On keys: snapshots use per-file keys; the artifact uses the drive key. Coarser,
but not weaker — anyone holding the drive key can already derive every file key.
A holder of a single shared file key simply cannot use an artifact, and was
never its audience.

---

## 2. Security

### 2.1 Export, never dump

The local database holds key material:

```
profiles.encryptedWallet        the Arweave wallet, encrypted with a
                                password-derived key
profiles.keySalt                the salt that key is derived with
profiles.encryptedPublicKey
drives.encryptedKey             the drive key, wrapped in the profile key
drives.keyEncryptionIv
```

`encryptedWallet` and `keySalt` together are a complete offline attack package:
ciphertext, plus the salt needed to derive candidate keys from guessed
passwords, with unlimited time to try. Publishing them is permanent; Arweave has
no delete. This is the one failure that would make the feature harmful rather
than merely disappointing.

The exporter must therefore be **structurally unable** to read them:

- Define **export views** in the schema naming only exportable columns, and let
  the exporter query views only, never tables. The schema has no views today, so
  this is additive.
- A view lists its columns, so a later migration adding a sensitive column to
  `drives` does not reach the export. That is the realistic failure this guards
  against — not this design being wrong today, but a future migration quietly
  widening what an exporter sees. `schemaVersion` is 29 and moves regularly.
- `profiles` gets no export view at all. The `drives` view omits
  `encryptedKey`, `driveKeyGenerated` and `keyEncryptionIv`.
- A test asserts the views against the live schema as a second line of defence,
  not the only one.

Separating key material into its own store was considered and **rejected as a
dependency**: it would migrate wallet material out of a live database whose
migration fixtures are stale at v19, with "user loses wallet access" as the
failure mode, and would still leave one drive being exported from a database
holding all of them. Worth doing on its own security merits — browser storage is
readable by any XSS in the origin — but as separate hardening work.

### 2.2 The payload is signed

The artifact carries a signature over its plaintext payload, made with the drive
owner's wallet.

This is what lets discovery be cheap without being credulous (§4). A client
verifies the signature against the drive's known owner address **regardless of
how the artifact arrived** — resolved from a name, found by GraphQL, handed over
directly. Authorship stops depending on the lookup path.

It also removes a practical problem: a bundled data item has no L1 transaction
header, so `GET /tx/<id>` returns **404** for it, and the transaction's owner is
knowable only through the GraphQL indexer. A signed payload makes bundled and
top-level artifacts verify identically.

Order of operations, and it matters: **serialise → sign → compress → encrypt**.
Signing the plaintext binds the author to the content rather than to a
particular encoding; compressing before encrypting is the only order that
compresses at all.

### 2.3 AES-GCM, and never CTR

Encrypt with the drive key using AES256-GCM, per `arfs/privacy.mdx`.

CTR was considered. Its advantages are streaming and random access, which is why
this codebase uses it above `maxSizeSupportedByGCMEncryption` (100 MiB) for file
*data*. Neither applies to an artifact that is buffered and imported whole.

CTR is unauthenticated, and the threat is not theoretical: gateways have been
observed serving wrong data — a truncated GraphQL response under an open
`UPSTREAM_CIRCUIT_OPEN` breaker silently dropped a drive from a user's list.
GCM detects a body that arrived wrong; CTR would import it as state.

Above the 100 MiB boundary the artifact must **split into authenticated parts
with a manifest**, never fall through to CTR. At 34.63 MiB for ~41k entities,
that boundary is somewhere near 120k entities and will be reached.

### 2.4 Never hand an untrusted file to SQLite

The payload is a **serialisation of rows**, not a database file. Opening an
attacker-controlled SQLite file exercises a parser with a history of
malformed-database CVEs.

This also stops the wire format being welded to `schemaVersion`: a row format
the client maps onto whatever schema it runs, rather than a file only one
version can open. Two independent reasons for the same decision.

### 2.5 Trust, replay and failure

- **Signature first.** An artifact whose signature does not verify against the
  drive owner is discarded before anything else is examined.
- **Newest wins** by coverage tags, not arrival order.
- **No rollback.** An artifact covering less than what is already synced is a
  no-op, never a regression.
- **Failure is silence, not error.** A drive key that cannot open an artifact
  means skip it and sync normally; it must never surface as a corrupt drive.
- **Residual risk.** The owner's client publishes whatever local state it has. A
  snapshot's entries can in principle be checked against chain, since each
  carries its original `gqlNode`; exported rows cannot. This is why the artifact
  is a cache and never the only copy — and why §5 forbids producing one from a
  sync that reported skipped entities.

### 2.6 Public drives

A public drive has no drive key, so its artifact would be unencrypted. The
contents are already public, but a single blob enumerating every name, size and
relationship is more useful to an adversary than the same facts scattered across
transactions — though §1.3 shows snapshots already concede most of this.

**Recommend private-only for v1.** Public drives skip the per-entity
decryptions entirely, so they have least to gain.

---

## 3. The entity

Specified in ArFS's own conventions, so it reads as one more entity type beside
Snapshot rather than a bolt-on.

### 3.1 Why a new `Entity-Type`, and not a snapshot variant

Reusing `Entity-Type: "snapshot"` would cause **silent data loss in existing
clients**:

1. An old client's snapshot query returns the artifact.
2. It reads `Block-Start`/`Block-End` and **claims that range** —
   `SnapshotDriveHistory.subRanges` is built from the tags, not from any
   content.
3. `HeightRange.difference` then hands GraphQL only what is left over, so the
   claimed range is not queried.
4. Parsing the encrypted body finds no `txSnapshots` array, logs a warning and
   yields nothing (`snapshot_item.dart`).

The range is claimed by something that produces no transactions, and queried by
nothing else. Those entities are never synced, while the drive's watermark
advances past them.

A distinct `Entity-Type` avoids this by construction: clients that predate it
never query for it, never fetch it, never claim its range. **That is the whole
basis of the additive property.**

### 3.2 Tags

```
ArFS:             "0.15"
Entity-Type:      "drive-state"
Drive-Id:         "<drive uuid this state belongs to>"
Drive-State-Id:   "<uuid of this drive-state entity>"
State-Version:    "1"
Content-Type:     "application/octet-stream"
Content-Encoding: "gzip"
Block-Start:      "<minimum block height accounted for, eg 0>"
Block-End:        "<maximum block height accounted for, eg 1814228>"
Data-Start:       "<first block in which data was found>"
Data-End:         "<last block in which data was found>"
Entity-Count:     "<number of entities in the payload>"
Unix-Time:        "<seconds since unix epoch>"
Cipher:           "AES256-GCM"
Cipher-IV:        "<12 byte IV as Base64>"
```

`Drive-State-Id` mirrors `Snapshot-Id`. `Block-*` and `Data-*` carry the same
meanings the Snapshot entity gives them — the range *searched* against the range
where data was actually *found*, which lets a client size the work, and know an
artifact is empty, without fetching it.

Two tags are specific to this entity:

- **`Content-Encoding`** — the payload is compressed before encryption
  (34.63 → 6.65 MiB, a 5.2× reduction, far larger than the snapshot comparison).
  A client cannot discover this from an encrypted body, so it must be declared.
- **`Entity-Count`** — an integrity check, not a statistic. GCM proves the
  ciphertext arrived intact; the count proves the body meant what the tags
  promised. A mismatch after import is decisive and cheap.

**Deliberately absent.** No size tag — `data.size` is already queryable. No
`Supersedes` pointer — derivable from `Block-End` ordering, and a tag that
duplicates derivable state is a tag that can eventually disagree with it. No
total byte count — derivable after import, and definitionally slippery (hidden
files? superseded revisions?); a candidate for §6 instead.

### 3.3 Payload

```
serialise rows  →  sign (drive owner's wallet)  →  gzip  →  AES256-GCM
```

The payload is a container of **named sections**. Section one is the drive's
exported rows; the signature covers the whole plaintext container.

### 3.4 A warning from the existing spec

Checking the spec against reality surfaced a divergence in the *existing*
Snapshot format:

| | field |
|---|---|
| `entity-types.mdx`, prose and JSON example | `dataJson` |
| `snapshot_types.dart`, `snapshot_item.dart` | `jsonMetadata` |
| A real snapshot (200 KB sample) | `jsonMetadata` ×189, `dataJson` ×0 |

An implementer following the published spec would read no metadata from any
snapshot and silently fall back to fetching every transaction individually —
precisely the pathology this document removes. It should be corrected
independently (§9).

The lesson for this entity: **the spec, the implementation and a real artifact
must be checked against each other**, never assumed to agree.

---

## 4. Discovery

### 4.1 A name, not a query

The GraphQL indexer is the least reliable component in the stack. It is what
rate limits, what truncates under an open circuit breaker, and what a client
must otherwise consult once per drive per sync merely to *find* an artifact.

ArNS removes it from the common path, and the plumbing already exists —
`ArnsRepository` points a name at an arbitrary transaction id today.

```
state_<driveId>.myname   →   latest drive-state transaction
```

```
resolve name  →  GET the bytes  →  verify signature  →  decrypt  →  import
                                         GraphQL only for the recent tail
```

For the ~99% of history an artifact covers, no indexer is involved at all. On a
connection being throttled or served by a struggling gateway, that is a
reliability gain before it is a performance one.

It also gives a sharing story: a recipient handed a name and a drive key can
open a large shared drive without walking its history — the case where today's
experience is worst.

### 4.2 What a name does not do

A name is a **mutable pointer** held by whoever controls it, and it can be
transferred or compromised. GraphQL discovery filtered on
`owners: [ownerAddress]` at least proved authorship as a side effect of the
query; a name proves nothing.

This is why §2.2 signs the payload. **Verification must not live in the
discovery path.** A resolved name yields bytes; the signature, the `Drive-Id`
tag and the coverage tags decide whether to trust them. A compromised name can
waste a download. It cannot introduce hostile state.

### 4.3 Discovery order

1. **ArNS name**, when the drive has one configured.
2. **GraphQL** by `Entity-Type` + `Drive-Id` + owner — the fallback, and the
   only path for drives without a name, which is most of them today.
3. **Nothing found** — sync from snapshots, exactly as now.

### 4.4 Layer 1 and bundled data items — both, always

Both occur in practice today: of two snapshots examined on one drive, the
December one is a bundled data item and the other a top-level transaction, the
difference being whether Turbo carried the upload.

**Both transports must be supported, and neither may become a requirement.**
Turbo is a hosted service; an artifact format that can only be produced through
it would make a permanent, protocol-level feature depend on one operator
remaining available and willing. A user with only an Arweave wallet must be able
to publish and read artifacts with no Turbo involvement at all — the same
guarantee the rest of ArFS gives.

This is affordable precisely because §2.2 signs the payload. Authorship is
carried by the signature rather than by the transaction header, so:

- a **top-level (L1) transaction** verifies from its own signature;
- a **bundled data item** verifies identically, even though `GET /tx/<id>`
  returns 404 for one and its owner is otherwise knowable only through the
  GraphQL indexer.

The transport therefore becomes a purely operational choice — cost, size,
whichever upload path the user already has — with no bearing on trust,
discovery or verification. Clients must read either without preference.

Reading has the same rule: an artifact is fetched by transaction id over
ordinary HTTP, which works for both, and never requires the bundler that
produced it to still exist.

---

## 5. How a client reads a drive

The artifact becomes the first of three sources. The range arithmetic that
composes them already exists.

```
1. state artifact   [0 → Block-End]        one decryption, bulk insert
2. snapshots        (Block-End → newest]   existing path
3. GraphQL          (newest → current]     existing path
```

- **`SyncRepository`** gains an artifact lookup before the snapshot prefetch.
- **`HeightRange`/`obscuredBy` need no change.** The accumulator in
  `SnapshotItem.instantiateAll` already composes ranges from multiple sources;
  the artifact is one more obscuring range.
- **Import is a merge, not a replace.** The database holds every drive and
  profile. Rows land in a sandbox, are validated, then merge for one drive,
  reconciling against anything newer already held locally.
- **A sync that reported skipped entities must not produce an artifact.** Sync
  advances `lastBlockHeight` regardless of skips
  (`SYNC_SKIPPED_ENTITY_PERSISTENCE.md`), so publishing from that state would
  make a gap permanent and immutable.

---

## 6. Extensibility

The payload is a container of named sections, and the rule that makes extension
safe is the separation of **additive** from **breaking**:

- **Unknown sections are skipped**, not rejected. A reader takes what it knows.
- **Unknown tags are ignored** — already how ArFS works.
- **`State-Version` bumps only when an older reader would *misinterpret* the
  payload**, never for an addition. Bumping on additions locks out clients that
  could have used most of it, which defeats the point.

Anything later — aggregate totals, additional indexes, whatever is wanted in six
months — arrives as a new section that existing clients ignore.

---

## 7. Observability

The failure this whole line of work came from was **silent**: sync fell back to
a slower path and nothing said why, which cost days of diagnosis. Shipping an
artifact with that property would repeat it.

The rule: **"no artifact was used" and "an artifact was rejected because X" must
never look the same.**

Per drive, per sync:

- whether an artifact was used;
- if not, an **enumerated reason** — `none found`, `unknown State-Version`,
  `signature failed`, `decrypt failed`, `integrity failed`, `entity count
  mismatch`, `range already covered`;
- entities imported from artifact / snapshot / GraphQL;
- time in bulk import against time in parse.

The `[snapshot]` instrumentation already merged is the right shape; this extends
it rather than inventing a second vocabulary.

---

## 8. Other clients

*Reasoned from the protocol boundary; those repositories were not read.*

- **Existing readers are unaffected** — a transaction whose `Entity-Type` they
  never query for, and snapshots keep being produced.
- **ardrive-core-js** needs the section format, the drive-key decryption path it
  already has, signature verification, and the merge rules. Reading is far
  simpler than writing.
- **The CLI is the more interesting producer** — real bandwidth, no browser
  connection limits. A better place to generate an artifact for a very large
  drive than a browser tab.
- **The wire format must not mirror Drift's schema**, or every other
  implementation inherits this app's migration history.

---

## 9. Documentation

ArFS is specified in the sibling repository `ar-io-docs`, and a new entity type
is not real until it is documented there.

**New, in `content/build/advanced/arfs/`:**

- `entity-types.mdx` — a `## Drive State` section beside `## Snapshot`, with
  `### Drive State Entity Tags` and `### Drive State Entity Data`.
- `data-model.mdx` — where the artifact sits relative to drives, snapshots and
  entities.
- `reading-data.mdx` — the read order in §5, discovery in §4, and the rule that
  any failure falls back rather than fails.
- `privacy.mdx` — that the payload is signed and encrypted with the **drive**
  key as a single unit, unlike a snapshot's per-entity ciphertext, and that
  public drives are out of scope for v1.

**Correction, independent of this work:**

- `entity-types.mdx` — the Snapshot data field is `jsonMetadata`, not
  `dataJson`, in both prose and example (§3.4). A live bug against every
  snapshot on chain; it should be fixed on its own, not bundled into a
  new-feature change.

---

## 10. Open questions

1. **Section format.** Readable from Dart and TypeScript, stable across
   `schemaVersion`, cheap to insert in bulk.
2. **Production trigger.** On demand, after a clean sync, or on a cadence —
   coupled to §5's rule that a sync reporting skips must not publish.
3. **Who pays.** It is an upload, on a drive the user may not be changing —
   and payable in either AR or Turbo credits, since §4.4 requires both
   transports. Cadence and cost interact: cheap increments favour publishing
   often, an L1 wallet-only user favours publishing rarely.
4. **Revision depth.** Full history, or current state plus a pointer to
   snapshots for older revisions? Current-state-only is much smaller and covers
   what the explorer shows; history matters for the activity view.
5. **Multi-part authentication** above the GCM boundary (§2.3): a manifest of
   authenticated parts is preferred, but the manifest's own integrity needs
   specifying.
6. **ArNS naming convention.** `state_<driveId>` is placeholder; undername
   length and readability constraints need checking against the ARIO spec.

---

## 11. Relationship to the other snapshot work

| Change | Fixes | Size |
|---|---|---|
| **Incremental snapshots** | Every snapshot re-encodes all history from block 0, because `create_snapshot_cubit.dart:225` defaults to `Range(start: 0, …)` even though line 222 already honours an arbitrary start. Starting where the last ended makes production cheap. | Smallest — a changed default |
| **Snapshots from ancestors** (`SNAPSHOT_CREATION_FROM_SNAPSHOTS.md`) | Producing one re-reads the chain instead of copying what earlier snapshots already hold. | Medium |
| **This document** | The per-entity decryptions, the plaintext structure leak, and the dependency on the GraphQL indexer. | Largest |

They are complementary and independently shippable. Incremental snapshots is the
cheapest; this is the largest change and the only one that addresses all three.
