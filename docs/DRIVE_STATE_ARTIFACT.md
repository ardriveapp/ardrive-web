# The drive state artifact

A published blob of a drive's parsed state, uploaded by the drive's owner and
encrypted under the drive key when the drive is private, which a client imports in bulk instead of
replaying the drive's history entity by entity.

**Additive.** Snapshots remain an ArFS interchange format and the fallback. A
client that does not understand a state artifact, cannot decrypt one, or never
finds one syncs exactly as it does today.

**Two decisions taken after the first revision of this document, folded in
below.** The payload is a SQLite file with a frozen schema rather than a
serialisation of rows (D12, superseding D1): see §2.4. And snapshots are no
longer the permanent companion this document opened by promising: production of
them ends once other clients read artifacts, while reading them continues for
ever, since every snapshot on chain is permanent. See §11.

**A second consumer exists.** A library page is a static page published to
Arweave that reads an artifact in the browser and renders a drive, with no
GraphQL and no app. It is specified in `LIBRARY_PAGES.md`, and it is the reason
§2.7 and §4.5 exist.

**The governing principle: this is a cache, and every failure is a fallback.**
Unknown version, wrong owner, failed decryption, failed integrity check, an
unexpected section — each means *ignore the artifact and sync normally*, never
*fail the drive*. The worst outcome of anything going wrong is today's
behaviour. Every design decision below follows from that.

---

## 1. The case

Three arguments, in increasing order of how much they matter.

### 1.1 Size — the weakest of the three

| | serialised | gzipped |
|---|---|---|
| State artifact | **52.16 MiB** | **9.55 MiB** |
| Snapshot `z78YIh…` | 43.92 MiB | 11.37 MiB |
| | 1.19× **larger** | 1.19× smaller |

**Measured, not modelled.** `test/drive_state/drive_state_scale_measurement_test.dart`
builds a drive of 41,767 files across 120 folders at 1.05 revisions per entity —
the shape of the real drive — runs the actual `exportDriveState`, serialises the
real wire format and weighs it. Run it with
`--run-skipped --tags=measurement`; it is skipped by default because it costs
about a minute.

Two details of that fixture matter more than anything else in it. Transaction
ids and uuids are drawn at their true entropy (32 bytes and 16 bytes), and file
names are assembled from a small vocabulary the way human file names repeat.
An earlier version of this measurement interpolated a counter into its ids —
`data-tx-id-1234-…` — and reported **2.09 MiB gzipped at a 26× ratio**. The ids
are roughly a third of the payload and real ones do not compress at all, so
that figure was wrong by more than four times. Anyone re-deriving these numbers
should check their fixture's entropy before believing a good result.

**An earlier revision of this document reported 34.63 MiB / 6.65 MiB.** Those
came from a different artefact: a Drift database file, `VACUUM`ed and weighed,
from when this proposal was still "publish the SQLite file". §2.4 rejected that
in favour of a serialisation of rows, and JSON is bulkier than SQLite's binary
pages — so the honest number went **up**, and the size column went from a
modest win to a small loss before compression.

A payload that is larger uncompressed and 1.19× smaller gzipped is not an
argument for anything. Size was always the weakest of the three, and measuring
it properly made it weaker. **This is not the reason to build it** — §1.2 is.

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
the local database — export, compress, encrypt, upload.

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

All of the above is about **private** drives, which are the only ones with
anything to hide. A public drive's artifact is unencrypted and leaks exactly
what a public drive's snapshot already leaks, which is everything; §2.6 works
through why that is not a reason to withhold the format from it.

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

### 2.2 Authorship is the upload's owner (D16)

An artifact is the drive owner's because the drive owner uploaded it. That is
the attribution every ArFS entity gets: a reader trusts the owner the indexer
reports for the transaction, and ignores any entity whose owner is not the
drive's. Discovery queries by that owner and filters on it again, and the
importer checks it once more before it opens anything (outcome
`owner-mismatch`).

The order of operations:

```
private:  serialise → compress → encrypt
public:   serialise → compress
```

and its inverse:

```
private:  check owner  →  decrypt (GCM, authenticated)  →  detect encoding  →  inflate (bounded)
public:   check owner  →                                   detect encoding  →  inflate (bounded)
```

**A private drive's payload is authenticated by AES-GCM under the drive key.**
Bytes nobody holding that key wrote never reach the decompressor, whatever the
indexer says about them. **A public drive's payload is not authenticated by
anything in the format.** It is as trustworthy as the gateway that served it
and the owner it reported, which is exactly how trustworthy that drive's own
files and folders are. The bounded decompression (§2.4) is what stops a bad
public payload doing harm, and it applies to both paths in full.

**Why there is no second signature inside the payload.** An earlier revision
signed the payload as an ANS-104 data item inside the upload, so the bytes
would prove their author however they were found. It was removed before
anything was published, because no reader could use what it bought:

- The upload is already a signed data item, and its signature is on chain
  inside its bundle. What a reader cannot do cheaply is fetch it: measured in
  October 2026 against ardrive.net and turbo-gateway.com for a Turbo-bundled
  item, no `X-Arweave-Signature` or `X-Arweave-Owner` headers are served, and
  GraphQL returns `"signature": "<not-found>"` and
  `"owner": { "key": "<not-found>" }`. AR.IO release 75 can send those headers,
  but for a bundled item only with `WRITE_ANS104_DATA_ITEM_DB_SIGNATURES=true`,
  which defaults to `false`.
- The inner signature cost a wallet prompt at publish, routed Wander and
  ArConnect through the deprecated `arweaveWallet.signature()` with
  `saltLength: 0`, made every reader implement data item verification, and
  made range reads of a public artifact unverifiable, since a signature covers
  the whole payload (`LIBRARY_PAGES.md`).

A reader that wants independent proof of authorship later can fetch the
upload's own signed data item from its bundle. Nothing in this format prevents
that, and nothing in it depends on it.

### 2.3 AES-GCM, and never CTR — and the size bound is not the cipher's

Encrypt with the drive key using AES256-GCM, per `arfs/privacy.mdx`. **A public
drive's artifact is not encrypted at all** (§2.6); everything in this subsection
about *which* cipher applies to the private path only, and everything about the
size bound applies to both.

