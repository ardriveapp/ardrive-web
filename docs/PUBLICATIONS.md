# Publications

> **Status: phases 1 and 2 built** (publication mode, and publishing from
> the app; 2026-10-24). Private publications (phase 3) and names (phase 4)
> are designed here and not built. Build order, code seams and tests are in
> `docs/publications/IMPLEMENTATION_PLAN.md`. A publication is an ArFS entity
> (`docs/ArweaveFS.md`, "Publication").

A publication is a permanent web page that shows one ArDrive drive, or one
folder of it, to anyone who opens its link. It is ArDrive itself in a
read-only "publication mode": the same file table, previews, search and downloads,
under the owner's title, icon, social card and cover. A public publication opens
as it is; a private one opens with the drive key.

## Vocabulary

| Term | Means | Shown to users as |
|---|---|---|
| Publication | What a visitor opens | "Published" to the owner; to a visitor, just a web page |
| Publish, republish, unpublish | The owner's actions | Publish to web, Update, Unpublish |
| Snapshot | A drive state artifact (`DRIVE_STATE_ARTIFACT.md`), the catalog the page loads | Snapshot |
| Viewer bundle | One release of the ArDrive web build, uploaded to Arweave | never shown |
| Page manifest | The Arweave path manifest that is the page | never shown; its link is the page's link |
| Name | An ArNS name or undername pointing at a page manifest | Name |

Publish is not Share. Share hands out a link to what exists, writes nothing and
costs nothing. Publish writes permanent objects to Arweave.

## Decisions (all agreed)

1. **The viewer is ArDrive in publication mode, from the same build.** No second
   UI. Every release is a viewer.
2. **Every publish assembles a fresh, static page manifest** that pins one
   release's bundle by transaction ID. The bundle is never re-uploaded per
   page. A page runs the release it pinned until it is republished.
3. **Release bundles are uploaded gzipped** with `Content-Encoding: gzip`
   (`@ar.io/deploy --compress gzip`, action `ar-io/ar-io-deploy` v2.1.2).
   This also shrinks the permaweb ArDrive at `ardrive.ar.io`.
4. **Snapshots stay always compressed.** The viewer loads the whole snapshot,
   so there is no range-read threshold. Remove "Producers always compress until
   Publications ship" from `DRIVE_STATE_ARTIFACT.md` §2.7.
5. **Customization:** title, description, icon, social card, cover banner
   (not a full-page background).
6. **Publish lives beside Share** in a drive's menu, a folder's menu and the
   details panel. Not in the New menu.
7. **No analytics, no third-party requests** on a publication.
8. **Every page shows "Made with ArDrive"**, once, as a quiet button in the
   top bar. No page offers "Open in ArDrive": a visitor has no use for it,
   and for a folder the app would let them walk up to the rest of the drive.
9. **No per-file URLs** in v1. Files load by transaction ID from the serving
   gateway.
10. **Update only on request.** The snapshot is chosen for the owner: the
    newest one when nothing in the drive changed after it, else a new one.
    An update is a new manifest with the same `Publication-Id`, so a new link;
    the earlier links keep working.
