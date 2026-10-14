# Library pages

> **Status: PLAN.** Not built, and blocked on the drive state artifact landing
> first. A library page maps an ArNS name to an ArDrive drive or folder so the
> name opens a browsable page, public or private. Evidence is cited to file and
> line; gateway behaviour was measured against live gateways in October 2026.

## What this is for

An owner points `phils-archive.ar.io` at a drive, or at one folder of it, and
anyone who opens that name gets a browsable page. A public drive opens with no
key. A private drive opens once the visitor supplies the drive key.

The shipped app can assign an ArNS name to one file and to a manifest, so a name
can already point at one object. It cannot point at a library, because nothing
generates the page that lists one and nothing serves the catalog that page would
read.

## Vocabulary

One term, one meaning, in this document and in the UI:

| Term | Means |
|---|---|
| Library page | What a visitor opens at the name |
| Publish, republish | The action that writes it |
| Drive state artifact, or artifact | The published catalog the page reads (`DRIVE_STATE_ARTIFACT.md`) |
| Manifest | The Arweave path manifest that serves the page and its files |
| Name | The ArNS record pointing at that manifest |

**Publish is not Share**, and the UI says so. Share hands someone a link to what
already exists, writes nothing to Arweave and costs nothing. Publish writes
permanent objects to Arweave, costs an upload, and cannot be undone.

## It is built on the drive state artifact

A library page invents no data format. The drive state artifact already carries
what the explorer renders: the drive, both entry tables, all three revision
tables and licenses (`DECISIONS.md` D2), signed as a data item, gzipped, and
encrypted under the drive key when the drive is private. Its read path is
already the one a static page needs: resolve a name, fetch bytes, verify the
signature, decrypt, read, with GraphQL nowhere in it (`DRIVE_STATE_ARTIFACT.md`
§4.1).

Three consequences:

- **No listing file.** An earlier revision of this plan proposed publishing a
  separate JSON catalog beside the manifest. That duplicated the artifact and is
  dropped.
- **Version history works in the page**, because D2 reversed to carry every
  revision rather than the newest per entity.
- **Licenses, assigned ArNS names, pinned owners and thumbnails all travel**, so
  the page renders what the explorer renders without asking a gateway anything
  else.

This feature also closes D6, which parked ArNS discovery as "not wired in v1".
A library page is the case §4.1 describes: a recipient handed a name and a key
opens a large drive without walking its history.

## The shape

Publishing writes two objects and one record:

1. **The artifact**, the drive's catalog, as specified in its own document.
2. **The manifest**, whose index is the viewer, which maps one path to the
   artifact, one path to the shared viewer code, and one path per published file
   to its data item.
3. **The record**, pointing the chosen name at the manifest.

The viewer itself is deployed once per app release and referenced **by
transaction id** from each page's manifest, never by a name. A manifest path may
point at any transaction, so every library page shares one copy of the viewer at
no extra cost, same-origin and immutable. A permanent page must not have a
mutable record in its critical path.

Every link the page emits is relative, so the page carries no gateway hostname
and keeps working on any gateway that resolves the name, and under `ar://`.

## Private library pages

The manifest and the viewer are public. The artifact inside them is encrypted,
which is how a private drive's page works:

- The visitor supplies the **drive key**, pasted or carried in the link exactly
  as a shared private drive does today with `driveKey`.
- That key decrypts the artifact, and every file key derives from it through
  `deriveFileKey()` (`lib/core/crypto/crypto.dart:119`), so the page decrypts
  file bytes with WebCrypto, choosing AES-GCM or AES-CTR at the uploader's
  boundary (`packages/ardrive_uploader/lib/src/constants.dart:3`, 100 MiB).
- **No new cryptography.** The page runs the derivation the app already ships
  and the artifact's own envelope. Nothing in the upload path moves.

**A private page's manifest paths must be opaque.** Manifest path keys are
plaintext inside a public JSON object, so publishing `Photos/medical/scan.jpg`
as a key publishes that structure even though the bytes stay encrypted. Private
pages key their paths by file id, and the readable tree lives only inside the
encrypted artifact.

What the review step has to say, in the step itself rather than in a notice:

- Publishing is permanent and cannot be withdrawn.
- A shared drive key opens the whole drive for ever, including files uploaded
  after the publish. That is already true of sharing a private drive today.
