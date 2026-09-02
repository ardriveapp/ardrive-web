# Aligning "Your Drives" with the rest of the app's tables

Why the drives list looks like a different product, exactly which properties
differ, and the order to close them in without breaking a surface that
currently works.

## The finding

They are not two configurations of one table. They are two tables.

Every other list in the app renders through `ArDriveDataTable`
(`packages/ardrive_ui/lib/src/components/data_table/data_table.dart`) — the file
explorer, the move dialog, the hide dialog, the license form, the shared-file
view. "Your Drives" is bespoke: a `CustomScrollView` of slivers in
`drives_list_page.dart` with rows from `drive_list_row.dart`, sharing no widget
and no token with the other one.

That is the whole reason it feels different. Nothing is subtly off; it was
built separately.

## What actually differs

Measured, not estimated.

| Property | Explorer (`ArDriveDataTable`) | Your Drives (bespoke) |
|---|---|---|
| Outer container | `ArDriveCard`, `tableTheme.backgroundColor` (`#FAFAFA` light) | none — rows sit on the page ground |
| Content padding | `horizontal: 16` | `horizontal: 16` (page-level) |
| Row surface | `ArDriveCard` per row | bare `Container` |
| Row separator | none | 1px `strokeLow` bottom border |
| Row padding | `h15 / v0` | `h16 / v14` |
| Trailing block | fixed `height: 44` | intrinsic |
| Selected row | `themeBorderDefault` @ 25% opacity | **nothing** |
| Hover | `containerL1` | `containerL1` |
| Header | inside the card, 28 above / 25 below | standalone sliver above the card-less list |
| Pagination / rows-per-page | yes | no |
| Multi-select | yes | no |
| Column show/hide | yes | no |
| Sort | yes | no |
| Narrow screens | **no stacked mode** — a separate `_mobileView` (~200 lines) in `drive_detail_page.dart` | one widget, `showsColumns` switches to a stacked card |

The two rows at the top of that table are the ones a user sees. The explorer's
list reads as a **panel** — a tinted card floating on the page ground. The
drives list reads as **bare rows on the page**, separated by hairlines. That
single difference accounts for most of "it looks like a different table".

## Recommendation: align the chrome, keep both implementations

Do **not** port the drives list onto `ArDriveDataTable`. Three reasons, in
order of weight:

1. **`ArDriveDataTable` has no responsive mode.** It renders one column layout
   at every width; the explorer copes by having a wholly separate mobile view.
   The drives list handles both in one widget through `showsColumns`. Porting
   means deleting the better of the two responsive designs and writing a second
   mobile path to replace it.
2. **It would import machinery the page does not want** — pagination,
   rows-per-page, multi-select, column visibility — all of which would then
   have to be suppressed.
3. **The page is more than a table.** Scope filtering, per-scope empty states,
   the sync-everything prompt and the sync states live in the sliver structure.
   They would all have to be rehomed around a widget that owns its own scroll.

The goal is that the two *look* like one system. That does not require them to
*be* one widget — it requires them to read their chrome from one place.

## Tier 1 — close the visible gap

Purely presentational. No behaviour changes, no structural changes.

1. **Give the drives table the panel.** Wrap the header + rows region in
   `ArDriveCard` with `tableTheme.backgroundColor` and
   `contentPadding: EdgeInsets.symmetric(horizontal: 16)`, matching
   `data_table.dart:432`. Biggest single win; do this one first and reassess,
   because it may be most of what is wanted.
2. **Settle the separator policy.** The explorer has no row borders; the drives
   list has a `strokeLow` bottom border on every row. Pick one. Recommend
   dropping the border, since the card ground plus hover already separates rows
   in the explorer and the border is what makes the drives list read as a
   "spreadsheet" rather than a panel.
3. **Align row metrics** to the explorer's `h15 / v0` with the trailing block's
   `height: 44`. The drives list's `h16 / v14` produces a visibly taller,
   looser row.
4. **Add the selected-row state.** The drives list has none at all; the explorer
   tints with `themeBorderDefault` at 25%. A drives list that cannot show which
   drive is current is a real gap, not only a cosmetic one.

