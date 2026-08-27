# The drive state artifact

A published, signed blob of a drive's parsed state — encrypted under the drive
key when the drive is private — which a client imports in bulk instead of
replaying the drive's history entity by entity.

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

Order of operations, and it matters:

```
private:  serialise → compress → sign → encrypt
public:   serialise → compress → sign
```

The public path is the same chain with the last step absent, because a public
drive has no drive key. **The signature is therefore load-bearing in a way it
is not for a private drive**: it is the only thing binding a public artifact to
the drive's owner. A private drive's artifact has a second filter — a stranger's
bytes will not decrypt under the drive key, whatever they claim — and a public
drive's has none, so anyone can post bytes tagged with a `Drive-Id` and the
signature check is the whole of what turns them away. This is an argument for
signing more carefully, not for signing less.

Compressing *before* signing rather than after, because the signature is an
ANS-104 **data item** signature and not a signature over raw bytes. That is not
a stylistic choice: wallet extensions no longer grant arbitrary-byte signing,
and a data item is what ArConnect and Wander still sign. A data item wraps the
bytes it authenticates, so the signed object is itself the container — sign
first and the gzip layer would sit *outside* the data item, where a reader must
decompress before it can even parse the thing that would have told it whether
the bytes were worth decompressing.

The order the implementation uses inverts that, and gives a reader a chain in
which every step's input has already been vouched for by the step before:

```
private:  decrypt (GCM, authenticated)  →  parse data item  →  verify owner  →  gunzip
public:                                    parse data item  →  verify owner  →  gunzip
```

**Only a payload the owner signed is ever inflated**, on both paths. That is
the property that makes a bound on the decompressed size meaningful rather than
decorative (§2.4), and it is the same discipline as never handing an untrusted
file to SQLite: spend nothing on input until something has attested to it.

What the private path has in addition is an earlier and cheaper filter. GCM
authenticates before an ANS-104 parse is attempted at all, so a body that
arrived wrong — or was never this drive's — is turned away before any parser
sees it. A public drive reaches the parser with unverified bytes and rejects
them a step later. That is a difference in how much work a bad artifact costs,
not in what is accepted.

Compressing before encrypting remains, as ever, the only order that compresses
at all — and on the public path compression is simply the last thing that
happens to the payload before it is signed.

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
arrived wrong is caught one step later, by the data item signature, which every
path checks (§2.2).

**The 100 MiB refusal is a bound on the producer, not on the cipher.** D5 was
originally justified as an AES-GCM constraint — GCM should not authenticate
more than about this much in one piece — and that justification does not
survive either of the two things below. It is kept, at the same number, on its
own reasoning.

**Where that boundary actually is.** An earlier draft of this section put it
near 120k entities, extrapolating from the 34.63 MiB in §1.1. That
was wrong twice over: 34.63 MiB is a VACUUMed SQLite file, and `seal` does not
weigh a SQLite file — it weighs the serialised JSON payload, whose rows are much
fatter than SQLite's binary encoding. It also counted entities, while the
payload carries a revision row per revision as well (D2).

Two measurements now exist, and they disagree by about 10% for a reason worth
keeping:

| | method | crossover | headroom at 42k |
|---|---|---|---|
| `qa_findings_test.dart` | one row of each type, weighed and multiplied | ~73,000 files | ~1.75× |
| `drive_state_scale_measurement_test.dart` | the real `exportDriveState` over a 41,767-file database, whole payload weighed | ~80,000 files | ~1.92× |

Neither is wrong. A row's serialised width is dominated by its **name and
path**, and the two fixtures assume different ones — so the honest answer is a
range, not a number:

> **The 100 MiB payload boundary is crossed somewhere between 70,000 and 80,000 files, depending on how long that drive's names and paths are.**
> The same figures apply to a public drive: what is weighed is the serialised
> payload, and the cipher — which a public drive does not have — is downstream
> of it.

The end-to-end figure is the one to plan against, because it weighs what `seal`
weighs: **52.16 MiB for 41,767 files**, 1,306 bytes per entity, of a 100 MiB
budget.

Headroom under 2× is not much, and three things spend it: **longer paths** (the
measured drive uses one folder level; a deeply nested drive doubles the path
and every file pays it twice, in the entry and in each revision),
**`customGQLTags` and `customJsonMetadata`** (absent from the measured drive,
unbounded in general), and **more revisions per entity** (1.05 is one real
drive's figure, not a law — at 2.0 the crossover falls to roughly 55,000
files). A drive of 50k heavily-revised files with long paths can reach the
boundary; the D5 refusal is a path users will meet, not a theoretical one.

Note which number the refusal weighs: the **uncompressed** payload — and that
this is the *only* place that number appears. Measured end to end at 41,767
files:

| stage | size |
|---|---|
| serialised JSON — **what D5 weighs** | 52.16 MiB |
| gzipped | 9.55 MiB |
| signed ANS-104 data item | 9.55 MiB + 1,046 B of header |
| **what AES-GCM encrypts** (private drives only) | 9.55 MiB |
| what the network carries | 9.55 MiB, either privacy |

