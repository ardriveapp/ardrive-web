# ArDrive Perpetual Access Layer

**Version:** 4.0 (final architecture)
**Date:** 2026-05-24

---

## The Problem

ArDrive user data lives permanently on Arweave. But finding it requires GraphQL gateways that index and serve ArFS metadata. If ArDrive stops operating, if gateways change their APIs, or if indexers go offline — users can't locate their files. The bytes exist forever; the catalog doesn't.

## The Solution

Two layers, one central directory. No per-user infrastructure required.

1. **Drive Manifests** — per-drive JSON files on Arweave that map every file path to its data transaction. Published automatically after each sync. Public drives are URL-addressable via any ar.io gateway. Private drives are encrypted with the drive key.

2. **Global Parquet Index** — a compressed catalog of all 58.1M ArFS entities, behind ONE central ArNS name (`ardrive-index.ar`). Queryable via DuckDB-WASM. This is the **universal directory** — any user's manifests are discoverable through it, regardless of wallet type.

### Discovery Architecture

```
ardrive-index.ar (ONE ArNS name, community-maintained)
       │
       ▼
Global Parquet Index on Arweave (58.1M rows, $65 one-time)
  │
  │  Query: "find manifest TXs for wallet address X"
  ▼
User's Drive Manifests (per-drive JSON, on Arweave)
  │
  │  Parse manifest → file paths → data TX IDs
  ▼
File Data on Arweave (permanent, fetch by TX ID)
```

**No per-user ArNS required.** No Solana wallet required for discovery.
Any wallet type works — the index maps Arweave addresses to manifest TXs.

Per-user ArNS (e.g., `photos_alice.ar`) is an optional acceleration for users who want URL-addressable public drives. It requires a Solana wallet (since ArNS is on Solana). But the system works without it.

---

## Real Data (chain-wide, 2026-05-24)

| Metric | Value |
|---|---|
| Unique ArDrive users | **24,033** |
| Unique drives | **42,740** |
| Unique files | **~57.6M** |
| Unique folders | **~462K** |
| Total ArFS entity transactions | **60.6M** |
| File revision ratio | **1.035x** (write-once in practice) |
| Public drives | 26,641 (62%) |
| Private drives | 16,093 (38%) |
| Encrypted file entities | **2.66%** of all files |
| Median files per drive | **2** |
| Users with < 100 files | **~89%** |
| Largest single drive | 2,777,581 files |
| Drives with 10K+ files | 102 (0.7%) |
| Shared drives on-chain | 11 (0.06%) — effectively zero |
| Total file content on Arweave | ~6.4 TB |

---

## Layer 1: Drive Manifests

### What They Are

An Arweave path manifest is a JSON file that maps file paths to Arweave transaction IDs. AR.IO gateways natively resolve these — when a manifest is pointed to by an ArNS name, any file within it becomes URL-addressable.

ArDrive already builds these. The code lives in `lib/manifest/domain/manifest_repository.dart` and `lib/entities/manifest_data.dart`.

### Extended Format (add metadata fields)

The standard Arweave manifest format allows extra fields — gateways ignore anything they don't need. We add file metadata so the ArDrive client can render a file listing without fetching each entity TX.

Two manifest types: **full** (complete drive catalog) and **delta** (changes since last snapshot).

#### Full Manifest

Published on first sync or when no snapshot exists. Contains every file and folder.

```json
{
  "manifest": "arweave/paths",
  "version": "0.2.0",
  "ardrive": {
    "version": 1,
    "type": "full",
    "driveId": "abc-123",
    "driveName": "My Photos",
    "privacy": "public",
    "owner": "arweave-address",
    "sourceWallet": "solana-address",
    "generatedAt": "2026-05-24T12:00:00Z"
  },
  "index": { "path": "photos/sunset.jpg" },
  "paths": {
    "photos/sunset.jpg": {
      "id": "dataTxId_for_file_bytes",
      "s": 4200000,
      "t": "image/jpeg",
      "m": 1716500000,
      "e": "entityTxId_for_metadata"
    },
    "photos/beach.png": {
      "id": "dataTxId_456",
      "s": 2100000,
      "t": "image/png",
      "m": 1716400000,
      "e": "entityTxId_789"
    },
    "documents/": {
      "id": "",
      "folder": true
    }
  }
}
```

#### Delta Manifest

Published when a snapshot exists. Contains ONLY entities added, changed, or deleted since the snapshot. The snapshot contains everything else.

```json
{
  "manifest": "arweave/paths",
  "version": "0.2.0",
  "ardrive": {
    "version": 1,
    "type": "delta",
    "driveId": "abc-123",
    "driveName": "My Photos",
    "privacy": "public",
    "owner": "arweave-address",
    "sourceWallet": "solana-address",
    "generatedAt": "2026-05-24T13:00:00Z",
    "snapshotTxId": "snapshot-covers-2.78M-files",
    "snapshotBlock": 1920000
  },
  "index": { "path": "photos/sunset.jpg" },
  "paths": {
    "photos/new-photo.jpg": {
      "id": "dataTxId_new",
      "s": 3500000,
      "t": "image/jpeg",
      "m": 1716600000,
      "e": "entityTxId_new"
    },
    "photos/deleted-old.jpg": null
  }
}
```

