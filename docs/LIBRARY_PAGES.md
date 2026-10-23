# Library pages

> **Status: DESIGN v2, agreed 2026-10-21. Not built.** Build order, code seams
> and tests are in `docs/library-pages/IMPLEMENTATION_PLAN.md`. Supersedes v1
> of this file (a plain HTML viewer with range reads), which is in git history.

A library page is a permanent web page that shows one ArDrive drive, or one
folder of it, to anyone who opens its link. It is ArDrive itself in a
read-only "library mode": the same file table, previews, search and downloads,
under the owner's title, icon, social card and cover. A public library opens
as it is; a private one opens with the drive key.

## Vocabulary

| Term | Means | Shown to users as |
|---|---|---|
| Library page | What a visitor opens | Library page |
| Publish, republish, unpublish | The owner's actions | Publish library page, Republish, Unpublish |
| Snapshot | A drive state artifact (`DRIVE_STATE_ARTIFACT.md`), the catalog the page loads | Snapshot |
| Viewer bundle | One release of the ArDrive web build, uploaded to Arweave | never shown |
| Page manifest | The Arweave path manifest that is the page | never shown; its link is the page's link |
| Name | An ArNS name or undername pointing at a page manifest | Name |

Publish is not Share. Share hands out a link to what exists, writes nothing and
costs nothing. Publish writes permanent objects to Arweave.

## Decisions (all agreed)

1. **The viewer is ArDrive in library mode, from the same build.** No second
   UI. Every release is a viewer.
2. **Every publish assembles a fresh, static page manifest** that pins one
   release's bundle by transaction ID. The bundle is never re-uploaded per
   page. A page runs the release it pinned until it is republished.
3. **Release bundles are uploaded gzipped** with `Content-Encoding: gzip`
   (`@ar.io/deploy --compress gzip`, action `ar-io/ar-io-deploy` v2.1.2).
   This also shrinks the permaweb ArDrive at `ardrive.ar.io`.
4. **Snapshots stay always compressed.** The viewer loads the whole snapshot,
   so there is no range-read threshold. Remove "Producers always compress until
   Library pages ship" from `DRIVE_STATE_ARTIFACT.md` §2.7.
5. **Customization:** title, description, icon, social card, cover banner
   (not a full-page background).
6. **Publish lives beside Share** in a drive's menu, a folder's menu and the
   details panel. Not in the New menu.
7. **No analytics, no third-party requests** on a library page.
8. **Every page shows "Made with ArDrive"; a drive's page also shows "Open in
   ArDrive".** A folder's page does not: the app would let a visitor walk up
   from the folder to the rest of the drive.
9. **No per-file URLs** in v1. Files load by transaction ID from the serving
   gateway.
10. **Republish only on request,** choosing an existing snapshot or making a
    new one.
11. **Names:** the owner picks the main name or an undername. Unpublishing an
    undername removes its record; unpublishing a main name points it at a
    shared "no longer published" page. See [Names](#names): this whole part
    waits on ArNS-on-Solana support in the app.

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
| ar-io.dev and gzip | Serves some gzipped items decompressed even when the browser accepts gzip (correct, larger). Served every path of a new Turbo upload only 1 h 27 min after it (404s until then, `AssetManifest.json` among them, so the app stopped at its splash), while turbo-gateway.com and ardrive.net served all of them at once. Charges for data past a free allowance: HTTP 402 with an x402 offer (USDC on Base Sepolia) after one evening of testing from one connection. It is the gateway of Turbo's **development sandbox** (`upload.services.ar-io.dev` is the Turbo SDK's `developmentUploadServiceURL`): uploads through that service show on ar-io.dev at once but are not permanent and no production gateway serves them; production uploads reach ar-io.dev only from the chain. Not a gateway for releases or library pages |
| ArDrive at a raw manifest URL | Boots: `https://turbo-gateway.com/<manifest-id>/` redirects to the sandbox subdomain and the app loads (no `<base>` tag in `web/index.html`, all paths relative) |
| Snapshot of 41,767 files | 6.0 MiB gzipped, imported in 0.6 s |
| Requests the normal app makes on start | Also fonts.gstatic.com, upload.ardrive.io, plausible.io: library mode must stop these |
| Library page, phase 1 (2026-10-23) | Hand-built pages on turbo-gateway.com for the UAT drive (52 entities) and one of its folders: requests only to the gateway, its sandbox subdomains and the page's own; first visit 8.95 MB, files on screen 4.0–4.3 s after navigation on a desktop connection, 50.4 s on Lighthouse's phone profile (1.6 Mbps, 150 ms, CPU ×4), which is the bundle's download |
| Release with fallback fonts | 613 files, 58.3 MB gzipped, of which the 144 fonts are 38.6 MB; incremental upload after phase 0's: 40.9 MiB, 0.5684 credits; a rebuild after that: 4.0 MiB, 0.0563 credits |
| Snapshot import, 569 entities (2,084 revisions) | 0.20 s; 0.67 s with CPU ×4 |

