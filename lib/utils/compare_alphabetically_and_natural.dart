import 'package:collection/collection.dart';

/// returns -1 when `a` is before `b`
/// returns 0 when `a` is equal to `b`
/// returns 1 when `a` is after `b`
int compareAlphabeticallyAndNatural(String a, String b) {
  return compareNatural(a.toLowerCase(), b.toLowerCase());
}
