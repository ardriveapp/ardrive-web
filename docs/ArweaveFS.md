# Arweave File System "ArFS" (version 0.15)

ArweaveFS is a data model designed to emulate file systems on Arweave.

Due to Arweave's permanent, immutable nature traditional file system operations such as file/folder renaming and moving, and file updates cannot be done by simply updating the on-chain data model. ArweaveFS works around this by defining an append only transaction data model that allows the state of the file system to be constructed on the client.

## Entity Data Model

ArweaveFS defines several entities for storing file system state on Arweave. These entities have their data split between being stored as tags on their transaction or encoded as JSON as the data of their transaction.

Drive entities require a single metadata transaction, with standard Drive tags and encoded JSON with secondary metadata.
Folder entities require a single metadata transaction, with standard Folder tags and an encoded JSON with secondary metadata.
File entities require a metadata transaction, with standard File tags and an encoded JSON with secondary metadata.
File entities also require a second data transaction, which includes a limited set of File tags and the actual file data itself.
Snapshot entities require a single data transaction, with standard Snapshot tags and encoded JSON with GQL plus JSON metadata (Base64-encoded if private) on it.
Drive State entities require a single data transaction, with standard Drive State tags and a SQLite database of the drive's parsed state (encrypted with the drive key if private) on it.
Drive Signature entities require a single data transaction, with standard Drive Signature tags and an encrypted wallet signature on it.
Publication entities (experimental) require a single transaction: an Arweave path manifest with standard Publication tags.

MetaData stored in any transaction tags will be defined in the following manner:

```
Example-Tag: "example-data"
```

While MetaData stored any JSON in the transaction will be defined in the following manner:

```
{
    "exampleField": "exampleData"
}
```

Fields suffixed with `?` are optional.

Field enum values are defined in the format "value 1 | value 2".

All metadata transactions that store these entities unencrypted should define a `Content-Type` tag with value `application/json` and an `ArFS` tag with the version of ArFS specification it implements, currently `0.15`.

### Version history

Old entities stay valid. Readers must accept entities tagged `ArFS: 0.10` to `ArFS: 0.15` (the ArDrive web app accepts exactly 0.10, 0.11, 0.12, 0.13, 0.14 and 0.15). A writer tags every entity with the current version.

| Version | Added |
|---|---|
| 0.12 | The baseline for this document. |
| 0.13 | The optional `pinnedDataOwner` field in File metadata JSON: a File entity that pins data owned by another address. |
| 0.14 | The optional `isHidden` field in File and Folder metadata JSON. A hidden entity stays on the drive but is not shown by default. |
| 0.15 | The `Signature-Type` tag on Drive entities and the Drive Signature entity (see Drive privacy). |

Three additions are not tied to a version bump. They were written under `ArFS: 0.15` and no later version exists:

- Drive State and Publication entities (Drive State from August 2026, Publication from October 2026 in the ArDrive web repository).
- The optional `dataContentEncoding` field in File metadata JSON (`"gzip"` when the stored data is gzip; November 2026 in the ArDrive web repository), the metadata side of the `Content-Encoding: gzip` data tag of a public file. A reader that does not know it ignores it.
- The optional `assignedNames` field in File metadata JSON, a list of ArNS names that point at the file. It is a hint: a reader checks a name against ArNS before showing it. It dates from September 2024, under `ArFS: 0.14`.

These dates and fields come from the history of the ArDrive web code. The ArFS version number was bumped there at the commits that added the hide flag (0.14, December 2023) and the signature type (0.15, April 2025). The 0.13 bump (August 2023) came with the pin feature. This repository does not hold the original 0.13 and 0.14 specification texts, so the exact boundary of the earlier versions is taken from the code.

## Drive Privacy

Drives can store either public or private data, indicated by the `Drive-Privacy` tag on the drive entity.

If a Drive entity is private, an additional tag `Drive-Auth-Mode` is used to indicate how the Drive Key is derived. ArDrive clients currently leverage a secure `password` along with the Arweave Wallet private key signature to derive the global Drive key.

On every encrypted entity, a `Cipher` tag must be specified. The required public parameters for decrypting the data must also be specified with the parameter's tag name prefixed by `Cipher-*` eg. `Cipher-IV`. If the parameter is byte data it should be encoded as Base64 in the tag. ArDrive web writes URL-safe Base64 without padding and ardrive-core-js writes standard Base64, so a reader must accept both alphabets. ArDrive clients leverage AES256-GCM for symmetric encryption, which requires a Cipher Initialization Vector consisting of 12 random bytes. File data larger than 100 MiB is encrypted with AES256-CTR instead (`Cipher: AES256-CTR`); a reader must pick the decryption from the `Cipher` tag.