11. **Names:** the owner picks the main name or an undername. Unpublishing an
    undername removes its record; unpublishing a main name points it at a
    shared "no longer published" page. See [Names](#names): this whole part
    waits on ArNS-on-Solana support in the app.
12. **A publication is an ArFS entity** (`Entity-Type: publication`), as a
    drive state is: owner only, never encrypted, never a file in the drive,
    found by GraphQL. Called "publication" because "page" collides with
    deploy, which can make any page, site or app; users see "Publish to web".

## Measured facts this design rests on (2026-10-21)

| Fact | Value |
|---|---|
| `ardrive.ar.io` `main.dart.js`, as served today | 28.2 MB, no compression, even with `Accept-Encoding: gzip` |
| Same file from `app.ardrive.io` (Firebase, brotli) | 2.9 MB |
| `main.dart.js` gzipped | 27.5 → 4.0 MB |
| `canvaskit.wasm` gzipped | 6.4 → 2.6 MB; Chromium build 5.1 → 1.9 MB |
| `Content-Encoding` tag passthrough | turbo-gateway.com, ar-io.dev, ardrive.net, vilenarios.com send the header (raw and sandboxed routes); frostor.xyz decompresses itself. A gateway that has not indexed a new item yet may send gzip bytes bare (ar-io-node #964/#966, fixed on ar.io and Turbo gateways) |
| Release manifest | 469 paths, 49 KB |
| Staging build uploaded gzipped (phase 0) | 466 files without source maps, 77.3 MB → 18.8 MiB; 19 s; 0.2666 Turbo credits (about $1.58) for a first upload; later uploads pay mostly for `main.dart.js` (4.2 MB) |
| First visit to the gzipped bundle | 8.96 MB on the wire, Flutter view at 2.9 s (turbo-gateway.com and ardrive.net alike); the uncompressed production upload of the same day: 38.16 MB |
| ar-io.dev and gzip | Serves some gzipped items decompressed even when the browser accepts gzip (correct, larger). Served every path of a new Turbo upload only 1 h 27 min after it (404s until then, `AssetManifest.json` among them, so the app stopped at its splash), while turbo-gateway.com and ardrive.net served all of them at once. Charges for data past a free allowance: HTTP 402 with an x402 offer (USDC on Base Sepolia) after one evening of testing from one connection. It is the gateway of Turbo's **development sandbox** (`upload.services.ar-io.dev` is the Turbo SDK's `developmentUploadServiceURL`): uploads through that service show on ar-io.dev at once but are not permanent and no production gateway serves them; production uploads reach ar-io.dev only from the chain. Not a gateway for releases or publications |
| ArDrive at a raw manifest URL | Boots: `https://turbo-gateway.com/<manifest-id>/` redirects to the sandbox subdomain and the app loads (no `<base>` tag in `web/index.html`, all paths relative) |
| Snapshot of 41,767 files | 6.0 MiB gzipped, imported in 0.6 s |
| Requests the normal app makes on start | Also fonts.gstatic.com, upload.ardrive.io, plausible.io: publication mode must stop these |
| Publication, phase 1 (2026-10-23) | Hand-built pages on turbo-gateway.com for the UAT drive (52 entities) and one of its folders: requests only to the gateway, its sandbox subdomains and the page's own; first visit 8.95 MB, files on screen 4.0–4.3 s after navigation on a desktop connection, 50.4 s on Lighthouse's phone profile (1.6 Mbps, 150 ms, CPU ×4), which is the bundle's download |
| Release with fallback fonts | 613 files, 58.3 MB gzipped, of which the 144 fonts are 38.6 MB; incremental upload after phase 0's: 40.9 MiB, 0.5684 credits; a rebuild after that: 4.0 MiB, 0.0563 credits |
| Snapshot import, 569 entities (2,084 revisions) | 0.20 s; 0.67 s with CPU ×4 |

## Architecture

### What a page is

A page manifest (`arweave/paths` 0.2.0) whose paths are:

| Path | Points at | Uploaded by |
|---|---|---|
| `index.html` (index and fallback) | The release's `index.html` with the page's head written in | the publish |
| `publication.json` | The page's settings and its snapshot's tags | the publish |
| `snapshot` | A drive state artifact | earlier, or the publish |
| `icon-32.png`, `icon-180.png`, `icon-512.png`, `social.jpg`, `cover.jpg` | The page's images, when set; `social.jpg` always (the owner's or the generated card) | the publish, or an earlier version's transaction |
| `files.html`, `sitemap.xml` | Every file as a link to its data on the gateway, for crawlers and anything that runs no script; at most 5,000 | the publish |
| every other path of the release manifest | The release's own files, by transaction ID | CI, once per release |

A page manifest is about 82 KB (616 paths, 144 of them the fallback fonts),
under 105 KiB. That was Turbo's free size; with free uploads restricted, a
page's three files cost about 0.0014 credits (October 2026). Its link is
`https://<gateway>/<manifest-id>/` (the trailing slash matters), and a name can
point at it later.

### `publication.json`