## Architecture

### What a page is

A page manifest (`arweave/paths` 0.2.0) whose paths are:

| Path | Points at | Uploaded by |
|---|---|---|
| `index.html` (index and fallback) | The release's `index.html` with the page's head written in | the publish |
| `library.json` | The page's settings and its snapshot's tags | the publish |
| `snapshot` | A drive state artifact | earlier, or the publish |
| `icon-32.png`, `icon-180.png`, `icon-512.png`, `social.jpg`, `cover.jpg` | The page's images, when set | the publish, or an existing transaction |
| every other path of the release manifest | The release's own files, by transaction ID | CI, once per release |

A page manifest is about 82 KB (616 paths, 144 of them the fallback fonts),
under 105 KiB. That was Turbo's free size; with free uploads restricted, a
page's three files cost about 0.0014 credits (October 2026). Its link is
`https://<gateway>/<manifest-id>/` (the trailing slash matters), and a name can
point at it later.

### `library.json`

```json
{
  "version": 1,
  "driveId": "c863be1f-a725-4554-9a9e-18268ed8a035",
  "rootFolderId": "41520b33-28c1-4892-886b-b845a5709085",
  "scope": { "type": "drive" },
  "privacy": "public",
  "owner": "iKryOeZQMONi2965nKz528htMMN_sBcjlhc-VncoRjA",
  "snapshot": {
    "path": "snapshot",
    "txId": "<artifact tx id>",
    "tags": { "Drive-Id": "…", "Block-Start": "0", "Block-End": "1879136",
              "Entity-Count": "6", "State-Version": "…" }
  },
  "title": "Phil's Archive",
  "description": "Photos, notes and the odd recording.",
  "images": { "icon": "icon-512.png", "social": "social.jpg", "cover": "cover.jpg" },
  "publishedAt": "2026-10-21T18:02:11Z",
  "viewer": { "release": "2.91.0", "manifest": "<release manifest tx id>" }
}
```

- `scope` is `{"type":"drive"}` or `{"type":"folder","folderId":"…"}`.
- `snapshot.tags` copies every tag the importer reads from the artifact
  (`DriveStateArtifactCandidate`), including `Cipher` and `Cipher-IV` for a
  private drive. The viewer builds the candidate from these instead of
  GraphQL.
- Nothing in `library.json` is secret. For a private drive it must not contain
  any drive, folder or file name (the title is typed by the owner).

### The page's `index.html`

The release's `index.html`, with these written into `<head>` (every value
HTML-escaped):

- `<meta name="ardrive-library" content="library.json">`: the switch that puts
  the app in library mode.
- `<title>`, `<meta name="description">`, `<meta name="theme-color">`.
- `<link rel="icon" sizes="32x32">`, `<link rel="apple-touch-icon">`.
- `og:title`, `og:description`, `og:type=website`, `og:image`,
  `twitter:card=summary_large_image`. `og:image` must be an absolute URL known
  before `index.html` is uploaded, so it cannot use the page manifest's ID:
  the manifest lists `index.html`, so it is built after it. The publish uploads
  the social image first and points `og:image` at that transaction,
  `https://<gateway>/<social-image-tx-id>` on the gateway the owner's app
  uses (a reused image keeps its existing transaction). It stays that URL when
  a name is added later, because `index.html` cannot change. With no social
  image, `og:image` and `twitter:card` are left out.

### How a page opens

1. The gateway serves the manifest's `index.html`.
2. ArDrive starts, finds the meta tag, and enters library mode before any
   service starts: no stored config, no login, no analytics, no Turbo, no
   GraphQL, no ArNS, no HTML auto-reload, an in-memory database.