**Delta rules:**
- New or changed files: full entry in `paths`
- Deleted files: `null` value
- Unchanged files: absent (inherited from snapshot)

**Recovery from delta:**
```
1. Fetch delta manifest (tiny — just recent changes)
2. See type = "delta" + snapshotTxId
3. Fetch snapshot (bulk load of base state)
4. Apply delta on top: add new entries, remove nulls
5. Result: complete current drive state
```

#### Publishing Logic

```dart
final snapshot = await getLatestSnapshot(driveId);
final changedSinceSnapshot = await getEntitiesChangedSince(snapshot?.blockHeight ?? 0);
final totalEntities = await getTotalEntityCount(driveId);

if (snapshot != null && changedSinceSnapshot.length < totalEntities) {
  // Delta: only publish changes since snapshot
  publishDeltaManifest(
    changedEntities: changedSinceSnapshot,
    snapshotTxId: snapshot.txId,
    snapshotBlock: snapshot.blockHeight,
  );
} else {
  // Full: no snapshot or everything changed
  publishFullManifest(allEntities);
}
```

#### Cost Impact of Delta Publishing

| Drive size | Full manifest | Delta (50 new files) | Savings |
|---|---|---|---|
| 100 files | $0.0002 | $0.0001 | Negligible |
| 10,000 files | $0.02 | $0.0001 | 200x cheaper |
| 100,000 files | $0.22 | $0.0001 | 2,200x cheaper |
| 2,778,000 files | **$6.00** | **$0.0001** | **60,000x cheaper** |

For the whale: annual cost drops from **$312/year** (weekly full publishes) to **$0.005/year** (weekly deltas). Snapshots are published independently of manifests — the manifest just references the latest one.

#### Field Keys (short to minimize JSON size)

| Key | Meaning | Present on |
|---|---|---|
| `id` | Data TX ID (actual file bytes) | Files |
| `s` | Size in bytes | Files |
| `t` | Content type (MIME) | Files |
| `m` | Last modified (unix seconds) | Files |
| `e` | Entity TX ID (ArFS metadata) | Files |
| `folder` | Marks entry as an empty folder | Folders only |
| `null` | Deleted (delta manifests only) | Removed entries |

**What the gateway uses:** only `id` (for path resolution). Everything else is for the ArDrive client.

**What the client uses:** all fields — renders the file explorer without any additional HTTP requests.

#### Gateway Path Resolution

Gateways resolve paths from the MANIFEST, not the delta. For public drives where users want URL-addressable files (`photos_alice.ar/sunset.jpg`):

- **Full manifest:** gateway resolves directly — all paths present
- **Delta manifest:** gateway resolves ONLY paths in the delta (new/changed files). For paths in the snapshot but not the delta, the gateway can't resolve them from the delta alone.

**Recommendation for public drives that want URL access:** periodically publish a full manifest (not just delta) and point ArNS at it. The delta is for the ArDrive CLIENT's recovery path. The full manifest is for GATEWAY path resolution.

Publishing strategy:
```
Every sync:     publish delta manifest (cheap, for client recovery)
Every N syncs:  publish full manifest (for gateway URL resolution)
                N = when delta exceeds 50% of total entities, or monthly
ArNS points at: latest full manifest (for gateway resolution)
Local cache:    latest delta manifest TX (for client recovery)
```

### Public vs Private Drives

**Public drive manifest:**
- Published as a standard Arweave data item
- Plaintext JSON
- Gateway resolves paths: `photos_alice.ar/sunset.jpg` serves the file directly
- Any browser can access files via URL

