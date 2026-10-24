/// The spacing scale. Gaps, padding and margins use these and nothing in
/// between, so screens line up with each other.
abstract final class ArDriveSpacing {
  /// Between an icon and its label, or two lines of one item.
  static const double xxs = 4;

  /// Between related items: chips, buttons in a row, a label and its field.
  static const double xs = 8;

  /// Inside a compact surface such as a notice or a list row.
  static const double sm = 12;

  /// The default padding of a card, and the page gutter on a phone.
  static const double md = 16;

  /// Between groups within a dialog or page, and a dialog's padding.
  static const double lg = 24;

  /// Between sections of a page.
  static const double xl = 32;

  /// Around an empty state or a page's main block.
  static const double xxl = 48;
}

/// The corner radii. Small controls take [sm], surfaces such as cards and
/// notices [md], and dialogs and sheets [lg].
abstract final class ArDriveRadius {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
}
