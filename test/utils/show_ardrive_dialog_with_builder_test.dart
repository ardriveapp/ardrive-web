import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/utils/show_general_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The note editor and its confirmations opened without telling the activity
/// tracker, so multi-select in the file list stayed live behind them.
void main() {
  testWidgets(
      'a dialog that answers is tracked while open and returns its value',
      (tester) async {
    final tracker = ActivityTracker();
    late BuildContext context;
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: tracker,
        child: ArDriveApp(
          builder: (_) => MaterialApp(
            home: Builder(builder: (c) {
              context = c;
              return const SizedBox();
            }),
          ),
        ),
      ),
    );

    final answer = showArDriveDialogWithBuilder<bool>(
      context,
      builder: (dialogContext) => TextButton(
        onPressed: () => Navigator.of(dialogContext).pop(true),
        child: const Text('Yes'),
      ),
    );
    await tester.pumpAndSettle();
    expect(tracker.isMultiSelectEnabled, isFalse);

    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();

    expect(await answer, isTrue);
    expect(tracker.isMultiSelectEnabled, isTrue);
  });
}