Additionally, all encrypted transactions should have the `Content-Type` tag `application/octet-stream` as opposed to `application/json`.

Private drives have a global drive key, `D`, and multiple file keys, `F`, for encryption. `D` is used for encrypting both Drive and Folder metadata whereas `F` is used for encrypting File metadata and the actual stored data. Having these different keys, `D` and `F`, allows a user to share specific files without revealing the contents of their entire drive.

`D` is derived using HKDF-SHA256 with an unsalted RSA-PSS signature of the drive's id and a user provided password. `F` is also derived using HKDF-SHA256 with the drive key and the file's id. A reference implementation is available [here](private_drive_kdf_reference.dart).

**Password encoding.** For `D`, the HKDF input key material is the wallet signature and the HKDF `info` is the password's UTF-8 bytes, once. For an ASCII password this is the same in every client.

ardrive-core-js (and so the ArDrive CLI and desktop app that use it) historically encode the password twice: its UTF-8 bytes are read as one character per byte, and that string is encoded as UTF-8 again. For a password with a non-ASCII character the two forms differ: `ä` is `c3 a4` in the canonical form and `c3 83 c2 a4` in the double-encoded form. A drive made by core-js with such a password has a key from the double-encoded form.

So a reader that unlocks a drive with a non-ASCII password must try the canonical form first and the double-encoded form second. A writer must use the canonical form. The ArDrive web app does this (`lib/locked_drives/domain/drive_password_info.dart`).

**Signature type.** A Drive entity may carry `Signature-Type`. A drive without it is `1`. The type says how the wallet signature in `D` was made:

- `1`: the wallet signs the bytes of `drive` followed by the drive id's 16 bytes.
- `2`: the wallet signs an ANS-104 data item with those same bytes as data, no target or anchor, and the tag `Action: Drive-Signature-V2`. The signature must be RSA-PSS with a salt of length 0, so it is unique. This lets a wallet that only signs data items (such as a browser wallet) make a drive key.

### Drive

A Drive is a logical grouping of folders and files. All folders and files must be part of a drive, and reference the Drive ID.

When creating a Drive, a corresponding folder must be created as well. This folder will act as the Drive Root Folder. This seperation of drive and folder entity enables features such as folder view queries.

```
ArFS: 0.15
Cipher?: AES256-GCM
Cipher-IV?: <12 byte initialization vector as Base64>
Content-Type: <application/json | application/octet-stream>
Drive-Id: <uuid>
Drive-Privacy: <public | private>
Drive-Auth-Mode?: password
Entity-Type: drive
Signature-Type?: <1 | 2>
Unix-Time: <seconds since unix epoch>

{
    "name": "<user defined drive name>",
    "rootFolderId": "<uuid of the drive root folder>"
}
```

### Folder

A Folder is a logical grouping of other folders and files. Folder entity metadata transactions without a parent folder id are considered the Drive Root Folder of their corresponding Drives. All other Folder entities must have a parent folder id. Since folders do not have underlying data, there is no Folder data transaction required.

```
ArFS: 0.15
Cipher?: AES256-GCM
Cipher-IV?: <12 byte initialization vector as Base64>
Content-Type: <application/json | application/octet-stream>
Drive-Id: <drive uuid>
Entity-Type: folder
Folder-Id: <uuid>
Parent-Folder-Id?: <parent folder uuid>
Unix-Time: <seconds since unix epoch>

{
    "name": "<user defined folder name>"
}
```

### File

A File contains actual data, like a photo, document or movie. File entity metadata transactions do no include the actual File data they represent. Instead, the File data must be uploaded as a separate transaction, called the File data transaction. The File metadata transaction JSON references the File data transaction for retrieval. This separation allows for file metadata to be updated without requiring the file data to be reuploaded.

```File MetaData Transaction
ArFS: 0.15
Cipher?: AES256-GCM
Cipher-IV?: <12 byte initialization vector as Base64>
Content-Type: <application/json | application/octet-stream>
Drive-Id: <drive uuid>
Entity-Type: file
File-Id: <uuid>
Parent-Folder-Id: <parent folder uuid>
Unix-Time: <seconds since unix epoch>

{
    "name": "<user defined file name with extension eg. happyBirthday.jpg>",
    "size": <computed file size - int>,
    "lastModifiedDate": <timestamp for OS reported time of file's last modified date represented as milliseconds since unix epoch - int>
    "dataTxId": "<transaction id of stored data>",
    "dataContentType": "<the mime type of the data associated with this file entity>",
    "dataContentEncoding?": "gzip"
}
```

