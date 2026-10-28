import 'package:ardrive/turbo/topup/components/cover_stack.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(List<Widget> children) => Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: CoverStack(children: children)),
      );

  testWidgets('every child takes the size of the largest', (tester) async {
    await tester.pumpWidget(host(const [
      SizedBox(key: Key('tall'), width: 200, height: 300),
      ColoredBox(
        key: Key('short'),
        color: Colors.black,
        child: SizedBox(width: 200, height: 120),
      ),
    ]));

    expect(tester.getSize(find.byType(CoverStack)), const Size(200, 300));
    expect(tester.getSize(find.byKey(const Key('tall'))), const Size(200, 300));
    expect(
      tester.getSize(find.byKey(const Key('short'))),
      const Size(200, 300),
    );
    expect(
      tester.getTopLeft(find.byKey(const Key('short'))),
      tester.getTopLeft(find.byType(CoverStack)),
    );
  });

  testWidgets('the last child is on top for taps', (tester) async {
    var under = 0;
    var over = 0;
    await tester.pumpWidget(host([
      GestureDetector(
        onTap: () => under++,
        child: const SizedBox(width: 200, height: 300),
      ),
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => over++,
        child: const SizedBox(width: 200, height: 120),
      ),
    ]));

    // Below where the top child ended before it was stretched.
    await tester.tapAt(
      tester.getTopLeft(find.byType(CoverStack)) + const Offset(100, 250),
    );

    expect(over, 1);
    expect(under, 0);
  });
}
