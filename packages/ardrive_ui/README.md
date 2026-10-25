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

## Components

| Need | Component | Notes |
|---|---|---|
| A button | `ArDriveButtonNew` | `variant`: primary for the main action, secondary, or outline. `size`: see below. Sized to its label unless given `maxWidth`; `double.infinity` fills |
| A dialog | `ArDriveStandardModalNew` with `ModalAction`s | Opened with `showArDriveDialog` in the app. The last action is primary. Cancel and Close use `ModalAction.dismiss`, which is never red, even alone. Set `scrollableContent` for long content |
| A dialog on a phone, or a menu from the bottom | `showArDriveBottomSheet` with `ArDriveBottomSheet` | Same title, spacing and action row as a dialog |
| A text link | `ArDriveLink`, or `ArDriveLink.span` inside text | Keyboard reachable and announced as a link. `external` adds the new-window icon; `isAction` announces an action such as Copy as a button |
| A message with a meaning | `ArDriveNotice` | `type`: info, warning, error or success. `layout`: inline box or full-width banner. Optional title, action and close button |
| Nothing to show | `ArDriveEmptyState` | Icon, heading, a line of text, and up to two actions |
| Loading | `ArDriveSpinner` | `small` (16) in buttons and rows, `large` (32) on its own |
| Progress | `ArDriveLinearProgress` | A 4 px bar; leave `value` null when progress isn't known |
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
meets WCAG AA contrast in both themes, so a new status colour that fails it
fails the suite.
