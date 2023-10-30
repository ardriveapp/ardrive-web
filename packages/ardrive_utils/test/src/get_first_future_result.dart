import 'package:ardrive_utils/src/get_first_future_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('should return the first future completed with a value', () async {
    final future1sec =
        Future.delayed(const Duration(seconds: 1)).then((value) => 1);
    final future2sec =
        Future.delayed(const Duration(seconds: 2)).then((value) => 2);
    final future3sec =
        Future.delayed(const Duration(seconds: 3)).then((value) => 3);

    final value =
        await getFirstFutureResult([future1sec, future2sec, future3sec]);

    expect(value, 1);
  });

  test(
      'should return the first future completed with a value even if some future failed before',
      () async {
    final future1sec = Future.delayed(const Duration(seconds: 1))
        .then((value) => throw Exception());
    final future2sec =
        Future.delayed(const Duration(seconds: 2)).then((value) => 2);
    final future3sec =
        Future.delayed(const Duration(seconds: 3)).then((value) => 3);

    final value =
        await getFirstFutureResult([future1sec, future2sec, future3sec]);

    expect(value, 2);
  });

  test('should throws only when ALL fails', () async {
    final future1sec = Future.delayed(const Duration(seconds: 1))
        .then((value) => throw Exception());
    final future2sec = Future.delayed(const Duration(seconds: 2))
        .then((value) => throw Exception());
    final future3sec = Future.delayed(const Duration(seconds: 3))
        .then((value) => throw Exception());

    expectLater(
        () async =>
            await getFirstFutureResult([future1sec, future2sec, future3sec]),
        throwsA(const TypeMatcher<List>()));
  });
}
