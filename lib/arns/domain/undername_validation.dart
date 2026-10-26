/// The undername that stands for the name itself.
const arnsApex = '@';

/// The console's and Turbo's undername rule (docs/NAMES.md, "Undername
/// rules"): letters, digits, `-` and `_`, starting with a letter or digit, 1
/// to 61 characters.
final _undernamePattern = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]{0,60}$');

/// The longest DNS label: the whole `undername_name` must fit in one.
const maxArNSLabelLength = 63;

enum UndernameProblem {
  empty,

  /// A character outside the rule, or not starting with a letter or digit.
  invalid,

  /// Longer than 61 characters.
  tooLong,

  /// `undername_name` is longer than 63 characters.
  labelTooLong,
}

/// What is wrong with [undername] under [name], or null when it is valid.
/// `@`, the name itself, is always valid.
UndernameProblem? validateUndername(String undername, {required String name}) {
  if (undername == arnsApex) return null;
  if (undername.isEmpty) return UndernameProblem.empty;
  if (undername.length > 61) return UndernameProblem.tooLong;
  if (!_undernamePattern.hasMatch(undername)) return UndernameProblem.invalid;
  if (literalArNSName(undername, name).length > maxArNSLabelLength) {
    return UndernameProblem.labelTooLong;
  }
  return null;
}

/// The name as typed in a browser: `blog_ardrive`, or `ardrive` for `@`.
String literalArNSName(String undername, String name) =>
    undername == arnsApex ? name : '${undername}_$name';
