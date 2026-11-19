import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/gallery/image_loader/gallery_image_loader.dart';
import 'package:ardrive/gallery/image_loader/gallery_variant_picker.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCall {
  FakeCall(this.target, this.cancelWhen);
  final GalleryFetchTarget target;
  final Future<void> cancelWhen;
  final Completer<Uint8List> completer = Completer();
  bool aborted = false;
}

class FakeFetcher implements GalleryImageFetcher {
  final List<FakeCall> calls = [];
  int inFlight = 0;
  int maxInFlight = 0;

  List<String> get started => calls.map((c) => c.target.fileId).toList();
  FakeCall call(String fileId) =>
      calls.lastWhere((c) => c.target.fileId == fileId);

  @override
  Future<Uint8List> fetch(
    GalleryFetchTarget target, {
    required Future<void> cancelWhen,
  }) {
    final c = FakeCall(target, cancelWhen);
    calls.add(c);
    cancelWhen.then((_) {
      c.aborted = true;
      if (!c.completer.isCompleted) {
        c.completer.completeError(Exception('aborted'));
      }
    });
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    return c.completer.future.whenComplete(() => inFlight--);
  }

  void succeed(String fileId, [int bytes = 100]) =>
      call(fileId).completer.complete(Uint8List(bytes));
  void fail(String fileId, Object e) => call(fileId).completer.completeError(e);
}

GalleryImageRequest req(
  String id, {
  bool isPrivate = false,
  int size = 5000,
  List<GalleryVariant>? variants,
  double tileW = 100,
  double tileH = 100,
  int vw = 512,
  int vh = 512,
}) =>
    GalleryImageRequest(
      fileId: id,
      isPrivate: isPrivate,
      variants: variants ??
          [GalleryVariant(txId: 'tx-$id', size: size, width: vw, height: vh)],
      tileWidth: tileW,
      tileHeight: tileH,
      devicePixelRatio: 1,
    );

