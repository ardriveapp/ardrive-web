import 'dart:async';

import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:arweave/utils.dart' show ownerToAddress;
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

void main() {
  late MockArConnectService wander;
  late StreamController<bool> focus;

  /// What the prompt was shown for, and the `answered` it was given.
  late List<ArConnectUnavailableReason> shown;
  late List<Future<void>> answeredSignals;

  /// What the person picks when the prompt shows; null leaves it open.
  late bool? Function() pick;

  setUp(() {
    ArConnectPrompt.reset();
    wander = MockArConnectService();
    when(() => wander.isExtensionPresent()).thenReturn(true);
    focus = StreamController<bool>.broadcast();
    ArConnectPrompt.tabFocus = () => focus.stream;
    shown = [];
    answeredSignals = [];
    pick = () => false;
    ArConnectPrompt.registerRetryPrompt((reason, answered) {
      shown.add(reason);
      answeredSignals.add(answered);
      final choice = pick();
      if (choice != null) return Future.value(choice);
      // Left open: closes, as the dialog does, once Wander answers.
      return answered.then((_) => true);
    });
  });

  tearDown(() async {
    ArConnectPrompt.reset();
    await focus.close();
  });

  group('coming back to ArDrive while Wander has not answered', () {
    test('shows the prompt then, not at the deadline', () {
      fakeAsync((async) {
        Object? error;
        ArConnectPrompt.ask(wander, () => Completer<bool>().future)
            .catchError((Object e) {
          error = e;
          return false;
        });

        async.elapse(const Duration(seconds: 5));
        expect(shown, isEmpty);

        focus.add(true);
        async.elapse(ArConnectPrompt.focusGrace);

        expect(shown, [ArConnectUnavailableReason.noAnswer]);
        expect(error, isA<ArConnectUnavailableException>());
      });
    });

    test('is not taken as an answer: Try again asks Wander again', () {
      fakeAsync((async) {
        var calls = 0;
        pick = () => true;
        bool? answer;
        ArConnectPrompt.ask(wander, () {
          calls++;
          return calls == 1 ? Completer<bool>().future : Future.value(true);
        }).then((value) => answer = value);

        async.elapse(const Duration(seconds: 1));
        focus.add(true);
        async.elapse(ArConnectPrompt.focusGrace);

        expect(calls, 2);
        expect(answer, isTrue);
      });
    });

    test('an answer that arrives within the grace shows nothing', () {
      fakeAsync((async) {
        final request = Completer<bool>();
        bool? answer;
        ArConnectPrompt.ask(wander, () => request.future)
            .then((value) => answer = value);

        async.elapse(const Duration(seconds: 1));
        focus.add(true);
        async.elapse(ArConnectPrompt.focusGrace ~/ 2);
        request.complete(true);
        async.elapse(ArConnectPrompt.focusGrace);

        expect(shown, isEmpty);
        expect(answer, isTrue);
      });
    });

    test('changes nothing when nobody can be asked', () {
      fakeAsync((async) {
        Object? error;
        ArConnectPrompt.ask(
          wander,
          () => Completer<bool>().future,
          askPerson: false,
        ).catchError((Object e) {
          error = e;
          return false;
        });

        async.elapse(const Duration(seconds: 1));
        focus.add(true);
        async.elapse(ArConnectPrompt.focusGrace * 2);
        expect(error, isNull);

        async.elapse(ArConnectPrompt.readTimeout);
        expect(error, isA<ArConnectUnavailableException>());
        expect(shown, isEmpty);
      });
    });
  });

  test('without coming back, the deadline still shows the prompt', () {
    fakeAsync((async) {
      ArConnectPrompt.ask(wander, () => Completer<bool>().future)
          .catchError((Object _) => false);

      async.elapse(
          ArConnectPrompt.readTimeout - const Duration(milliseconds: 1));
      expect(shown, isEmpty);

      async.elapse(const Duration(milliseconds: 1));
      expect(shown, [ArConnectUnavailableReason.noAnswer]);
    });
  });

  test('a late answer wins while the prompt is open, and closes it', () {
    fakeAsync((async) {
      final first = Completer<bool>();
      pick = () => null;
      bool? answer;
      ArConnectPrompt.ask(wander, () => first.future)
          .then((value) => answer = value);

      async.elapse(ArConnectPrompt.readTimeout);
      expect(shown, hasLength(1));
      var closed = false;
      answeredSignals.single.then((_) => closed = true);

      first.complete(true);
      async.flushMicrotasks();

      expect(answer, isTrue);
      expect(closed, isTrue);
    });
  });

  test('after Try again, the answer to the first request still wins', () {
    fakeAsync((async) {
      final first = Completer<String>();
      var calls = 0;
      var tries = 0;
      pick = () => ++tries == 1;
      String? answer;
      ArConnectPrompt.ask(wander, () {
        calls++;
        return calls == 1 ? first.future : Completer<String>().future;
      }).then((value) => answer = value);

      // The deadline, Try again, then the first request answers while the
      // second one waits.
      async.elapse(ArConnectPrompt.readTimeout);
      expect(calls, 2);
      first.complete('late');
      async.flushMicrotasks();

      expect(answer, 'late');
    });
  });

  test('leaving again within the grace starts the wait over', () {
    fakeAsync((async) {
      ArConnectPrompt.ask(wander, () => Completer<bool>().future)
          .catchError((Object _) => false);

      // Wander's unlock window closes, then its signature window opens.
      async.elapse(const Duration(seconds: 1));
      focus.add(true);
      async.elapse(ArConnectPrompt.focusGrace ~/ 2);
      focus.add(false);
      async.elapse(ArConnectPrompt.focusGrace * 3);
      expect(shown, isEmpty);

      // Back for good.
      focus.add(true);
      async.elapse(ArConnectPrompt.focusGrace);
      expect(shown, [ArConnectUnavailableReason.noAnswer]);
    });
  });

  group('two asks at once', () {
    test('share one prompt, and Cancel ends both', () {
      fakeAsync((async) {
        final choice = Completer<bool>();
        ArConnectPrompt.registerRetryPrompt((reason, answered) {
          shown.add(reason);
          return choice.future;
        });
        final errors = <Object>[];
        for (var i = 0; i < 2; i++) {
          ArConnectPrompt.ask(wander, () => Completer<bool>().future)
              .catchError((Object e) {
            errors.add(e);
            return false;
          });
        }

        async.elapse(ArConnectPrompt.readTimeout);
        expect(shown, hasLength(1));
        expect(errors, isEmpty);

        choice.complete(false);
        async.flushMicrotasks();

        expect(shown, hasLength(1));
        expect(errors, hasLength(2));
        expect(errors, everyElement(isA<ArConnectUnavailableException>()));
      });
    });

    test('an answer to one closes the prompt, and the other asks again', () {
      fakeAsync((async) {
        pick = () => null;
        final a = Completer<bool>();
        var bCalls = 0;
        bool? aAnswer, bAnswer;
        ArConnectPrompt.ask(wander, () => a.future)
            .then((value) => aAnswer = value);
        ArConnectPrompt.ask(wander, () {
          bCalls++;
          return bCalls == 1 ? Completer<bool>().future : Future.value(true);
        }).then((value) => bAnswer = value);

        async.elapse(ArConnectPrompt.readTimeout);
        expect(shown, hasLength(1));

        a.complete(false);
        async.flushMicrotasks();

        expect(aAnswer, isFalse);
        expect(bCalls, 2);
        expect(bAnswer, isTrue);
        expect(shown, hasLength(1));
      });
    });
  });

  test('stops listening for focus once each ask is over', () {
    fakeAsync((async) {
      var listening = 0;
      ArConnectPrompt.tabFocus = () {
        late StreamController<bool> c;
        c = StreamController<bool>(
          onListen: () => listening++,
          onCancel: () => listening--,
        );
        return c.stream;
      };
      for (var i = 0; i < 3; i++) {
        ArConnectPrompt.ask(wander, () => Future.value(true));
        ArConnectPrompt.ask(wander, () => Completer<bool>().future)
            .catchError((Object _) => false);
      }

      async.elapse(ArConnectPrompt.readTimeout * 2);

      expect(listening, 0);
    });
  });

  // A dialog removed from under another route never answers. The answer
  // that removed it must still free the prompt for the next ask.
  test('a prompt that never answers is let go once Wander answers', () {
    fakeAsync((async) {
      var prompts = 0;
      ArConnectPrompt.registerRetryPrompt((reason, answered) {
        prompts++;
        return prompts == 1 ? Completer<bool>().future : Future.value(false);
      });

      final first = Completer<bool>();
      bool? firstAnswer;
      ArConnectPrompt.ask(wander, () => first.future)
          .then((value) => firstAnswer = value);
      async.elapse(ArConnectPrompt.readTimeout);
      first.complete(true);
      async.flushMicrotasks();
      expect(firstAnswer, isTrue);

      Object? second;
      ArConnectPrompt.ask(wander, () => Completer<bool>().future)
          .catchError((Object e) {
        second = e;
        return false;
      });
      async.elapse(ArConnectPrompt.readTimeout);

      expect(prompts, 2, reason: 'the next failure shows a prompt again');
      expect(second, isA<ArConnectUnavailableException>());
    });
  });

  group('Wander has lost ArDrive\'s permissions', () {
    // What Wander throws after an update reset every site's permissions.
    Exception missing() =>
        Exception('Missing permission(s) for "signDataItem": SIGN_TRANSACTION');

    test('Reconnect connects once, then asks again', () async {
      pick = () => true;
      var calls = 0;
      when(() => wander.connect()).thenAnswer((_) async {});

      final answer = await ArConnectPrompt.ask(wander, () async {
        calls++;
        if (calls == 1) throw missing();
        return 'signed';
      });

      expect(answer, 'signed');
      expect(shown, [ArConnectUnavailableReason.noPermission]);
      verify(() => wander.connect()).called(1);
      expect(ArConnectPrompt.hasAnswered, isTrue);
    });

    test('Cancel ends it, without connecting', () async {
      pick = () => false;

      await expectLater(
        ArConnectPrompt.ask<String>(wander, () async => throw missing()),
        throwsA(isA<ArConnectUnavailableException>().having((e) => e.reason,
            'reason', ArConnectUnavailableReason.noPermission)),
      );
      verifyNever(() => wander.connect());
    });

    test('nobody asked in the background, and nothing connects', () async {
      await expectLater(
        ArConnectPrompt.ask<String>(wander, () async => throw missing(),
            askPerson: false),
        throwsA(isA<ArConnectUnavailableException>().having((e) => e.reason,
            'reason', ArConnectUnavailableReason.noPermission)),
      );
      expect(shown, isEmpty);
      verifyNever(() => wander.connect());
    });

    test('asks that fail together share one prompt and one connect', () async {
      final choice = Completer<bool>();
      var prompts = 0;
      ArConnectPrompt.registerRetryPrompt((reason, answered) {
        prompts++;
        return choice.future;
      });
      var allowed = false;
      when(() => wander.connect()).thenAnswer((_) async => allowed = true);
      Future<String> sign() async {
        if (!allowed) throw missing();
        return 'signed';
      }

      final both = Future.wait([
        ArConnectPrompt.ask(wander, sign),
        ArConnectPrompt.ask(wander, sign),
        ArConnectPrompt.ask(wander, sign),
      ]);
      await pumpEventQueue();
      choice.complete(true);

      expect(await both, ['signed', 'signed', 'signed']);
      expect(prompts, 1);
      verify(() => wander.connect()).called(1);
    });

    test('a connect that fails shows the prompt again', () async {
      final picks = [true, false];
      pick = () => picks.removeAt(0);
      when(() => wander.connect())
          .thenAnswer((_) async => throw Exception('User cancelled'));

      await expectLater(
        ArConnectPrompt.ask<String>(wander, () async => throw missing()),
        throwsA(isA<ArConnectUnavailableException>()),
      );
      expect(shown, [
        ArConnectUnavailableReason.noPermission,
        ArConnectUnavailableReason.noPermission,
      ]);
    });

    test('reconnected on another wallet is a mismatch, and says so', () async {
      // One Reconnect only: without the address check this ends in Cancel
      // rather than asking forever.
      final picks = [true];
      pick = () => picks.isEmpty ? false : picks.removeAt(0);
      var told = 0;
      ArConnectPrompt.registerOtherWalletHandler(() => told++);
      when(() => wander.connect()).thenAnswer((_) async {});
      when(() => wander.getWalletAddress())
          .thenAnswer((_) async => ownerToAddress('other-public-key'));
      var calls = 0;

      await expectLater(
        ArConnectPrompt.ask<String>(wander, () async {
          calls++;
          throw missing();
        }, savedPublicKey: 'saved-public-key'),
        throwsA(isA<ArConnectWalletMismatchException>()),
      );
      expect(told, 1);
      expect(calls, 1, reason: 'nothing is signed for another wallet');
    });

    test('after a mismatch, nothing more is asked for that account', () async {
      final picks = [true];
      pick = () => picks.isEmpty ? false : picks.removeAt(0);
      when(() => wander.connect()).thenAnswer((_) async {});
      when(() => wander.getWalletAddress())
          .thenAnswer((_) async => ownerToAddress('other-public-key'));
      await expectLater(
        ArConnectPrompt.ask<String>(wander, () async => throw missing(),
            savedPublicKey: 'saved-public-key'),
        throwsA(isA<ArConnectWalletMismatchException>()),
      );

      // The rest of an unlock pass: Wander is not asked to sign.
      var calls = 0;
      await expectLater(
        ArConnectPrompt.ask<String>(wander, () async {
          calls++;
          return 'signed';
        }, savedPublicKey: 'saved-public-key'),
        throwsA(isA<ArConnectWalletMismatchException>()),
      );
      expect(calls, 0);

      // Until the next sign-in.
      ArConnectPrompt.signedIn();
      expect(
        await ArConnectPrompt.ask(wander, () async => 'signed',
            savedPublicKey: 'saved-public-key'),
        'signed',
      );
    });

    test(
        'after Cancel, an unlock pass asks nobody until the person acts, '
        'and a write is still offered Reconnect', () async {
      pick = () => false;
      await expectLater(
        ArConnectPrompt.ask<String>(wander, () async => throw missing()),
        throwsA(isA<ArConnectUnavailableException>()),
      );
      expect(shown, hasLength(1));

      // A drive unlock pass: quiet.
      await expectLater(
        ArConnectPrompt.quietAfterCancel(() =>
            ArConnectPrompt.ask<String>(wander, () async => throw missing())),
        throwsA(isA<ArConnectUnavailableException>().having((e) => e.reason,
            'reason', ArConnectUnavailableReason.noPermission)),
      );
      expect(shown, hasLength(1));

      // A write, such as Hide, that signs straight through Wander: asked.
      await expectLater(
        ArConnectPrompt.ask<String>(wander, () async => throw missing()),
        throwsA(isA<ArConnectUnavailableException>()),
      );
      expect(shown, hasLength(2));

      // Once the person acts, a pass may ask again.
      ArConnectPrompt.personActed();
      await expectLater(
        ArConnectPrompt.quietAfterCancel(() =>
            ArConnectPrompt.ask<String>(wander, () async => throw missing())),
        throwsA(isA<ArConnectUnavailableException>()),
      );
      expect(shown, hasLength(3));
    });

    test('a failure while a reconnect runs waits for it, with no new prompt',
        () async {
      pick = () => true;
      final connected = Completer<void>();
      var allowed = false;
      when(() => wander.connect()).thenAnswer((_) async {
        await connected.future;
        allowed = true;
      });
      Future<String> sign() async {
        if (!allowed) throw missing();
        return 'signed';
      }

      final first = ArConnectPrompt.ask(wander, sign);
      await pumpEventQueue();
      expect(shown, hasLength(1), reason: 'Reconnect chosen, connecting');

      // Another request fails while Wander's connect window is open.
      final second = ArConnectPrompt.ask(wander, sign);
      await pumpEventQueue();
      expect(shown, hasLength(1));

      connected.complete();
      expect(await first, 'signed');
      expect(await second, 'signed');
      verify(() => wander.connect()).called(1);
    });

    test('a failure to a request sent before a reconnect just asks again',
        () async {
      pick = () => true;
      var allowed = false;
      when(() => wander.connect()).thenAnswer((_) async => allowed = true);
      final early = Completer<String>();
      var calls = 0;

      // Sent before the reconnect; Wander fails it after.
      final second = ArConnectPrompt.ask(wander, () {
        calls++;
        return calls == 1 ? early.future : Future.value('signed');
      });
      final first = ArConnectPrompt.ask(wander, () async {
        if (!allowed) throw missing();
        return 'signed';
      });
      expect(await first, 'signed');

      early.completeError(missing());
      expect(await second, 'signed');
      expect(shown, hasLength(1));
    });

    test('reconnected on the saved wallet signs', () async {
      pick = () => true;
      when(() => wander.connect()).thenAnswer((_) async {});
      when(() => wander.getWalletAddress())
          .thenAnswer((_) async => ownerToAddress('saved-public-key'));
      var calls = 0;

      final answer = await ArConnectPrompt.ask(wander, () async {
        calls++;
        if (calls == 1) throw missing();
        return 'signed';
      }, savedPublicKey: 'saved-public-key');

      expect(answer, 'signed');
    });
  });

  group('Wander\'s unlock window closed', () {
    // What Wander throws when its unlock window is closed or cancelled.
    Exception dismissed() => Exception('User cancelled the operation');

    test('is no answer: the Try again prompt, and Try again asks again',
        () async {
      pick = () => true;
      var calls = 0;

      final answer = await ArConnectPrompt.ask(wander, () async {
        calls++;
        if (calls == 1) throw dismissed();
        return 'signed';
      });

      expect(answer, 'signed');
      expect(shown, [ArConnectUnavailableReason.noAnswer]);
      expect(calls, 2);
    });

    test('Cancel ends it as no answer', () async {
      pick = () => false;

      await expectLater(
        ArConnectPrompt.ask<String>(wander, () async => throw dismissed()),
        throwsA(isA<ArConnectUnavailableException>().having(
            (e) => e.reason, 'reason', ArConnectUnavailableReason.noAnswer)),
      );
    });

    test('a refused prompt is still a refusal, with no prompt', () async {
      await expectLater(
        ArConnectPrompt.ask<String>(wander,
            () async => throw Exception('User rejected the signature request')),
        throwsA(isA<Exception>()
            .having((e) => '$e', 'message', contains('rejected'))),
      );
      expect(shown, isEmpty);
    });
  });
}
