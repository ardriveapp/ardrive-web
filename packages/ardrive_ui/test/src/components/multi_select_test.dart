import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// When a list shows its checkboxes: the explorer's rule, shared with the
/// drives list.
void main() {
  group('ArDriveMultiSelect.showsCheckboxes', () {
    test('hidden when nothing asks for them', () {
      expect(
        ArDriveMultiSelect.showsCheckboxes(anyTicked: false, keyHeld: false),
        isFalse,
      );
    });

    test(
        'shown once something is ticked, while the key is held, or after '
        'a long press', () {
      expect(
        ArDriveMultiSelect.showsCheckboxes(anyTicked: true, keyHeld: false),
        isTrue,
      );
      expect(
        ArDriveMultiSelect.showsCheckboxes(anyTicked: false, keyHeld: true),
        isTrue,
      );
      expect(
        ArDriveMultiSelect.showsCheckboxes(
          anyTicked: false,
          keyHeld: false,
          longPressed: true,
        ),
        isTrue,
      );
    });
  });

  testWidgets('ArDriveMultiSelectKey follows the key down and up',
      (tester) async {
    final seen = <bool>[];
    await tester.pumpWidget(ArDriveMultiSelectKey(
      builder: (context, held) {
        seen.add(held);
        return const SizedBox();
      },
    ));

    // Cmd: the test platform is not Windows.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(seen, [false, true, false]);
  });

  testWidgets('and is not moved by other keys', (tester) async {
    final seen = <bool>[];
    await tester.pumpWidget(ArDriveMultiSelectKey(
      builder: (context, held) {
        seen.add(held);
        return const SizedBox();
      },
    ));

    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(seen, [false]);
  });
}