So the 100 MiB bound guards neither the cipher nor the transport: AES-GCM
holds exactly what the network carries, 5.46× less than the figure being
checked. An earlier revision of this section claimed the bound was "on what
AES-GCM must hold in one piece" — that is wrong, and the measurement above is
what disproves it.

**And there is now a path with no cipher in it at all.** A public drive's
artifact is signed and not encrypted, so a bound inherited from AES-GCM would
have nothing to inherit from and would have to be dropped for public drives —
which is plainly the wrong answer, because the cost the bound guards is the
same on both paths and is spent before any cipher is reached. A justification
that produces the wrong answer on a case it did not anticipate was never the
real reason.

What the bound actually guards is the **producer's memory**, which is where
the cost really lands. Building a payload of this size takes a process from a
263 MiB baseline to a peak of roughly 950 MiB: the exported object graph adds
~310 MiB, `jsonEncode` plus UTF-8 another ~175 MiB, and sealing sets a further
high-water mark before releasing it. The consumer is cheaper — importing never
set a new peak in the same run. That asymmetry is worth stating plainly:
**producing an artifact is the expensive half, and it is the half that runs in
the user's browser tab.**

That cost is **identical for a public drive**. The export, the `jsonEncode` and
the UTF-8 encoding are the whole of the peak; encryption adds one buffer of the
*compressed* size, 9.55 MiB, to a figure near 950 MiB. So the bound is the same
number for both privacies, deliberately. Two numbers would mean the reader's
inflation limit (§2.4) differed by drive, which is a window in which a payload
is writable by one path and unreadable by another. One number is checkable; two
drift.

The private path stays inside AES-GCM's own comfortable range as a
*consequence* of this bound rather than by construction — 100 MiB of payload is
9.55 MiB of ciphertext — and `drive_state_envelope_test.dart` asserts the
constant never grows past `maxSizeSupportedByGCMEncryption` so that consequence
keeps holding.

Two caveats on those figures. They are VM resident-set size, not a browser
heap — and a browser is likely worse, because dart2js strings are UTF-16, so
the 52 MiB of JSON is nearer 104 MB there, and a tab has a hard ceiling where
this process had the operating system. Reproduce them with
`test/drive_state/drive_state_scale_measurement_test.dart`.

### 2.4 Never hand an untrusted file to SQLite

The payload is a **serialisation of rows**, not a database file. Opening an
attacker-controlled SQLite file exercises a parser with a history of
malformed-database CVEs.

This also stops the wire format being welded to `schemaVersion`: a row format
the client maps onto whatever schema it runs, rather than a file only one
version can open. Two independent reasons for the same decision.

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

This check is cheap because of the ordering in §2.2 — the signature has already
verified by the time anything is inflated, so the bound is a backstop against a
*compromised or buggy owner client*, not the front line against anonymous
input. That holds for a public drive too, where the signature is the only thing
that ran before it.

### 2.5 Trust, replay and failure

- **Signature first.** An artifact whose signature does not verify against the
  drive owner is discarded before anything else is examined.
- **Newest wins** by the signed coverage claim — cross-checked against the
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

A public drive has no drive key, so its artifact is **signed and not
encrypted**. The chain is the private one minus a layer, and inverted on read:

```
private:  serialise → gzip → sign as a data item → AES256-GCM
public:   serialise → gzip → sign as a data item
```

`Cipher` and `Cipher-IV` are absent for a public artifact, and **their absence
is the discriminator**. Everything else about the entity — the ArFS tags, the
coverage claim, `Entity-Count`, the signature, the size bound, the section
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
signed payload's own `privacy` field is checked against the same trustworthy
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
  what the tags promised; on a public drive the data item signature proves the
  first and the count still proves the second. A mismatch after import is
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
  for a public drive a **signed ANS-104 data item** whose framing wraps the
  gzip stream; the gzip layer is two steps further in on one path and one step
  further in on the other (§3.3), and never the outermost thing. A browser
  `fetch` will try to gunzip whichever of those arrives, at the network layer,
  and fail with `ERR_CONTENT_DECODING_FAILED`. There is no opt-out in the
  browser, and `dart:io` auto-decompresses by default.
- **Tags are immutable.** An artifact published with this tag is unfetchable
  for as long as it exists, by every client, with no remedy but republishing.

Compression stays an internal detail of the payload, discovered by decompressing
it after the signature verifies — on both paths, since it is the signature and
not the cipher that gates inflation (§2.2). A reader must bound that
decompression (§2.4);
the ratio here is roughly 5.2× on real data (34.63 → 6.65 MiB), and a payload
that inflates past the AES-GCM size boundary is refused rather than buffered.

**Deliberately absent.** No size tag — `data.size` is already queryable. No
`Supersedes` pointer — derivable from `Block-End` ordering, and a tag that
duplicates derivable state is a tag that can eventually disagree with it. No
total byte count — derivable after import, and definitionally slippery (hidden
files? superseded revisions?); a candidate for §6 instead.