- Clearing the record stops the name resolving. It does not unpublish anything.

Wrapping the drive key under a passphrase, so a link alone is not the key, is a
later refinement rather than the mechanism.

## How the page reads the artifact

The viewer opens the artifact with SQLite compiled to wasm, which this
repository already ships and loads on every page (`web/sql-wasm.wasm`, 1.2 MB
raw, about 458 KB gzipped, loaded at `web/index.html:332`). DuckDB is the right
tool for parquet analytics over a global index and the wrong tool for opening
one drive's catalog.

Gateway behaviour, measured in October 2026 against two AR.IO gateways in three
browsers, cross-origin:

| Property | Measured behaviour |
|---|---|
| Range requests | Work on `/{txId}`, a bundled data item, a manifest path and an ArNS path, single and multi-range |
| CORS | `Access-Control-Allow-Origin: *`, `range` allowed, headers exposed |
| A gzip-stored object plus a range | Returns a slice of the compressed bytes, which no browser can decode |
| Negotiated compression | Does not happen. No gateway compresses on request |
| A cold object | The gateway fetches the whole object before answering a range: 9 to 22 seconds measured |
| A warm object | About 70 ms per read |

Five rules follow, and they are requirements rather than preferences:

1. **Publish the artifact with no `Content-Encoding` tag.** ArDrive sets none
   anywhere today, so this costs nothing to honour.
2. **Compress inside the envelope only below the range-read threshold.** A small
   artifact is fetched whole and compression is free value. A large public one
   is published identity so the page can read the pages it needs. Readers tell
   the two apart by the payload's first bytes, so the choice needs no flag, and
   it is permanent per artifact.
3. **Warm the cache at publish.** One full GET against the serving gateway after
   upload, so the first visitor never pays the cold-miss cliff.
4. **Read in few large blocks.** The gateway's per-resource token bucket is keyed
   `host:method:path` and shared by every reader of the same page, charged per
   KiB with a one-token minimum, so hundreds of 4 KB reads are the wrong shape.
5. **Ignore `Content-Digest` on a partial response.** A gateway returns the
   whole-object digest on a 206 and signs it, so verifying it always fails. The
   page verifies the artifact's own data item signature instead, which is the
   trust model the artifact specifies anyway.

The page also pins `x-arns-resolved-id` from the first response and reads the
rest against that id, because a name is mutable and `If-Range` is not
implemented.

## The publish flow

Three entry points open the same flow with a different preselected scope: a
drive's details panel and row overflow menu, a folder's, and one entry in the
New menu. Publish belongs beside Share, which already appears in all three
places (`lib/components/details_panel.dart:1341`,
`lib/pages/drive_detail/drive_detail_page.dart:777`,
`lib/drives_list/presentation/drive_actions_menu.dart`).

The New menu gains one item and loses the temptation to add three:

```text
Upload Files · Upload Folder · New Folder · New Note · New File Pin
────
Publish…
────
New Drive · Attach Drive
Advanced ▸  Import from Manifest · Create Manifest · New Snapshot
```

**"Publish Drive State" must not reach a user.** An artifact is how Publish
works, as a manifest is. Four engineering artifacts offered as four menu items
is how a user ends up choosing between Create Manifest, New Snapshot and Publish
Drive State. The drive state branch adds exactly that string today
(`lib/components/new_button/new_button.dart`), and it folds into Publish.

The flow is one dialog with four steps, and the first carries most of the value:

1. **Confirm what gets published.** Scope, file count, total size, and what is
   left out with counts: hidden items, pending uploads, ghost folders, and names
   that collide after path normalization.
2. **Choose the name.** The name itself and its undernames in one picker, with
   the resulting URL built by `getAddressesFromArns()`
   (`lib/arns/utils/arns_address_utils.dart`).
3. **Settings.** Title, a line of description, cover, accent, layout (list, grid
   or gallery), default sort, and which columns show.
4. **Review and publish.** Cost and payment method, the permanence line, then
   progress across the uploads and the record write.

Preconditions are the artifact's own, reused rather than restated: an explicit
user action (D3), never from a sync that reported skipped entities, never above
the payload bound (D5), paid through whichever upload path the user already has
(D4), and hidden from a wallet that does not own the drive.