CTR was considered. Its advantages are streaming and random access, which is why
this codebase uses it above `maxSizeSupportedByGCMEncryption` (100 MiB) for file
*data*. Neither applies to an artifact that is buffered and imported whole.

CTR is unauthenticated, and the threat is not theoretical: gateways have been
observed serving wrong data — a truncated GraphQL response under an open
`UPSTREAM_CIRCUIT_OPEN` breaker silently dropped a drive from a user's list.
GCM detects a body that arrived wrong; CTR would import it as state.

A public drive gets neither cipher and so gets neither property: a body that
arrived wrong is caught only if it fails to decompress or fails the payload
checks (§2.4), the same exposure that drive's own entities have (§2.2).

**The 100 MiB refusal is a bound on memory, not on the cipher.** D5 was
originally justified as an AES-GCM constraint — GCM should not authenticate
more than about this much in one piece — and that justification does not
survive either of the two things below. It is kept, at the same number, on its
own reasoning.

**Where that boundary actually is.** What `seal` weighs is the payload, and
since D12 the payload is the SQLite file, uncompressed. Measured with rows a
real drive carries (36-character ids, real-length names and paths, transaction
ids at their true entropy, 1.05 revisions per file, a folder per hundred
files), it grows in a straight line:

| files | artifact |
|---|---|
| 1,000 | 741,376 B |
| 3,000 | 2,154,496 B |
| 6,000 | 4,268,032 B |

That is about 640 bytes a file, revisions included, on roughly 36 KiB of fixed
schema and metadata. So:

> **The 100 MiB payload boundary is crossed at about 164,000 files.** A
> 41,767-file drive weighs about 26 MiB, roughly 3.9x under it.
> The same figures apply to a public drive: what is weighed is the payload,
> and the cipher, which a public drive does not have, is downstream of it.

`qa_findings_test.dart` takes this measurement on every run and fails if the
crossover or the headroom leaves the band quoted here.