```json
{
  "version": 1,
  "driveId": "c863be1f-a725-4554-9a9e-18268ed8a035",
  "rootFolderId": "41520b33-28c1-4892-886b-b845a5709085",
  "scope": { "type": "drive" },
  "privacy": "public",
  "owner": "iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA",
  "ownerName": "Phil",
  "snapshot": {
    "path": "snapshot",
    "txId": "<artifact tx id>",
    "tags": { "Drive-Id": "…", "Block-Start": "0", "Block-End": "1879136",
              "Entity-Count": "6", "State-Version": "…" }
  },
  "title": "Phil's Archive",
  "description": "Photos, notes and the odd recording.",
  "fileCount": 79,
  "keywords": ["photos", "notes"],
  "license": { "name": "Attribution", "shortName": "CC-BY",
               "definitionTxId": "<licence definition tx id>" },
  "images": { "icon": "icon-512.png", "social": "social.jpg", "cover": "cover.jpg" },
  "publishedAt": "2026-10-21T18:02:11Z",
  "viewer": { "release": "2.91.0", "manifest": "<release manifest tx id>" }
}
```

- `scope` is `{"type":"drive"}` or `{"type":"folder","folderId":"…"}`.
- `generatedSocialCard: true` marks `social.jpg` as the card ArDrive drew.
  An update keeps an owner's own card, and keeps a generated one while
  nothing it shows (title, description, icon, cover, file count) changes.
- `fileCount`, `keywords` and `license` are optional. `fileCount` is what the
  publisher counted, for the owner's published view; `license` covers
  everything in the publication and is shown in its byline (a UDL adds its
  terms as `params`); `keywords` are also `Keyword` tags on the manifest.
- `snapshot.tags` copies every tag the importer reads from the artifact
  (`DriveStateArtifactCandidate`), including `Cipher` and `Cipher-IV` for a
  private drive. The viewer builds the candidate from these instead of
  GraphQL.
- Nothing in `publication.json` is secret. For a private drive it must not contain
  any drive, folder or file name (the title is typed by the owner).

### The page's `index.html`

The release's `index.html`, with these written into `<head>` (every value
HTML-escaped):

- `<meta name="ardrive-publication" content="publication.json">`: the switch that puts
  the app in publication mode.
- `<title>`, `<meta name="description">`, `<meta name="theme-color">`.
- `<link rel="icon" sizes="32x32">`, `<link rel="apple-touch-icon">`.
- `og:title`, `og:description`, `og:type=website`, `og:image`,
  `twitter:card=summary_large_image`. `og:image` must be an absolute URL known
  before `index.html` is uploaded, so it cannot use the page manifest's ID:
  the manifest lists `index.html`, so it is built after it. The publish uploads
  the social image first and points `og:image` at that transaction on the
  gateway the owner's app is set to (`turbo-gateway.com` by default), the
  same gateway as the publication's link (a reused image keeps its existing
  transaction). A path inside the page (`https://<gateway>/<manifest-id>/social.jpg`)
  cannot work: the manifest's ID exists only after `index.html` is uploaded.
  Once names arrive (phase 4), a page published under a name can point
  `og:image` at an undername of its own, `https://social_<name>.<gateway>`,
  whose record points at the card; it can be moved later, so the card can
  change without republishing. Every page has a social image: the owner's
  own, or the card the publish generates (see the look), so `og:image` and
  `twitter:card` are always there.
- `<link rel="sitemap" href="sitemap.xml">`, and as the first thing in
  `<body>` a `<noscript>` link to `files.html`: the page itself is a script,
  so these are what a crawler that runs none finds.

### How a page opens

1. The gateway serves the manifest's `index.html`.
2. ArDrive starts, finds the meta tag, and enters publication mode before any
   service starts: no stored config, no login, no analytics, no Turbo, no
   GraphQL, no ArNS, no HTML auto-reload, an in-memory database.
