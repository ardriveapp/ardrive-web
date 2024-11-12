import 'package:ardrive/utils/ardrive_io_integration_test.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../utils.dart';

abstract class Tester {}

abstract class Action {
  Future<void> execute(WidgetTester tester, Component component);
}

class Tap extends Action {
  @override
  Future<void> execute(WidgetTester tester, Component component) async {
    await tester.tap(component.findComponent());
  }
}

class EnterText extends Action {
  final String text;

  EnterText(this.text);

  @override
  Future<void> execute(WidgetTester tester, Component component) async {
    await tester.enterText(component.findComponent(), text);
  }
}

class Wait extends Action {
  final int milliseconds;

  Wait(this.milliseconds);

  @override
  Future<void> execute(WidgetTester tester, Component component) async {
    await Future.delayed(Duration(milliseconds: milliseconds));
  }
}

abstract class Component {
  Component({required this.tester});

  final WidgetTester tester;

  Finder findComponent();

  void expectComponent() {
    final component = findComponent();
    expect(component, findsOneWidget);
  }

  Component wait(int milliseconds) {
    actions.add(Wait(milliseconds));
    return this;
  }

  Component tap() {
    actions.add(Tap());
    return this;
  }

  Component doubleTap() {
    actions.add(Tap());
    actions.add(Tap());
    return this;
  }

  Component enterText(String text) {
    actions.add(EnterText(text));
    return this;
  }

  Component and(Action action) {
    actions.add(action);
    return this;
  }

  Future<void> go() async {
    for (var action in actions) {
      await action.execute(tester, this);
    }
  }

  List<Action> actions = [];
}

abstract class ButtonTest extends Component {
  ButtonTest({required super.tester});

  Future<ButtonTest> andTap(WidgetTester tester) async {
    actions.add(Tap());
    await go();
    return this;
  }
}

abstract class ButtonTestByText extends ButtonTest {
  final String text;

  ButtonTestByText(this.text, {required super.tester});
}

abstract class ButtonTestByKey extends ButtonTest {
  final String key;

  ButtonTestByKey(this.key, {required super.tester});
}

abstract class TextFieldTest extends Component {
  final String key;

  TextFieldTest(this.key, {required super.tester});
}

class _TextFieldTest extends TextFieldTest {
  _TextFieldTest(super.key, {required super.tester});

  @override
  Finder findComponent() {
    return find.byKey(Key(key));
  }
}

class ButtonTestWithKey extends ButtonTestByKey {
  ButtonTestWithKey(super.key, {required super.tester});

  @override
  Finder findComponent() {
    return find.byKey(Key(key));
  }
}

class GenericButtonTest extends ButtonTestByText {
  GenericButtonTest(super.text, {required super.tester});

  @override
  Finder findComponent() {
    final component = find.text(text);
    expect(component, findsOneWidget);
    return component;
  }
}

class CheckboxTest extends Component {
  CheckboxTest({required super.tester});

  @override
  Finder findComponent() {
    final component = find.byType(Checkbox);
    expect(component, findsOneWidget);
    return component;
  }
}

class PageTest extends Component {
  final String pageKey;

  PageTest(this.pageKey, {required super.tester});

  @override
  Finder findComponent() {
    final component = find.byKey(Key(pageKey));
    expect(component, findsOneWidget);
    return component;
  }
}

class TextTest extends Component {
  final String text;

  TextTest(this.text, {required super.tester});

  @override
  Finder findComponent() {
    final component = find.text(text);
    expect(component, findsOneWidget);
    return component;
  }
}

class MultipleTextTest extends Component {
  final String text;
  final int count;

  MultipleTextTest(this.text, this.count, {required super.tester});

  @override
  Finder findComponent() {
    final component = find.text(text);
    expect(component, findsNWidgets(count));
    return component;
  }

  @override
  void expectComponent() {
    expect(findComponent(), findsNWidgets(count));
  }
}

class See extends Action {
  See({required this.tester});

  final WidgetTester tester;

  ButtonTestByText button(String text) {
    final button = GenericButtonTest(text, tester: tester);
    button.expectComponent();
    return button;
  }

  ButtonTestByKey buttonByKey(String key) {
    final button = ButtonTestWithKey(key, tester: tester);
    button.expectComponent();
    return button;
  }

  ButtonTestByText newButton() {
    final newButton = NewButtonTest(tester: tester);
    newButton.expectComponent();
    return newButton;
  }

  TextFieldTest textField(String key) {
    final textField = _TextFieldTest(key, tester: tester);
    textField.expectComponent();
    return textField;
  }

  PageTest page(String pageKey) {
    final page = PageTest(pageKey, tester: tester);
    page.expectComponent();
    return page;
  }

  TextTest text(String text) {
    final textTest = TextTest(text, tester: tester);
    textTest.expectComponent();
    return textTest;
  }

  CheckboxTest checkbox() {
    final checkbox = CheckboxTest(tester: tester);
    checkbox.expectComponent();
    return checkbox;
  }

  MultipleTextTest multipleText(String text, int count) {
    final multipleTextTest = MultipleTextTest(text, count, tester: tester);
    multipleTextTest.expectComponent();
    return multipleTextTest;
  }

  ButtonTestWithKey publicDriveButton(String driveName) {
    final driveButton =
        ButtonTestWithKey('public_drives_$driveName', tester: tester);
    driveButton.expectComponent();
    return driveButton;
  }

  ButtonTestWithKey privateDriveButton(String driveName) {
    final driveButton =
        ButtonTestWithKey('private_drives_$driveName', tester: tester);
    driveButton.expectComponent();
    return driveButton;
  }

  ButtonTestWithKey profileCard() {
    final profileCard = ButtonTestWithKey('profile_card', tester: tester);
    profileCard.expectComponent();
    return profileCard;
  }

  ButtonTestWithKey fileOnDriveExplorer(String fileName) {
    final file = ButtonTestWithKey('file_$fileName', tester: tester);
    file.expectComponent();
    return file;
  }

  ButtonTestWithKey folderOnDriveExplorer(String folderName) {
    final folder = ButtonTestWithKey('folder_$folderName', tester: tester);
    folder.expectComponent();
    return folder;
  }

  @override
  Future<void> execute(WidgetTester tester, Component component) async {
    component.expectComponent();
  }
}

class I extends Tester {
  I({required this.see});

  final See see;

  Future<void> wait(int milliseconds) async {
    await Future.delayed(Duration(milliseconds: milliseconds));
  }

  Future<void> waitAppToLoad(WidgetTester tester, int seconds) async {
    await waitAndUpdate(tester, seconds);
  }

  Future<void> pickFileTestWallet(WidgetTester tester) async {
    final context = arDriveAppKey.currentState!.context;
    final ardriveIO = context.read<ArDriveIO>() as ArDriveIOIntegrationTest;
    ardriveIO.setPickFileResult(await testWalletFile());
  }

  Future<void> waitToSee(
      String widgetKey, WidgetTester tester, int timeout) async {
    await waitAndUpdate(tester, timeout, breakCondition: () {
      try {
        final component = find.byKey(Key(widgetKey));
        expect(component, findsOneWidget);
        return true;
      } catch (e) {
        return false;
      }
    });
  }
}

class NewButtonTest extends ButtonTestByText {
  NewButtonTest({required super.tester}) : super('New');

  @override
  Finder findComponent() {
    return find.byKey(const Key('newButton_desktop'));
  }
}