The states after the first publish matter more than the flow:

| Condition | What the UI shows | Action |
|---|---|---|
| Published and current | The URL, the published date, the file count | Copy, open, republish |
| Published and behind | How many files changed since the published date | Republish |
| Drive still syncing | That the local view is incomplete | Unavailable, with the reason |
| Pending uploads in scope | Which files are not yet confirmed | Unavailable, with the reason |
| No ArNS name on the wallet | What a name is and where to get one | Link out, never a dead end |
| Signed in with Ethereum or Solana | That a record write needs an Arweave wallet | Explain, rather than fail at signing |
| Not on web | Nothing | Hide the action |

Those states derive from `DriveListItem`
(`lib/drives_list/domain/drive_list_item.dart`), which already carries
`hasBeenWalked`, `lastSyncedAt`, `isSyncing`, `lastSyncFailed` and
`hasUnreadChanges`. Publishing adds one fact, the published artifact and its
date, and derives the rest.

## What the page shows

A read-only library, not an editor: breadcrumbs and a folder tree, list, grid
and gallery views, client-side search and sort over the catalog it already
holds, and per row the name, size, type, modified date, a license badge where
`licenseTxId` is set, attribution where `pinnedDataOwnerAddress` is set, the
ArNS names a file carries from `assignedNames`, and version history, since every
revision travels in the artifact.

Image rows use the thumbnail variants ArDrive already uploads
(`lib/models/tables/file_entries.drift:19`, `Variant` in
`lib/entities/file_entity.dart:213`). The footer names the artifact transaction
and the published date. The page makes no request to anything but the gateway
serving it and carries no analytics. Theme follows the ArDrive brand palette in
light and dark, as CSS variables in the viewer rather than imported from the app.

## ArDrive specifics that have to be handled

Ordered by damage. The first two were verified with a throwaway test against
`ManifestDataBuilder`; the rest are read off the code at the cited lines.

| # | Finding | Evidence | What has to change |
|---|---|---|---|
| 1 | Hidden folders are published. Only a file's own hidden flag is honoured, and hiding a folder does not cascade. Verified: a hidden folder's `notes.txt` published as `secret/notes.txt`. | `manifest_data.dart:127`, `drive_queries.drift:35`, `folder_node.dart:67`, `hide_bloc.dart:72`, contrary claim at `create_manifest_form.dart:987` | Prune hidden folders and drives recursively from both the manifest and the published set, report the count, fix the form's claim |
| 2 | Path normalization drops files. Verified: `my file.txt` and `my_file.txt` produce one path carrying the second file's id. | `manifest_data.dart:103` | Give each colliding file its raw path, which gateways resolve because they decode a request before matching it. Never percent-encode a key: that would break every one of them. Fixed in #2265 |
| 3 | The index points at an arbitrary file when the folder has no `index.html` | `manifest_data.dart:129` to `:140` | A library page always sets the index to the viewer |
| 4 | The name picker drops the name itself and labels the apex "No undername" | `assign_name_bloc.dart:92` and `:118`, `assign_name_modal.dart:649` | Offer the apex in both flows, labelled as the name |
| 5 | Undername URLs use an underscore: `library_phils-archive.ar.io` | `get_literal_arns_record_name.dart`, host at `constants.dart:71` | Show the resolved URL rather than a dot-separated guess |
| 6 | Republishing is not instant: the record TTL is 900 seconds | `arns_record.dart:8` | Say so in the done state, and do not claim success at the name before the record reads back |
| 7 | Publishing from a partially read drive would publish a partial library | D3, and the warning already in `drive_state_creation_modal.dart` | Reuse the artifact's precondition rather than writing a second one |
| 8 | Pending uploads produce dead rows | `hasPendingFilesOnTargetFolder()` | Keep the gate, and name the files in the confirm step |
| 9 | Ghost folders have no metadata and are a normal state | `lib/sync/domain/ghost_folder.dart`, `folder_entries.drift:11` | Exclude them, and list them among the exclusions |
| 10 | Pinned files point at another wallet's transaction | `file_entries.drift:21` | Publish them, show the attribution |
| 11 | The manifest is an ArFS file inside the drive, so each page adds a file the user browses | `existingManifestFileId`, `manifest_repository.dart:118` | Mark library page manifests so the explorer presents them as the page |
| 12 | The assign action is web-only | `details_panel.dart:1603` | Hide publishing off web, keep the published state readable |
| 13 | Two separate gates block private drives | `new_button.dart:339`, `create_manifest_cubit.dart:62` | Change both in the private phase, routing private publishing through its own flow |
| 14 | A record write needs an Arweave signer, and `ProfileType` has two values | `arns_repository.dart:126`, `profile_types.dart` | Explain unavailability for Ethereum and Solana sign-ins rather than failing at signing |
| 15 | Drive scope is folder scope | `create_manifest_cubit.dart:82` | One code path, two entry points, recording the scope so republish does not widen it |

