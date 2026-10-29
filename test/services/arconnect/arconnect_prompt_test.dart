import 'dart:async';

import 'package:ardrive/services/arconnect/arconnect_prompt.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

void main() {
  late MockArConnectService wander;
  late StreamController<void> focus;

  /// What the prompt was shown for, and the `answered` it was given.
  late List<ArConnectUnavailableReason> shown;
  late List<Future<void>> answeredSignals;

  /// What the person picks when the prompt shows; null leaves it open.
  late bool? Function() pick;

  setUp(() {
    ArConnectPrompt.reset();
    wander = MockArConnectService();
    when(() => wander.isExtensionPresent()).thenReturn(true);
    focus = StreamController<void>.broadcast();
    ArConnectPrompt.focusRegained = () => focus.stream;
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

        focus.add(null);
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
        focus.add(null);
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
        focus.add(null);
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
        focus.add(null);
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
}
