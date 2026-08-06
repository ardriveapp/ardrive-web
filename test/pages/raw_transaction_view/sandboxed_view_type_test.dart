import 'package:ardrive/components/sandboxed_transaction_view/sandboxed_view_type.dart';
import 'package:flutter_test/flutter_test.dart';

/// The name a sandboxed frame registers its view factory under.
///
/// `registerViewFactory` keyed by a timestamp was a collision waiting for two
/// frames in the same millisecond: on the web `DateTime.now()` has millisecond
/// resolution, so `microsecondsSinceEpoch` is always a multiple of 1000 and two
/// registrations in one tick asked for the same name. The registry then either
/// rejects the second or replaces the first, and one transaction renders the
/// other one's URL - inside the frame whose entire job is keeping those two
/// apart.
///
/// These assertions are therefore not about *a* unique name; they are about
/// where the uniqueness comes from.
void main() {
  /// Everything in a view type except the clock reading.
  String withoutTheClock(String viewType) {
    final parts = viewType.split('-');

    expect(parts.length, greaterThanOrEqualTo(4),
        reason: 'a view type is "sandboxed-transaction-{clock}-{counter}"');

    return '${parts.first}-${parts.sublist(3).join('-')}';
  }

  test('is unique even with the clock taken out of it', () {
    final types = List.generate(1000, (_) => nextSandboxedViewType());

    expect(types.toSet().length, types.length);

    // The real assertion: strip the timestamp and the names are *still* all
    // different. A name whose only varying part is the clock cannot pass this,
    // which is precisely the version that shipped a collision.
    expect(types.map(withoutTheClock).toSet().length, types.length);
  });

  test('names a sandboxed transaction frame, readably', () {
    expect(nextSandboxedViewType(), startsWith('sandboxed-transaction-'));
  });
}