Four findings from the earlier revision are resolved by building on the
artifact rather than a listing file: empty folders survive because folder rows
travel, licenses render because the `licenses` table travels, assigned names
render because `assignedNames` travels on the file rows (D10), and version
history renders because every revision travels (D2).

## What breaks, and for whom

A published page is a permanent public artifact supported for as long as Arweave
exists. Old pages keep running old viewers, so a viewer bug ships for ever and
is fixed only for pages republished afterwards. That argues for a small viewer
and for pinning its transaction per publish.

A private page moves a security boundary from a wallet to a key the owner hands
out. Neither the artifact nor the ciphertext can be withdrawn. The UI has to be
honest at the moment of commitment rather than in a help page.

A stale page misleads visitors in a way a share link does not, because a share
link reads live state. The published date and the republish prompt are part of
the feature rather than polish.

## Scope

1. **Land the artifact.** D12 accepted as the container, D5 re-derived, the
   entity specified in `ar-io-docs`. Nothing here ships first.
2. **Public library pages.** Viewer, manifest, naming, publish and republish,
   and findings 1 to 3 and 5 to 15. Done when a public drive and a public folder
   each resolve at an owned name and the excluded counts match what is published.
3. **Private library pages.** Opaque paths, drive key unlock, in-page decryption
   for both ciphers, and findings 12 to 14. Done when a private folder opens in a
   clean browser profile and no file name appears in the manifest or in any tag.
4. **Passphrase unlock, and the full app as a second tier.** The app already
   deploys itself to Arweave under a name through `ar-io/ar-io-deploy@v1`
   (`.github/workflows/production.yaml:59`), so once it can hydrate a drive from
   an artifact, a deployed copy becomes the heavyweight option beside the viewer.

## Decisions needed before building

- Whether the default offered name is the apex or an undername.
- What unpublish means, given that clearing the record stops resolution while the
  data stays readable by transaction id for ever.
- The size threshold at which a public artifact is published identity rather than
  compressed: measured with the real page, starting from 16 MiB (D13).
- Whether the viewer source lives in `assets/` here or in its own repository.
- Whether republish happens automatically after an upload into a published
  folder, as AutoDeploy does for manifests, or stays explicit.

## Tests the implementation has to carry

- A hidden folder holding visible files publishes none of them, and the excluded
  count reports them.
- Two files whose names normalize to one path both appear, deterministically
  ordered, and the collision is reported before publishing.
- A private publish leaks no file name, folder name or path fragment into the
  manifest JSON or any transaction tag.
- The viewer opens an encrypted artifact with the drive key and decrypts a file
  below and a file above the 100 MiB GCM boundary.
- Publishing is unavailable while a drive syncs and available once it settles,
  asserted on cubit states rather than on a call count.
- Republish writes a new revision of the same ArFS file and points the record at
  the new manifest.
- The apex record is offered for a name that has undernames.
- The viewer renders from the artifact with no GraphQL request at all.

Each test earns its place by failing when the rule it covers is broken on
purpose.

## References

- `docs/DRIVE_STATE_ARTIFACT.md` and `docs/drive-state/DECISIONS.md`, the format
  this feature reads.
- `lib/entities/manifest_data.dart` and `lib/manifest/domain/manifest_repository.dart`,
  the manifest and its uploader.
- `lib/arns/`, the record picker, repository and address helpers.
- `lib/core/crypto/crypto.dart` and `docs/private_drive_kdf_reference.dart`, key
  derivation for the private phase.
- `docs/SHARE_LINKS.md`, the other way an ArDrive entity reaches someone else.
