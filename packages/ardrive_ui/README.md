# ardrive_ui

The ArDrive design system: the components, tokens and type every screen in
ArDrive web is built from. Use these pieces instead of drawing your own, and
when one falls short, fix it here so every screen gets the fix.

The package has two generations. Build with the new one, whose names end in
`New` or have no old counterpart. The old one (`ArDriveButton`,
`ArDriveTypography`, `ArDriveStandardModal`, `ArDriveTextField` and
`themeData.colors`) is being removed screen by screen.

## Tokens

| What | Use | Values |
|---|---|---|
| Colour | `ArDriveTheme.of(context).themeData.colorTokens` | Surfaces `containerL0`–`L3` and `containerRaised` (a card one step above its surroundings in both themes), text `textHigh`/`Mid`/`Low`, strokes, buttons, icons, and status colours |
| Status colour | `statusInfo…`, `statusWarning…`, `statusError…`, `statusSuccess…` | Each has `Fg` (icon, emphasis), `Container` (fill) and `Stroke` (edge). Body text on a status container stays `textHigh` |
| Spacing | `ArDriveSpacing` | `xxs` 4, `xs` 8, `sm` 12, `md` 16, `lg` 24, `xl` 32, `xxl` 48 |
| Radius | `ArDriveRadius` | `sm` 4 for small controls, `md` 8 for cards and notices, `lg` 12 for dialogs and sheets |
| Type | `ArDriveTypographyNew.of(context)` | Wavehaus. `heading1`–`6`, `paragraphXXLarge`–`paragraphSmall`, `caption`, each with a weight of `book`, `semiBold` or `bold`. Phone sizes apply under 834 px |

Secondary buttons are a translucent tint (8% white in dark, 8% black in light),
so they read as a step up from whatever surface they sit on.

Every colour comes from a token, in both themes. A literal colour, or a
Material one such as `Colors.green`, looks right in one theme only.

Status colours come from the [brand palette](https://ardrive.io/brand-kit/):
info from brand Info `#3142C4`, success from brand Success `#18A957`, and
error from the brand reds (the `solidRed` primitives). A lighter or darker
shade of the same hue is fine where the brand value can't be read on its
container. The palette has no warning colour, so a warning is neutral: a
raised surface, its edge and the normal text colour, with the warning icon
carrying the meaning. Don't add a yellow, orange or pink.

### Monospace

`ArDriveTypographyNew.of(context).code()` is Roboto Mono, Regular only. It
is for two kinds of text:

- Code, text-file previews and the note editor, where columns and markup
  have to line up.
- Transaction, file and drive IDs, wallet addresses and keys, whole or
  shortened (`abc123...xyz9`), where every character has to be told apart.
  An ArNS, ENS or SNS name is a name and stays in Wavehaus; the address
  under it is monospace.

Wavehaus stays the face for everything else, the same rule as the desktop
app (its D-046). The brand kit names no monospace face; ardrive.io uses the
system mono stack.

`code()` takes a `fontSize`, a step under the text beside it by default,
where monospace reads the same size. An ID or address that shares a row
with other things is drawn at its final width, so nothing moves when the
face loads and replaces the narrower fallback:

- `ArDriveIdText(id, style: typography.code())` for an ID on its own, and
  `ArDriveIdText.spansIn(sentence, id, idStyle: ...)` for one inside a
  sentence, such as "Owner: abc123...xyz9".
- `ArDriveLink` with a `code()` style sizes itself the same way.
- `ArDriveCopyField(isMonospace: true)` for a key or an ID to copy. A link
  stays in Wavehaus, key in it or not: it reads as an address to open.
- `ArDriveTextFieldNew(textStyle: typography.code())` for a field that takes
  an ID or a key. The field keeps the height of the others in the form.
- For anything else, `ArDriveMonospace.widthOf(text, fontSize)` gives the
  width.

The face is an asset, not an entry in the pubspec's fonts block: Flutter
web downloads every listed font before the first frame, and most sessions
never show code. `ArDriveMonospace` loads it the first time `code()` is
asked for, about 27 KB subset to Latin, and the text shows in Wavehaus until
it arrives. The licence is `assets/fonts/mono/OFL.txt`.

## Components

| Need | Component | Notes |
|---|---|---|
| A button | `ArDriveButtonNew` | `variant`: primary for the main action, secondary, or outline. `size`: see below. Sized to its label unless given `maxWidth`; `double.infinity` fills |
| A dialog | `ArDriveStandardModalNew` with `ModalAction`s | Opened with `showArDriveDialog` in the app. The last action is primary. Cancel and Close use `ModalAction.dismiss`, which is never red, even alone. Set `scrollableContent` for long content |
| A dialog on a phone, or a menu from the bottom | `showArDriveBottomSheet` with `ArDriveBottomSheet` | Same title, spacing and action row as a dialog |
| A text link | `ArDriveLink`, or `ArDriveLink.span` inside text | Keyboard reachable and announced as a link. `external` adds the new-window icon; `isAction` announces an action such as Copy as a button |
| A message with a meaning | `ArDriveNotice` | `type`: info, warning, error or success. `layout`: inline box or full-width banner. Optional title, action and close button |
| A label beside an item's name | `ArDriveTag` | `type`: neutral (default), info or success, and an optional leading `icon`. Caption, semi-bold, on a quiet fill with `ArDriveRadius.sm`. There is no warning or error tag: those are status text |
| A status in a line of text | `ArDriveStatusText` | `type`: neutral, info, warning, error or success, each with its own icon. Error is red text and icon; warning is neutral text with the warning icon. Use it for "Lease ends in 12 days" or "2 drives could not be read", never a boxed tag |
| Nothing to show | `ArDriveEmptyState` | Icon, heading, a line of text, and up to two actions |
| Loading | `ArDriveSpinner` | `small` (16) in buttons and rows, `large` (32) on its own |
| Progress | `ArDriveLinearProgress` | A 4 px bar; leave `value` null when progress isn't known. `color` marks progress that has stalled or finished without moving the bar |
| A value to copy | `ArDriveCopyField` | Read-only field with a Copy link; `isSecret` masks it behind a reveal toggle |
| A text field | `ArDriveTextFieldNew` | |
| Content on a surface that is dark in both themes, such as a video | `ArDriveOnDark` | Its child takes the dark theme's tokens, so text, spinners and buttons need no literal colours |

### Button sizes

There are three, and a button's place decides its size, so every button in the
same place is the same height.

| Size | Height | Where |
|---|---|---|
| `compact` | 36 | Inside a card, banner, list row or notice |
| `regular` (default) | 40 | Dialog actions, toolbars, and anywhere else |
| `large` | 48 | A full-width button that is a page's main action, such as sign-in or an empty page |

## Tests

```sh
cd packages/ardrive_ui
flutter test
```

Tests wrap a widget in `ArDriveApp(builder: (context) => MaterialApp(...))`,
which provides the dark theme; pass `themeData: lightTheme()` for light.
`test/src/styles/status_colors_test.dart` checks that every status colour pair
meets WCAG AA contrast for text (4.5:1) in both themes, that warning is a
grey and that error is one of the brand reds, so a status colour that breaks
any of those fails the suite.
