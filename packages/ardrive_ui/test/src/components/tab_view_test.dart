import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ArDriveTabView widget and its contents render', (tester) async {
    await tester.runAsync(() async {
      const tabview = ArDriveTabView(
        tabs: [
          ArDriveTab(
            Tab(child: Text('Tab One')),
            Center(child: Text('Value One')),
          ),
          ArDriveTab(
            Tab(child: Text('Tab Two')),
            Center(child: Text('Value Two')),
          ),
          ArDriveTab(
            Tab(child: Text('Tab Three')),
            Center(child: Text('Value Three')),
          ),
          ArDriveTab(
            Tab(child: Text('Tab Four')),
            Center(child: Text('Value Four')),
          )
        ],
      );
      await tester.pumpWidget(ArDriveApp(
        builder: (context) => const MaterialApp(
          home: Scaffold(body: Center(child: tabview)),
        ),
      ));

      expect(find.byWidget(tabview), findsOneWidget);
      expect(find.text('Tab One'), findsOneWidget);
      expect(find.text('Value One'), findsOneWidget);
      expect(find.text('Tab Two'), findsOneWidget);
      expect(find.text('Tab Three'), findsOneWidget);
      expect(find.text('Tab Four'), findsOneWidget);
    });
  });
  testWidgets('ArDriveTabView change the tab when click in another',
      (tester) async {
    await tester.runAsync(() async {
      const tabview = ArDriveTabView(
        tabs: [
          ArDriveTab(
            Tab(child: Text('Tab One')),
            Center(child: Text('Value One')),
          ),
          ArDriveTab(
            Tab(child: Text('Tab Two')),
            Center(child: Text('Value Two')),
          ),
          ArDriveTab(
            Tab(child: Text('Tab Three')),
            Center(child: Text('Value Three')),
          ),
          ArDriveTab(
            Tab(child: Text('Tab Four')),
            Center(child: Text('Value Four')),
          )
        ],
      );
      await tester.pumpWidget(ArDriveApp(
        builder: (context) => const MaterialApp(
          home: Scaffold(body: Center(child: tabview)),
        ),
      ));

      expect(find.byWidget(tabview), findsOneWidget);
      expect(find.text('Tab One'), findsOneWidget);
      expect(find.text('Value One'), findsOneWidget);

      await tester.ensureVisible(find.byWidget(tabview));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      // click on the tab `Tab Two`
      await tester.tap(find.byType(Tab).at(1));
      await tester.pumpAndSettle(const Duration(seconds: 3));

      expect(find.text('Value Two'), findsOneWidget);
    });
  });
}
