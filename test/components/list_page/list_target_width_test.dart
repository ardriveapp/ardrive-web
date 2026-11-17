import 'package:ardrive/components/list_page/list_page_layout.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('narrows an opening list to where the panel will leave it',
      (tester) async {
    double? seen;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ListTargetWidth(
          width: 600,
          child: Builder(builder: (context) {
            seen = ListTargetWidth.narrowed(context, 900);
            return const SizedBox();
          }),
        ),
      ),
    );
    expect(seen, 600);
  });

  testWidgets('keeps the narrower actual width while a panel closes',
      (tester) async {
    double? seen;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: ListTargetWidth(
          width: 900,
          child: Builder(builder: (context) {
            seen = ListTargetWidth.narrowed(context, 700);
            return const SizedBox();
          }),
        ),
      ),
    );
    expect(seen, 700);
  });

  testWidgets('is the actual width without a host', (tester) async {
    double? seen;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Builder(builder: (context) {
          seen = ListTargetWidth.narrowed(context, 900);
          return const SizedBox();
        }),
      ),
    );
    expect(seen, 900);
  });
}