3. It reads `./publication.json`.
4. File data comes from the gateway serving the page (the existing
   `/ar-io/info` detection on the page's host).
5. A private publication shows the unlock screen.
6. It fetches `./snapshot`, seeds the drive row from `publication.json`, and
   imports with the existing `DriveStateImporter`.
7. The explorer opens at the scope's root. No sync ever runs.

**Rule, enforced by a test:** a publication makes requests only to the host
serving it and the gateway it detected, nothing else.

### The viewer bundle

- Production deploys, and staging builds uploaded by hand
  (`staging-arweave.yaml`), use `--compress gzip`, leave out source maps,
  and keep `index.html`'s relative paths.
- The app knows which release a new page pins through a config value,
  `publicationViewerManifestSource`. A 43-character value is a manifest ID, used
  as is. Anything else is an ArNS name, which the publisher resolves to the
  manifest ID (`x-arns-resolved-id`) with a plain HTTP read through the
  gateway. That needs no wallet, so it works before names do in the app (see
  [Names](#names)).
- Production sets `ardrive`, the name the production deploy moves. Staging has
  no name and pushes to `dev` never upload to Arweave, so the staging and
  development configs also use `ardrive`: a page published from staging pins
  the current production release. To try a viewer built from a branch, run
  *Staging build to Arweave* (`staging-arweave.yaml`) and put the manifest ID
  from its job summary in the stored config (`flutter.config` in local
  storage). The phase 1 test-page tool takes a manifest ID directly.
- CI warms the bundle after each deploy by reading every file once through
  turbo-gateway.com and ardrive.net.

## Names

**ArNS moved to Solana** (`@ar.io/sdk` 4.x). Names are Metaplex Core assets
owned by Solana keys; every record change needs a Solana signer. Names held by
Arweave wallets before the move sit in an escrow until claimed into a Solana
wallet (`ANTEscrow`, Arweave-attested claim). The app's own name features are
stubbed (`packages/ario_sdk/web/src/index.js`: "not yet implemented for
Solana"), so "Assign name" does not work in 2.90 either.

So publications ship in two halves:

- **Without names (phases 1 to 3):** a page is its manifest link. The owner
  copies it, or points a name at the manifest ID by hand with any ArNS tool.
- **With names (phase 4):** the name step, unpublish, and the main-name
  placeholder arrive with ArNS-on-Solana support in the app (a Solana wallet
  connection, listing names the wallet owns or controls, setting and removing
  records). That is its own project, and publications consume it.

## UX: the visitor

All of it is the existing explorer (`DriveDetailPage`, the data table, the
details panel, previews, downloads, breadcrumbs, search), framed by publication
chrome instead of account chrome.

### Loading screen

Centred on the page background: the publication's icon (or ArDrive's), the title,
a thin progress bar, and one line that changes with the step: "Loading
files..." (snapshot download, with MB of total when the size is known),
"Almost there..." (import). The title and icon come from `publication.json`, so
this screen appears after one small request; until then the page shows only
its background, never an empty slot where the icon will be.

### Unlock screen (private publications)

Same frame as the loading screen. Below the description: "This page is
private. Paste the drive key you were given to open it." A `Drive key` field
(`ArDriveTextFieldNew`, obscured, show/hide toggle), an **Open**
primary button (disabled until the field is non-empty), and in small text "The
key stays in this browser." A key in the link (`#/?driveKey=…`) skips this
screen. A rejected key shows "This key doesn't open this page." under the
field, and the field keeps its text for correction. A typed key is never
written to the address bar.

### Error screens

One frame, a heading, one sentence, one action:

| Case | Heading | Sentence | Action |
|---|---|---|---|
| `publication.json` missing or unreadable | This page can't be opened | Its settings are missing or damaged. | Open ArDrive |
| Snapshot can't be fetched | This page can't load right now | The gateway didn't return its files. Try again in a minute. | Try again |
| Snapshot rejected by the importer | This page can't be opened | Its data didn't pass ArDrive's checks. | Open ArDrive |
| Viewer older than `publication.json`'s version | This page needs a newer ArDrive | Ask its owner to republish it. | Open ArDrive |

### The publication frame (desktop)

Agreed 2026-10-23 after a review of the first build: as familiar as a shared
folder on Google Drive or Dropbox, nothing said twice.

- **No sidebar.** Everything it held is in the top bar or the header.
- **Top bar:** the publication's icon (40 px), the existing search field ("Search
  this publication..."), then on the right the theme toggle and one quiet
  outlined button, **Made with ArDrive**, opening ardrive.io. The only place
  the page names ArDrive. No login, profile card, sync indicator, New button,
  footer, or "Open in ArDrive" (a visitor has no reason to want the drive in
  the app).
- **Header,** on the publication's root only, in place of the breadcrumb row
  there: the cover as a banner (200 px, cropped to fill, rounded, nothing
  printed on it), then the title, then "By <owner> • N files • size •
  published <date>" (bullets, as the file rows use: Wavehaus draws "·" on
  the baseline), then the description. **Download** and **Copy link** sit
  beside the title. Download takes the whole publication, or the rows selected in
  the list, when its label says "Download selected". The owner is the name
  they chose (`ownerName`), else their address shortened; the whole address
  is the tooltip, and a click copies it.
- **The header folds** as the list beneath it scrolls: the cover and the
  lines under the title fold away, the title and actions stay, and the list
  has the window. Scrolling back to the list's top unfolds it; the wheel over
  the header does both. The column headings have a hairline under them, so
  rows pass beneath an edge.
- **Subfolders:** no header; the breadcrumb row leads, with its menu. The
  root crumb is the title.
- **Data table, details panel, previews:** unchanged, except that a click on a
  row opens it: a folder is entered, a file opens its details and preview. The
  app's own model (a click selects, a double-click opens) is a file manager's;
  a visitor is browsing a page, and the first visitor to try one expected a
  click to open. Choosing several to download is the checkboxes' job.
- **Row and toolbar actions offered:** Download, Download folder (zip), Preview
  in the panel, More info, and **Copy link**, which copies the publication's own
  link to that folder or file (`<page link>#/folders/<id>?file=<id>`).
  Everything else is hidden: Share (replaced by Copy link), Rename, Move, Hide,
  License add/update, Pin, Create snapshot, Sync, Full resync, Export, Attach,
  Edit note.
- **Never shown:** hidden items or anything inside a hidden folder, ghost
  folders, failed or pending uploads, anything outside a folder publication's
  folder, the "Show hidden" toggle.
- **No terms or footer:** the page shows the owner's own public data, served
  by a gateway under its own content policy, and collects nothing from a
  visitor. A "Report" link is an open question for legal.

### The publication frame (phone)

ArDrive's mobile layout without a drawer. The app bar shows the publication's
icon, then search, the theme toggle and ArDrive's mark (the "Made with
ArDrive" button, its label as a tooltip). The header is the desktop's with a
120 px cover and the actions as icons. No FAB.

### Copy

Publication chrome strings are new keys in `app_en.arb`. Dates use the app's
existing date formatting.

## UX: the owner

Users see **Publish to web**, **Published to web** and **Update**; the word
"publication" is for the code and the protocol.

### Entry points

**Publish to web**, with a globe, beside Share in: a drive's menu (the drive
page on desktop and phone, and the drives list), a folder row's menus, and
the details panel's toolbar for a drive or folder. Offered on the web, in the
app (never in a publication), to the owner of a public drive, where snapshots
can be published (`enableDriveStatePublishing`). Hidden on private drives
until phase 3.

Once published it reads **Published to web** and opens the published view. A
globe ("Published to web" on hover) marks published drives in the drives list
and published folders in the explorer. One GraphQL query when the wallet
signs in finds every publication it made, so the marks are there on any
device before anything is synced; a publish this session is counted at once,
since GraphQL lags.

### The publish dialog

`ArDriveStandardModalNew`, "Step N of 3", Back and Next in the footer, closed
only by its own buttons. On a phone it is the same dialog at the screen's
width, with the look in one column.

**Blocked**, with a sentence and Close, while (and when the list of
publications cannot be read at all, rather than risk a second publication of
the same drive or folder):

- the drive is syncing, or has not been fully read in this session (the
  snapshot dialog's own sync check and sentence);
- any upload in the drive is unconfirmed: "Some uploads in this drive aren't
  confirmed yet. Publish once they are; it usually takes a few minutes." (a
  new snapshot would refuse them);
- the folder is hidden, or inside a hidden folder;
- nothing visible is in it: "There's nothing to publish here yet: no files
  visitors could see.";
- the release a publication runs cannot be read, or a new snapshot is
  refused (its reason).

**Step 1 · What's included.** "The whole drive • <name>" or "This folder and
everything in it • <name>"; files, folders and size; **Left out**, one line
each: hidden items, files in hidden folders, files in folders whose details
are missing (ghost folders), failed uploads. "Anyone with the link can
browse, preview and download these files. Nothing else in your drive is
shown."

**Step 2 · How it looks.** The form on the left, live previews on the right
(below on a phone): the page header as it will look (cover, icon, title, "By
… • N files • license", description) and the link preview (the social card).
On a wide screen the form scrolls on its own and the previews stay in view.

| Field | Control | Rules |
|---|---|---|
| Title | text, 60 characters | Required. Prefilled with the drive or folder name |
| Description | text, 160 characters | Optional |
| Display name | text, 40 characters | Optional. "Shown after "By" under the title. Empty shows your wallet address." Prefilled from the owner's last publication in this browser, or from the version an update starts from; no ENS or SNS lookups |
| Keywords | chips, up to 5 | Optional. `Keyword` tags on the manifest and `keywords` in `publication.json`; not written into the page |
| License | menu: none, the Creative Commons licences, UDL (with its terms form) | Optional. For everything in the publication; shown in its byline, linked to its definition |
| Icon | Upload or From this drive | Square, at least 512 pixels wide. Makes 32, 180 and 512 px PNGs |
| Cover | Upload or From this drive | At least 1600 × 400; cropped to 4:1 from the middle; JPEG aiming under 100 KiB |
| Social card | Upload or From this drive | At least 1200 × 630. Until the owner picks one, the card is drawn from the other fields: the cover (or a background tinted from the icon's colour), the icon, title, description, an exact "N files", and ArDrive's mark; Remove goes back to it |

Pictures are decoded by the browser (PNG, JPEG, WebP, GIF, up to 20 MB) and
cropped to the middle. A picture smaller than it is shown says "This image is
small, so it may look soft."; one that is not a picture says what to use.
**From this drive** lists the drive's images (by type, or by name when the
type was never recorded), newest first.

**Step 3 · Review and publish.** What (name • N files), title, snapshot (the
newest one in a block, when nothing in the drive is newer and it counts what
this device holds: "The latest snapshot. Nothing changed since." or "A new snapshot of the drive,
included in the cost."), link ("A new link of its own." or, for an update,
"A new link. The current one keeps working."), the Turbo free-tier message,
the app's payment cards (each way to pay with its cost and balance), and with AR:
"With AR, the page opens a few minutes after it's published, once the network
confirms it." Then, in the step: "Publishing is permanent. It can't be undone
or deleted." The button is **Publish**.

**Progress.** Saving a snapshot of the drive (when new), signing the page's
files, uploading, getting the page ready (Turbo). "Keep this window open until
it's done."

**Failed.** "Publishing didn't finish", why, **Close**, **Back to review**
and **Try again**. Try
again reuses what was signed and posted, so nothing is paid twice: an AR
transaction (the snapshot or the bundle) whose header was accepted and whose
data did not finish is sent again as the same transaction, which costs
nothing more. Back to review returns to the review with all that kept, to add credits
or pay with AR instead; switching to AR bundles only what Turbo had not
taken. A transaction that reached the network first is named. A publish
that fails while it is being priced goes back through pricing, so it never
publishes a look the owner has since changed.

**Done.** "Your page is published" (AR: "Your page is on its way"), the link
in the field and Copy link that sharing uses, and "A new page can take a
minute to load the first time." (AR: "It opens in a few minutes, once the
network confirms it."). Actions: **Open page** and **Done**.

### Published view

"Published to web": the title, "Published <date> • N files", the link with
Copy link, "An update gets a new link. Earlier links keep working.", and
**Earlier versions** (collapsed), each with its date and time and an Open
link. Actions: **Update** (the dialog prefilled from the latest version,
opening on the look, where Next keeps it), **Open page** and **Done**.

### Tags

The manifest is the Publication entity (`docs/ArweaveFS.md`, "Publication"):
`ArFS: 0.15`, `Entity-Type: publication`, `Drive-Id`, `Publication-Id` (kept by
every version), `Publication-Scope` (`drive` or the folder ID),
`Publication-Version: 1`, `Content-Type: application/x.arweave-manifest+json`,
a `Keyword` tag per keyword, and the app's tags (`App-Name: ArDrive-App`,
`App-Platform`, `App-Version`, `Unix-Time`). Every other file carries its
`Content-Type`, the `Publication-Id` and the app's tags, and no `Entity-Type`.

They are plain public data items, never ArFS files: they must be public for a
private drive, and they must not appear in the drive. Found by GraphQL: the
owner's transactions with `Entity-Type: publication`, grouped by
`Publication-Id`; only the drive owner's count.

## Private publications

- The key travels like a private drive link's, `#/?driveKey=…`, in the fragment
  only. Typed keys are never written to the URL.
- The snapshot and files decrypt in the browser with the existing derivation.
- Nothing about the drive's contents is outside the encrypted snapshot: no
  manifest file paths, no names in `publication.json` or tags.
- The review step states the three facts above.

## Phases

| Phase | Ships | Done when |
|---|---|---|
| 0 · Compressed bundle (#2343) | `--compress gzip` in staging and production deploys; a staging channel | A staging upload loads through turbo-gateway.com and ardrive.net with every JS/wasm file carrying `Content-Encoding: gzip`; every path loads through ar-io.dev once it has fetched the upload (it may serve gzipped items decompressed, which is valid); first-visit transfer is measured |
| 1 · Publication mode | The viewer, public publications, a script that builds a test page by hand | A hand-built page at a raw manifest URL opens a public drive and a public folder, with no request outside the serving host and gateway |
| 2 · Publish (public) | The dialog, the published view, update, the globe, discovery, the publication entity | A public drive and folder publish from the app with Turbo and AR; an update with nothing changed reuses the snapshot and earlier images; what is left out matches the page (done 2026-10-24) |
| 3 · Private | Unlock screen, encrypted snapshots, private rules | A private folder opens in a clean profile with the key, and no drive, folder or file name appears in the manifest, `publication.json`, `index.html` or any tag |
| 4 · Names | The name step, unpublish, placeholder page | Needs ArNS-on-Solana in the app first |

Phase 1 must reach a production release before any real page works, because a
page runs the release it pins.

## Risks

- **A gateway serving gzip bytes bare** breaks a page on that gateway. Load
  each deploy through every gateway that matters before switching production.
- **Phones and large snapshots:** a snapshot near the 100 MiB bound lives in
  memory. Measure in phase 1; above a size to be found, step 2 warns "This
  publication may be slow on phones."
- **Old pages run old code for ever.** Publication mode must stay narrow (one host,
  one gateway) so pages age well.
- **Fallback fonts (decided 2026-10-22: self-host all of them).** Flutter
  3.19.6 hard-codes `https://fonts.gstatic.com/s/` (`font_fallbacks.dart:452`;
  `fontFallbackBaseUrl` arrived later), downloads Roboto from it on every start
  unless a `Roboto` family is bundled, and downloads one of 143 Noto fonts
  whenever text needs a glyph the bundled fonts lack. It fetches them through
  `window.fetch`. So the Arweave bundle carries the engine's 144 font files
  under `fonts/gstatic/` (fetched by CI from a checksum-pinned list, not kept
  in git, not deployed to Firebase: 80.7 MB raw, about 45 MB gzipped, uploaded
  once per Flutter version and reused after), and in publication mode a short
  script in `index.html`, run before Flutter starts, rewrites
  `https://fonts.gstatic.com/s/` to `./fonts/gstatic/`. Visitors download only
  the fonts their text needs, as before. Re-derive the list on every Flutter
  upgrade.