## Tier 2 — make it stay aligned

Tier 1 fixes today's drift and does nothing about tomorrow's. Extract the
chrome into `ardrive_ui`:

- `ArDriveTableShell` — the outer card, background, content padding, header
  spacing.
- `ArDriveTableRowShell` — row surface, padding, height, hover, selection tint,
  separator policy.

Have `ArDriveDataTable` build from them internally, and have `DriveListRow` and
`drives_list_page` use them directly. Both tables then read one source, and the
next new surface gets the chrome for free instead of copying whichever table it
happened to be sitting next to.

This is the step that makes the alignment permanent, and it is the one worth
doing properly.

## The other direction: bringing the drives list's model to `ArDriveDataTable`

The more interesting question, and a better one than porting. It is worth
doing, but "our better model" needs to be said precisely, because the drives
list is better mainly where it is *narrower*.

**Portable, and genuinely better:**

- **One widget for both widths.** `showsColumns` switches columns to a stacked
  card. `ArDriveDataTable` renders one layout at every width, so the explorer
  carries a separate `_mobileView` with its own `ArDriveItemListTile` and
  `ListView.separated`. Collapsing that is the real prize — it deletes a whole
  duplicate rendering path rather than tidying one.
- **Sliver-based whole-page scroll.** `SliverChildBuilderDelegate` is already
  lazy, so this is not only a scrolling change: it could replace pagination
  outright rather than sitting beside it.

**Not better — simply absent.** The explorer depends on all of these and the
drives list has none of them:

- Pagination at 100 per page. Fine to omit for a wallet's ~20 drives; not for a
  folder with ten thousand files.
- Multi-select — load-bearing for bulk download, move and hide.
- Column visibility and sort.

So this is not a model swap. It is: **take the drives list's chrome and its
responsive strategy, keep the explorer's data machinery.**

### Sequencing, by blast radius

`ArDriveDataTable` renders eleven surfaces. That governs the order.

1. **Extract the shared chrome** (Tier 2 above). Additive, no behaviour change,
   both tables benefit at once. Worth doing regardless of what follows.
2. **Collapse the explorer's mobile path** into one responsive widget. Its own
   PR — that path is not purely duplicated chrome, it carries its own search
   field and tile widget, and each needs a home in the merged design.
3. **Lazy slivers instead of pagination.** A UX decision before it is a code
   change: decide whether infinite scroll is wanted in a file explorer at all.
   Do not let it ride along with step 2.

Step 1 is safe because it changes nothing that renders. Steps 2 and 3 change
what eleven surfaces do, which is the reason they are separate PRs and not a
single "modernise the table" branch.

## Tier 3 — not now

Full port of the drives list onto `ArDriveDataTable`, once that widget has a
stacked mode and its optional machinery is genuinely optional. Blocked on both.

## Risk register

- **The card must not reintroduce a fixed height inside a scroll view.** The
  page is a `CustomScrollView` because the whole page scrolls — a landscape
  phone (568x264, also a portrait phone at large text scale) has less height
  than the sync prompt alone. Wrapping the list in a `Container` with a pinned
  height inside a scroll view is exactly the bug just fixed in the sidebar,
  where the scroll view had nothing taller than itself to scroll and the drive
  list simply clipped. Wrap the sliver content — `SliverToBoxAdapter` segments
  or a decorated sliver — never a height-bounded box.
- **Row metrics feed the sync states.** The row renders "Never synced",
  "Syncing…" and the failure line; tightening vertical padding must be checked
  against the tallest of those, not the shortest.
- **The stacked mode has no card to sit in.** On a phone the row *is* a card.
  Applying a panel background behind stacked cards can produce a card on a card;
  Tier 1 step 1 should apply on the columns layout only.

## Verification

Each step is covered by tests that already exist:

- `test/drives_list/` — the drives list's own widget tests, including the
  320px phone and 1.6x text-scale cases.
- `test/pages/drive_detail/` — the explorer, if Tier 2 touches shared chrome.
- `packages/ardrive_ui/test/` — the shared table's own suite.

Run all three after every step, not only at the end: Tier 2 changes a widget
that eleven surfaces render through.