The File data transaction contains limited information about the file, such as the information required to decrypt it or the Content-Type (mime-type) needed to view in the browser.

```File Data Transaction
Cipher?: AES256-GCM
Cipher-IV?: <12 byte initialization vector as Base64>
Content-Type: <file mime-type | application/octet-stream>
Content-Encoding?: gzip
 { File data }
```

A file whose stored data is gzip says so in its metadata with the optional `dataContentEncoding` field, `"gzip"` being the only value defined. A writer includes it whenever the stored data is gzip and leaves it out otherwise (never null, never an empty string); a reader ignores a value it does not know. `size` is the length of the decoded content, and `dataContentType` stays the type of the decoded content.

A public file's data transaction MAY also carry `Content-Encoding: gzip`, written together with the field. A gateway sends the data with the same `Content-Encoding` header and a client decodes it, so a reader that goes through a gateway never has to know. A reader that fetches the bytes some other way (directly from a node, or from a bundle) does not get that decoding for free and must decode the data itself when `dataContentEncoding` is `gzip`. A reader that asks for a byte range of such a file is asking for ranges of the stored (gzipped) bytes, which cannot be resumed from a count of decoded bytes.

The intended convention for private data, which ArDrive does not write yet: the file carries only the field and never the `Content-Encoding` tag, because the tag is readable by anyone and a gateway cannot decode what it cannot decrypt. The field sits in the encrypted metadata, so the reader decrypts, then decodes. Only unencrypted data is written compressed today, for compressed text and code (public drives; see `docs/DEPLOYMENT_COMPRESSION.md`).

A reader that acts on the field should cross-check it against the response header, the data item's tag or the gzip magic bytes (`1f 8b`), and not trust the JSON alone.

## Snapshot

A Snapshot is a transaction that contains a list of all transactions belonging to a drive. This allows for a client to quickly retrieve all transactions of a specific drive without having to query for each transaction individually. This is particularly useful for big drives with many transactions.

```Snapshot Transaction
ArFS: 0.15
Drive-Id: <drive uuid>
Entity-Type: snapshot
Content-Type: <application/json | application/octet-stream>
Block-Start: <start block height of the snapshot>
Block-End: <end block height of the snapshot>
Data-Start: <first block where there's data on the snapshot>
Data-End: <last block where there's data on the snapshot>

{ Snapshot Data }
```

The snapshot data is a JSON array of objects containing `gqlNode` and `jsonMetadata` fields. The `gqlNode` field contains the transaction node returned from GQL, and the `jsonMetadata` field contains the transaction's JSON metadata (Base64-encoded if private). It is `null` for entities whose body is not JSON metadata: snapshots, drive state artifacts and publications. Their nodes are still listed, and readers that need their data fetch it by transaction ID.

```Snapshot Data
[
    {
        "gqlNode": "<transaction>",
        "jsonMetadata": "<transaction metadata>"
    },
    ...
]
```

## Drive Signature

A Drive Signature entity stores a version 1 drive's wallet signature, encrypted, so that the drive key can be made from a wallet that can only make version 2 signatures. It is an ANS-104 data item whose data is the version 1 signature encrypted with the drive's version 2 key.

```Drive Signature Transaction
ArFS: 0.15
Drive-Id: <drive uuid>
Entity-Type: drive-signature
Signature-Format: <1>
Cipher: AES256-GCM
Cipher-IV: <12 byte initialization vector as Base64>

{ the encrypted version 1 wallet signature }
```

## Drive State

A Drive State entity holds a drive's whole parsed state, up to a block height, in one SQLite database published by the drive's owner. A client imports it in one step and then queries only later blocks, instead of replaying every entity. It is a cache: a client that cannot use one syncs from snapshots and GQL as before.

```Drive State Transaction
ArFS: 0.15
Drive-Id: <drive uuid>
Entity-Type: drive-state
Drive-State-Id: <uuid of this drive state>
State-Version: <major.minor, eg 0.2>
Content-Type: application/octet-stream
Block-Start: 0
Block-End: <the producer's synced block height>
Data-Start: <first block where there's data>
Data-End: <last block where there's data>
Entity-Count: <drive, folders and files in the data>
Unix-Time: <seconds since unix epoch>
Cipher: AES256-GCM            (private drives only)
Cipher-IV: <12 byte IV, base64url>  (private drives only)

{ SQLite database, optionally gzipped, then AES256-GCM with the drive key if private }
```

