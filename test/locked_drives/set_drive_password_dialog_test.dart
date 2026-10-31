import 'package:ardrive/authentication/password/breached_password.dart';
import 'package:ardrive/core/activity_tracker.dart';
import 'package:ardrive/locked_drives/presentation/set_drive_password_dialog.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

class _Breaches extends Fake implements BreachedPasswordCheck {
  final breached = <String>{};
  var asked = 0;

  @override
  Future<bool?> isBreached(String password) async {
    asked++;
    return breached.contains(password);
  }
}

const _strong = 'Velvet harbour 47 lanterns drift';

/// "Keep your files private": the drive password a browser wallet account
/// sets before its first private drive.
void main() {
  late _Breaches breaches;

  setUp(() {
    breaches = _Breaches();
  });

  Future<Future<String?>> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    late Future<String?> result;
    await tester.pumpWidget(ChangeNotifierProvider<ActivityTracker>(
      create: (_) => ActivityTracker(),
      child: ArDriveTheme(
        themeData: lightTheme(),
        child: MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en', '')],
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => result = showSetDrivePasswordDialog(
                  context,
                  walletAddress: 'wallet-address',
                  breachCheck: breaches,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return Future.value(result);
  }

  Finder field(String key) => find.descendant(
      of: find.byKey(Key(key)), matching: find.byType(EditableText));

  Finder setButton() => find.text('Set password');

  testWidgets(
      'says it cannot be recovered, and offers the browser a new '
      'password for this account', (tester) async {
    await open(tester);

    expect(find.text('Keep your files private'), findsOneWidget);
    expect(
        find.textContaining("We can't recover this password"), findsOneWidget);
    // The TextField is the autofill client; EditableText only draws.
    List<String>? hints(String key) => tester
        .widget<TextField>(find.descendant(
            of: find.byKey(Key(key)), matching: find.byType(TextField)))
        .autofillHints
        ?.toList();
    expect(hints('newPassword'), [AutofillHints.newPassword]);
    expect(hints('confirmNewPassword'), [AutofillHints.newPassword]);
    final username = tester.widget<TextField>(
        find.byKey(const Key('passwordAutofillUsername'), skipOffstage: false));
    expect(username.controller!.text, 'wallet-address');
  });

  testWidgets('follows the new-account rules before it returns the password',
      (tester) async {
    final result = await open(tester);

    await tester.enterText(field('newPassword'), 'short');
    await tester.pump();
    expect(find.text('Use at least 12 characters.'), findsOneWidget);

    await tester.enterText(field('newPassword'), _strong);
    await tester.enterText(field('confirmNewPassword'), 'something else');
    await tester.pump();
    await tester.tap(setButton());
    await tester.pumpAndSettle();
    expect(breaches.asked, 0, reason: 'not usable yet, so nothing is checked');

    breaches.breached.add(_strong);
    await tester.enterText(field('confirmNewPassword'), _strong);
    await tester.pump();
    await tester.tap(setButton());
    await tester.pumpAndSettle();
    expect(
        find.text(
            'This password has shown up in a data breach. Choose another.'),
        findsOneWidget);
    expect(find.byKey(const Key('setDrivePasswordDialog')), findsOneWidget);

    const other = 'Copper meadow 92 kites unfold';
    await tester.enterText(field('newPassword'), other);
    await tester.enterText(field('confirmNewPassword'), other);
    await tester.pump();
    await tester.tap(setButton());
    await tester.pumpAndSettle();

    expect(await result, other);
  });

  testWidgets('Cancel returns nothing', (tester) async {
    final result = await open(tester);

    await tester.enterText(field('newPassword'), _strong);
    await tester.enterText(field('confirmNewPassword'), _strong);
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(await result, isNull);
    expect(breaches.asked, 0);
  });

  testWidgets(
      'a suggestion fills both fields masked; one eye shows and hides both; '
      'typing one\'s own drops the suggestion', (tester) async {
    await open(tester);
    bool obscured(String key) =>
        tester.widget<EditableText>(field(key)).obscureText;
    String text(String key) =>
        tester.widget<EditableText>(field(key)).controller.text;
    expect(obscured('newPassword'), isTrue);

    await tester.tap(find.byKey(const Key('suggestPasswordButton')));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
    final phrase = text('newPassword');
    expect(phrase, isNotEmpty);
    expect(text('confirmNewPassword'), phrase);
    expect(obscured('newPassword'), isTrue);
    expect(obscured('confirmNewPassword'), isTrue);
    expect(
        find.descendant(
            of: find.byKey(const Key('suggestedPassphrase')),
            matching: find.text(phrase)),
        findsNothing);
    expect(find.textContaining("ArDrive can't recover it"), findsNothing);

    await tester.tap(find.byKey(const Key('newPasswordReveal')));
    await tester.pump();
    expect(obscured('newPassword'), isFalse);
    expect(obscured('confirmNewPassword'), isFalse);

    await tester.tap(find.byKey(const Key('newPasswordReveal')));
    await tester.pump();
    expect(obscured('newPassword'), isTrue);
    expect(obscured('confirmNewPassword'), isTrue);

    await tester.enterText(field('newPassword'), _strong);
    await tester.pump();
    expect(obscured('newPassword'), isTrue);
    expect(obscured('confirmNewPassword'), isTrue);
    expect(find.byKey(const Key('suggestedPassphrase')), findsNothing);
  });

  for (final refuses in [false, true]) {
    testWidgets(
        refuses
            ? 'Copy refused by the browser says so, never Copied'
            : 'Copy copies the suggestion and says so', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          if (refuses) throw PlatformException(code: 'denied');
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await open(tester);
      await tester.tap(find.byKey(const Key('suggestPasswordButton')));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      final phrase =
          tester.widget<EditableText>(field('newPassword')).controller.text;

      await tester.tap(find.text('Copy'));
      await tester.pump();
      expect(copied, refuses ? isEmpty : [phrase]);
      expect(find.text('Copied!'), refuses ? findsNothing : findsOneWidget);
      expect(
          find.text("Couldn't copy"), refuses ? findsOneWidget : findsNothing);
      await tester.pump(const Duration(seconds: 2));
      expect(find.byKey(const Key('suggestedPassphraseCopyMessage')),
          findsNothing);
    });
  }
}