### 3.3 Payload

```
private:  serialise rows → gzip → sign as a data item (owner's wallet) → AES256-GCM
public:   serialise rows → gzip → sign as a data item (owner's wallet)
```

The payload is a container of **named sections**, plus a top-level `version`
and a top-level `coverage` object. The signature covers the whole container —
sections, version and coverage alike. See §2.2 for why the gzip step comes
before the signature and not after, and §2.6 for why the last step is absent
for a public drive.

The container itself is **identical between the two privacies**. Nothing in it
is conditioned on the drive's privacy, no section appears or disappears, and
the `drives` section carries the drive's own `privacy` value on both paths —
which a reader checks against the privacy of the drive it holds locally, for
the same reason it checks the coverage tags: the merge writes that value onto
the local drive row, and the payload is the half somebody signed.

`version` is the same `major.minor` string the `State-Version` tag carries, and
a producer writes both from one constant. **A reader must refuse an artifact
whose tag and payload version disagree**, for the same reason it refuses one
whose `Block-*` tags disagree with the signed coverage: the tag is chosen by
whoever posts the transaction and the payload is what the owner signed. Any
disagreement, including one only in the minor — "the minor changes nothing this
reader dispatches on" is true, and is not a reason to believe the half anybody
can rewrite.

**The sections.** Seven, named for the tables they carry, each an object with
a `rows` array. All seven are required and any may be empty (§6.1).

| section | carries |
|---|---|
| `drives` | exactly one row: the drive itself, including its `privacy`, and minus its key material, sync cursor and watermark |
| `folder_entries` | current folder rows |
| `file_entries` | current file rows, including `thumbnail`, `pinnedDataOwnerAddress`, `assignedNames`, `licenseTxId`, `isHidden` and both custom-metadata columns |
| `drive_revisions` | every drive revision |
| `folder_revisions` | every folder revision |
| `file_revisions` | every file revision, not only the newest (D2) |
| `licenses` | licence rows for the files carried |

**Two tables are deliberately absent, and a reader must not expect them.**
`network_transactions` is **derived on import**, not carried: it is four
columns, fully reconstructible from the revisions, and it has no `driveId` — so
publishing it would publish rows about the producer's *other* drives to
everyone holding this drive's key. A reader rebuilds it from the revision rows
it just imported. `arns_records` and `ant_records` are likewise not carried
(D10); the drive-side fact travels as `assignedNames` on the file rows.

Nothing else in the local database travels. `profiles` never does.

**`coverage` is load-bearing, not informational.**

```json
{ "version": "1.0", "coverage": { "blockStart": 0, "blockEnd": 1814228 }, "...": "sections" }
```

It states the block range the rows in *this* payload account for, and it is the
value a reader adopts as its own sync watermark. The same numbers appear in the
`Block-Start` / `Block-End` tags, which is deliberate duplication: the tags let
discovery order candidates without downloading them, and the payload copy is
the one that is signed.

**A reader must refuse any artifact whose tags disagree with the payload's
claim, on either end.** Tags are chosen by whoever posts the transaction and
nobody signs them. Re-tagging a genuine artifact with a higher `Block-End` and
re-posting it would have every client that imports it advance its watermark
across blocks whose rows the artifact never carried — the entities in that gap
are then never queried, and the drive is quietly missing files with no error
anywhere. `Block-Start` matters for the same reason and is not the lesser half:
re-tagging a `[700, 900]` artifact as starting at 0 jumps the watermark across
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
(`SNAPSHOT_CREATION_FROM_SNAPSHOTS.md`). One fetch, one signature to verify, one
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
  repeat costs a 9.55 MiB download, ~173,000 statements and about 8.5 seconds,
  and writes **zero** rows. Key the check on the artifact's transaction id and
  not on its range: a *different* artifact covering the same range can still
  carry entities a consumer's own sync skipped, and importing it is how those
  get repaired.

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
entries — with no revisions. A producer built from that revision signs a
payload that:

- verifies against the drive owner's wallet;
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
  `signature failed`, `decrypt failed`, `integrity failed`, `entity count
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
- `privacy.mdx` — that a private drive's payload is signed and encrypted with
  the **drive** key as a single unit, unlike a snapshot's per-entity
  ciphertext; that a public drive's is signed and not encrypted, with `Cipher`
  and `Cipher-IV` absent; and that a reader refuses an artifact whose
  cipher-presence contradicts the privacy of the drive it names (§2.6).

**Correction, independent of this work:**

- `entity-types.mdx` — the Snapshot data field is `jsonMetadata`, not
  `dataJson`, in both prose and example (§3.5). A live bug against every
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
   what the explorer shows; history matters for the activity view. This is the
   lever that keeps the full copy of §3.4 affordable as a drive grows, and is
   worth deciding before the artifact size is what forces increments.
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