void main() {
  const config = GalleryLoaderConfig(
    maxConcurrent: 2,
    idleDelay: Duration(milliseconds: 150),
    retryDelay: Duration(milliseconds: 100),
    cacheBytes: 1000,
  );

  late FakeFetcher fetcher;
  late GalleryImageLoader loader;

  void run(void Function(FakeAsync async) body) {
    fakeAsync((async) {
      fetcher = FakeFetcher();
      loader = GalleryImageLoader(fetcher: fetcher, config: config);
      body(async);
      loader.dispose();
    });
  }

  GalleryImageHandle show(String id, {double priority = 0, bool priv = false}) {
    final h = loader.acquire(req(id, isPrivate: priv));
    h.updatePosition(onScreen: true, priority: priority);
    return h;
  }

  test('never more than the cap in flight', () {
    run((async) {
      for (var i = 0; i < 6; i++) {
        show('f$i', priority: i.toDouble());
      }
      async.flushMicrotasks();
      expect(fetcher.inFlight, 2);
      for (var i = 0; i < 6; i++) {
        async.flushMicrotasks();
        final next = fetcher.calls.firstWhere((c) => !c.completer.isCompleted);
        next.completer.complete(Uint8List(10));
        async.flushMicrotasks();
      }
      expect(fetcher.calls.length, 6);
      expect(fetcher.maxInFlight, 2);
    });
  });

  test('off-screen items never start', () {
    run((async) {
      final h = loader.acquire(req('a'));
      h.updatePosition(onScreen: false);
      async.elapse(const Duration(seconds: 5));
      expect(fetcher.calls, isEmpty);
      expect(h.value.status, GalleryImageStatus.loading);
    });
  });

  test('leaving the screen cancels a queued item', () {
    run((async) {
      show('a', priority: 0);
      show('b', priority: 1);
      final c = show('c', priority: 2);
      async.flushMicrotasks();
      expect(fetcher.started, ['a', 'b']);
      c.updatePosition(onScreen: false);
      fetcher.succeed('a');
      async.flushMicrotasks();
      expect(fetcher.started, ['a', 'b']);
      c.release();
      async.elapse(const Duration(seconds: 1));
      expect(fetcher.started, ['a', 'b']);
    });
  });

  test('leaving mid-flight aborts a large fetch, lets a small one finish', () {
    run((async) {
      final big = loader.acquire(req('big', size: 1024 * 1024))
        ..updatePosition(onScreen: true);
      final small = show('small');
      async.flushMicrotasks();
      big.release();
      small.release();
      async.flushMicrotasks();
      expect(fetcher.call('big').aborted, isTrue);
      expect(fetcher.call('small').aborted, isFalse);
      fetcher.succeed('small');
      async.flushMicrotasks();
      expect(loader.isCached('small', 'tx-small'), isTrue);
    });
  });

  test('waits for scroll to rest before starting', () {
    run((async) {
      loader.notifyScrolling();
      show('a');
      async.elapse(const Duration(milliseconds: 100));
      expect(fetcher.calls, isEmpty);
      loader.notifyScrolling();
      async.elapse(const Duration(milliseconds: 100));
      expect(fetcher.calls, isEmpty);
      async.elapse(const Duration(milliseconds: 60));
      expect(fetcher.started, ['a']);
    });
  });

  test('order follows priority, not arrival', () {
    run((async) {
      loader.notifyScrolling();
      show('far', priority: 9);
      show('near', priority: 1);
      show('mid', priority: 5);
      show('last', priority: 20);
      async.elapse(const Duration(milliseconds: 200));
      expect(fetcher.started, ['near', 'mid']);
      fetcher.succeed('near');
      async.flushMicrotasks();
      expect(fetcher.started, ['near', 'mid', 'far']);
    });
  });

  test('a 429 pauses everything and resumes after Retry-After', () {
    run((async) {
      show('a', priority: 0);
      show('b', priority: 1);
      show('c', priority: 2);
      async.flushMicrotasks();
      fetcher.fail(
          'a', const GalleryRateLimited(retryAfter: Duration(seconds: 10)));
      async.flushMicrotasks();
      // b still in flight; finishing it must not start c during the pause.
      fetcher.succeed('b');
      async.elapse(const Duration(seconds: 9));
      expect(fetcher.started, ['a', 'b']);
      async.elapse(const Duration(seconds: 2));
      // Resumes gently: one request, not a burst, then grows back.
      expect(fetcher.started.length, 3); // a again, c still waiting
      expect(fetcher.inFlight, 1);
      fetcher.succeed(fetcher.calls.last.target.fileId);
      async.flushMicrotasks();
      expect(fetcher.started.length, 4);
      expect(fetcher.started.toSet(), {'a', 'b', 'c'});
    });
  });

  test('without Retry-After the pause backs off exponentially and is capped',
      () {
    run((async) {
      show('a');
      async.flushMicrotasks();
      fetcher.fail('a', const GalleryRateLimited());
      async.flushMicrotasks();
      // base 2s + up to 25% jitter
      async.elapse(const Duration(seconds: 1, milliseconds: 900));
      expect(fetcher.calls.length, 1);
      async.elapse(const Duration(seconds: 1));
      expect(fetcher.calls.length, 2);
      fetcher.fail('a', const GalleryRateLimited());
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3, milliseconds: 900));
      expect(fetcher.calls.length, 2); // second pause is 4s+
      async.elapse(const Duration(seconds: 2));
      expect(fetcher.calls.length, 3);
    });
  });

  test('a huge Retry-After is capped', () {
    run((async) {
      show('a');
      async.flushMicrotasks();
      fetcher.fail(
          'a', const GalleryRateLimited(retryAfter: Duration(hours: 1)));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 59));
      expect(fetcher.calls.length, 1);
      async.elapse(const Duration(seconds: 2));
      expect(fetcher.calls.length, 2);
    });
  });

  test('other failures retry a bounded number of times then fail', () {
    run((async) {
      final h = show('a');
      for (var i = 0; i < 3; i++) {
        async.elapse(const Duration(seconds: 1));
        fetcher.fail('a', Exception('boom'));
        async.flushMicrotasks();
      }
      async.elapse(const Duration(seconds: 5));
      expect(fetcher.calls.length, 3); // 1 try + 2 retries
      expect(h.value.status, GalleryImageStatus.failed);
      expect(h.value.failure, GalleryFailureReason.fetchFailed);
    });
  });

  test('success yields a tile-sized provider; cached item is not refetched',
      () {
    run((async) {
      final h = show('a');
      async.flushMicrotasks();
      fetcher.succeed('a', 100);
      async.flushMicrotasks();
      expect(h.value.status, GalleryImageStatus.loaded);
      expect(h.value.image, isA<ResizeImage>());
      h.release();

      final again = loader.acquire(req('a'));
      expect(again.value.status, GalleryImageStatus.loaded);
      again.updatePosition(onScreen: true);
      async.elapse(const Duration(seconds: 1));
      expect(fetcher.calls.length, 1);
    });
  });

  test('two tiles for one image share a single fetch', () {
    run((async) {
      show('a');
      show('a');
      async.flushMicrotasks();
      expect(fetcher.calls.length, 1);
    });
  });

  test('cache evicts least recently used by bytes', () {
    run((async) {
      for (final id in ['a', 'b', 'c']) {
        final h = show(id);
        async.flushMicrotasks();
        fetcher.succeed(id, 400);
        async.flushMicrotasks();
        h.release();
      }
      // 1000 byte budget: a (oldest) evicted.
      expect(loader.isCached('a', 'tx-a'), isFalse);
      expect(loader.isCached('b', 'tx-b'), isTrue);
      expect(loader.isCached('c', 'tx-c'), isTrue);
      expect(loader.cacheSizeBytes, 800);
    });
  });

  test('no usable variant fails without a fetch', () {
    run((async) {
      final h = loader.acquire(req('a', variants: const []));
      h.updatePosition(onScreen: true);
      async.elapse(const Duration(seconds: 1));
      expect(fetcher.calls, isEmpty);
      expect(h.value.failure, GalleryFailureReason.noSource);
    });
  });

  test('private files never fetch an original', () {
    run((async) {
      const r = GalleryImageRequest(
        fileId: 'p',
        isPrivate: true,
        variants: [GalleryVariant(txId: 't', size: 10, width: 64, height: 64)],
        original:
            GalleryVariant(txId: 'o', size: 100, width: 4000, height: 3000),
        tileWidth: 300,
        tileHeight: 300,
        devicePixelRatio: 1,
      );
      loader.acquire(r).updatePosition(onScreen: true);
      async.flushMicrotasks();
      expect(fetcher.calls.single.target.variant.txId, 't');
      expect(fetcher.calls.single.target.isOriginal, isFalse);
    });
  });

  test('a tile that left the screen alive is not refetched or failed', () {
    run((async) {
      final h = loader.acquire(req('big', size: 1024 * 1024))
        ..updatePosition(onScreen: true);
      async.flushMicrotasks();
      // More aborts than maxRetries (2): if an abort counted as a failed
      // attempt the tile would be marked failed by now.
      for (var i = 0; i < 4; i++) {
        h.updatePosition(onScreen: false);
        async.flushMicrotasks();
        expect(fetcher.calls.length, i + 1);
        expect(fetcher.call('big').aborted, isTrue);
        async.elapse(const Duration(seconds: 10));
        expect(fetcher.calls.length, i + 1, reason: 'not refetched off screen');
        expect(h.value.status, GalleryImageStatus.loading);
        h.updatePosition(onScreen: true);
        async.flushMicrotasks();
      }
      expect(fetcher.calls.length, 5);
      expect(h.value.status, GalleryImageStatus.loading);
      fetcher.succeed('big');
      async.flushMicrotasks();
      expect(h.value.status, GalleryImageStatus.loaded);
    });
  });

  test('a retryable failure off screen waits until back on screen', () {
    run((async) {
      final h = show('a');
      async.flushMicrotasks();
      h.updatePosition(onScreen: false);
      fetcher.fail('a', Exception('boom'));
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 10));
      expect(fetcher.calls.length, 1);
      expect(h.value.status, GalleryImageStatus.loading);
      h.updatePosition(onScreen: true);
      async.elapse(const Duration(seconds: 1));
      expect(fetcher.calls.length, 2);
    });
  });

  test('a burst of 429s is one hit, and concurrency ramps back up', () {
    run((async) {
      show('a', priority: 0);
      show('b', priority: 1);
      show('c', priority: 2);
      show('d', priority: 3);
      async.flushMicrotasks();
      fetcher.fail('a', const GalleryRateLimited());
      fetcher.fail('b', const GalleryRateLimited());
      async.flushMicrotasks();
      // One hit: base 2 s (+25% jitter), not 2 s then 4 s.
      async.elapse(const Duration(milliseconds: 2600));
      expect(fetcher.calls.length, 3);
      expect(fetcher.inFlight, 1);
      fetcher.succeed(fetcher.calls.last.target.fileId);
      async.flushMicrotasks();
      expect(fetcher.inFlight, 2); // ramp: 1 -> 2
      expect(fetcher.maxInFlight, 2);
    });
  });

  test('a success from before the pause does not reset the backoff', () {
    run((async) {
      show('a', priority: 0);
      show('b', priority: 1);
      async.flushMicrotasks();
      fetcher.fail('a', const GalleryRateLimited());
      async.flushMicrotasks();
      fetcher.succeed('b'); // started before the pause
      async.elapse(const Duration(milliseconds: 2600));
      expect(fetcher.calls.length, 3);
      fetcher.fail('a', const GalleryRateLimited());
      async.flushMicrotasks();
      // second hit => 4 s, so nothing within 3.9 s
      async.elapse(const Duration(milliseconds: 3900));
      expect(fetcher.calls.length, 3);
      async.elapse(const Duration(seconds: 2));
      expect(fetcher.calls.length, 4);
    });
  });

  test('continuous scrolling still loads the nearest few after a second', () {
    run((async) {
      loader.notifyScrolling();
      for (var i = 0; i < 4; i++) {
        show('f$i', priority: i.toDouble());
      }
      for (var t = 0; t < 9; t++) {
        loader.notifyScrolling();
        async.elapse(const Duration(milliseconds: 100));
      }
      expect(fetcher.calls, isEmpty);
      for (var t = 0; t < 4; t++) {
        loader.notifyScrolling();
        async.elapse(const Duration(milliseconds: 100));
      }
      expect(fetcher.started, ['f0', 'f1']);
    });
  });

  group('decode size', () {
    int? widthOf(GalleryImageHandle h) => (h.value.image as ResizeImage).width;

    test('panorama in a cover tile decodes by the limiting side', () {
      run((async) {
        final h = loader
            .acquire(req('p', tileW: 300, tileH: 100, vw: 1000, vh: 200))
          ..updatePosition(onScreen: true);
        async.flushMicrotasks();
        fetcher.succeed('p');
        async.flushMicrotasks();
        expect(widthOf(h), 500);
      });
    });

    test('a shared entry decodes for the largest tile', () {
      run((async) {
        final small = loader
            .acquire(req('s', tileW: 100, tileH: 100, vw: 1000, vh: 1000))
          ..updatePosition(onScreen: true);
        loader
            .acquire(req('s', tileW: 400, tileH: 400, vw: 1000, vh: 1000))
            .updatePosition(onScreen: true);
        async.flushMicrotasks();
        fetcher.succeed('s');
        async.flushMicrotasks();
        expect(widthOf(small), 400);
      });
    });

    test('no resize when the stored image is not larger than the tile', () {
      run((async) {
        final h = loader
            .acquire(req('z', tileW: 600, tileH: 600, vw: 512, vh: 512))
          ..updatePosition(onScreen: true);
        async.flushMicrotasks();
        fetcher.succeed('z');
        async.flushMicrotasks();
        expect(h.value.image, isA<MemoryImage>());
      });
    });
  });

  test('dispose disposes notifiers without throwing on later release', () {
    run((async) {
      final h = show('a');
      loader.dispose();
      h.release();
      async.flushMicrotasks();
    });
  });

  test('concurrency ramps 1, 2, 3, 4 after a pause and never exceeds 4', () {
    fakeAsync((async) {
      fetcher = FakeFetcher();
      loader = GalleryImageLoader(
        fetcher: fetcher,
        config: const GalleryLoaderConfig(
          maxConcurrent: 4,
          retryDelay: Duration(milliseconds: 100),
        ),
      );
      for (var i = 0; i < 12; i++) {
        show('f$i', priority: i.toDouble());
      }
      async.flushMicrotasks();
      expect(fetcher.inFlight, 4);
      fetcher.fail(
          'f0', const GalleryRateLimited(retryAfter: Duration(seconds: 1)));
      async.flushMicrotasks();
      // The three that started before the pause finish during it.
      for (final id in ['f1', 'f2', 'f3']) {
        fetcher.succeed(id);
        async.flushMicrotasks();
      }
      expect(fetcher.inFlight, 0);
      async.elapse(const Duration(seconds: 2));
      final steps = <int>[fetcher.inFlight];
      for (var i = 0; i < 4; i++) {
        fetcher.calls
            .firstWhere((c) => !c.completer.isCompleted)
            .completer
            .complete(Uint8List(10));
        async.flushMicrotasks();
        steps.add(fetcher.inFlight);
      }
      expect(steps, [1, 2, 3, 4, 4]);
      expect(fetcher.maxInFlight, 4);
      loader.dispose();
    });
  });
}