Three things still spend the headroom: **longer names** (every file pays its
name once in its entry and again in each revision), **`customGQLTags` and
`customJsonMetadata`** (absent from the measurement, unbounded in general), and
**more revisions per entity** (1.05 is one real drive's figure, not a law). They
spend it more slowly than they did against JSON, but a very large, heavily
revised drive with long paths can still reach the bound. D5's refusal remains
a path a user can meet.

**Three earlier figures, and why each was wrong.** The first draft put the
bound near 120k entities by extrapolating from a VACUUMed SQLite file while the
container was JSON. Measured against JSON (D1), the honest crossover was
between 70,000 and 80,000 files, because a JSON row is about twice the width of
a SQLite one. And the 17.70 MiB for 41,767 files in `SQLITE_ARTIFACT.md` comes
from a fixture with short ids; realistic ids make the same drive about 1.6x
larger. That head-to-head is still fair, because both containers were measured
on the same fixture, but its absolute sizes understate a real drive.

**And there is a path with no cipher in it at all.** A public drive's artifact
is not encrypted, so a bound inherited from AES-GCM would have
nothing to inherit from and would have to be dropped for public drives, which
is plainly the wrong answer, because the cost the bound guards is the same on
both paths and is spent before any cipher is reached. A justification that
produces the wrong answer on a case it did not anticipate was never the real
reason.

What the bound guards is **memory**. It was first re-founded on the
**producer's memory**, measured on the JSON path at a peak near 950 MiB from a
263 MiB baseline, almost all of it the exported object graph and `jsonEncode`.
D12 removes that multiplication: the SQLite producer copies rows inside SQLite,
and its peak measured +167 MiB from a 182 MiB baseline on the short-id fixture.
What remains is roughly the artifact itself, held whole in the tab that builds
it and again in the tab that reads it, because a reader decrypts and attaches
the entire file. 100 MiB caps that, on both sides.

That cost is **identical for a public drive**, so the bound is the same number
for both privacies, deliberately. Two numbers would mean the reader's
inflation limit differed by drive, which is a window in which a payload is
writable by one path and unreadable by another. One number is checkable; two
drift.

The private path stays inside AES-GCM's own comfortable range as a
*consequence* of this bound rather than by construction, and
`drive_state_envelope_test.dart` asserts the constant never grows past
`maxSizeSupportedByGCMEncryption` so that consequence keeps holding.

The memory figures are VM resident-set size, not a browser heap, and a tab has
a hard ceiling where this process had the operating system. Reproduce them
with `test/drive_state_sqlite/artifact_scale_test.dart --run-skipped`.

### 2.4 The payload is a SQLite file, and it is never trusted

**The payload is a SQLite database file with a frozen artifact schema** (D12,
superseding D1). An earlier revision of this section made it a serialisation of
rows, on two arguments. The second one survives and shapes the decision; the
first one is narrower than it read.

**The surviving argument: never weld the wire format to `schemaVersion`.** The
artifact's schema is frozen and is *not* Drift's. A reader maps it onto whatever
schema it runs, so this app's migration history is not inherited by every other
implementation. Shipping Drift's tables also measured worst of every option
tried, 10.14 M gzipped against 6.09 M, because the indexes are dead weight a
reader throws away.

**The narrower argument: the malformed-database CVE history.** It is real, and
it is why the read gate below is not optional. On a private drive it is narrower than it
reads, because the payload is authenticated under the drive key: feeding a
hostile file requires the key, and with it the attacker already owns the drive.
On a **public** drive the payload is not authenticated (§2.2), so a gateway that
lies about an artifact's owner, or the owner's own wallet, can hand a reader a
hostile file. That is the same exposure the app already has to every file a
gateway serves it for preview, and the read gate below is what stands in front
of it. On web the parser runs inside the wasm sandbox; on mobile and desktop it
is the native library, which makes the gate the whole defence there.

**The read gate, in order. Every refusal is a fallback.**

1. Check the upload's owner is the drive's, decrypt (private), detect the
   encoding, inflate under the bound.
2. Open **read-only** with `SQLITE_DBCONFIG_DEFENSIVE` and
   `SQLITE_DBCONFIG_TRUSTED_SCHEMA=0`.
3. `PRAGMA integrity_check`.
4. Refuse unless `sqlite_master` matches the frozen schema exactly: no views, no
   triggers, no virtual tables, no indexes, every DDL string identical.
5. Check `meta` against the tags: version, drive id, owner, privacy, entity
   count, and a range that advances the watermark.
6. `ATTACH`, then `INSERT INTO main.x SELECT … FROM artifact.x` per table, in one
   transaction.

**Building up, never tearing down.** An artifact is constructed by selecting
named columns into an *empty* database, so a column nobody named cannot reach
one. The inverse, copying the local database and dropping what must not ship,
does not work: `DROP TABLE` leaves the dropped bytes on the freelist unless
`secure_delete` is on, and it is **off in the wasm build the browser runs**
(measured: `0` on wasm, `2` on macOS). This is also what supersedes D7, since
the `INSERT … SELECT` column list is the typed projection, expressed once, in
the statement that physically builds the file.

The same suspicion applies one layer down, to the gzip. **Bound the
decompression, and bound it during inflation rather than after.** A gzip stream
of a few kilobytes expands to gigabytes at will; a reader that inflates into
memory and checks the size afterwards has already lost. The gzip trailer's
`ISIZE` field is not the bound either — it is chosen by whoever wrote the
stream, which is to say by the attacker.

The bound belongs on the output sink, refusing at the first byte past the
limit. Reuse the payload boundary from §2.3, unchanged for either privacy: a
payload that inflates past what a producer is allowed to seal is, by
construction, not a payload this format produced.

On a private drive GCM has authenticated the bytes before anything is
inflated, so the bound is a backstop against a *compromised or buggy owner
client*. On a public drive nothing authenticated them, so the bound is the
front line, and it is the same bound.

### 2.5 Trust, replay and failure

- **Owner first.** An artifact not uploaded by the drive owner is discarded
  before anything else is examined.
- **Newest wins** by the payload's coverage claim — cross-checked against the
  tags before it is believed (§3.3) — and never by arrival order.
- **No rollback.** An artifact covering less than what is already synced is a
  no-op, never a regression.
- **Failure is silence, not error.** A drive key that cannot open an artifact
  means skip it and sync normally; it must never surface as a corrupt drive.
- **Residual risk.** The owner's client publishes whatever local state it has. A
  snapshot's entries can in principle be checked against chain, since each
  carries its original `gqlNode`; exported rows cannot. This is why the artifact
  is a cache and never the only copy — and why §5 forbids producing one from a
  sync that reported skipped entities.

### 2.6 Public drives — supported, and the earlier recommendation was wrong

A public drive has no drive key, so its artifact is **not encrypted**. The
chain is the private one minus a layer, and inverted on read:

```
private:  serialise → gzip → AES256-GCM
public:   serialise → gzip
```

`Cipher` and `Cipher-IV` are absent for a public artifact, and **their absence
is the discriminator**. Everything else about the entity — the ArFS tags, the
coverage claim, `Entity-Count`, the owner check, the size bound, the section
rules — is unchanged.

#### The earlier recommendation, and why it does not hold

An earlier revision of this section recommended private-only for v1, on two
arguments. Both are wrong, and it is worth saying how, because the shape of the
design follows from it.

**"Public drives have least to gain."** This was the load-bearing claim and it
is simply false. What an artifact buys is §1.2: not paying ~420 paginated
GraphQL queries and ~42,000 metadata fetches to replay a drive's history. A
public drive pays every one of those, identically. What it does *not* pay is
the per-entity AES decryption — one of the three costs per entity, alongside a
JSON parse and an insert, and by far the cheapest of the three to skip in bulk.
So a public drive gains nearly all of what a private drive gains. The
recommendation inverted the size of the win it was weighing.

**"A single blob enumerating every name, size and relationship is more useful
to an adversary."** True as a statement about aggregation, and already conceded
in full. **A snapshot of a public drive is exactly that blob**, unencrypted,
enumerating the same names, sizes and relationships, and snapshots are produced
and published today. §1.3 makes the same point about private drives from the
other direction — a private drive's snapshot already leaks its whole shape in
plaintext — and this section half-admitted it ("snapshots already concede most
of this") and recommended against anyway. A public artifact concedes **nothing
a public drive's snapshot does not already concede**. There is no new exposure
to weigh, so there is nothing on the other side of the scale.

Note what this argument is *not*. It is not "public data is public, so nothing
matters" — aggregation is a real distinction and a format that introduced it
would deserve the scrutiny. It is that this format does not introduce it: the
aggregated form is already published by the mechanism this one sits beside.

#### The guard that replaces it, and it runs in both directions

Dropping the privacy gate makes one thing critical, and it is the inverse of
what the old recommendation worried about:

**A private drive must never publish an unencrypted artifact.** That would
expose the drive's entire structure — every name, every size, every
relationship — permanently and irrevocably. It is the single worst thing this
feature could do, and unlike every other failure here it is not a fallback to
today's behaviour; it is worse than today's behaviour, for ever.

So it is not implemented as a check. `DriveStateProtection`
(`lib/drive_state/domain/drive_state_protection.dart`) is a sealed type with
two variants and private constructors, reachable only through a factory that
takes the drive's own `privacy` column and its key together. The unencrypted
variant is only produced by the `public` arm. A caller does not assert how an
artifact is protected — it hands over what the drive row says and is told. The
codec switches exhaustively over the type, so a third variant would be a
compile error rather than a silent fall-through to the clear. **Publishing a
private drive in the clear is not a check that could be skipped; it is a value
that cannot be constructed.**

**A reader refuses any artifact whose cipher-presence contradicts the privacy
of the drive it claims to be for**, in both directions:

| the drive | the artifact | outcome |
|---|---|---|
| private | no `Cipher` tag | `privacy-mismatch` |
| public | a `Cipher` tag | `privacy-mismatch` |
| either | `Cipher` without `Cipher-IV`, or the reverse | `integrity-failed` |

This follows the `Block-Start`/`Block-End` cross-check of §3.3 rather than
inventing a second convention: a claim from an untrusted source — the
transaction's tags, chosen by whoever posted it — checked against something
trustworthy, here the privacy of the drive in the reader's own database. It is
checked twice for the same reason the size bound is: once against the tags,
before the body is touched, and once in the codec, which is the layer that
decides whether to decrypt and must not decide it from anything else. The
payload's own `privacy` field is checked against the same trustworthy
value a step later — that one matters because the merge writes the payload's
`privacy` onto the local drive row.

The refusal has its own outcome code rather than being folded into
`integrity-failed`, for the reason `coverage-mismatch` has one: a private drive
being offered an artifact in the clear is a producer somewhere having published
the thing this design most exists to prevent, and it should not arrive as a
shade of "the payload did not match its tags".

#### What does not change

`State-Version` stays at **1.0**. Public support is folded into the initial
format rather than added as a minor bump, because nothing has been published to
chain — so there is never a fragmented world in which some 1.0 readers handle
public drives and others do not. Had anything been published this would have
been a clean minor bump under §6: a 1.0 reader meeting a cipher-less artifact
finds no `Cipher` tag and refuses it, which is a correct refusal rather than a
misread. That fallback exists and is not needed.

Every other gate on publishing still applies to a public drive, unchanged: the
D3 skip precondition, drive ownership, write permissions, a non-empty drive, a
sync watermark, and the payload size bound. The only condition removed is the
privacy one.

---

### 2.7 Compression, and the random access it forecloses

Gzip inside the envelope is not free, because it decides whether a reader can
open an artifact without downloading all of it.

A SQLite file answers a question by touching the pages that hold the answer, and
a gateway serves byte ranges, so a reader can open a large artifact by fetching
the pages it needs. Compression inside the envelope removes that: the bytes on
the wire are a gzip stream, and a slice of a gzip stream cannot be inflated on
its own. Encryption removes it as well, which is why this applies to public
artifacts only.

**The rule.** A reader accepts both encodings and tells them apart by the
first bytes of the payload: `1f 8b` is a gzip stream, `SQLite format 3`
followed by a NUL is an uncompressed file, and anything else is refused. The
producer chooses per artifact, and that artifact keeps its choice for ever. It
is not a `meta` flag, because `meta` is inside the compressed bytes it would
describe.

- **Compressed** below the random-access threshold. A small artifact is fetched
  whole, and gzip recovers most of its bytes. The median drive is two files, so
  this is nearly every artifact.
- **Identity** above it, for a public artifact a library page will serve. 17.70
  MiB against 5.98 at 41,767 files, paid once, to make page-level reads possible
  for ever.

**Never set a `Content-Encoding` tag.** Transport compression has the same
effect as envelope compression and is worse, because the gateway passes the tag
through unchanged and the browser then cannot read ranges at all. ArDrive sets
no such tag anywhere today.

Producers always compress until Library pages ship. The threshold is then set
by measuring the real page, starting from 16 MiB of SQLite (about 26,000
files), and it can change later because no reader depends on it. It is recorded
in `LIBRARY_PAGES.md`, because §4.5 shows the gain is smaller than it looks on
a cold object.

### 2.8 The web database moves with it, for every user, on first load

D12 has a prerequisite that is not behind any flag. An artifact is built by
attaching an empty database to the app's own, and the sql.js backend the web
app ran cannot hand back an attached database's bytes. So the app's web
database moves to SQLite compiled to WebAssembly, and every web user's local
database is copied across the first time this build opens. Unlike the artifact
itself, that is live for everyone from the release.

The handoff is written so that nothing it does can cost a user their data
(`lib/models/database/web.dart`):

- **A marker file is the commit point**, written after the copy is flushed.
  A failure that may pass next time runs that session on an in-memory copy,
  seeded with the user's data when it was read, and the next start tries
  again. A store that is not a sound SQLite file is settled once, not retried
  every start.
- **The legacy store is never deleted**, so a rolled-back build finds its
  database where it left it.
- **One tab owns the database**, through a Web Lock. This tier is drift's
  `unsafeIndexedDb`: each tab caches the file and writes 4 KiB blocks with no
  lock between tabs, so two writers would interleave diverged pages into one
  corrupt file. Any other tab works on a private copy that never reaches
  IndexedDB. Browsers without Web Locks keep the behaviour every tab had
  before.

`test/models/database/web_database_test.dart` runs each of these against a
real IndexedDB and a real sql.js store in headless Chrome, through
`tool/browser_tests.sh`, which CI runs.

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
State-Version:    "1.0"       (major.minor — see 6)
Content-Type:     "application/octet-stream"
Block-Start:      "0"          (always — see 3.4)
Block-End:        "<maximum block height accounted for, eg 1814228>"
Data-Start:       "<first block in which data was found>"
Data-End:         "<last block in which data was found>"
Entity-Count:     "<number of entities in the payload>"
Unix-Time:        "<seconds since unix epoch>"
Cipher:           "AES256-GCM"                      (private drives only)
Cipher-IV:        "<12 byte IV as Base64>"          (private drives only)
```

**`Cipher` and `Cipher-IV` are present together or absent together**, and a
public drive's artifact carries neither, because nothing about it is encrypted
(§2.6). Their absence is how a reader tells the two chains apart, so it is a
state the format names rather than an omission: there is no `Cipher: "none"`
and no empty value. One without the other is refused as `integrity-failed` —
a `Cipher` with no `Cipher-IV` is ciphertext nothing can address, and a
`Cipher-IV` with no `Cipher` reads to every consumer as an unencrypted
artifact, which for a private drive is the far end of the cross-check.

A reader that finds these tags disagreeing with the privacy of the drive in its
own database refuses the artifact in either direction (§2.6). A producer cannot
construct that disagreement at all.

`Drive-State-Id` mirrors `Snapshot-Id`. `Block-*` and `Data-*` carry the same
meanings the Snapshot entity gives them — the range *searched* against the range
where data was actually *found*, which lets a client size the work, and know an
artifact is empty, without fetching it.

One tag is specific to this entity:

- **`Entity-Count`** — an integrity check, not a statistic. On a private drive
  GCM proves the ciphertext arrived intact and the count proves the body meant
  what the tags promised; on a public drive nothing proves the first, and the
  count still proves the second. A mismatch after import is
  decisive and cheap, and it is the same check on both paths.

**Never set `Content-Encoding: gzip` on this entity.** An earlier draft of this
document specified it, on the reasoning that a client cannot discover
compression from an encrypted body so it ought to be declared. That reasoning
is sound and the conclusion is still wrong, because the tag is not
documentation — it is an instruction to the transport:

- `ar-io-node` indexes `Content-Encoding` from both L1 transactions
  (`src/database/standalone-sqlite.ts`) and bundled data items
  (`src/lib/ans-104.ts`), then echoes it onto the data response —
  `res.header('Content-Encoding', dataAttributes.contentEncoding)` in
  `src/routes/data/handlers.ts`.
- What the gateway then serves is **GCM ciphertext** for a private drive, and
  for a public drive the gzip stream itself, which a transport layer would
  then decode before the reader's own bounded inflation could run (§2.4). On
  the private path the gzip layer is one step further in (§3.3). A browser
  `fetch` will try to gunzip whichever of those arrives, at the network layer,
  and fail with `ERR_CONTENT_DECODING_FAILED`. There is no opt-out in the
  browser, and `dart:io` auto-decompresses by default.
- **Tags are immutable.** An artifact published with this tag is unfetchable
  for as long as it exists, by every client, with no remedy but republishing.

Compression stays an internal detail of the payload, detected from its first
bytes (§2.7) after the owner check and, for a private drive, decryption. A
reader must bound that decompression (§2.4);
the ratio here is roughly 5.2× on real data (34.63 → 6.65 MiB), and a payload
that inflates past the AES-GCM size boundary is refused rather than buffered.

**Deliberately absent.** No size tag — `data.size` is already queryable. No
`Supersedes` pointer — derivable from `Block-End` ordering, and a tag that
duplicates derivable state is a tag that can eventually disagree with it. No
total byte count — derivable after import, and definitionally slippery (hidden
files? superseded revisions?); a candidate for §6 instead.

### 3.3 Payload

```
private:  serialise rows → gzip → AES256-GCM
public:   serialise rows → gzip
```

The payload is a container of **named sections**, plus a top-level `version`
and a top-level `coverage` object. On a private drive GCM authenticates the
whole container, sections, version and coverage alike. See §2.2 for
authorship, and §2.6 for why the last step is absent for a public drive.

The container itself is **identical between the two privacies**. Nothing in it
is conditioned on the drive's privacy, no section appears or disappears, and
the `drives` section carries the drive's own `privacy` value on both paths —
which a reader checks against the privacy of the drive it holds locally, for
the same reason it checks the coverage tags: the merge writes that value onto
the local drive row, and the payload is the half that is imported.

`version` is the same `major.minor` string the `State-Version` tag carries, and
a producer writes both from one constant. **A reader must refuse an artifact
whose tag and payload version disagree**, for the same reason it refuses one
whose `Block-*` tags disagree with the payload's coverage: the tag is what an
indexer reports and the payload is what is imported. Any disagreement,
including one only in the minor — "the minor changes nothing this reader
dispatches on" is true, and is not a reason to believe the half nobody
authenticated.

**The sections.** Seven, named for the tables they carry, each an object with
a `rows` array. All seven are required and any may be empty (§6.1).

| section | carries |
|---|---|
| `drives` | exactly one row: the drive itself, including its `privacy`, and minus its key material, sync cursor and watermark |
| `folder_entries` | current folder rows, without `path` or `isGhost` (below) |
| `file_entries` | current file rows, including `thumbnail`, `pinnedDataOwnerAddress`, `assignedNames`, `licenseTxId`, `isHidden` and both custom-metadata columns, without `path` |
| `drive_revisions` | every drive revision |
| `folder_revisions` | every folder revision |
| `file_revisions` | every file revision, not only the newest (D2) |
| `licenses` | licence rows for the files carried |
| `transaction_statuses` | the transactions those rows reference that the producer had not confirmed, with the status it held (D15) |

**Two tables are deliberately absent, and a reader must not expect them.**
`network_transactions` is **derived on import**, not carried: it is four
columns, fully reconstructible from the revisions, and it has no `driveId` — so
publishing it would publish rows about the producer's *other* drives to
everyone holding this drive's key. A reader rebuilds it from the revision rows
it just imported, as `confirmed` except for what `transaction_statuses` lists:
a listed data transaction becomes `pending`, so the reader's own confirmation
pass checks it, and any other listed transaction stays `failed` (D15).
`arns_records` and `ant_records` are likewise not carried
(D10); the drive-side fact travels as `assignedNames` on the file rows.

**The file says what it is and who made it.** Its SQLite header carries
`application_id` `0x41724453` (`ArDS`), and a reader refuses a database
without it. `meta.producer` names the client that built it, as
`<App-Name>/<App-Version>` (for this app, for example `ArDrive-App/2.88.1`): on a private
drive that claim is authenticated under the drive key, where the `App-Version`
tag is only what an indexer reports, so it is what a reader refuses a build
with a known defect by (D17).

**Two of the app's columns are not carried.** `path` is written as `''`
everywhere in the app and read by nothing: every path shown is built from
`parentFolderId`, which any reader can do in one pass. `isGhost` is always
false for a row a revision vouches for, the only kind that travels. A reader
writes `''` and false for them. `action` on the revision tables is carried
although it is derivable from consecutive revisions: it is informational, the
app's tables require it, and it costs 0.3% of the artifact.

Nothing else in the local database travels. `profiles` never does.

**`coverage` is load-bearing, not informational.**

```json
{ "version": "1.0", "coverage": { "blockStart": 0, "blockEnd": 1814228 }, "...": "sections" }
```

It states the block range the rows in *this* payload account for, and it is the
value a reader adopts as its own sync watermark. The same numbers appear in the
`Block-Start` / `Block-End` tags, which is deliberate duplication: the tags let
discovery order candidates without downloading them, and the payload copy is
the one that is imported.

**A reader must refuse any artifact whose tags disagree with the payload's
claim, on either end.** Tags reach a reader as an indexer reports them, and the
indexer is not trusted. A tag reporting a higher `Block-End` than the payload
claims would have every client that believed it advance its watermark across
blocks whose rows the artifact never carried — the entities in that gap
are then never queried, and the drive is quietly missing files with no error
anywhere. `Block-Start` matters for the same reason and is not the lesser half:
reporting a `[700, 900]` artifact as starting at 0 jumps the watermark across
200 blocks of unread history.

A producer must therefore read its watermark and its rows in **one database
transaction**, and tag from the claim it sealed rather than re-reading. A
producer that reads the watermark twice can have a sync land in between and
publish an artifact whose tags contradict its own payload — permanently
unusable, and paid for.

The claim is also clamped on read: `Block-End` above the current block height
is honoured only up to that height. An artifact may legitimately claim more
than a lagging gateway has seen, and that must cost a wasted download rather
than fail the drive.

### 3.4 Every artifact is a full copy

`Block-Start` is **always 0**. Each artifact carries the drive's entire state as
of its `Block-End`, and supersedes every earlier one outright. There are no
diffs, no increments, and no chain to assemble.

This is worth stating because the recommendation **inverts** between snapshots
and artifacts, and for a reason:

| | cost of producing | therefore |
|---|---|---|
| Snapshot | re-reads the chain — ~420 queries and ~42,000 fetches | incremental, so production stays affordable |
| Artifact | a local database export | **full copy**, because production was never the expensive part |

For an artifact the only cost is the upload, and a full copy buys back the
property that matters most: it is **self-contained**. Any single artifact is
sufficient on its own. There is no ancestor to locate, no ancestor to still be
retrievable, and no way for one missing link to invalidate a chain — which is
precisely the residual risk that hangs over snapshot chains
(`SNAPSHOT_CREATION_FROM_SNAPSHOTS.md`). One fetch, one owner check, one
decryption, and either it works or the client falls back.

The format does not forbid the alternative. `Block-Start` is a tag, not a
constant, and the range composition in §5 already handles several sources
covering different spans — an incremental artifact would simply be one with a
non-zero `Block-Start`. So this is a **policy for v1, not a limitation**, and
can be revisited without a format break if it ever needs to be.

It would need revisiting for a drive large enough that republishing the whole
state is expensive: at 6.65 MiB compressed this drive is nowhere near that, but
a 500k-entity drive published weekly would be. Until then, self-contained is
worth more than small.

### 3.5 A warning from the existing spec

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
resolve name  →  look up the owner  →  GET the bytes  →  decrypt  →  import
                                         GraphQL only for the recent tail
```

For the ~99% of history an artifact covers, one indexer lookup replaces the
walk. On a
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

So a resolved name yields a transaction id and nothing more. The reader looks
up that transaction's owner, by id, and applies the same owner check as GraphQL
discovery (§2.2), then the `Drive-Id` tag and the coverage tags. On a private
drive a compromised name also meets GCM: bytes not sealed under the drive key
do not open. A compromised name can waste a download and one lookup. It cannot
introduce state from anyone but the drive's owner, as far as the indexer can
tell.

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

Authorship is the upload's owner as the indexer reports it (§2.2), which the
indexer reports identically for both:

- a **top-level (L1) transaction**, whose owner is in its header;
- a **bundled data item**, whose owner is in the item, and for which
  `GET /tx/<id>` returns 404.

The transport is therefore a purely operational choice — cost, size, whichever
upload path the user already has — with no bearing on trust or discovery. Clients must read either without preference.

Reading has the same rule: an artifact is fetched by transaction id over
ordinary HTTP, which works for both, and never requires the bundler that
produced it to still exist.

---

### 4.5 What a gateway actually does, measured

Measured in October 2026 against two AR.IO gateways running release 85, in
Chromium, Firefox and WebKit, with the reading page on a different origin.
arweave.net rate-limited the test host throughout and was not measured.

| Property | Behaviour |
|---|---|
| Range requests | Honoured on `/{txId}`, a bundled data item, a manifest path and an ArNS path, single and multi-range |
| CORS | `Access-Control-Allow-Origin: *`, `range` allowed, headers exposed |
| A stored `Content-Encoding` | Passed through unchanged, never decoded |
| A range of a gzip-stored object | A 206 carrying a slice of the compressed bytes, which no browser can decode |
| Negotiated compression | Does not happen. No gateway compresses on request |
| A cold object | The whole object is fetched upstream before the range is answered: 9 to 22 seconds measured |
| A warm object | About 70 ms per read |

Four consequences for any reader of an artifact, including the app:

1. **Random access does not help the first reader.** On a cache miss the gateway
   pulls the whole object anyway, and issues a second, uncoalesced ranged fetch
   after it. A producer that wants fast first reads performs one full GET against
   the serving gateway after publishing.
2. **Read in few large blocks.** The per-resource token bucket is keyed
   `host:method:path` and shared by every reader of the same URL, charged per KiB
   with a one-token minimum, so hundreds of small reads are the wrong shape.
3. **Do not verify `Content-Digest` on a partial response.** A gateway returns
   the whole-object digest on a 206 and signs it, so the check fails on correct
   data. A reader relies on the owner check and, on a private drive, GCM
   (§2.2).
4. **Pin the resolved id.** A name is mutable and `If-Range` is not implemented,
   so a reader takes `x-arns-resolved-id` from the first response and reads the
   rest against it.

Five defects were found in the gateway while measuring, the first of which
matters beyond this feature: a cached 206, 416 or 400 carries the whole-object
`Content-Digest`, and that header is inside the signature, so a verifying client
receives a valid signature over a false claim. They are reported to the node
team and none of them blocks this format.

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

Three rules a reader has to get right, each of which cost time to learn here:

- **A deep sync must not read an artifact.** "Rebuild this drive from the
  chain" is a request to stop trusting local state, and an artifact is local
  state — someone else's, arrived at by the same reasoning being distrusted.
  It is also usually the *only* remedy an interface offers for a drive that
  looks wrong, so an artifact that left a drive incomplete would otherwise
  re-apply itself as the fix.

- **Do not re-import an artifact already imported.** A successful import
  leaves the artifact's `Block-End` and the drive's watermark **equal**, and
  the no-rollback rule refuses only `Block-End < watermark` — so nothing stops
  the next sync doing all of it again, forever. Measured at 41,767 files, that
  repeat costs a download of about 10 MiB and over 6 seconds, and writes
  **zero** rows. Key the check on the artifact's transaction id and not on its
  range: a *different* artifact covering the same range can still carry
  entities a consumer's own sync skipped, and importing it is how those get
  repaired. Keep the record where the rows are, so it survives a restart and
  cannot outlive them: ArDrive web writes it to the drive row in the import's
  own transaction, and skips only while the drive's watermark is still at or
  past the artifact's `Block-End`.

- **Skip snapshots the artifact has already covered — before validating
  them.** Once the artifact's range seeds the obscuring accumulator, a
  snapshot wholly below `Block-End` is left with no sub-ranges and can serve
  no block, so any work spent on it is wasted. If validation involves a
  network probe, that waste is measured in tens of seconds per snapshot, and a
  client that prefetches snapshots per *owner* rather than per *drive* will
  hand a drive its neighbours' snapshots routinely.
- **A sync that reported skipped entities must not produce an artifact.** Sync
  advances `lastBlockHeight` regardless of skips
  (`SYNC_SKIPPED_ENTITY_PERSISTENCE.md`), so publishing from that state would
  make a gap permanent and immutable.

---

## 6. Extensibility

The payload is a container of named sections, and the rule that makes extension
safe is the separation of **additive** from **breaking**:

- **Unknown sections are skipped**, not rejected. A reader takes what it knows.
- **Known sections are required**, even when empty. See below — this is the
  half that is easy to get wrong.
- **Unknown tags are ignored** — already how ArFS works.
- **`State-Version` is `major.minor`, and only the *major* bumps when an older
  reader would *misinterpret* the payload.** An addition moves the minor.
  Bumping the major on additions locks out clients that could have used most of
  it, which defeats the point.

Anything later — aggregate totals, additional indexes, whatever is wanted in six
months — arrives as a new section that existing clients ignore, under a higher
minor.

**Why two components, and what a reader does with them.**

A single integer conflates the two changes above. It has to move for a
breaking change, so an older reader can refuse; and it must not move for an
addition, so an older reader can still read. One number cannot do both, and the
one that stayed put through an addition is the one §6.1 is about.

`major.minor` separates them. **No patch component**: the version answers one
question — what may a reader assume is in this payload — and there is no
bug-fix level of that. A third digit would be a number no reader could act on.
Two components also match the protocol this extends, which tags `ArFS: "0.15"`.

The reader rule, in full:

| what arrives | what a reader does |
|---|---|
| **a higher major** | refuse — `unknown-version`, "the artifact is newer than this client" |
| **a lower major** | refuse — `unknown-version`, "the artifact predates a breaking change". Its **own** message; see below |
| **the same major, any minor** | accept. Unknown sections and fields are ignored; known sections are still required |
| **anything that will not parse** — absent, `"1"`, `"1.0.0"`, `"x.y"`, a number too long to hold identically on every platform | `integrity-failed`, not `unknown-version`. A version you cannot compare tells you nothing about whether you could have read the artifact |

The lower-major arm is refused *explicitly*, and not left to whatever the
section checks make of it. Without its own arm, what an older major meets
depends on the payload's **shape** rather than on its version, and both answers
are wrong: a payload that genuinely lacks a section is refused with
*"payload is missing the `file_revisions` section"* — a sentence about a
truncated artifact, not an obsolete one, sending the reader after the wrong bug
— and a payload that is structurally compatible by accident is **accepted**,
under a format the reader never agreed to. That is §6.1's mistake read from the
other end.

A bare `"1"` is **not** tolerated as `1.0`. No writer emits that shape, and
nothing has been published on chain, so accepting it would be a compatibility
path with no producer at the other end of it — untested code guarding a case
that cannot occur.

### 6.1 Why a known section must be present even when empty

The two halves of the first rule look symmetric and are not. On the wire, an
**absent** section and an **empty** one are indistinguishable, and they mean
opposite things: "I have nothing to say about this table" versus "this table is
empty". A reader that treats absence as emptiness silently believes the second
whenever a producer meant the first.

This is not hypothetical; it is how this format nearly shipped. An early
revision carried three sections — the drive row and its folder and file
entries — with no revisions. A producer built from that revision publishes a
payload that:

- is uploaded by the drive owner's wallet;
- carries a correct `Entity-Count`, which counts entities, not revisions;
- claims coverage its tags agree with.

Every check passes. And the drive it restores shows an **empty file list**,
because a file row is only visible through a join to its newest revision's
transactions — so entries without revisions render nothing at all. The user
sees a drive they know has files, containing none, with nothing in any log.

Hence the asymmetry. A section this build knows must be present; its rows array
may be empty, which is a producer saying something rather than saying nothing.
A load-bearing section added later raises the **major** of `State-Version`,
which older readers already refuse cleanly — the one case the third rule above
is *for*. An optional one raises the minor, and older readers keep working.

---

## 7. Observability

The failure this whole line of work came from was **silent**: sync fell back to
a slower path and nothing said why, which cost days of diagnosis. Shipping an
artifact with that property would repeat it.

The rule: **"no artifact was used" and "an artifact was rejected because X" must
never look the same.**

Per drive, per sync:

- whether an artifact was used;
- if not, an **enumerated reason** — `none found`, `unknown State-Version`
  (a major this build does not read, in either direction),
  `owner mismatch`, `decrypt failed`, `integrity failed`, `entity count
  mismatch`, `coverage mismatch`, `privacy mismatch` (the artifact's
  cipher-presence contradicts the drive's privacy, §2.6), `range already
  covered`, `fetch failed`;
- entities imported from artifact / snapshot / GraphQL;
- time in bulk import against time in parse.

The `[snapshot]` instrumentation already merged is the right shape; this extends
it rather than inventing a second vocabulary.

One case sits outside the vocabulary on purpose: **the indexer never
answered**. That is a fact about the lookup, not about an artifact, and giving
it a reason code would let "this drive has no artifact" and "we could not tell"
read identically — the exact confusion this section exists to prevent. It is
reported as a warning, and the discovery result carries the distinction as a
separate flag so no caller has to infer it from an empty list.

**`fetch failed` is inside the vocabulary**, and the line between the two is
worth stating because it is easy to get wrong: by then a specific artifact has
been identified, by transaction id, and the fact recorded is about *that
artifact*. A consumer asking "of the drives that had an artifact, how many
actually used one?" gets a wrong denominator if this is only a log line.

---

## 8. Other clients

*Reasoned from the protocol boundary; those repositories were not read.*

- **Existing readers are unaffected for now** — a transaction whose
  `Entity-Type` they never query for. This is a transition rather than a
  permanent arrangement: snapshot production ends once core-js and the CLI read
  artifacts (§11), so "snapshots keep being produced" is true only until then,
  and no client should be built on the assumption that it lasts.
- **ardrive-core-js** needs the owner check, the drive-key decryption path it
  already has, and the merge rules. It does **not** need a format
  reimplemented from prose: the payload is a SQLite file, and a SQLite library
  reads it (`node:sqlite` needs Node 22, while core-js supports Node 18; see
  the delivery plan, B1.1). Reading is far simpler than writing.
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
- `privacy.mdx` — that a private drive's payload is encrypted with the
  **drive** key as a single unit, unlike a snapshot's per-entity ciphertext;
  that a public drive's is not encrypted, with `Cipher`
  and `Cipher-IV` absent; and that a reader refuses an artifact whose
  cipher-presence contradicts the privacy of the drive it names (§2.6).

**Correction, independent of this work:**

- `entity-types.mdx` — the Snapshot data field is `jsonMetadata`, not
  `dataJson`, in both prose and example (§3.5). A live bug against every
  snapshot on chain; it should be fixed on its own, not bundled into a
  new-feature change.

---

## 10. Open questions

**Closed since the first revision:** 1 (the container, by D12), 4 (revision
depth, by D2's reversal to full history), and 6 (ArNS, which `LIBRARY_PAGES.md`
now needs and therefore specifies). They are kept below with their answers
rather than deleted, because each one's reasoning is still load-bearing.

1. ~~**Section format.**~~ **Closed: a SQLite file with a frozen schema (D12).**
   Readable from Dart and TypeScript, stable across `schemaVersion`, cheap to
   insert in bulk.
2. **Production trigger.** On demand, after a clean sync, or on a cadence —
   coupled to §5's rule that a sync reporting skips must not publish.
3. **Who pays.** It is an upload, on a drive the user may not be changing —
   and payable in either AR or Turbo credits, since §4.4 requires both
   transports. Cadence and cost interact: cheap increments favour publishing
   often, an L1 wallet-only user favours publishing rarely.
4. ~~**Revision depth.**~~ **Closed: every revision travels (D2).** Full
   history, or current state plus a pointer to snapshots for older revisions? Current-state-only is much smaller and covers
   what the explorer shows; history matters for the activity view. This is the
   lever that keeps the full copy of §3.4 affordable as a drive grows, and is
   worth deciding before the artifact size is what forces increments.
5. **Multi-part authentication** above the GCM boundary (§2.3): a manifest of
   authenticated parts is preferred, but the manifest's own integrity needs
   specifying.
6. ~~**ArNS naming convention.**~~ **Closed by `LIBRARY_PAGES.md`**, which
   makes a name the point rather than an acceleration, and specifies the human
   name over `state_<driveId>`. Undername length and readability still need
   checking against the ARIO spec, and the apex must be offerable from the
   existing picker, which today drops it.

7. **The random-access threshold** of §2.7: the artifact size above which a
   public artifact is published identity rather than compressed.

---

## 11. Relationship to the other snapshot work

| Change | Fixes | Size |
|---|---|---|
| **Incremental snapshots** | Every snapshot re-encodes all history from block 0, because `create_snapshot_cubit.dart:225` defaults to `Range(start: 0, …)` even though line 222 already honours an arbitrary start. Starting where the last ended makes production cheap. | Smallest — a changed default |
| **Snapshots from ancestors** (`SNAPSHOT_CREATION_FROM_SNAPSHOTS.md`) | Producing one re-reads the chain instead of copying what earlier snapshots already hold. | Medium |
| **This document** | The per-entity decryptions, the plaintext structure leak, and the dependency on the GraphQL indexer. | Largest |

**That table described a world where all three ship. Only one of them will.**
The artifact replaces the snapshot rather than sitting beside it, so neither
incremental snapshots nor snapshots from ancestors is worth building beyond
keeping what exists working. That is the most valuable thing this decision
settles, because both were scoped as work.

### 11.1 The retirement path

**Stop producing, keep reading, never break what is published.**

1. **Now: stop nudging private drives to snapshot.**
   `lib/blocs/prompt_to_snapshot/prompt_to_snapshot_bloc.dart` has no privacy
   gate, so the app asks a private drive's owner to publish the drive's whole
   shape in the clear, permanently. §1.3 is the argument; the gate is worth
   adding whether or not anything else here ships.
2. **Then: Publish writes an artifact, and not a snapshot too.** Writing both
   doubles the bytes to say the same thing twice. Snapshot creation stays
   available for anyone who wants the interchange format.
3. **Then: stop producing snapshots at all**, once ardrive-core-js and the CLI
   read artifacts and the entity is documented in `ar-io-docs` (§9). Before both
   are true, retiring production breaks other clients quietly.
4. **Never stop reading them.** Every snapshot on chain is permanent, and for a
   drive that has one and no artifact it remains the fastest path. The reader
   stays for ever.

What the artifact does **not** inherit is the one property a snapshot has:
entries carry their original `gqlNode`, so a snapshot's contents can in
principle be checked against chain, while exported rows cannot. §2.5 records
this as the residual risk, and it is the reason the retirement is sequenced
behind other clients rather than taken on trust.