The published specification is the Drive State section of the ArFS entity types page on docs.ar.io (`ar-io-docs`, `content/build/advanced/arfs/entity-types.mdx`), with the read order in `reading-data.mdx`. The design and its reasoning are in `docs/DRIVE_STATE_ARTIFACT.md`, and the exact schema a reader compares is `lib/drive_state_sqlite/drive_state_artifact_schema.dart`.

## Publication

**Experimental.** The Publication entity was added under ArFS 0.15 and its format may change. A reader must ignore fields it does not know, in tags and in `publication.json`, and must ignore `Publication-Version` values it does not know. A writer must not assume a reader exists for it.

A Publication is a drive, one folder of it, or one file, published by the drive's owner as a permanent web page. The entity is an Arweave path manifest. Opening `https://<gateway>/<publication tx id>/` shows the page. How a client shows it, and the gateway and viewer mechanics, are described in [PUBLICATIONS.md](PUBLICATIONS.md).

A publication is permanent. ArFS has no way to delete or retract one, and there is no tombstone entity. A new version of a publication supersedes the earlier one in lists, but every version stays readable at its own link for ever.

```Publication Transaction
ArFS: 0.15
Drive-Id: <drive uuid>
Entity-Type: publication
Publication-Id: <uuid, kept by every version of this publication>
Publication-Scope: <drive | folder uuid | file>
Publication-File-Id?: <file uuid, on a file page only; never File-Id, which file lookups match alone>
Publication-Version: <1 for a public drive or folder, 2 for a file, 3 for a private drive or folder>
Content-Type: application/x.arweave-manifest+json
Unix-Time: <seconds since unix epoch>
Keyword?: <a word the owner chose>   (repeated)

{ arweave/paths manifest }
```

`Publication-Version` is written to the same number as the `publication.json` `version`. No reader reads the tag and nothing checks it against the JSON. It exists for future compatibility. The `version` in `publication.json` is what a reader acts on. Neither is related to the ArFS version.

The manifest and `publication.json` are never encrypted, so a client can read them without a drive key. A private drive or folder page keeps its contents in encrypted parts of its own, under Private publications.

### Manifest

The manifest has the paths below. The rest of its paths are the files of the web app release it pins, each by transaction ID. A private drive or folder page has other paths, under Private publications.

| Path | Points at |
|---|---|
| `index.html` (also the manifest index and its fallback) | The release's `index.html` with the title, description, icons and social card written into its head |
| `publication.json` | The publication's settings (below) |
| `snapshot` | A Drive State entity of the drive, by the same owner. Public drive and folder pages only |
| `icon-32.png`, `icon-180.png`, `icon-512.png`, `cover.jpg` | The publication's images, when the owner set them |
| `social.jpg` | The social card. Always written on a public page: the owner's image, or a generated card |
| `files.html`, `sitemap.xml` | The publication's files as gateway links, for clients that run no script. At most 5,000 files are listed. Public drive and folder pages only |

Every file the publish uploads, other than the Drive State, is a plain data item carrying `Publication-Id` and no `Entity-Type`. None is an ArFS entity, and none appears in the drive.

### publication.json

`publication.json` is a JSON object. A reader reads these keys. Types are JSON types. This table is versions 1 and 2; version 3 is under Private publications.

