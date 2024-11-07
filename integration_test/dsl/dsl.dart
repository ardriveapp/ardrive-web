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

  Component enterText(String text) {
    actions.add(EnterText(text));
    return this;
  }

  Component and(Action action) {
    actions.add(action);
    return this;
  }

  Future<void> go(WidgetTester tester) async {
    for (var action in actions) {
      await action.execute(tester, this);
    }
  }

  List<Action> actions = [];
}

abstract class ButtonTest extends Component {
  Future<ButtonTest> andTap(WidgetTester tester) async {
    actions.add(Tap());
    await go(tester);
    return this;
  }
}

abstract class ButtonTestByText extends ButtonTest {
  final String text;

  ButtonTestByText(this.text);
}

abstract class ButtonTestByKey extends Component {
  final String key;

  ButtonTestByKey(this.key);
}

abstract class TextFieldTest extends Component {
  final String key;

  TextFieldTest(this.key);
}

class _TextFieldTest extends TextFieldTest {
  _TextFieldTest(super.key);

  @override
  Finder findComponent() {
    return find.byKey(Key(key));
  }
}

class ButtonTestWithKey extends ButtonTestByKey {
  ButtonTestWithKey(super.key);

  @override
  Finder findComponent() {
    return find.byKey(Key(key));
  }
}

class GenericButtonTest extends ButtonTestByText {
  GenericButtonTest(super.text);

  @override
  Finder findComponent() {
    final component = find.text(text);
    expect(component, findsOneWidget);
    return component;
  }
}

class CheckboxTest extends Component {
  @override
  Finder findComponent() {
    final component = find.byType(Checkbox);
    expect(component, findsOneWidget);
    return component;
  }
}

class PageTest extends Component {
  final String pageKey;

  PageTest(this.pageKey);

  @override
  Finder findComponent() {
    final component = find.byKey(Key(pageKey));
    expect(component, findsOneWidget);
    return component;
  }
}

class TextTest extends Component {
  final String text;

  TextTest(this.text);

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

  MultipleTextTest(this.text, this.count);

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
  ButtonTestByText button(String text) {
    final button = GenericButtonTest(text);
    button.expectComponent();
    return button;
  }

  ButtonTestByKey buttonByKey(String key) {
    final button = ButtonTestWithKey(key);
    button.expectComponent();
    return button;
  }

  ButtonTestByText newButton() {
    final newButton = NewButtonTest();
    newButton.expectComponent();
    return newButton;
  }

  TextFieldTest textField(String key) {
    final textField = _TextFieldTest(key);
    textField.expectComponent();
    return textField;
  }

  PageTest page(String pageKey) {
    final page = PageTest(pageKey);
    page.expectComponent();
    return page;
  }

  TextTest text(String text) {
    final textTest = TextTest(text);
    textTest.expectComponent();
    return textTest;
  }

  CheckboxTest checkbox() {
    final checkbox = CheckboxTest();
    checkbox.expectComponent();
    return checkbox;
  }

  MultipleTextTest multipleText(String text, int count) {
    final multipleTextTest = MultipleTextTest(text, count);
    multipleTextTest.expectComponent();
    return multipleTextTest;
  }

  @override
  Future<void> execute(WidgetTester tester, Component component) async {
    component.expectComponent();
  }
}

class I extends Tester {
  static See see = See();
  static Future<void> wait(int milliseconds) async {
    await Future.delayed(Duration(milliseconds: milliseconds));
  }

  static Future<void> waitAppToLoad(WidgetTester tester, int seconds) async {
    await waitAndUpdate(tester, seconds);
  }

  static Future<void> pickFileTestWallet(WidgetTester tester) async {
    final context = arDriveAppKey.currentState!.context;
    final ardriveIO = context.read<ArDriveIO>() as ArDriveIOIntegrationTest;
    ardriveIO.setPickFileResult(await testWalletFile());
  }

  static Future<void> waitToSee(
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
  NewButtonTest() : super('New');

  @override
  Finder findComponent() {
    return find.byKey(const Key('newButton_desktop'));
  }
}
