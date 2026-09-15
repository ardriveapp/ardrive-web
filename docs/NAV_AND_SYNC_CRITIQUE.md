# Navigation and sync — a design critique

Written against the drives list on desktop at `2.86.0`, and the code behind it.
Opinionated on purpose. Ordered by how much each item costs the user, not by how
hard it is to fix.

## What is genuinely good

- **"Your Drives" as the landing page is the right call.** Landing inside one
  arbitrary drive was worse, and the table answers the question a returning user
  actually has: which drives do I have, and are they current.
- **The columns are well chosen.** Name, last synced, files, size, created. Nothing
  decorative, and `-` rather than `0` for what is not yet known is exactly right —
  it is the difference between "empty" and "unread" and most apps get it wrong.
- **The per-row kebab is standard** and the actions in it are the right set.
- **New is unmissable.** The one thing a new user must find is the one thing they
  cannot miss.
- **The sync menu groups sensibly** — run it, run it harder, see what happened.
- **The private/public glyph on every row** carries real meaning at a glance.

## Navigation — the structural problems

### 1. The sidebar and the main panel are the same list

This is the big one. The left nav lists every drive; the table lists every drive.
On this page the sidebar is pure duplication — the same names, in the same order,
with less information. Two answers to one question, side by side.

Every comparable product uses the sidebar for **scopes** and the main panel for
**contents**: Drive has My Drive / Shared / Recent / Trash; Dropbox has All files /
Shared / Signatures. The contents change; the scopes do not.

What this costs: on a wallet with fifteen drives the sidebar is a fifteen-item
scroll that has to be got past before Private and Shared are reachable at all —
they are sections *below* the public list, so they are off-screen in the
screenshot. The user cannot see their private drives without scrolling a list they
are already looking at in full on the right.

**What I would do:** make the sidebar scopes, not drives.

```
  ▣  All drives          ← the current page
  ⊞  Public
  🔒 Private
  ⇄  Shared with me
  ⊘  Hidden
```

The drive names then live in one place — the table — where they have columns to
explain themselves. The sidebar becomes short, fixed-height and genuinely
navigational, and Private stops being something you scroll to find. Inside a
drive, the sidebar can show that drive's folder tree, which is what the space is
actually worth.

This is the change that makes the rest of the layout make sense. It is also the
largest.

### 2. The sidebar and the page disagree about where you are

In the screenshot the sidebar highlights **ArDrive Desktop Drive** while the page
is **Your Drives**. Two "you are here" signals, pointing at different things.

The highlight means "last opened", but it is drawn exactly like "current". Either
drop it on this page or give last-opened its own weaker treatment.

### 3. Home sits beside the account, and the logo does nothing

The house is in the top-right cluster next to the wallet address. Home is not an
account action, and no comparable product puts it there — it belongs at the start
of the navigation, or it *is* the logo.

The ArDrive logo is top-left and inert. That is the most conventional home
affordance on the web and it is currently decoration. **Make the logo the way
home.** Then the house is either redundant, or it moves to the head of the sidebar
where a "back to all drives" control belongs.

Verified: `_buildLogo` has no tap handler.

### 4. Home is offered while you are already home

No active or disabled state. Pressing it on the drives list is a no-op the user
cannot predict. Whatever survives item 3 should read as current when it is.

### 5. Mobile inherits the duplication, worse

On a phone the sidebar is a drawer. Opening it from the drives list slides a
duplicate of the list you are already reading over the top of it. If the sidebar
becomes scopes (item 1), the drawer becomes useful; until then it is a second copy.

## Navigation — the details

- **The sync menu opens over the table headers.** It is anchored to the icon and
  expands left across "Files" and "Size". Anchor it to the right edge, or shift it
  down clear of the header row.
- **"Last synced" column, "Synced 20 minutes ago" values.** The word twice. The
  values should read `20 minutes ago` / `Never` and let the header do its job.
- **Sort is missing.** Five columns, no sort affordance. With thirteen drives —
  three of them named `UAT-TESTONLY-DELETEME` — sorting by last-synced or size is
  the first thing anyone will want.
- **Duplicate names are undisambiguated.** Two `Demo Drive 2`, three
  `UAT-TESTONLY-DELETEME`. Only "Created" tells them apart, and it is the furthest
  column from the name. Consider a truncated drive id on hover, or under the name
  when a duplicate exists.