| Key | Type | Required | Rule |
|---|---|---|---|
| `version` | integer | yes | At least 1. 1 for public drive and folder pages, 2 for file pages, 3 for private drive and folder pages. A reader that does not know the value must refuse the page as "needs a newer client" and read no other field |
| `driveId` | string | yes | A UUID in lowercase |
| `rootFolderId` | string | yes | A UUID in lowercase: the drive's root folder |
| `scope` | object | yes | `{"type":"drive"}`, `{"type":"folder","folderId":"<uuid>"}` or `{"type":"file","fileId":"<uuid>"}`, with lowercase UUIDs |
| `privacy` | string | yes | `public` or `private` |
| `owner` | string | yes | The Arweave address of the publisher: 43 base64url characters |
| `title` | string | yes | Not empty after trimming. Shown as plain text. Writers keep it to 60 characters; readers do not enforce this |
| `description` | string | no | Plain text. Writers keep it to 160 characters; readers do not enforce this |
| `ownerName` | string | no | A display name the owner typed. A claim, not a proof. Writers keep it to 40 characters |
| `snapshot` | object | yes for drive and folder pages; must be absent on a file page | See below |
| `file` | object | yes on a file page | See below |
| `fileCount` | integer | no | At least 0. What the publisher counted |
| `keywords` | array of strings | no | Also written as `Keyword` tags. Writers allow at most 5, each clipped to 32 characters; readers do not validate either |
| `license` | object | no | `name`, `shortName` and `definitionTxId` (all required strings, the last a 43-character transaction ID), and optional `params`, an object of string values |
| `images` | object | no | Optional `icon`, `social` and `cover`: each a plain relative path inside the manifest |
| `publishedAt` | string | no | An ISO 8601 date |
| `names` | array of strings | no | ArNS names the owner pointed at this version. A hint, checked against a gateway before it is shown. Entries that are not non-empty strings are dropped |
| `viewer` | object | no | `release` (string) and `manifest` (a 43-character transaction ID): the web app release the page pins |
| `generatedSocialCard` | boolean | no | `true` when `social.jpg` is the generated card. Read only by the publishing client |

