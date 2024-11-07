import 'dart:typed_data';

import 'package:ardrive_io/ardrive_io.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart';
import 'dsl/dsl.dart';
import 'integration_test_cli_arguments.dart';
import 'login_tests.dart';

Future<void> waitAndUpdate(WidgetTester tester, int seconds,
    {bool Function()? breakCondition}) async {
  for (int i = 0; i < seconds; i++) {
    if (breakCondition != null) {
      if (breakCondition()) {
        await tester.pump(const Duration(milliseconds: 0));
        break;
      }
    }

    await tester.pump(const Duration(seconds: 1));
  }
}

Future<IOFile> testWalletFile() {
  return IOFileAdapter().fromData(
    Uint8List.fromList(integationTestWalletKeyFile.codeUnits),
    name: 'keyfile.json',
    lastModifiedDate: DateTime.now(),
  );
}

Future<IOFile> testFileUpload(String fileName) {
  return IOFileAdapter().fromData(
    Uint8List.fromList('test'.codeUnits),
    name: fileName,
    lastModifiedDate: DateTime.now(),
  );
}

Future<void> waitToSee({
  required WidgetTester tester,
  required Type widgetType,
  Duration timeout = const Duration(seconds: 10),
}) async {
  await waitAndUpdate(tester, timeout.inSeconds, breakCondition: () {
    try {
      final widget = find.byType(widgetType);
      expect(widget, findsOneWidget);
      return true;
    } catch (e) {
      return false;
    }
  });
}

Finder newButtonDesktop() {
  return find.byKey(const Key('newButton_desktop'));
}

Finder newButtonMobile() {
  return find.byKey(const Key('newButton_mobile'));
}

abstract class Seconds {
  final int seconds;

  Seconds(this.seconds);
}

class OneSecond extends Seconds {
  OneSecond() : super(1);
}

class TwoSeconds extends Seconds {
  TwoSeconds() : super(2);
}

class ThreeSeconds extends Seconds {
  ThreeSeconds() : super(3);
}

class FourSeconds extends Seconds {
  FourSeconds() : super(4);
}

class FiveSeconds extends Seconds {
  FiveSeconds() : super(5);
}

class NSeconds extends Seconds {
  NSeconds(super.seconds);
}

Future<void> runPreConditionUserLoggedIn(WidgetTester tester) async {
  await initApp(tester, deleteDatabase: true);
  await I.wait(1000);
  await testLoginSuccess(tester);
  await I.wait(5000);
}
