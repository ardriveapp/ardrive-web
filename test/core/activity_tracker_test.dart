import 'package:ardrive/core/activity_tracker.dart';
import 'package:test/test.dart';

void main() {
  group('ActivityTracker dialogs', () {
    test('multi-select is allowed with no dialog open', () {
      expect(ActivityTracker().isMultiSelectEnabled, isTrue);
    });

    // A flag was cleared by the inner dialog closing, so multi-select came
    // back while the note editor or the upload form was still open.
    test('a dialog opened from another keeps multi-select off until both close',
        () {
      final tracker = ActivityTracker()
        ..setShowingAnyDialog(true)
        ..setShowingAnyDialog(true)
        ..setShowingAnyDialog(false);

      expect(tracker.isMultiSelectEnabled, isFalse);

      tracker.setShowingAnyDialog(false);
      expect(tracker.isMultiSelectEnabled, isTrue);
    });

    test('an extra close does not leave the count below zero', () {
      final tracker = ActivityTracker()
        ..setShowingAnyDialog(false)
        ..setShowingAnyDialog(true);

      expect(tracker.isMultiSelectEnabled, isFalse);
    });
  });
}