`snapshot` has `path` (a plain relative path inside the manifest), `txId` (the Drive State's transaction ID) and `tags` (an object whose values are all strings: every tag of the Drive State transaction that an importer reads). A public publication's `snapshot.tags` must not contain `Cipher` or `Cipher-IV`. A private publication's must contain both.

`file` has `dataTxId` and `metadataTxId` (43-character transaction IDs, the version of the file shown) and optional `name`, `size` (integer, at least 0), `contentType`, `cipher` and `cipherIv`. The JSON keys are camelCase, unlike the tags. On a public file page the block may carry `name`, `size` and `contentType` and must not carry `cipher` or `cipherIv`. On a private file page it must carry `cipher` and `cipherIv` (the values on the data transaction's tags, which are not secret) and must not carry `name`, `size` or `contentType`.

A reader must refuse a `publication.json` that breaks a rule above, with these further checks: a file page must have `version` 2 or later, and `images` and `snapshot.path` must be plain relative paths (letters, digits, `.`, `_`, `-` and `/`; no leading `/`, no empty, `.` or `..` segment). A reader ignores keys it does not know.

Nothing in `publication.json` is secret. It must not contain a drive, folder or file name that is not already public. The `title` is typed by the owner.

### Versions

A manifest cannot change, so every update is a new Publication transaction with the same `Publication-Id`, at a link of its own, and with the same `Publication-Scope`.

A reader orders the versions of a publication, newest first, as follows:

1. A version not yet in a block ranks above every mined version.
2. Among mined versions, the one in the higher block ranks first.
3. Versions in the same block, or both unmined, are ordered by `Unix-Time`, higher first.

The first is the latest version. Two versions with the same block and `Unix-Time` have no defined order.

A reader drops a version that:

- has no `Unix-Time` tag that parses as an integer;
- has `Publication-Scope: file` without `Publication-File-Id`;
- has a `Publication-Scope` different from the oldest version's, since it is then not a version of that publication.

Any `Publication-Scope` value other than `drive` and `file` is read as a folder ID. It is not validated.

### File pages

A file page (`Publication-Scope: file`) shows one file. Its manifest has no `snapshot`, `files.html` or `sitemap.xml`. Its `publication.json` has `version` 2 and a `file` block. A private file page names its file's ID and transactions, as a share link does, and never the file. The file key travels only in the page link's fragment.

### Private publications

A private publication is a page of a private drive. Two forms exist:

- **Private file pages** (`version` 2, above). They need the file key, which is not in the manifest or `publication.json`. It travels in the page link's fragment, as `#/?k=<file key>`, or the visitor pastes it.
- **Private drive and folder pages** (`version` 3, below). They have a key of their own, the publication key. The drive key never leaves the owner's device, so a folder page cannot open anything outside its folder.

The `privacy: private` form of `snapshot` above is reserved. A writer must not produce one, and a reader may refuse one. Version 3 replaces it.

#### Keys

| Key | What it is |
|---|---|
| Publication key | 32 random bytes, made when the publication is first published. Every version of the publication keeps it. It decrypts the sealed block |
| Catalog key | 32 random bytes for one catalog. It is inside the sealed block, never in the clear |
| File keys | The ArFS file keys of the files in scope, derived from the drive key as usual. They are inside the sealed block |

The publication key reaches a visitor in one of three ways:

1. In the link: `https://<gateway>/<publication tx id>/#/?k=<publication key>`. The key is in the hash route, so it never reaches a server.
2. Pasted by the visitor, when the link has no key and the owner sent the key separately.
3. Unwrapped from a password slot by a password the visitor types.

The owner gets it from the owner slot, with the drive key.

Anyone who has the publication key can open every version of the publication. A file keeps its key across revisions, so they can also decrypt any revision of a file that was ever in scope. A writer cannot take access back: every version stays on Arweave and keeps its slots. So a writer must not offer to change or remove a password. It may add a password slot to a later version. A later version carries its slots forward byte for byte; a writer never wraps the key again under a key that was already used.

#### Encodings

Keys, salts, IVs and ciphertexts are base64url without padding. A reader refuses one that is not the canonical encoding of its bytes. All AES-256-GCM ciphertexts are the ciphertext followed by the 16-byte tag. IVs are 12 random bytes and never reused under one key.

#### Manifest of a version 3 page

| Path | Points at |
|---|---|
| `index.html` | As for any publication. It also carries `<meta name="robots" content="noindex">` |
| `publication.json` | The settings (below) |
| `sealed` | The sealed block (below) |
| `catalog` | The catalog (below) |
| `icon-32.png`, `icon-180.png`, `icon-512.png`, `cover.jpg`, `social.jpg` | Only the images the owner set. No social card is generated |

There is no `snapshot`, `files.html` or `sitemap.xml`. `sealed` and `catalog` are plain data items carrying `Publication-Id`, no `Entity-Type` and `Content-Type: application/octet-stream`. The catalog is never tagged as a Drive State, so sync never finds it.

#### publication.json, version 3

| Key | Type | Required | Rule |
|---|---|---|---|
| `version` | integer | yes | 3 |
| `publicationId` | string | yes | The `Publication-Id` tag's value: a lowercase UUID. Slots and the sealed block are bound to it |
| `driveId` | string | yes | A lowercase UUID |
| `scope` | object | yes | `{"type":"drive"}` or `{"type":"folder","folderId":"<uuid>"}`. The folder ID is already public in `Publication-Scope` |
| `privacy` | string | yes | `private`. A version 3 page is always private |
| `owner` | string | yes | As in version 1 |
| `sealed` | object | yes | `path` (a plain relative path), `txId` (the sealed block's transaction ID), `cipher` (`AES256-GCM`) and `iv` |
| `slots` | array | yes | Objects, below. A writer writes exactly one owner slot and at most one password slot. A reader reads only the first slot of each `type` and ignores types it does not know |
| `title` | string | yes | May be empty. A reader shows "Private page" for an empty title |
| `description`, `ownerName`, `keywords`, `license`, `images`, `publishedAt`, `names`, `viewer` | | no | As in version 1 |

A version 3 `publication.json` must not have `rootFolderId`, `snapshot`, `file` or `fileCount`. A reader refuses one that does, and one larger than 64 KiB. Nothing in it is secret: it holds no drive, folder or file name, no count of files and no key except wrapped ones. What stays visible: whether the page has a password, and the sizes of `sealed` and `catalog`, which show roughly how many files and folders it has.

**Password slot:**

```json
{ "type": "password", "kdf": "argon2id", "salt": "…", "m": 65536, "t": 3, "p": 1,
  "cipher": "AES256-GCM", "iv": "…", "wrapped": "…" }
```

1. Normalise the password to Unicode NFC and encode it as UTF-8. Any password is allowed, including an empty one; the writer warns about weak ones.
2. Run Argon2id (RFC 9106, version 0x13) over it with the slot's `salt` (at least 16 random bytes), memory `m` in KiB, `t` passes and `p` lanes, with no secret and no associated data, for 32 bytes.
3. Those 32 bytes are the key that wraps: `wrapped` is the AES-256-GCM encryption of the publication key under it, with the slot's `iv` and the associated data `ArDrive publication slot v1|<publicationId>` in UTF-8.

A reader never runs a password slot with `m` outside 8192 to 262144, `t` outside 1 to 10, `p` outside 1 to 4, a salt outside 16 to 64 bytes, or any field it cannot read. The page can still open by key. Writers use a 16-byte salt and `m` 65536, `t` 3, `p` 1 unless a release raises them. The slot's associated data does not cover these settings. It doesn't need to: changing one changes the key that wraps.

**Owner slot:**

```json
{ "type": "owner", "kdf": "hkdf-sha256", "cipher": "AES256-GCM", "iv": "…", "wrapped": "…" }
```

The key that wraps is HKDF-SHA256 (RFC 5869) over the drive key (32 bytes; a reader refuses any other length), with an empty salt and the info `ArDrive publication owner v1|<publicationId>` in UTF-8, for 32 bytes. It is made for this one publication, and the drive key itself never wraps anything. `wrapped` is as in a password slot.

#### The sealed block

The `sealed` path holds AES-256-GCM, under the publication key, with `sealed.iv`, of a JSON object in UTF-8. Writers write it with sorted keys and no whitespace; readers accept any JSON. A reader refuses a sealed part larger than 32 MiB before decrypting it.

Its associated data binds it to the page: `ArDrive publication sealed v1|` followed by this header as JSON with sorted keys and no whitespace, in UTF-8:

```json
{"description":"<description, or empty>","driveId":"…","owner":"…","publicationId":"…","scope":{…},"title":"…"}
```

`scope` holds only `type` and, for a folder, `folderId`. A sealed part copied under another drive, owner, scope, title or description does not open. Images and the manifest's other paths are not covered.

A reader refuses a sealed block that breaks these rules:

| Key | Type | Rule |
|---|---|---|
| `v` | integer | 1. A reader refuses other values |
| `scope` | object | Equal to `publication.json`'s `scope` |
| `rootFolderId` | string | The drive's root folder: a lowercase UUID |
| `catalog` | object | `path` (a plain relative path), `txId`, `key` (the catalog key, 32 bytes) and `tags` (string values: the tags an importer reads, as `snapshot.tags` in version 1, with `Cipher: AES256-GCM` and a 12-byte `Cipher-IV` describing the catalog's encryption) |
| `files` | object | Lowercase file ID to file key (32 bytes), for every file in the catalog. The number of entries is the page's file count |
| `ciphers` | object | Transaction ID to `{"cipher", "iv"}`: the `Cipher` and `Cipher-IV` tags of each file's data and thumbnails. For `AES256-GCM` and `AES256-CTR` the `iv` must be canonical base64url. An entry with another cipher is ignored, and a transaction missing here is looked up as usual |

A reader ignores keys it does not know.

#### The catalog

The catalog is a Drive State artifact ([DRIVE_STATE_ARTIFACT.md](DRIVE_STATE_ARTIFACT.md)) holding only the publication's scope: the folder and everything under it, or the whole drive, each at its current version. Hidden items are left out completely. It is serialised, gzipped and encrypted with AES-256-GCM under the catalog key, like a private Drive State under its drive key, and read by the same importer with the catalog key in place of the drive key.

#### Opening a version 3 page

A reader tries, in order: the link's `k`; what the visitor typed, as a publication key if it is the canonical spelling of 32 bytes, then as a password against the password slot; and, for the owner, the owner slot. A password of 43 base64url characters is therefore still tried as a password. A malformed `k` is passed over, not an error. A key opens the page when the sealed block decrypts and passes the checks above. A failed attempt is not an error the visitor sees, only "That didn't open this page."

The test vectors in `test/publication/fixtures/sealed/vectors.json`, written by `tool/publication/vectors.mjs`, hold every step above, a page of each scope, and pages a reader must refuse. A client must pass them.

### Owner

A publication counts only if the drive's owner published it. Anyone can write a manifest with any `owner` and any `Drive-Id`.

What the ArDrive viewer checks today: it asks the serving gateway who signed the `snapshot` transaction (for a file page, the `file.metadataTxId` transaction), and refuses the page only if that signer is not `publication.json`'s `owner`. If the gateway cannot answer, the page opens as declared. On a version 3 page it checks the signer of `sealed.txId` the same way, and once the page opens, of the catalog's `txId`. For a file page, when the lookup also returns the transaction's tags, the viewer checks too that it is a `file` entity with the page's file ID and drive ID. The viewer does not check who signed the manifest, and does not check that `owner` owns the drive. The list of an owner's own publications is scoped to the signed-in owner's transactions.

A full client should check all of these, and fail closed:

1. The Publication transaction was signed by the drive's owner (the signer of the Drive entity).
2. `publication.json`'s `owner` equals that signer.
3. The `snapshot` (or the file's metadata) was signed by the same owner.

### Discovery

A client finds a drive's publications by querying the owner's transactions with `Entity-Type: publication` and the `Drive-Id`, and groups them by `Publication-Id`.

### Other clients

ardrive-core-js and the ArDrive CLI query by `Entity-Type`, so they do not see publications and are not affected by them.

Clients that sync a drive's history should skip `publication` entities (and `drive-state` and `snapshot` ones) without fetching their data. ArDrive web builds up to v2.90.0 do not skip them: they download each manifest during a sync and discard it. Only newer builds skip.

## Creating a Drive

To properly create a new drive, two new entities need to be created, a new Drive entity and a new Folder entity representing the root folder of that drive.

The `name` of the drive and folder entity should be the same. The drive entity's `rootFolderId` should refer to the `Folder-Id` of the root folder entity. The folder entity should not include a `Parent-Folder-Id` tag.

The Drive's privacy settings must also be determined in order for its subfolders and files to have the right security settings.

## Updating and Constructing the File System State

To update the file system clients can simply create transactions for the entities they would like to update, making sure to specify the same entity id as the update target. For example, to move a folder to another folder, the client can create a transaction with that same folder entity's fields pointing to a different parent folder.

Clients can then create a timeline of entity write transactions which the client can replay to construct the Drive state. This timeline of transactions should be grouped by the block number of each transaction. At every step of the timeline, the client can check if the entity was written by an authorised user. This also conveniently enables the client to surface a trusted entity version history to the user.

The `Unix-Time` defined on each transaction should be reserved for tie-breaking same entity updates in the same block and should not be trusted as the source of truth for entity write ordering. This is unimportant for single owner drives but is crucial for multi-owner drives with updateable permissions (currently undefined in this spec) as a malicious user could fake the `Unix-Time` to modify the drive timeline for other users.

ArweaveFS utilises a bottom-up data model (files refer to parent folder, folders refer their parent folder etc) to avoid race conditions in file system updates. A top-down data model would require the parent model (ie. a folder) to store references to its children. When multiple users update the parent entity with new children, there's no way to do so in a consistent manner as a user's update to the parent model will not be seen by another user until the transaction has been mined.

## Extending the Arweave File System Schema

Web app and clients can extend the ArFS Schema as needed by adding additional tags into the File and Folder MetaData Transaction JSON. This gives Developers additional flexibility to support specific application needs, without breaking the overall data model or impacting privacy.

For example a Music Sharing App could use the following expanded File Metadata for specific music files.

```Expanded File MetaData Transaction JSON Example
{
    "name": "<user defined file name>",
    "size": <computed file size - int>,
    "lastModifiedDate": <timestamp for OS reported time of file's last modified date represented as milliseconds since unix epoch - int>
    "dataTxId": "<transaction id of stored data>",
    "dataContentType": "<the mime type of the data associated with this file entity>"
    "dataContentEncoding?": "gzip"
    "bandName": "<the name of the band/artist>"
    "bandAlbum": "<the album of the band/artist>"
    "albumSong": "<the title of the song>"
}
```

Additionally, the above extended MetaData fields could be added directly as a transaction tag as well, in order to support GraphQL queries. However, it is important to not overload transaction tags for optimal performance.

## Additional Client Concerns

### Folder/File Paths

ArweaveFS does not store folder or file paths along with entities as these paths will need to be updated whenever the parent folder name changes which can require many updates for deeply nested file systems. Instead, folder/file paths are left for the client to generate from the folder/file names.

### Client Syncing

Drives that have been updated many times can have a long entity timeline which can be a performance bottleneck. To avoid this clients can cache the drive state locally and sync updates to the file system by only querying for entities in blocks higher than the last time they checked.

### Folder View Queries

Clients that want to provide users with a quick view of a single folder can simply query for an entity timeline for a particular folder by its id. Clients with multi-owner permissions will additionally have to query for the folder's parent drive entity for permission based filtering of the timeline.

### Browser wallet identities

Solana and Ethereum sign-in in ArDrive derive the Arweave wallet that owns the ArFS entities. This is an ArDrive client convention and not part of ArFS: see [BROWSER_WALLET_IDENTITIES.md](BROWSER_WALLET_IDENTITIES.md).

## Future Work

### GraphQL

GraphQL currently has a limit of 100 items returned per query.

GraphQL is not optimized for ArDrive specific queries for drive, folder and file entity data.

### Multi-User Dynamic Permissioned Drives

A drive can have a dynamic set of users that are able to write to it. This will take advantage of the entity timeline for filtering of malicious/invalid entities.

ArweaveFS does not store folder or file paths along with entities as these paths will need to be
[kdf]: https://en.wikipedia.org/wiki/Key_derivation_function
