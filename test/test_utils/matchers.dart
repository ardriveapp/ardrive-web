import 'package:test/test.dart';

class Sorted extends Matcher {
  Sorted();

  @override
  Description describe(Description description) =>
      description.addDescriptionOf('sorted');

  @override
  Description describeMismatch(dynamic item, Description mismatchDescription,
          Map matchState, bool verbose) =>
      mismatchDescription.add('is not sorted');

  @override
  bool matches(dynamic item, Map matchState) {
    if (item is Iterable<String>) {
      String? previousEl;
      for (final element in item) {
        if (previousEl != null && element.compareTo(previousEl) < 0) {
          return false;
        }
        previousEl = element;
      }

      return true;
    }

    return false;
  }
}