3. It reads `./library.json`.
4. File data comes from the gateway serving the page (the existing
   `/ar-io/info` detection on the page's host).
5. A private library shows the unlock screen.
6. It fetches `./snapshot`, seeds the drive row from `library.json`, and
   imports with the existing `DriveStateImporter`.
7. The explorer opens at the scope's root. No sync ever runs.

**Rule, enforced by a test:** a library page makes requests only to the host
serving it and the gateway it detected, nothing else.

### The viewer bundle

- Production deploys, and staging builds uploaded by hand
  (`staging-arweave.yaml`), use `--compress gzip`, leave out source maps,
  and keep `index.html`'s relative paths.
- The app knows which release a new page pins through a config value,
  `libraryViewerManifestSource`. A 43-character value is a manifest ID, used
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

So library pages ship in two halves:

- **Without names (phases 1 to 3):** a page is its manifest link. The owner
  copies it, or points a name at the manifest ID by hand with any ArNS tool.
- **With names (phase 4):** the name step, unpublish, and the main-name
  placeholder arrive with ArNS-on-Solana support in the app (a Solana wallet
  connection, listing names the wallet owns or controls, setting and removing
  records). That is its own project, and library pages consume it.

## UX: the visitor

All of it is the existing explorer (`DriveDetailPage`, the data table, the
details panel, previews, downloads, breadcrumbs, search), framed by library
chrome instead of account chrome.

### Loading screen

Centred on the page background: the library's icon (or ArDrive's), the title,
a thin progress bar, and one line that changes with the step: "Opening
library...", "Loading files..." (snapshot download, with MB of total when the size
is known), "Almost there..." (import). The title and icon come from
`library.json`, so this screen appears after one small request.

### Unlock screen (private libraries)

Same frame as the loading screen. Below the description: "This library is
private. Paste the drive key you were given to open it." A `Drive key` field
(`ArDriveTextFieldNew`, obscured, show/hide toggle), an **Open library**
primary button (disabled until the field is non-empty), and in small text "The
key stays in this browser." A key in the link (`#/?driveKey=…`) skips this
screen. A rejected key shows "This key doesn't open this library." under the
field, and the field keeps its text for correction. A typed key is never
written to the address bar.

### Error screens

One frame, a heading, one sentence, one action:

| Case | Heading | Sentence | Action |
|---|---|---|---|
| `library.json` missing or unreadable | This library can't be opened | Its settings are missing or damaged. | Open ArDrive |
| Snapshot can't be fetched | This library can't load right now | The gateway didn't return its files. Try again in a minute. | Try again |
| Snapshot rejected by the importer | This library can't be opened | Its data didn't pass ArDrive's checks. | Open ArDrive |
| Viewer older than `library.json`'s version | This library needs a newer ArDrive | Ask its owner to republish it. | Open ArDrive |

### The library frame (desktop)

- **Sidebar** (replaces drives list, New button and profile): the icon (48 px),
  the title, the description, "Published <date>", then at the bottom "Open in
  ArDrive" (link, drive libraries only) and "Made with ArDrive" (muted), then
  the existing collapse control.
- **Top bar:** the existing search field ("Search this library…"), the theme
  toggle. No login, profile card, sync indicator or New button.
- **Cover band:** on the library's root only, above the breadcrumbs: the cover
  image, cropped to fill, 200 px tall on desktop, with a bottom scrim and the
  title plus "N files • size • published <date>" over it (bullets, as the
  file rows use: Wavehaus draws "·" on the baseline). Without a cover, the
  band is the title line on the normal background. On subfolders the band is
  gone and the breadcrumbs lead.
- **Breadcrumbs** start at the scope's root; the root crumb is the title.
- **Data table, details panel, previews:** unchanged.
- **Row and toolbar actions offered:** Download, Download folder (zip), Preview
  in the panel, More info, and **Copy link**, which copies the library's own
  link to that folder or file (`<page link>#/folders/<id>?file=<id>`).
  Everything else is hidden: Share (replaced by Copy link), Rename, Move, Hide,
  License add/update, Pin, Create snapshot, Sync, Full resync, Export, Attach.
- **Never shown:** hidden items or anything inside a hidden folder, ghost
  folders, failed or pending uploads, anything outside a folder library's
  folder, the "Show hidden" toggle.