- **The kebab is marooned.** At this width there is a large dead gap between
  "Created" and `⋮`. Right-align the actions column against the content, not the
  viewport.
- **"Version 2.86.0" is developer chrome in a user surface.** Move it into the
  account menu, next to Help.
- **The collapse control is a floating circle at the bottom-left** — an unusual
  spot. Sidebar collapse conventionally lives at the top of the rail or on its
  edge.
- **The Sync history row uses an ⓘ icon.** Information is not history. A clock or
  a list glyph says what it opens.
- **"Deep Resync" is unexplained jargon** in a menu with no room to explain it.
  There is already a written explanation in the ARB — `deepResyncTooltip` — and it
  is a dead key, referenced by nothing.

## The initial login sync — where this really hurts

The screenshot is the honest outcome of the current design, and it is not good:
**eleven of thirteen rows say "Never synced", with `-` for files and `-` for
size.** The landing page of a storage product, mostly blank.

Worse, the one control that would fix it in a single press is **not on the page**.
`nothingHasEverBeenSynced` requires *every* drive to be unwalked:

```dart
bool get nothingHasEverBeenSynced =>
    drives.isNotEmpty && drives.every((drive) => !drive.hasBeenWalked);
```

Two drives are synced here, so the offer to sync everything has already
disappeared — permanently, for the rest of this wallet's life. The remaining
eleven can only be synced one at a time, through a kebab menu, eleven times. The
top bar's "Resync" would do it, but it is named for a repeat of something that has
never happened.

That is the design flaw: **the bulk action vanishes exactly when there is bulk
work left to do.**

### What I would change, in order

**1. Keep the offer while there is anything unread.** Change the condition from
"nothing has ever been synced" to "something is still unread", and change the copy
to match what remains:

> **11 of 13 drives have not been read yet.** Sync them all · about 4 minutes

That single line replaces eleven kebab journeys.

**2. Put the action on the row, not in the menu.** A `Never synced` cell is dead
text where it could be the affordance. Make the cell itself the control —
`Never synced · Sync` — so the row explains itself and fixes itself in the same
place. The kebab stays for everything else.

**3. Name the first one honestly.** "Resync" is wrong before anything has synced.
When `nothingHasEverBeenSynced`, the menu row should read **Sync all drives**.

**4. Sort unread drives to the top on first landing.** Alphabetical is right once
everything is current. On a wallet where most drives are unread, the two that are
useful are scattered among eleven that are not. Sort by "needs attention" until
nothing does.

**5. Set the expectation before the wait, not during it.** `firstTimeSyncDriveCount`
is already computed in four places in the repository and rendered nowhere. A first
walk of a large drive takes minutes; nothing says so before it starts. One
sentence, once:

> First sync of 11 drives. Reading their full history takes a few minutes — you
> can keep using the app.

**6. Fill the table in as it goes.** The drives are already on screen with empty
cells. A sync that lands drive by drive could fill `files` and `size` in place, so
the page visibly becomes useful rather than sitting still behind a spinner. This
is the most interesting option and the least conventional: the progress indicator
*is* the table.

### On being more creative with the sync itself

The honest constraint is that this is not Dropbox: there is no push channel, one
HTTP request per revision, and a first walk of a large drive genuinely takes
minutes. Creativity has to go into **making the wait legible and useful**, not
into hiding it.

Three ideas, cheapest first:

- **Sync what they are looking at.** The drives list knows which rows are on
  screen. Syncing visible unread drives first — rather than alphabetically — means
  the part of the page a user is staring at fills in first.
- **Let the first run be different from every run.** Sync-on-login defaults off,
  which is right for a returning user and wrong for a brand-new one who has
  nothing. A one-time full sync on the *first* login of a wallet, then never
  again unless asked, gets a new user a working app without signing everyone up
  to a sync on every launch.
- **Spend the wait on something true.** During a first sync we know the drive
  count, the file counts as they arrive, and the total size. "Found 711 files ·
  13.17 GiB so far" is more interesting than a percentage, and it is the only
  moment the app can show a user the shape of what they own.

## If I could only fix three things

1. **Make the sidebar scopes, not a second copy of the drive list.** Everything
   else about the layout follows from this.
2. **Keep the bulk sync offer while anything is unread**, and put a Sync
   affordance on the row. Eleven kebab journeys is not a design.
3. **Make the logo the way home**, and drop or demote the house next to the
   account.