**Private drive manifest:**
- Same JSON format inside
- Encrypted with drive key (AES-256-GCM) before upload
- Stored as encrypted blob on Arweave
- Gateway serves the encrypted bytes (can't resolve paths — correct behavior)
- Client fetches, decrypts with drive key, parses JSON locally
- File data is separately encrypted — fetched and decrypted on demand

**Encryption is identical to how ArDrive already encrypts any private entity.** No new crypto code. The manifest is just another entity encrypted with the drive key.

### Size Estimates

#### Full manifests (published once or periodically)

| Drive size | Full manifest | Compressed (gzip) |
|---|---|---|
| 2 files (median) | ~400 bytes | ~200 bytes |
| 100 files | ~12 KB | ~4 KB |
| 1,000 files | ~120 KB | ~35 KB |
| 10,000 files | ~1.2 MB | ~350 KB |
| 100,000 files | ~12 MB | ~3.5 MB |
| 2,778,000 files (whale) | ~330 MB | ~95 MB |

#### Delta manifests (published every sync, tiny)

| Changes since snapshot | Delta manifest |
|---|---|
| 1-10 files changed | < 2 KB |
| 50 files changed | ~6 KB |
| 500 files changed | ~60 KB |
| 5,000 files changed | ~600 KB |

**89% of users never exceed 15 KB total (full manifest is tiny enough to always publish full).**

**The delta strategy only matters for the 0.7% of drives with 10K+ files.** For them, it reduces per-publish cost by 200-60,000x.

### Publishing Trigger

```
Sync completes with changes detected:
  → If drive has snapshot AND changes < total entities:
      publish DELTA manifest (changes only, cheap)
  → Else:
      publish FULL manifest (complete catalog)
  → If public drive AND (no full manifest published recently OR delta > 50% of total):
      also publish FULL manifest for gateway URL resolution
  → If user has per-user ArNS: update undername → latest full manifest
  → Cache delta TX ID locally for fast recovery
```

- Public drives: full manifest = plaintext (gateway-servable), delta = plaintext (client-only)
- Private drives: both full and delta encrypted with drive key
- ArNS points at latest FULL manifest (for gateway path resolution)
- Previous manifests remain on Arweave permanently (version history for free)

### ArNS Integration (Optional — for URL-addressable public drives)

Per-user ArNS names are an **optional premium feature**, not a system requirement. They enable permanent URLs for public drives:

```
photos_alice.ar       → manifest TX for "My Photos" drive (public, gateway-servable)
docs_alice.ar         → manifest TX for "Documents" drive (public)
```

**Requirements:** ArNS is on Solana. User needs a Solana wallet to register/update names.
**Who benefits:** Users who want to share permanent links like `photos_alice.ar/sunset.jpg`
**Who doesn't need it:** Users who just want to store and recover files (global index handles discovery)

### Manifest Discoverability (without ArNS)

All manifests are tagged for discoverability via Arweave tag scan or the global index:
```
Tags on every manifest TX:
  App-Name:           ArDrive
  Entity-Type:        drive-manifest
  Drive-Id:           {drive-uuid}
  Drive-Privacy:      public | private
  Owner-Address:      {arweave-address}
  Content-Type:       application/x.arweave-manifest+json
```

**Discovery priority:**
1. Local cache (instant) — saved from last session
2. Global Parquet index via `ardrive-index.ar` (3-5 sec) — universal, any wallet
3. Arweave tag scan (30 sec) — fallback, always works
4. Per-user ArNS (2 sec) — optional acceleration for Solana users

### What Manifests Give You

| Capability | Works? |
|---|---|
| Browse files without GraphQL | Yes — manifest has all metadata |
| Access files via URL (public) | Yes — gateway resolves paths natively |
| Recover private drives | Yes — decrypt manifest with drive key |
| Offline file browsing | Yes — cache the manifest locally |
| Survive company shutdown | Yes — manifest is permanent on Arweave |
| Cross-user search | **No** — only the global index does this |
| Find your manifest without ArNS | **Partial** — Arweave tag scan (slow) |

### What Manifests DON'T Do

1. **Cross-user queries.** "Find all public PDFs on ArDrive" — impossible with per-drive manifests.
2. **Discovery when you've never published a manifest.** If no manifest exists for a user, only the global index can reconstruct their drives from raw entity data.
3. **Incremental sync.** Manifests are snapshots. "What changed since yesterday?" still needs transaction scanning.

These gaps are why Layer 2 exists.

---

## Layer 2: Global Parquet Index (Universal Directory)

### What It Is

A compressed catalog of every ArFS entity ever created, behind ONE central ArNS name: `ardrive-index.ar`. Stored as partitioned Parquet files permanently on Arweave. Queryable via DuckDB-WASM in the browser using HTTP byte-range requests.

**This is the universal directory for all ArDrive users.** It replaces the need for per-user ArNS names, GraphQL, or any other lookup infrastructure.

### Role in the Architecture

| Function | How the index serves it |
|---|---|
| **Discovery** (primary) | Query by wallet address → find user's manifest TX IDs |
| **Recovery** (when no manifest exists) | Query by wallet address → find all entities directly |
| **Cross-user search** | Query by file name, content type, size, etc. |
| **Analytics** | Aggregate stats on users, drives, storage |
| **Third-party tools** | Build alternative clients, explorers, search engines |

### Why One Central ArNS Name Works for Everyone

- `ardrive-index.ar` is ONE ArNS name maintained by the community
- Costs ~200 ARIO to register permanently (one-time)
- Points to a manifest.json listing all Parquet partition TX IDs
- Any user, any wallet type, queries the same index
- No individual user needs ArNS or Solana for discovery
- ArConnect users, Solana users, MetaMask users — all equal

### Discovery Flow (any wallet type)

```
User connects wallet (any type)
  → App resolves: ardrive-index.ar
  → Gets manifest.json (partition list)
  → Queries tip partition via byte-range:
      SELECT entity_tx_id, drive_id, block_height
      FROM index
      WHERE owner_address = '{derived_arweave_address}'
        AND entity_type = 'drive-manifest'
      ORDER BY block_height DESC
  → Gets latest manifest TX IDs for each drive
  → Fetches those manifests → full drive access
```

Time: 3-5 seconds. Works for any wallet type. No per-user ArNS needed.

### Schema

```sql
CREATE TABLE arfs_entities (
    entity_id           BINARY(16),     -- UUID
    entity_type         TINYINT,        -- 0=drive, 1=folder, 2=file
    drive_id            BINARY(16),
    owner_address       VARCHAR,
    parent_folder_id    BINARY(16),
    name                VARCHAR,        -- NULL for encrypted entities
    data_tx_id          BINARY(32),
    bundled_in          BINARY(32),
    entity_tx_id        BINARY(32),
    data_size           BIGINT,
    data_content_type   VARCHAR,
    cipher              TINYINT,        -- 0=none, 1=AES256-GCM, 2=AES256-CTR
    date_created        BIGINT,
    last_updated        BIGINT,
    drive_privacy       TINYINT,
    signature_type      TINYINT,
    block_height        BIGINT
);
```

### Size and Cost

| Metric | Value |
|---|---|
| Total rows | 58.1M unique entities |
| Uncompressed | ~9.9 GB |
| Parquet (ZSTD) | **~2.8 GB** |
| Arweave storage cost | **~$55** |
| Upload fees | ~$10 |
| ArNS name | ~200 ARIO |
| **Total bootstrap** | **~$65 + 200 ARIO** |

### Partitioning

```
ardrive-global-index.ar → manifest.json → partition list

Partitions (by block height, ~50K blocks each):
  arfs_507429_557429.parquet    (~70 MB)
  arfs_557429_607429.parquet    (~70 MB)
  ...
  arfs_1873993_1923993.parquet  (tip, updated weekly)
```

~28 partitions total. Each is a standalone Parquet file on Arweave.

### Browser Query (DuckDB-WASM, lazy-loaded only when needed)

```sql
-- Find all of alice's drives (recovery)
SELECT DISTINCT drive_id, name, drive_privacy
FROM read_parquet('https://ardrive.net/{partition_tx}')
WHERE owner_address = '7xKX...' AND entity_type = 0;

-- Find alice's latest manifest TX (when ArNS is down)
-- Search for her drive-manifest entities
SELECT entity_tx_id, block_height
FROM read_parquet('https://ardrive.net/{tip_partition}')
WHERE owner_address = '7xKX...' AND entity_type = 'drive-manifest'
ORDER BY block_height DESC LIMIT 1;
```

DuckDB uses HTTP byte-range requests — only fetches the column chunks and row groups needed. Querying a 70 MB partition for one user's drives reads maybe 500 KB from the network.

---

## End-to-End Flows

### Flow 1: User Uploads a File

```
Alice uploads sunset.jpg to her "Photos" drive
  │
  ├─ 1. ArDrive uploads file data to Arweave via Turbo
  │     → Turbo confirms: dataTxId = "abc123..."
  │     → No GraphQL needed. Turbo's response IS the confirmation.
  │
  ├─ 2. ArDrive uploads file entity metadata to Arweave
  │     → Turbo confirms: entityTxId = "def456..."
  │
  ├─ 3. Local database updated immediately
  │     → App knows: file exists, dataTxId, entityTxId, size, name, parent
  │     → User sees the file in their drive INSTANTLY (no sync wait)
  │
  ├─ 4. Publish manifest (makes this upload discoverable from other devices)
  │     │
  │     ├─ Drive has snapshot? Yes (snapshotTxId = "snap789...", block 1920000)
  │     ├─ Entities changed since snapshot? Just this one new file
  │     ├─ Total entities in drive: 2,500
  │     ├─ Decision: publish DELTA (1 change < 2,500 total)
  │     │
  │     └─ Delta manifest JSON:
  │        {
  │          "ardrive": { "type": "delta", "snapshotTxId": "snap789...", ... },
  │          "paths": {
  │            "photos/sunset.jpg": { "id": "abc123...", "s": 4200000, ... }
  │          }
  │        }
  │
  ├─ 5. Upload delta manifest to Arweave via Turbo
  │     → manifestTxId = "mani111..." (~2 KB, costs $0.0001)
  │     → Tags: Entity-Type=drive-manifest, Drive-Id=..., Owner-Address=...
  │
  ├─ 6. Cache manifestTxId locally
  │
  └─ 7. (Periodically) Publish full manifest
        → Full manifest TX = "full222..." (complete drive catalog)
        → If user has ArNS: update photos_alice.ar → "full222..."
        → Then: https://photos_alice.ar/photos/sunset.jpg serves the file
        → Manifest is also discoverable via global index (no ArNS needed)
```

**No GraphQL involved at any step.** Turbo confirms uploads. Local DB is the source of truth. Manifest makes it discoverable from other devices. ArNS makes it URL-addressable. Total extra cost: ~$0.0001.

---

### Flow 2: User Returns Next Day (same device)

```
Alice opens ArDrive on same laptop
  │
  ├─ 1. App starts, renders drives from local DB (instant)
  │
  ├─ 2. Background: check for updates from other devices
  │     │
  │     ├─ Fetch latest manifest TX for each drive (via cached TX ID or ArNS)
  │     ├─ Compare manifest timestamp with local last-sync timestamp
  │     │
  │     ├─ If manifest is newer than local:
  │     │   → Fetch manifest → diff against local DB → apply changes
  │     │   → "2 new files synced from your other device"
  │     │
  │     └─ If local is newer (user uploaded from this device since last manifest):
  │         → Publish updated delta manifest (background)
  │
  └─ 3. User sees current state immediately. Cross-device changes appear within seconds.
```

**No GraphQL.** Manifest IS the cross-device sync mechanism. Fetch latest manifest, diff with local, apply changes. Same result as GraphQL sync but peer-to-peer via Arweave.

---

### Flow 3: User Logs In on New Device

```
Alice logs in on her work computer for the first time
  │
  ├─ 1. Connect wallet + enter password
  │
  ├─ 2. Discover drives via global index (no GraphQL, no per-user ArNS needed):
  │     │
  │     ├─ Resolve ardrive-index.ar → get partition manifest
  │     ├─ Query tip partition (byte-range, ~500 KB fetched):
  │     │     SELECT entity_tx_id, drive_id
  │     │     WHERE owner_address = '{alice}'
  │     │       AND entity_type = 'drive-manifest'
  │     │     ORDER BY block_height DESC
  │     ├─ Gets manifest TX IDs for each of Alice's drives
  │     │
  │     └─ (If global index unavailable) Arweave tag scan fallback
  │
  ├─ 3. Fetch manifests (one HTTP call per drive, ~2-5 seconds total)
  │     │
  │     ├─ Full manifest: parse JSON → all files with metadata
  │     ├─ Delta manifest: fetch snapshot + apply delta
  │     └─ Encrypted manifest: decrypt with drive key → parse JSON
  │
  ├─ 4. Populate local database from manifests
  │     → Insert all entities into local tables
  │     → App renders drives
  │
  └─ 5. Done — new device is fully operational
        → Can upload (Turbo still works without GraphQL)
        → Can browse (local DB populated from manifest)
        → Can sync across devices (publish/fetch manifests)
```

**No GraphQL. No per-user ArNS.** The global index (`ardrive-index.ar`) finds the user's manifests. Works for any wallet type. First load: 3-5 seconds.

---

### Flow 4: User Uploads Without GraphQL

```
GraphQL doesn't exist. Alice uploads a file from her laptop.
  │
  ├─ 1. Upload file data to Arweave via Turbo
  │     → Turbo confirms: dataTxId = "abc123..."
  │     → Turbo is independent of GraphQL (it's a bundler service)
  │
  ├─ 2. Upload file entity metadata via Turbo
  │     → entityTxId = "def456..."
  │
  ├─ 3. Local DB updated with new file
  │     → User sees the file immediately
  │
  ├─ 4. Publish delta manifest (adds the new file)
  │     → ~2 KB upload via Turbo → $0.0001
  │     → Now discoverable from Alice's other devices
  │
  ├─ 5. Alice opens her phone
  │     → Phone fetches latest manifest
  │     → Sees the new file
  │     → Synced. No GraphQL.
  │
  └─ What if Turbo is also down?
        → Can't upload at all (no way to write to Arweave without a bundler)
        → This is the ONE hard dependency: a functioning Arweave bundler
        → But there are multiple: Turbo, Irys, direct L1 (slow but works)
        → As long as ANY upload path to Arweave exists, ArDrive works
```

**GraphQL is gone. App still fully functional.** Only hard dependency: a way to write to Arweave (Turbo, Irys, or L1 direct).

---

### Flow 5: Discovery Fallback Layers

```
Alice logs in. Discovery priority in order:
  │
  ├─ Layer 1: Local cache (instant)
  │   → Stored manifest TX IDs from previous session
  │   → If found: fetch manifests directly, done in 1-2 seconds
  │
  ├─ Layer 2: Global index via ardrive-index.ar (3-5 seconds)
  │   → Resolve ONE ArNS name (community-maintained, always available)
  │   → Byte-range query Parquet for alice's manifest TXs
  │   → Standard path for new devices — works for ANY wallet type
  │
  ├─ Layer 3: Arweave tag scan (30 seconds)
  │   → Scan for TXs tagged: Entity-Type=drive-manifest + Owner-Address
  │   → Finds all manifests without any external service
  │   → Slowest but zero dependencies beyond raw Arweave nodes
  │
  └─ Layer 4: Global index full reconstruction (60+ seconds)
      → When NO manifests exist at all (user never published one)
      → Query global index for ALL entities by owner_address
      → Rebuild drive structure from raw entity data
      → Prompt user to publish their first manifest
```

**Every layer works for every wallet type.** No per-user ArNS. No Solana wallet requirement.
The standard new-device flow (Layer 2) takes 3-5 seconds for any user.

---

### Flow 6: User Accesses File via URL (no ArDrive app needed)

```
Alice shares a link: https://photos_alice.ar/vacation/beach.jpg
  │
  ├─ 1. Browser navigates to photos_alice.ar
  │
  ├─ 2. AR.IO gateway resolves ArNS name "photos_alice"
  │     → Gets manifest TX ID from ArNS record
  │
  ├─ 3. Gateway fetches manifest TX from Arweave
  │     → Parses Arweave path manifest (standard format)
  │     → Looks up path "vacation/beach.jpg" in manifest
  │     → Finds: { "id": "dataTxId_beach" }
  │
  ├─ 4. Gateway fetches dataTxId_beach from Arweave
  │     → Returns file bytes with Content-Type from data TX tags
  │
  └─ 5. Browser displays the image
        → No ArDrive app. No login. No JavaScript.
        → Just a URL that resolves to a file.
        → Works in curl, wget, img tags, embeds, anywhere.
```

**Result:** Any public ArDrive file is a permanent URL. Like a website, but can never go down.

---

### Flow 7: Private File Access (requires ArDrive app)

```
Alice wants to view her private tax return
  │
  ├─ 1. Browse to "Private" drive in ArDrive app
  │     → Local DB has folder structure (from manifest recovery or sync)
  │     → File names visible (decrypted from manifest during recovery)
  │
  ├─ 2. Click "tax-return-2025.pdf"
  │     → Look up in local DB: dataTxId = "enc789...", cipher = AES256-GCM
  │
  ├─ 3. Fetch encrypted file bytes from Arweave
  │     → GET https://arweave.net/enc789... → returns encrypted blob
  │
  ├─ 4. Derive file key
  │     → fileKey = HKDF(driveKey, fileId_uuid_bytes)
  │
  ├─ 5. Decrypt file bytes
  │     → AES-256-GCM decrypt with fileKey + cipher_iv from entity
  │     → Plaintext PDF bytes
  │
  └─ 6. Display/download the PDF
```

**Result:** Private files require the app (for decryption) but NOT GraphQL. The manifest provides the dataTxId; Arweave provides the bytes; the wallet + password provide the keys.

---

### Flow 8: User Has Never Synced, No Manifest Exists, GraphQL Down

```
Brand new user created account, uploaded 5 files, never synced again.
Company shut down. GraphQL is gone. No manifest was ever published.
  │
  ├─ 1. Connect wallet
  │
  ├─ 2. Recovery layers A-C all fail:
  │     → No local cache (new device)
  │     → No ArNS name (never set up)
  │     → No manifest TXs found in tag scan (never published)
  │
  ├─ 3. Layer D: Global Parquet Index
  │     → Load DuckDB-WASM
  │     → Query: SELECT * WHERE owner_address = '{alice}'
  │     → Finds 5 file entities, 2 folders, 1 drive
  │     → Has names (public drive) or entity_tx_ids (private)
  │
  ├─ 4. Reconstruct drive from global index
  │     → Build folder tree from parent_folder_id relationships
  │     → Populate local database
  │     → App renders drive
  │
  └─ 5. Prompt: "Publish a manifest now to secure your data?"
        → User clicks yes → manifest published → now self-sufficient
```

**Result:** Even users who never opted in are recoverable via the global index. After recovery, they can publish their first manifest and become self-sufficient going forward.

---

### Flow 9: Snapshot Publication (background, periodic)

```
ArDrive periodically publishes snapshots for active drives (existing feature)
  │
  ├─ 1. Snapshot trigger: N files uploaded, or weekly schedule
  │
  ├─ 2. Build snapshot data
  │     → All entity metadata for the drive up to current block height
  │     → Stored as a single Arweave TX (existing ArFS snapshot format)
  │
  ├─ 3. Upload snapshot to Arweave
  │     → snapshotTxId = "snap999..."
  │     → Tags: Entity-Type=snapshot, Drive-Id=..., Block-Start=..., Block-End=...
  │
  ├─ 4. Local DB records snapshot
  │     → Used by manifest publisher to determine delta vs full
  │
  └─ 5. Next manifest publish uses this snapshot as base
        → Delta manifest references snapshotTxId
        → Delta only contains changes AFTER snapshot block height
        → Keeps manifest tiny regardless of drive size
```

**Result:** Snapshots are the bulk state. Manifests are the thin delta. Together they cover everything cheaply.

---

### Flow 10: Community Member Maintains the Global Index

```
ArDrive company is gone. Community member "Bob" maintains the index.
  │
  ├─ 1. Bob runs an AR.IO gateway (open source, already syncing Arweave)
  │
  ├─ 2. Weekly: export new ArFS entities since last partition
  │     → DuckDB query against gateway's local index
  │     → Export to Parquet file (~5 MB for one week of activity)
  │
  ├─ 3. Upload new tip partition to Arweave via Turbo
  │     → Cost: ~$0.10
  │
  ├─ 4. Update global index manifest.json
  │     → Add new partition to list
  │     → Upload updated manifest
  │     → Update ArNS: ardrive-global-index.ar → new manifest TX
  │
  ├─ 5. Monthly: finalize completed partitions
  │     → When a 50K-block range fills up, publish as final partition
  │     → Cost: ~$0.50
  │
  └─ 6. Total annual effort: ~1 hour/week, $11/year
        → Any individual, DAO, or grant can sustain this indefinitely
```

**Result:** The global index stays current. Costs $11/year. Bob could stop and Carol could pick up — the process is documented and automated.

---

### Flow 11: Third-Party App Uses ArDrive Data

```
Developer builds "ArDrive Explorer" — a simple file browser web app
  │
  ├─ 1. Load DuckDB-WASM in browser
  │
  ├─ 2. Point at global index: ardrive-global-index.ar
  │     → Fetch manifest.json → get partition TX IDs
  │
  ├─ 3. User enters a wallet address or ArNS name
  │
  ├─ 4. Query: SELECT * WHERE owner_address = '{address}' AND drive_privacy = 0
  │     → DuckDB byte-range fetches only relevant rows from Parquet
  │     → Returns all public drives, folders, files
  │
  ├─ 5. Render a file browser
  │     → For each file: link to https://arweave.net/{dataTxId}
  │     → No ArDrive app, no login, no GraphQL
  │
  └─ 6. Could also fetch user's manifest via ArNS for richer experience
        → Faster than global index (smaller file, pre-filtered)
```

**Result:** ArDrive data is open infrastructure. Anyone can build on it. The format (JSON manifests + Parquet) is universally readable.

---

### Flow Summary Table

| Flow | Uses manifest? | Uses global index? | Requires GraphQL? | Requires Turbo? |
|---|---|---|---|---|
| 1. Upload file | Publishes after | No | **No** | Yes |
| 2. Return same device | Cross-device sync | No | **No** | No (read-only) |
| 3. New device | **Primary load** | Fallback | **No** | No |
| 4. Upload without GraphQL | Publishes after | No | **No** | Yes |
| 5. No ArNS, no manifest | Fallback | **Primary** | **No** | No |
| 6. URL access (public) | Gateway resolves | No | **No** | No |
| 7. Private file access | Provides dataTxId | No | **No** | No |
| 8. Never synced, no manifest | N/A | **Primary** | **No** | No |
| 9. Snapshot publish | Referenced by delta | No | **No** | Yes |
| 10. Community maintains index | No | Publishes to | **No** | Yes |
| 11. Third-party app | Optional | **Primary** | **No** | No |

**GraphQL is required for: NOTHING.** It can be used as an optimization (faster incremental sync) but is never a hard dependency.

**Per-user ArNS is required for: NOTHING.** It's an optional premium feature for URL-addressable public drives. Discovery works through the central `ardrive-index.ar` for all wallet types.

**The only hard dependency is a functioning Arweave write path** (Turbo, Irys, or direct L1). Without it, ArDrive becomes read-only — but nothing is lost.

---

## Private Drive Details

### What's Encrypted vs What's Visible

**In the encrypted manifest (hidden, requires password):**
- File names
- Folder names
- Drive name
- Full path structure
- All metadata (sizes, types, dates)
- Entity TX pointers

**On Arweave tags (publicly visible regardless of manifest):**
- Entity UUIDs
- Drive ID
- Parent-folder-ID relationships
- That the entity exists and when it was created
- Cipher type used

**Assessment:** The encrypted manifest reveals NOTHING beyond what's already on public Arweave tags. It's strictly more secure than the current GraphQL-indexed state (which exposes the same tag data to anyone who queries).

### Scale of Encryption

- 38% of drives are private
- But only 2.66% of file entities are encrypted
- Private drives are overwhelmingly small or empty
- 97.3% of manifest entries will have plaintext metadata (public drives)
- The "decrypt to see names" flow affects a small minority of data

### Key Derivation (unchanged from current app)

```
Drive key = HKDF-SHA256(
    IKM: wallet.sign("drive" + driveId_uuid_bytes),
    info: password_utf8_bytes,
    salt: single_null_byte
) → 256-bit key

Manifest encryption: AES-256-GCM(manifest_json_bytes, drive_key, random_iv)
```

User needs: wallet + password + manifest TX. All available during recovery.

---

## Implementation

### What Already Exists

| Component | Location | Status |
|---|---|---|
| Manifest builder | `lib/entities/manifest_data.dart` | Built, needs metadata extension |
| Manifest uploader | `lib/manifest/domain/manifest_repository.dart` | Built |
| ArNS undername assignment | `lib/arns/domain/arns_repository.dart` | Built |
| Entity encryption (AES-GCM) | `lib/core/crypto/crypto.dart` | Built |
| Drive key derivation | `lib/core/crypto/crypto.dart` | Built |
| Sync completion detection | `lib/sync/domain/repositories/sync_repository.dart` | Built |

### What Needs to Be Built

| Component | Effort | Description |
|---|---|---|
| Extend `ManifestData` with metadata fields | 1-2 days | Add `s`, `t`, `m`, `e` to path entries |
| Auto-publish trigger after sync | 2-3 days | Wire sync completion → manifest build → upload → ArNS update |
| Encrypted manifest support | 2-3 days | Encrypt manifest JSON with drive key before upload |
| Recovery mode (load from manifest) | 3-5 days | Fallback chain: local → ArNS → tag scan → global index |
| `ardrive` metadata header in manifest | 1 day | Add drive-level metadata to manifest JSON |
| Add `setUndernameRecord()` to ario_sdk | 2-3 days | Dart binding for updating ArNS pointer |
| Global Parquet index bootstrap | 2-3 days | Export + upload + ArNS registration |
| DuckDB-WASM integration (lazy) | 3-5 days | For global index queries (recovery last-resort) |

**Total: 4-6 weeks.** First 2 weeks deliver manifests (the critical path). Remaining weeks deliver the global index safety net.

### Phase 1: Manifests (weeks 1-2)

Ship in this order:
1. Extend ManifestData with metadata fields
2. Auto-publish after sync (public drives, plaintext)
3. Auto-publish after sync (private drives, encrypted)
4. Recovery mode: fetch manifest when GraphQL unavailable
5. ArNS undername pointing

After Phase 1: **every active user has a permanent, self-contained backup of every drive.** Survives company shutdown. No new dependencies.

### Phase 2: Global Index (weeks 3-4)

1. Export all 58.1M entities from indexer to Parquet
2. Upload ~28 partitions to Arweave (~$65)
3. Register ArNS name
4. DuckDB-WASM lazy integration for browser queries
5. Recovery mode: fallback to global index when manifests not found

After Phase 2: **any user can recover from zero state with just their wallet.**

### Phase 3: Community Handoff (weeks 5-6)

1. Standalone recovery tool (simple web page)
2. Documentation: how to maintain the global index
3. Automated maintenance scripts (export new partitions, upload)
4. Open-source everything with instructions

---

## Ongoing Costs

### Per-User (paid by user, automatic)

| User type | Publish type | Size per sync | Cost per sync | Annual (weekly syncs) |
|---|---|---|---|---|
| Most users (89%, < 100 files) | Full (always) | < 15 KB | < $0.001 | < $0.05 |
| Active user (1K files) | Full (always) | ~120 KB | ~$0.002 | ~$0.10 |
| Power user (10K files) | **Delta** | ~6 KB | ~$0.0001 | ~$0.005 |
| Heavy user (100K files) | **Delta** | ~6 KB | ~$0.0001 | ~$0.005 |
| Whale (2.78M files) | **Delta** | ~6 KB | ~$0.0001 | **~$0.005** |

With delta publishing, ALL users pay effectively the same: **< $0.10/year** regardless of drive size. The snapshot absorbs the bulk; the manifest is just the thin delta layer on top.

### Community Maintenance (global index)

| Task | Frequency | Annual cost |
|---|---|---|
| Tip partition update | Weekly | ~$5 |
| Partition finalization | Monthly | ~$6 |
| ArNS renewal (if leased) | Annual | ~40 ARIO |
| **Total** | | **~$11/year** |

---

## What This Guarantees

**For every ArDrive user, after one sync with manifests enabled:**

1. Your drive catalog is permanently on Arweave
2. Your ArNS name points to it (cross-device, instant discovery)
3. Public files are URL-addressable: `photos_you.ar/sunset.jpg`
4. Private files are recoverable with wallet + password
5. No company, API, gateway, or GraphQL required
6. Any HTTP client can fetch your manifest and file data
7. The format is standard JSON — readable by any programming language
8. Previous manifests remain on Arweave as version history

**For the ecosystem:**

9. Global index enables search, analytics, and third-party tools
10. $11/year keeps the index current — any individual or DAO can maintain it
11. Community can build alternative ArDrive clients from the index
12. The entire system is documented and open-source

---

## Failure Mode Analysis

| What fails | Impact | Recovery |
|---|---|---|
| ArDrive company shuts down | No new app updates | Manifests + global index still work. Community forks app. |
| All GraphQL gateways go down | No incremental sync | Load from manifest (snapshot). Miss recent uploads until gateways return. |
| ArNS goes down | Can't resolve names | Tag scan finds manifests by owner address. |
| Arweave gateways go down | Can't fetch anything | Connect to raw Arweave nodes (HTTP API). Data is replicated across network. |
| User forgets password | Can't decrypt private drives | Public drives still accessible. Private drives unrecoverable (by design — same as today). |
| User loses wallet | Can't prove ownership | Unrecoverable (by design — same as today). |
| Global index becomes stale | New users after last update not in index | Manifests still work. New users self-publish manifests — discoverable via tag scan until index catches up. |
| Whale publishes 330 MB manifest | Expensive for them | Their choice. Could paginate in future. Only affects 1 drive. |

**No single failure loses data.** Multiple independent recovery paths exist for every scenario except "lost wallet" and "forgot password" — which are unrecoverable by design in any system.

---

## Community Handoff Checklist

### Before release to community

- [ ] Phase 1 shipped: manifests auto-publish for all active users
- [ ] Phase 2 shipped: global Parquet index on Arweave
- [ ] All active users have at least one published manifest
- [ ] ArNS names registered (permanent purchase, not lease)
- [ ] Standalone recovery tool published (HTML page, no app dependency)
- [ ] Maintenance scripts open-sourced (GitHub Actions workflow)
- [ ] Documentation: "How to maintain ArDrive's global index for $11/year"
- [ ] Documentation: "How to build an ArDrive client from manifests"
- [ ] Format spec: extended manifest JSON schema documented

### The promise to users

> **Your files are permanent. Your catalog is permanent.**
> Public files are addressable by URL. Private files decrypt with your password.
> One sync gives you a permanent backup. $0.001 per update.
> Any HTTP client can read your manifest. Any browser can access your files.
> No company required. No API required.
> $65 built the safety net. $11/year maintains it.
> **Your data is yours. Forever.**
