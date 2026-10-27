# Names

> **Status: phase 1 built** on the `arns-names` branch, behind the
> `enableArNS` config flag: on in development and staging, off in production
> until it is turned on there with a `configVersion` bump. The design was agreed with
> Phil on 2026-10-25 and 2026-10-26 (decisions Q1 to Q29 below). This is the
> standard for names, deployments and publishing across every ArDrive app:
> web, desktop, CLI and core-js.

ArNS names are human-readable names for Arweave content (`ardrive.ar.io`,
`blog_ardrive.ar.io`). ArNS moved to Solana: names are owned by Solana keys,
and every change to what a name points to needs a Solana signature. Turbo can
pay for those changes with credits, so nobody needs SOL.

This spec covers giving a deployment, a public file or a publication a name,
managing your names in one place, and paying with credits. Buying names is
phase 2.

## Contents

- [Terminology](#terminology)
- [Principles](#principles)
- [Where it lives](#where-it-lives)
- [Wallets and paying](#wallets-and-paying)
- [Flows](#flows)
- [Where names are recorded](#where-names-are-recorded)
- [Protocol](#protocol)
- [Code](#code)
- [Across ArDrive](#across-ardrive)
- [Phases](#phases)
- [Testing](#testing)
- [Risks](#risks)
- [Decisions](#decisions)

## Terminology

These words are used in every ArDrive app, help article and release note.

| Say | Means | Don't say |
|---|---|---|
| Name | An ArNS name, such as `ardrive`, reachable at `ardrive.ar.io` and on every gateway. "ArNS name" on first mention and in help, which also bridges to the console's "domains". | domain, ANT, record, process |
| Undername | A name under a name: `blog` in `blog_ardrive.ar.io`. ar.io's own word. | subdomain |
| Points to | What a name opens: an ArDrive item or a transaction. | target, transactionId |
| Cache time | How long gateways may keep the old answer after a change. 5 minutes by default. | TTL |
| ArNS wallet | The Solana wallet linked to approve name changes. | Solana signer, secondary wallet |
| Wallet | Your ArDrive wallet: your account, and what pays in credits. | primary wallet (in the app) |
| Deployment | A manifest: a folder served as a website or app. | manifest |
| Publication | A published drive or folder page. | library page |
| On the web | The left-nav group for what you've put on the web: Names now, Published later. | Permaweb, Publishing |
| Credits | Turbo credits, the only way to pay for name changes. | winc |

## Principles

- **Name things where they live.** You name a deployment from the deployment
  and a publication while publishing. The Names page is an overview, not the
  only door.
- **One account, one way to pay.** Your ArDrive wallet is your account and
  pays in credits. The ArNS wallet only approves name changes, and only when
  you act.
- **The chain is the truth.** What a name points to is read from ArNS, so
  changes made in the console show up in ArDrive. What ArDrive writes into
  metadata is a public hint, checked before anyone relies on it.
- **Say the cost before the prompt.** Every change shows its price in credits
  before any wallet asks for approval.
- **Plain words.** People see "name", "points to" and "cache time", not
  "ANT", "record" and "TTL".

## Where it lives

Names appear at three levels, each with one job.

| Level | Where | Job |
|---|---|---|
| Item | The item's menu (Add name, Change name, Remove name), the details panel's **Name** section, and a name chip (the ArNS name icon) on explorer rows | Name this thing, see its name, copy its link |
| Flow | An optional step in Publish, Create deployment and uploading a single public file | Name it while making it |
| Account | **On the web › Names** in the left nav; the ArNS wallet row in the profile card | See every name and undername, what each points to and its cache time; link the wallet |

Settings is not a level: names aren't preferences. Buying, renewing,
ownership, controllers and primary names stay in the ar.io console
(`https://console.ar.io`), linked from the Names page.

The left nav today has drive rows only (`lib/components/side_bar.dart`,
`lib/drives_list/presentation/drive_scope_rail.dart`). "On the web" is a new
group below the drives, shown both on the drives list and inside a drive,
with one row, **Names**. It needs its own row type: `DriveScope` filters
drives and must not grow a non-drive value.

Nameable items (Q5): deployments, public files, and publications (public or
private). Never a private file.

## Wallets and paying

This follows the ar.io console.

- **Link once.** Any Solana wallet that implements the
  [Wallet Standard](https://github.com/wallet-standard/wallet-standard)
  (Phantom, Solflare, Backpack, MetaMask's Solana account). ArDrive remembers
  the address per profile, so reading names needs no live connection. The
  address is cleared on sign-out.
- **Asked for at commit.** The action button itself becomes the next step:
  "Link a Solana wallet", then "Reconnect Solana wallet". The line under it:
  "Link the wallet that holds your names to approve this. Your ArDrive
  account stays the same."
- **Signed in with Solana?** That wallet is the ArNS wallet already.
- **Credits pay; the ArNS wallet approves.** Turbo allows the payer and the
  owner to be different wallets. The ArDrive wallet signs the payment and its
  credits are debited; the ArNS wallet signs a proof message for each change.
  When Turbo is not a controller of the name, the ArNS wallet also signs one
  transaction that Turbo has already paid for, so the wallet may ask twice.
  The ArNS wallet never needs SOL.
- **Cost first.** Read from Turbo's price endpoint before the prompt, never
  "free". On 2026-10-25: about 0.12 credits to point or repoint a name, 0.001
  credits to remove an undername. The cost line covers the name change and the
  small metadata update together.
- **Nothing lost on a cancel.** Rejecting the proof prompt charges nothing,
  because it comes before the action is created. If the transaction approval
  comes too late or is declined, Turbo refunds the credits automatically
  (within 15 minutes) and ArDrive says so, once: a declined prompt is
  forgotten, while a reload during the prompt is kept and reported on the
  next load.
- **After a reload.** The next load reads the status of each change the
  page left unfinished, once, and never creates it again. Completed: "Name
  saved". Failed: the credits come back. Expired, or still awaiting the
  ArNS wallet's approval: "The change to blog_acme.ar.io wasn't approved in
  time, so it wasn't made. Your credits come back within 15 minutes." A change still awaiting
  approval can't be finished after a reload, because Turbo's status read
  never returns its transaction, so it is left to expire and is refunded.
  Each of these is then forgotten. A status that can't be read is asked
  again on the next load, and anything still unresolved after a day is
  dropped.
- **Names you manage for someone else** (Q23). Turbo sponsors only a name's
  owner and rejects a controller's proof. A controller's ArNS wallet signs the
  change itself and pays the Solana fee: about 0.000005 SOL to repoint, about
  0.003 SOL of rent for a new undername. Said once, under the amount in the
  cost line: "You manage this name for its owner, so your ArNS wallet pays
  this network fee instead of credits." A wallet without enough SOL is told
  so before anything is signed.
  This is the only exception to credits only.
- **Wrong account connected.** If the wallet is on a different account from
  the linked one: "Switch to 7xKp…q2Fd in your wallet, or change your ArNS
  wallet."
- **No Solana wallet on this device.** Common on phones, where wallets only
  inject inside their own app browsers: "No Solana wallet found", with links to
  open ArDrive in Phantom or Solflare, or to install one. Names stay readable
  from the remembered address.
- **Profile card.** A second row under the wallet: "ArNS wallet", the
  shortened address in monospace, and Connected or Reconnect, Change, Unlink.

## Flows

### Name an item

1. From the item's menu, the details panel or a flow step, choose **Add name**.
2. The picker lists the names you own or manage, with undernames under each,
   in the console's simple style. Pick the name itself or an undername, or
   create an undername inline while slots remain ("3 of 10 undernames used").
   When every slot is used: "All 10 undernames are in use", with a console
   link (Q28).
3. If the chosen name already points somewhere, confirm: "blog_acme.ar.io
   points to *Last year's site*. Point it here instead?" (Q11)
4. Advanced, folded away: **Cache time** 1 min, **5 min**, 15 min, 1 hour,
   1 day, with one line on the trade-off (Q8, Q16).
5. The cost line, then **Add name**. The ArNS wallet approves; Turbo makes the
   change; the details panel shows the name with "Live within about 5
   minutes".
6. ArDrive writes the name into the item's metadata as a public hint (Q6).

**Change name moves the name.** When the item already has a name, Change
name points the chosen name at it and removes the old one in the same flow
("Also remove blog_acme.ar.io", checked by default). The removal is its own
change with its own nonce, and its cost is in the cost line: about 0.001
credits for an undername; a main name goes to the empty page at the
set-record price, and when no page is configured the box isn't offered and
the old main name stays. If the removal fails, the new name is
live, the old one is unchanged, and nothing is tried again.

**Undername rules.** Letters, digits, `-` and `_`; starts with a letter or
digit; 1 to 61 characters (`^[a-zA-Z0-9][a-zA-Z0-9_-]{0,60}$`, the console's
and Turbo's rule). The whole `undername_name` label must fit DNS, at most 63
characters. `@` is the name itself.

### In flows

Publish, Create deployment and uploading exactly one file to a public drive
have an optional name step, folded away, with the dialog's picker and cost
line. The flow's button waits until the step is priced and the ArNS wallet
is connected. The record change runs once the item's transaction exists;
the flow's success screen shows the name, or says plainly which name wasn't
changed (the upload stands). Files get the metadata hint in a small
revision afterwards; a publication carries its names in `publication.json`.

### New versions

- **Update a deployment, upload a new version of a named file, or republish a
  named publication:** the name moves to the new version automatically, said
  in the confirm step with its cost, with a box to leave the name where it is
  (Q12, Q29). Only ArDrive web moves names: a new version uploaded from
  another app leaves the name on the old one, and the Names page shows it
  pointing at an older version.

Updating a deployment, uploading a new version of a named file (same file
ID, one file to a public drive) and republishing a named publication each
say "acme.ar.io moves to the new version" in the confirm step, with the
cost and a box to leave it. If the upload succeeds and the name change
fails, the flow says so; the upload stands.

### Removing

- **Remove an undername:** its record is deleted (Q13).
- **Remove a main name** (`acme.ar.io`): it points at the empty page, a
  small page of ArDrive's, so the name never breaks. The page is uploaded
  once by ArDrive (a free-size upload) and its transaction ID is set in the
  app config as `arnsPlaceholderTxId`.
- **Hide a named file:** ArDrive offers to remove its name. Files can't move
  between drives, so hiding is the only way an item leaves public view.

### What stays as built

- The metadata part of the cost line is an upper bound: one revision is
  priced as a 4 KiB upload, so the line never undersells it.
- Repointing a name away from another item leaves that item's
  `assignedNames` stale. Harmless: hints are checked against the gateway
  before anyone else sees them.
- Remove name in an item's menu acts on its first name when it has several;
  the details panel's Name section offers Remove on each.
- The desktop details panel has no menu: its Name section carries Change
  and Remove. The phone details menu has the menu items.

### The Names page

Every name and undername you own or manage, with no wallet address in the
header (the profile card has it, where the ArNS wallet is linked), and:

- what each points to: the ArDrive item when recognised, "Empty page" for a
  main name on the empty page, otherwise "Points elsewhere" (Q22), which you
  can point at an ArDrive item. The transaction ID is in the tooltip, not
  the row;
- its cache time, changeable here (Q16);
- Change and Remove actions;
- "Managed for its owner" on names you control but don't own (Q23);
- a prompt to use a name with nothing linked;
- console links for buying, renewing and ownership.

**Lease ends.** Each leased name shows its end date. From 30 days out:
"Renews in 12 days", with a console link. In the 14-day grace period after a
lease ends, changes are blocked (the chain rejects them) and the page says
"Renew this name in the console to keep it". Permanent names show no date.

### Publications

- The name step sits in Publish. The page and its share link use the name
  when there is one.
- A private publication's name opens its unlock screen (Q27). "Copy link"
  gives the name plus the key after the `#`, with the usual private-link
  warning. Private publications aren't built yet (docs/PUBLICATIONS.md,
  phase 3: the publisher writes public pages only), so this lands with them.
- Publications are nameable from the Names page: its picker lists the
  owner's publications (latest version) beside files and deployments.
- The social image stays on its own transaction, as built today (Q26): no
  `social_` undername.

### Visitors

Someone viewing a public drive, a shared drive or a publication sees a file's
name only after the gateway confirms the name still points at it, with one
request per named item, cached for the session. That holds for the row chip,
the details panel's read-only Name section (the name to open or copy, nothing
to manage) and the Activity tab, where an unconfirmed name change reads "This
file was modified."

The check is a `HEAD` to `https://<undername>_<name>.<gateway host>/`: ar.io
gateways return the transaction the name resolved to in
`X-ArNS-Resolved-Id` (ar-io-node `src/constants.ts`), and expose every
header to browsers (`exposedHeaders: '*'` in `src/app.ts`). A name is shown
when that ID is the file's data transaction. A failed or slow request means
no chip; the listing never waits for it (`lib/arns/data/arns_name_verifier.dart`).

### The empty page

The empty page is what a removed main name points at. Visitors see "Nothing
here right now"; owners see "Empty page" in the Names page's "Points to"
column. It is `assets/arns/nothing_published.html` (about 32 KiB, no
external requests, light and dark, with the ArDrive logo and Wavehaus
inlined; rebuild it with `python3 tool/arns/build_nothing_published.py`).
It is not bundled into the app. On mainnet it is
`hAs_l8a7vXqD2LTZ8MtM09-HpwYo21ynvZwoJtbYaTk` (uploaded 2026-10-26, set in
all three configs; ar-io.dev serves it for devnet names too). To set up a
new copy:

1. Upload the file as a public file, `Content-Type: text/html`, from an
   ArDrive team wallet (any public drive, or `ardrive upload-file` with the
   CLI). It is under Turbo's free size.
2. Put its data transaction ID in `arnsPlaceholderTxId` in
   `assets/config/prod.json`, `staging.json` and `dev.json` (a devnet
   upload for dev if names run on devnet there), and bump `configVersion`
   so stored configs pick it up.
3. Until it is set, removing a main name is disabled with a short reason.

## Where names are recorded

| Record | Who reads it | Trust |
|---|---|---|
| ArNS (on Solana) | The owner's ArDrive, the console, every gateway | The truth |
| File metadata `assignedNames` | Visitors, shared drives, publications (through the drive state), the CLI and desktop | A hint: written on every add and removal, checked against the gateway before it's shown |
| `publication.json` `names` | Visitors of a publication | A hint, written each time the publication is published (Q25) |
| Local tables `arns_records`, `ant_records` | The app, for speed and search | A cache, refreshed from ArNS when the Names page opens and after every change |

`assignedNames` exists on file entities only (`FileEntity`, the uploader's
`arfs_upload_metadata.dart`, the drive state artifact), which covers
deployments. Writing the hint on every change also fixes an old gap: naming a
file used to skip the metadata write when paying in AR.

## Protocol

### Reads (`@ar.io/sdk` 4.5.x, in the browser bridge)

- `ARIO.getArNSRecordsForAddress` lists the names a Solana address owns or
  controls, with `endTimestamp`, `type` (lease or permabuy) and
  `undernameLimit`. It reads access-control accounts plus point lookups and
  never scans a program.
- Owner versus controller comes from `getANTSummaries` (owner and
  controllers per ANT). The access-control list lags a marketplace transfer
  until someone updates it, so the owner check is what decides the payment
  route.
- Undernames come from `ANT.getRecords` (one `getProgramAccounts` per ANT) or
  `getRecord` for one.
- Lease grace period: 14 days (`LEASE_GRACE_PERIOD`).
- RPC: ArDrive's own endpoint, no public fallback. Mainnet and devnet program
  IDs come from the SDK.

### Writes (Turbo ArNS actions)

The turbo-sdk documents the protocol; ArDrive implements it directly in Dart
over HTTP, with only the Solana signatures in JavaScript, so no key crosses
into the bridge and the 17 MB turbo bundle isn't needed.

1. **Price.** `GET {payment}/v1/arns/actions/{action}/price`, no auth.
2. **Owner proof.** The ArNS wallet signs `message + proofNonce`, where
   `message` is newline-joined: `arns`, the action, then its fields.
   - `set-record`: `antId`, `undername`, `transactionId`, `ttlSeconds`
   - `remove-record`: `antId`, `undername`

   Headers: `x-owner-public-key` (base64url of the 32-byte key, which is the
   base58-decoded address), `x-owner-nonce`, `x-owner-signature` (base64url),
   `x-owner-signature-type: 4`.
3. **Create.** `POST {payment}/v1/arns/actions/{action}` with the payer's
   signed-request headers over a fresh UUID nonce (`x-nonce`, `x-signature`,
   `x-public-key`, and `x-signature-type` for non-Arweave signers) and a JSON
   body: `set-record` takes `antId`, `ownerAddress`, `transactionId`,
   `undername` (`@` for the name itself), `ttlSeconds`; `remove-record` takes
   `antId`, `ownerAddress`, `undername`. **Credits are debited here.** The
   response's `nonce` is the idempotency key: persist it before any further
   prompt. Never re-create an action to retry. A 402 means not enough credits.
4. **Branch on `status`, never on the action.** `completed`: done.
   `awaiting-signature`: Turbo was not a controller; the ArNS wallet signs the
   returned base64 `transaction` as is (Turbo has already signed as fee payer)
   within about 30 seconds.
5. **Sign.** `POST {payment}/v1/arns/actions/{nonce}/sign` with
   `{"transaction": "<base64 signed transaction>"}`, no payer headers.
   Re-posting the same bytes is safe. 409, or 400 "expired": the action
   expired and its credits are refunded. 503 "Blockhash not found": re-post
   the same bytes, don't re-create.
6. **Status.** `GET {payment}/v1/arns/actions/{nonce}` to learn how an
   action ended after a lost response or a reload. It never returns the
   transaction of an action awaiting signature, so such an action can't be
   finished after a reload: it is left to expire and is refunded.

Always pass `ttlSeconds` (300 by default): Turbo's own default is 3600.

**Controllers** write directly with `@ar.io/sdk`'s ANT writer, signing and
paying with the ArNS wallet (the console's `antWriter.ts`).

**Devnet.** Turbo's sandbox, `https://payment.services.ar-io.dev`, runs ArNS
on Solana devnet. The dev-tools devnet switch points the bridge at devnet
program IDs and RPC and the action client at the sandbox together.

## Code

| Piece | Where |
|---|---|
| Browser bridge: reads, Wallet Standard connection, message and transaction signing, controller writes | `packages/ario_sdk/web/src/` (built to `web/js/ario_sdk.min.js`) |
| Dart API over the bridge | `packages/ario_sdk/lib/` |
| Turbo ArNS action client (price, create, sign, status) | `lib/arns/data/` |
| Names repository: the names an ArNS wallet owns or manages, their records, mapped to ArDrive items; the local cache | `lib/arns/data/`, `lib/arns/domain/` |
| UI: picker dialog, details Name section, row chip, Names page, profile row | `lib/arns/presentation/` |
| Flag | `enableArNS` in `assets/config/*.json` and `AppConfig`, with a dev-tools toggle |

The feature follows the app's design system (`packages/ardrive_ui`, new
generation only) and the monospace rule: every transaction ID and wallet
address in Roboto Mono, full or shortened.

## Across ArDrive

- **Web app:** everything here.
- **Desktop:** the same words, the same `assignedNames` hint, the same
  5-minute default, and, when names come to desktop, the same three levels.
- **CLI and core-js:** read and write `assignedNames` the same way; command
  and flag names use "name" and "undername".
- **Help centre and releases:** the terminology table.

## Phases

### Phase 1: names you already own

One PR, `arns-names`, kept off `dev` until the publishing release ships, and
behind `enableArNS` after that.

1. **Foundation.** `@ar.io/sdk` 4.5.x in the bridge; the Wallet Standard
   connector and remembered ArNS wallet; the Turbo action client; the names
   repository; the flag; devnet.
2. **Naming.** The picker, add, repoint with confirm, remove, cache time, the
   cost line and the approval flow; the metadata hint; the details panel's
   Name section, the row chip and search by name.
3. **Placement.** The On the web group and the Names page; the ArNS wallet
   row in the profile card.
4. **Flows.** The name step in Publish, Create deployment and single-file
   upload; names moving with new versions; the empty page;
   visitor checks.

### Phase 2: getting a name

Buy a name with credits inside Publish and from the Names page (a lease of 1
to 5 years or permanent, its target set in the same step), and buy more
undername slots.

## Testing

- Unit tests for the action client (message bytes, headers, the two status
  shapes, no re-create on failure, refunds), name validation, and the
  repository's mapping to ArDrive items.
- Devnet end to end first, against the sandbox, with a devnet name.
- Mainnet with a name the test wallet owns. Each record change costs about
  0.12 credits; report every cost, and get Phil's go-ahead beyond the
  approved budget.
- Desktop and phone-width screenshots of every new screen, light and dark.

## Risks

- **Double charges.** Each action debits when created. ArDrive never
  re-creates an action to retry; it polls the one it made and reports a
  refund when there is one.
- **Two prompts.** Names where Turbo isn't a controller need a proof and a
  transaction signature; the second must land within about 30 seconds.
- **Names moved outside ArNS** drop out of "your names" until the owner
  resyncs them. The Names page says so when it happens.
- **Solana RPC limits.** ArDrive's own endpoint, no public fallback, no
  program scans.
- **Unclaimed Arweave-era names** are ignored (Q7). Their owners claim them
  through ar.io; ArDrive shows them once they're in a Solana wallet.

## Decisions

| # | Decision |
|---|---|
| Q1 | Naming actions and a Names page in ArDrive; buying, renewing, ownership and controllers link to the console. |
| Q2 | Buying with credits is phase 2. |
| Q3 | The console's wallet model: one linked ArNS wallet, remembered, asked for at commit, automatic for Solana sign-in, shown in the profile card. |
| Q4 | Credits only, cost shown before the wallet prompt. One exception: controllers (Q23). |
| Q5 | Nameable: deployments, public files, publications (public or private). Never private files. |
| Q6 | Keep writing names into metadata as a hint; the owner sees the chain, visitors see a name only after the gateway confirms it. |
| Q7 | Unclaimed Arweave-era names: ignore. |
| Q8 | Cache time 5 minutes by default, changeable. |
| Q9 | Remove the dead name step now (#2357). |
| Q10 | A simple picker like console.ar.io: the name or an undername, new undernames inline. |
| Q11 | Confirm before repointing. |
| Q12 | New versions move the name automatically, said in the confirm step with its cost. |
| Q13 | Undernames are deleted on removal; main names point at the empty page; offer removal when a file is hidden. |
| Q14 | Names show as a row chip, a details Name section, in search, and on publications. |
| Q15 | An "On the web" group in the left nav: Names now, Published later. |
| Q16 | Cache time in the dialog's Advanced section and on the Names page. |
| Q17 | No primary-name work for now. |
| Q19 | The word is "Name"; "ArNS name" on first mention; not "domain". |
| Q20 | "Undername", explained once in the picker. |
| Q21 | Add name, Change name, Remove name. |
| Q22 | Names pointing outside ArDrive are listed as "Points elsewhere" and can be repointed. |
| Q23 | Controllers can change records, paying the Solana fee themselves. |
| Q24 | The design page first, then this spec, shared with desktop and the CLI. |
| Q25 | Publications carry the name in `publication.json`, written on each publish. |
| Q26 | The social image stays on its transaction; no `social_` undername. |
| Q27 | A private publication's name opens the unlock screen; "Copy link" adds the key. |
| Q28 | Out of undername slots: a console link; buying more slots is phase 2. |
| Q29 | Names follow new file versions and republished publications, with a box to leave the name where it is. |