### The library frame (phone)

ArDrive's mobile layout. The app bar shows the icon and title; the drawer holds
the sidebar's content. The cover band is 120 px tall and crops to its centre.
No FAB.

### Copy

Library chrome strings are new keys in `app_en.arb`. Dates use the app's
existing date formatting.

## UX: the owner

### Entry points

"Publish library page" with a globe icon, beside Share in: the drive's overflow
menu (desktop and mobile), a folder row's menu, the details panel toolbar for a
drive or folder. Shown only when: web, signed in, the wallet owns the drive.
Once a scope is published, the item reads "Library page…" and opens the
management section instead.

### The publish dialog

One `ArDriveStandardModal`-style dialog, 560 px wide, a step indicator ("Step 2
of 5"), Back and Next in the footer, Cancel always available. Closing midway
asks "Discard this library page?" only once something has been uploaded.

**Step 1 · What gets published.** Scope as two radio rows when opened from a
drive with a folder selected, otherwise fixed and named. Then: files, folders,
total size; and "Left out:" with counts for hidden items, items in hidden
folders, pending uploads, ghost folders, each with a one-line reason. Blocking
states replace Next with the reason: "This drive is still syncing", "N uploads
in this folder aren't confirmed yet" (with the file names, collapsible), "This
drive hasn't been fully read on this device. Sync it first."

**Step 2 · Snapshot.** "Which snapshot should the page show?" Radio rows, newest
first, for every drive state snapshot of this drive made by its owner: date,
file count, size, and "N changes since" (revisions after its `Block-End` in the
local database). Last row: "Create a new snapshot · Includes every change up to
now · <cost>". Below: "Snapshots in the older format can't be used." Over 100
MiB: the row is disabled with "Too large for a library page". With no
qualifying snapshot, "Create a new snapshot" is preselected and the only
option.

**Step 3 · Look.** Fields with live preview on the right (a social-card preview
and a browser-tab preview with the icon):

| Field | Control | Rules |
|---|---|---|
| Title | text, 60 chars | Required. Prefilled with the drive or folder name for a public drive, empty for a private one |
| Description | text, 160 chars, counter | Optional |
| Icon | image picker | Square, at least 512 × 512, PNG/JPEG/WebP/SVG, under 2 MB. Makes 32, 180, 512 px PNGs |
| Social card | image picker | 1200 × 630. Cropped to 1.91:1, re-encoded JPEG, aiming under 100 KiB |
| Cover | image picker | 1600 × 400. Cropped to 4:1, re-encoded JPEG, aiming under 100 KiB. Hint: "Keep text and faces in the middle; phones crop the sides" |

The image picker is a thumbnail plus "Change" opening a menu: **Upload an
image**, **Choose from this drive** (public drives only; lists image files),
**Use a transaction ID** (validated: the gateway returns an `image/*` content
type and the size rules above), **Remove**. For a private drive, "Choose from
this drive" is disabled with "Files in a private drive are encrypted. Upload
the image instead." A too-small or wrong-type image explains what is wrong and
what size to use.

**Step 4 · Name.** Until phase 4: a short panel: "Your library page will have
its own link. You can point an ArNS name at it later." No input. In phase 4:
the name picker (see [Names](#names)).

**Step 5 · Review and publish.** A summary (scope, snapshot, title, link or
name), the cost lines (new snapshot if any; images; page files: "Free") with
the existing payment cards, then, in the step itself, not a tooltip:

- "Publishing is permanent. It can't be undone or deleted."
- Private only: "Anyone with the drive key can read the whole drive, including
  files added later, folders outside this one, and hidden items."
- Private only: "The title, description and images are public."

The button is **Publish library page**.

**Progress.** The same dialog lists the steps with spinners and ticks:
snapshot (if new), images, page settings, page, page manifest, warm-up. A
failed step shows its error and **Try again**, which resumes from that step
(already uploaded items are reused, not re-paid).

**Done.** "Your library page is published." The link with **Copy** and
**Open**. Private: two copy buttons, "Copy link" and "Copy link with key",
the second with "Anyone with this link can read the whole drive." A note: "A
new page can take a minute to load the first time."

### Management section

In the details panel of a published drive or folder, a "Library page" section:
status chip (Live), the link with Copy and Open, "Published <date> from the
<date> snapshot", "N changes since then", **Republish**, and in phase 4
**Unpublish**. States:

| Condition | Shows | Action |
|---|---|---|
| Live and current | Link, dates | Copy, Open, Republish |
| Live and behind | "N changes since then" | Republish |
| Drive syncing | "Syncing; republish when it's done" | Republish disabled |
| Pending uploads in scope | "N uploads aren't confirmed yet" | Republish disabled |
| Not on web | Link and dates only | none |

Published pages are found from the owner's own uploads by tags (below), so the
section shows on any device. No database change.

**Republish** opens the dialog prefilled from the page's current
`library.json`, with scope fixed, starting at the snapshot step. It writes a
new page manifest; in phase 4 it also moves the name.

### Tags

Every library upload carries `App-Name: ArDrive-Web`, `App-Version`, and
`Type`: `library-page` (manifest), `library-config` (`library.json`),
`library-index` (`index.html`), `library-asset` (images). The manifest also
carries `Drive-Id`, `Library-Scope` (`drive` or the folder ID) and
`Library-Version: 1`. Discovery: owner = wallet, `Type = library-page`,
`Drive-Id`.

Images, `library.json`, `index.html` and the manifest are plain public data
items, never ArFS entities: they must be public for a private drive, and they
must not appear as files in the drive.

## Private libraries

- The key travels like a private drive link's, `#/?driveKey=…`, in the fragment
  only. Typed keys are never written to the URL.
- The snapshot and files decrypt in the browser with the existing derivation.
- Nothing about the drive's contents is outside the encrypted snapshot: no
  manifest file paths, no names in `library.json` or tags.
- The review step states the three facts above.

## Phases

| Phase | Ships | Done when |
|---|---|---|
| 0 · Compressed bundle (#2343) | `--compress gzip` in staging and production deploys; a staging channel | A staging upload loads through turbo-gateway.com and ardrive.net with every JS/wasm file carrying `Content-Encoding: gzip`; every path loads through ar-io.dev once it has fetched the upload (it may serve gzipped items decompressed, which is valid); first-visit transfer is measured |
| 1 · Library mode | The viewer, public libraries, a script that builds a test page by hand | A hand-built page at a raw manifest URL opens a public drive and a public folder, with no request outside the serving host and gateway |
| 2 · Publish (public) | Dialog steps 1, 2, 3, 5; management section; republish; tag discovery | A public drive and folder publish from the app; republishing with an existing snapshot and the same images costs nothing; excluded counts match the page |
| 3 · Private | Unlock screen, encrypted snapshots, private rules | A private folder opens in a clean profile with the key, and no drive, folder or file name appears in the manifest, `library.json`, `index.html` or any tag |
| 4 · Names | Step 4, unpublish, placeholder page | Needs ArNS-on-Solana in the app first |

Phase 1 must reach a production release before any real page works, because a
page runs the release it pins.

## Risks

- **A gateway serving gzip bytes bare** breaks a page on that gateway. Load
  each deploy through every gateway that matters before switching production.
- **Phones and large snapshots:** a snapshot near the 100 MiB bound lives in
  memory. Measure in phase 1; above a size to be found, step 2 warns "This
  library may be slow on phones."
- **Old pages run old code for ever.** Library mode must stay narrow (one host,
  one gateway) so pages age well.
- **Fallback fonts (decided 2026-10-22: self-host all of them).** Flutter
  3.19.6 hard-codes `https://fonts.gstatic.com/s/` (`font_fallbacks.dart:452`;
  `fontFallbackBaseUrl` arrived later), downloads Roboto from it on every start
  unless a `Roboto` family is bundled, and downloads one of 143 Noto fonts
  whenever text needs a glyph the bundled fonts lack. It fetches them through
  `window.fetch`. So the Arweave bundle carries the engine's 144 font files
  under `fonts/gstatic/` (fetched by CI from a checksum-pinned list, not kept
  in git, not deployed to Firebase: 80.7 MB raw, about 45 MB gzipped, uploaded
  once per Flutter version and reused after), and in library mode a short
  script in `index.html`, run before Flutter starts, rewrites
  `https://fonts.gstatic.com/s/` to `./fonts/gstatic/`. Visitors download only
  the fonts their text needs, as before. Re-derive the list on every Flutter
  upgrade.
