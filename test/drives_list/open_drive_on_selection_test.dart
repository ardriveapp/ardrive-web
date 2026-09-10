import 'dart:async';

import 'package:ardrive/drives_list/presentation/open_drive_on_selection.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sidebar sits on the drives list route too, listing every drive and
/// tappable - and a tap there only selects a drive. On the explorer selecting
/// is opening, because the explorer draws whatever is selected. On the list it
/// is not: the list draws the list. So the most obvious navigation control on
/// the first screen a login sees did nothing at all.
void main() {
  late StreamController<String> selections;
  late List<String> opened;

  setUp(() {
    selections = StreamController<String>.broadcast();
    opened = <String>[];
  });

  tearDown(() => selections.close());

  Future<void> pump(WidgetTester tester, {Stream<String>? stream}) =>
      tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: OpenDriveOnSelection(
            selections: stream ?? selections.stream,
            onOpenDrive: opened.add,
            child: const Text('the list'),
          ),
        ),
      );

  testWidgets('a drive chosen anywhere in the shell is opened', (tester) async {
    await pump(tester);

    selections.add('drive-b');
    await tester.pump();

    expect(opened, ['drive-b']);
  });

  testWidgets('it draws its child and nothing of its own', (tester) async {
    await pump(tester);

    expect(find.text('the list'), findsOneWidget);
  });

  testWidgets('two choices in a row are two openings', (tester) async {
    await pump(tester);

    selections.add('drive-a');
    await tester.pump();
    selections.add('drive-b');
    await tester.pump();

    expect(opened, ['drive-a', 'drive-b']);
  });

  testWidgets('nothing is opened after the page is gone', (tester) async {
    await pump(tester);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Text('somewhere else'),
      ),
    );

    selections.add('drive-b');
    await tester.pump();

    expect(opened, isEmpty);
  });
}
