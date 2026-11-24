import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:ardrive/gallery/image_loader/gallery_variant_picker.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// What a fetch is asked for. Public and private files both come through
/// here; the fetcher decides how (gateway read, or download + decrypt).
class GalleryFetchTarget {
  const GalleryFetchTarget({
    required this.fileId,
    required this.variant,
    required this.isPrivate,
    required this.isOriginal,
  });

  final String fileId;
  final GalleryVariant variant;
  final bool isPrivate;
  final bool isOriginal;
}

/// Gets the (decrypted) bytes of one rendition. Injected so the loader is
/// testable.
abstract class GalleryImageFetcher {
  /// [cancelWhen] completes if the loader no longer wants the bytes; a fetcher
  /// that can abort should. One that cannot may ignore it.
  ///
  /// Throw [GalleryRateLimited] on HTTP 429/503 so the loader pauses, and
  /// [GalleryNotFound] when the gateway has no such transaction so the loader
  /// does not retry.
  Future<Uint8List> fetch(
    GalleryFetchTarget target, {
    required Future<void> cancelWhen,
  });
}

/// A fetcher that can do cheap shared work for many tiles at once before any
/// of them takes a download slot. The loader calls [prepare] once per screenful
/// at rest, with every on-screen tile not yet prepared, so (for private files)
/// their cipher tags are read with one query instead of one per slot.
abstract class GalleryFetchPreparer {
  /// Must not throw, and must not wait for the work it starts.
  void prepare(List<GalleryFetchTarget> targets);
}

/// The gateway said slow down (429 or 503).
class GalleryRateLimited implements Exception {
  const GalleryRateLimited({this.retryAfter});

  /// From the Retry-After header, when the gateway sent one.
  final Duration? retryAfter;

  @override
  String toString() => 'GalleryRateLimited(retryAfter: $retryAfter)';
}

/// The gateway answered and has no such transaction (an indexing gap). Not
/// retried by the loader: the tile fails once. The source of the answer
/// remembers it for a cool-down, after which a tile scrolled back into view
/// asks again.
class GalleryNotFound implements Exception {
  const GalleryNotFound();

  @override
  String toString() => 'GalleryNotFound()';
}

class GalleryLoaderConfig {
  const GalleryLoaderConfig({
    this.maxConcurrent = 5,
    this.idleDelay = const Duration(milliseconds: 150),
    this.maxOriginalBytes = galleryMaxOriginalBytes,
    this.cacheBytes = 64 * 1024 * 1024,
    this.maxRetries = 2,
    this.retryDelay = const Duration(milliseconds: 500),
    this.backoffBase = const Duration(seconds: 2),
    this.backoffCap = const Duration(seconds: 60),
    this.cancelInFlightAboveBytes = 256 * 1024,
    this.starvationDelay = const Duration(seconds: 1),
    this.starvedConcurrent = 2,
    this.requestsPerMinute = 240,
    this.burst = 80,
  });

  /// The app's existing data-fetch setting.
  factory GalleryLoaderConfig.fromAppConfig(AppConfig config) =>
      GalleryLoaderConfig(
        maxConcurrent: math.max(1, config.maxConcurrentDataFetches),
      );

  final int maxConcurrent;

  /// How long scrolling must rest before new work starts.
  final Duration idleDelay;
  final int maxOriginalBytes;

  /// Budget for encoded bytes kept for the session.
  final int cacheBytes;

  /// Retries after the first attempt for failures that are not rate limits.
  final int maxRetries;
  final Duration retryDelay;
  final Duration backoffBase;
  final Duration backoffCap;

  /// A tile that leaves the screen mid-fetch aborts the fetch only when the
  /// rendition is larger than this; small thumbnails finish into the cache.
  final int cancelInFlightAboveBytes;

  /// Unbroken scrolling longer than this starts the nearest on-screen tiles
  /// anyway (at most [starvedConcurrent] at once), so a long scroll is not a
  /// blank screen.
  final Duration starvationDelay;
  final int starvedConcurrent;

  /// Request budget: a token bucket that refills at [requestsPerMinute] and
  /// holds at most [burst]. Every image fetch attempt (retries included) takes
  /// one token. With the bucket empty, queued tiles stay loading and start as
  /// tokens refill, nearest on-screen first; nothing is dropped or failed.
  ///
  /// Why 240 and 80: a screenful is ~60 tiles at 1440 and up to ~100 at 4K, so
  /// a burst of 80 loads a normal screen at once (limited only by
  /// [maxConcurrent]) and the rest within a second or two (4 per second). A
  /// fling through a huge folder can then never ask the gateway for more than
  /// 80 + 240 per minute, however many tiles pass by, because scrolling tiles
  /// are not started and what does start is paced. Tag lookups are not counted
  /// here: the batcher already sends one query per batch of up to 50.
  /// [requestsPerMinute] of 0 turns the budget off.
  final int requestsPerMinute;
  final int burst;
}

/// A tile's request: which file, which renditions exist, and how big the tile
/// is.
class GalleryImageRequest {
  const GalleryImageRequest({
    required this.fileId,
    required this.isPrivate,
    required this.variants,
    required this.tileWidth,
    required this.tileHeight,
    required this.devicePixelRatio,
    this.original,
  });

  final String fileId;
  final bool isPrivate;
  final List<GalleryVariant> variants;
  final GalleryVariant? original;

  /// Logical pixels.
  final double tileWidth;
  final double tileHeight;
  final double devicePixelRatio;

  double get tileWidthPx => tileWidth * devicePixelRatio;
  double get tileHeightPx => tileHeight * devicePixelRatio;
}

enum GalleryImageStatus { loading, loaded, failed }

enum GalleryFailureReason {
  noSource,
  fetchFailed,

  /// The gateways answered that the data is not there: not tried again when
  /// the tile scrolls back in, unlike [fetchFailed].
  notFound,
}

@immutable
class GalleryImageState {
  const GalleryImageState.loading()
      : status = GalleryImageStatus.loading,
        image = null,
        failure = null;

  const GalleryImageState.loaded(ImageProvider this.image)
      : status = GalleryImageStatus.loaded,
        failure = null;

  const GalleryImageState.failed(GalleryFailureReason this.failure)
      : status = GalleryImageStatus.failed,
        image = null;

  final GalleryImageStatus status;

  /// Set when [status] is loaded. Already sized for the tile.
  final ImageProvider? image;
  final GalleryFailureReason? failure;

  @override
  bool operator ==(Object other) =>
      other is GalleryImageState &&
      other.status == status &&
      other.image == image &&
      other.failure == failure;

  @override
  int get hashCode => Object.hash(status, image, failure);
}

/// A tile's view of one image. Listen to it; tell it where the tile is.
class GalleryImageHandle implements ValueListenable<GalleryImageState> {
  GalleryImageHandle._(this._loader, this._entry, this._request);

  final GalleryImageLoader _loader;
  final _Entry _entry;
  final GalleryImageRequest _request;
  bool _released = false;
  bool _onScreen = false;
  double _priority = 0;

  @override
  GalleryImageState get value => _entry.notifier.value;

  @override
  void addListener(VoidCallback listener) =>
      _entry.notifier.addListener(listener);

  @override
  void removeListener(VoidCallback listener) =>
      _entry.notifier.removeListener(listener);

  /// Report visibility. Nothing starts until the tile is on screen. A lower
  /// [priority] starts first (distance from the viewport; the caller can
  /// favour the scroll direction by making those tiles nearer).
  void updatePosition({required bool onScreen, double priority = 0}) {
    if (_released) return;
    _onScreen = onScreen;
    _priority = priority;
    _loader._positionChanged(_entry);
  }

  /// Try again after a failure.
  void retry() {
    if (_released) return;
    _loader._retry(_entry);
  }

  /// The tile is gone. Cancels queued work; see
  /// [GalleryLoaderConfig.cancelInFlightAboveBytes] for in-flight work.
  void release() {
    if (_released) return;
    _released = true;
    _onScreen = false;
    _loader._release(_entry, this);
  }
}

class _Entry {
  _Entry(this.key, this.target);

  final String key;
  final GalleryFetchTarget? target;
  final ValueNotifier<GalleryImageState> notifier =
      ValueNotifier(const GalleryImageState.loading());
  final List<GalleryImageHandle> handles = [];
  int order = 0;
  int attempts = 0;
  DateTime? notBefore;
  bool inFlight = false;
  bool queued = false;
  bool prepared = false;

  /// Rate limits this entry has met. A tile that keeps meeting them goes
  /// behind those that have not, so it cannot take every recovery attempt.
  int limits = 0;
  Completer<void>? cancel;
  DateTime? startedAt;
}

/// One shared, polite queue for gallery images.
///
/// Requests come per tile ([acquire]); only on-screen tiles are started, in
/// priority order, at most [GalleryLoaderConfig.maxConcurrent] at a time and
/// only once scrolling has rested ([notifyScrolling]). A 429/503 pauses the
/// whole queue. Fetched bytes sit in an LRU by size, so nothing is fetched
/// twice in a session, and images are handed out as [ResizeImage]s so they
/// decode at tile size.
class GalleryImageLoader {
  GalleryImageLoader({
    required GalleryImageFetcher fetcher,
    this.config = const GalleryLoaderConfig(),
    math.Random? random,

    /// Each event ends a session: [forgetAll] runs.
    Stream<void>? sessionEnds,

    /// Run by [forgetAll], for what holds decoded copies of the images
    /// outside the loader: in the app, Flutter's image cache.
    void Function()? onForget,
  })  : _fetcher = fetcher,
        _onForget = onForget,
        _random = random ?? math.Random() {
    _sessionEnds = sessionEnds?.listen((_) => forgetAll());
  }

  StreamSubscription<void>? _sessionEnds;
  final void Function()? _onForget;

  final GalleryImageFetcher _fetcher;
  final GalleryLoaderConfig config;
  final math.Random _random;

  final Map<String, _Entry> _entries = {};
  // Insertion order == recency (re-inserted on hit).
  final LinkedHashMap<String, Uint8List> _cache = LinkedHashMap();
  int _cacheSize = 0;

  /// Images the gateways said are not there, with when they said so. A tile
  /// rebuilt after scrolling away fails at once instead of asking again;
  /// after [_notFoundFor] it is asked again, as uploads do land late.
  final LinkedHashMap<String, DateTime> _notFound = LinkedHashMap();
  static const _notFoundFor = Duration(minutes: 5);
  static const _notFoundMax = 500;

  /// Bumped by [forgetAll]; a request started before then is not cached or
  /// shown when it finishes.
  int _epoch = 0;

  int _inFlight = 0;
  int _counter = 0;
  bool _idle = true;
  Timer? _idleTimer;
  Timer? _wakeTimer;
  DateTime? _pausedUntil;
  // When the most recent pause began and ends: a 429 from a request started
  // before the pause began is the same burst, not a new hit.
  DateTime? _lastPauseStart;
  DateTime? _lastPauseEnd;
  int _rateLimitHits = 0;
  // After a pause resume with one request and add one per success.
  late int _rampLimit = config.maxConcurrent;
  bool _starving = false;
  Timer? _starveTimer;
  final Set<_Entry> _live = {};
  bool _disposed = false;
  late double _tokens = config.burst.toDouble();
  bool _prepareScheduled = false;
  DateTime? _tokensAt;

  /// Requests currently being fetched. For tests and diagnostics.
  int get inFlightCount => _inFlight;

  /// Bytes held by the memory cache.
  int get cacheSizeBytes => _cacheSize;

  bool _isMissing(String key) {
    final since = _notFound[key];
    if (since == null) return false;
    if (clock.now().difference(since) < _notFoundFor) return true;
    _notFound.remove(key);
    return false;
  }

  bool isCached(String fileId, String txId) =>
      _cache.containsKey(_key(fileId, txId));

  /// The bytes held for this variant of a file, if any: what the full-screen
  /// preview shows at once while the original loads.
  Uint8List? cachedBytes(String fileId, String txId) =>
      _cacheGet(_key(fileId, txId));

  /// Ask for an image. Starts nothing until [GalleryImageHandle.updatePosition]
  /// reports the tile on screen (unless the bytes are already cached).
  ///
  /// A variant the gateways recently said is not there is passed over for
  /// the next best: a file's metadata can list a thumbnail whose upload never
  /// landed.
  GalleryImageHandle acquire(GalleryImageRequest request) {
    bool missing(GalleryVariant v) => _isMissing(_key(request.fileId, v.txId));
    final original = request.original;
    final choice = chooseGalleryVariant(
      variants: [
        for (final v in request.variants)
          if (!missing(v)) v
      ],
      original: original == null || missing(original) ? null : original,
      tileWidthPx: request.tileWidthPx,
      tileHeightPx: request.tileHeightPx,
      isPrivate: request.isPrivate,
      maxOriginalBytes: config.maxOriginalBytes,
    );

    if (choice == null) {
      final entry = _Entry('${request.fileId}/-', null);
      _live.add(entry);
      entry.notifier.value =
          const GalleryImageState.failed(GalleryFailureReason.noSource);
      final handle = GalleryImageHandle._(this, entry, request);
      entry.handles.add(handle);
      return handle;
    }

    final key = _key(request.fileId, choice.variant.txId);
    final cached = _cacheGet(key);
    if (cached != null) {
      // Standalone: already loaded, nothing to schedule or share.
      final entry = _Entry(key, null);
      _live.add(entry);
      entry.notifier.value = GalleryImageState.loaded(
        _provider(
            cached, choice.variant, request.tileWidthPx, request.tileHeightPx),
      );
      final handle = GalleryImageHandle._(this, entry, request);
      entry.handles.add(handle);
      return handle;
    }

    var entry = _entries[key];
    if (entry == null) {
      entry = _Entry(
        key,
        GalleryFetchTarget(
          fileId: request.fileId,
          variant: choice.variant,
          isPrivate: request.isPrivate,
          isOriginal: choice.isOriginal,
        ),
      );
      _live.add(entry);
      _entries[key] = entry;
    }

    final handle = GalleryImageHandle._(this, entry, request);
    entry.handles.add(handle);
    return handle;
  }

  /// Tell the loader scrolling is happening (call on every scroll update or
  /// scrubber move). New work waits for [GalleryLoaderConfig.idleDelay] of
  /// rest, except that unbroken scrolling longer than
  /// [GalleryLoaderConfig.starvationDelay] lets the nearest few tiles start.
  void notifyScrolling() {
    if (_disposed) return;
    if (_idle) {
      _idle = false;
      _starving = false;
      _starveTimer?.cancel();
      _starveTimer = Timer.periodic(config.starvationDelay, (_) {
        _starving = true;
        _pump();
      });
    }
    _idleTimer?.cancel();
    _idleTimer = Timer(config.idleDelay, () {
      _idle = true;
      _starving = false;
      _starveTimer?.cancel();
      _pump();
    });
  }

  /// Forgets every image and hangs up on every request: on sign-out, so
  /// nothing decrypted in a session outlives it. A request that finishes
  /// anyway is dropped, not cached or shown.
  void forgetAll() {
    _epoch++;
    for (final e in _live) {
      if (e.inFlight) _abort(e);
    }
    _cache.clear();
    _cacheSize = 0;
    _notFound.clear();
    _onForget?.call();
  }

  void dispose() {
    _disposed = true;
    _sessionEnds?.cancel();
    _idleTimer?.cancel();
    _wakeTimer?.cancel();
    _starveTimer?.cancel();
    for (final e in _live) {
      _abort(e);
      e.notifier.dispose();
    }
    _live.clear();
    _entries.clear();
    _cache.clear();
    _cacheSize = 0;
  }

  // ---- handle callbacks ----

  void _positionChanged(_Entry entry) {
    if (_disposed) return;
    final state = entry.notifier.value;
    final onScreen = entry.handles.any((h) => h._onScreen);
    if (state.status == GalleryImageStatus.loading && !entry.inFlight) {
      entry.queued = onScreen;
      if (onScreen && entry.order == 0) entry.order = ++_counter;
    } else if (entry.inFlight && !onScreen) {
      _maybeAbort(entry);
    }
    _pump();
  }

  void _retry(_Entry entry) {
    if (entry.notifier.value.status != GalleryImageStatus.failed ||
        entry.target == null) {
      return;
    }
    entry.attempts = 0;
    entry.notBefore = null;
    entry.notifier.value = const GalleryImageState.loading();
    _positionChanged(entry);
  }

  void _release(_Entry entry, GalleryImageHandle handle) {
    if (_disposed) return;
    entry.handles.remove(handle);
    if (entry.handles.isNotEmpty) {
      _positionChanged(entry);
      return;
    }
    entry.queued = false;
    if (entry.inFlight) {
      _maybeAbort(entry);
      return; // finish handler cleans up
    }
    _dispose(entry);
    _pump();
  }

  void _maybeAbort(_Entry entry) {
    final target = entry.target;
    if (target != null &&
        target.variant.size > config.cancelInFlightAboveBytes) {
      _abort(entry);
    }
  }

  void _abort(_Entry entry) {
    final c = entry.cancel;
    if (c != null && !c.isCompleted) c.complete();
  }

  void _dispose(_Entry entry) {
    if (identical(_entries[entry.key], entry)) _entries.remove(entry.key);
    if (!_live.remove(entry)) return;
    // Defer so a listener removing itself in the same turn is not disturbed.
    scheduleMicrotask(entry.notifier.dispose);
  }

  // ---- scheduling ----

  int get _effectiveCap {
    var cap = math.min(config.maxConcurrent, _rampLimit);
    if (!_idle) cap = math.min(cap, config.starvedConcurrent);
    return math.max(1, cap);
  }

  void _pump() {
    if (_disposed) return;
    final now = clock.now();

    final pausedUntil = _pausedUntil;
    if (pausedUntil != null) {
      if (now.isBefore(pausedUntil)) {
        _wakeAfter(pausedUntil.difference(now));
        return;
      }
      _pausedUntil = null;
    }
    // While scrolling, new work waits for rest, unless it has gone on so long
    // that the screen would stay blank.
    if (!_idle && !_starving) return;

    _schedulePrepare();

    Duration? wait;
    while (_inFlight < _effectiveCap) {
      _Entry? best;
      for (final e in _entries.values) {
        if (!e.queued || e.inFlight) continue;
        if (!e.handles.any((h) => h._onScreen)) continue;
        final nb = e.notBefore;
        if (nb != null && now.isBefore(nb)) {
          final d = nb.difference(now);
          if (wait == null || d < wait) wait = d;
          continue;
        }
        if (best == null || _before(e, best)) best = e;
      }
      if (best == null) break;
      final tokenWait = _takeToken(now);
      if (tokenWait != null) {
        if (wait == null || tokenWait < wait) wait = tokenWait;
        break;
      }
      _start(best);
    }
    if (wait != null) _wakeAfter(wait);
  }

  /// Tiles report their positions one by one as a frame lays out; waiting a
  /// microtask lets the whole screenful arrive before it is handed over.
  void _schedulePrepare() {
    if (_prepareScheduled || _fetcher is! GalleryFetchPreparer) return;
    _prepareScheduled = true;
    scheduleMicrotask(() {
      _prepareScheduled = false;
      if (_disposed || (!_idle && !_starving)) return;
      _prepareOnScreen(clock.now());
    });
  }

  /// Hands every on-screen tile that will start soon, and has not been
  /// handed over yet, to the fetcher's [GalleryFetchPreparer.prepare] in one
  /// call.
  void _prepareOnScreen(DateTime now) {
    final Object fetcher = _fetcher;
    if (fetcher is! GalleryFetchPreparer) return;
    final targets = <GalleryFetchTarget>[];
    for (final e in _entries.values) {
      final target = e.target;
      // Started ones count too: their download is still waiting on the tags.
      if (target == null || e.prepared || !(e.queued || e.inFlight)) continue;
      if (!e.handles.any((h) => h._onScreen)) continue;
      final nb = e.notBefore;
      if (nb != null && now.isBefore(nb)) continue;
      e.prepared = true;
      targets.add(target);
    }
    if (targets.isNotEmpty) fetcher.prepare(targets);
  }

  /// Takes a token and returns null, or returns how long until one is there.
  Duration? _takeToken(DateTime now) {
    if (config.requestsPerMinute <= 0) return null;
    final rate = config.requestsPerMinute / 60000.0; // tokens per ms
    final last = _tokensAt;
    if (last != null) {
      _tokens = math.min(
        config.burst.toDouble(),
        _tokens + now.difference(last).inMilliseconds * rate,
      );
    }
    _tokensAt = now;
    if (_tokens >= 1) {
      _tokens -= 1;
      return null;
    }
    return Duration(milliseconds: ((1 - _tokens) / rate).ceil());
  }

  bool _before(_Entry a, _Entry b) {
    final pa = a.handles.where((h) => h._onScreen).map((h) => h._priority);
    final pb = b.handles.where((h) => h._onScreen).map((h) => h._priority);
    if (a.limits != b.limits) return a.limits < b.limits;
    final va = pa.isEmpty ? double.infinity : pa.reduce(math.min);
    final vb = pb.isEmpty ? double.infinity : pb.reduce(math.min);
    if (va != vb) return va < vb;
    return a.order < b.order;
  }

  void _wakeAfter(Duration d) {
    _wakeTimer?.cancel();
    _wakeTimer = Timer(d, _pump);
  }

  Future<void> _start(_Entry entry) async {
    entry.inFlight = true;
    entry.queued = false;
    entry.cancel = Completer<void>();
    entry.startedAt = clock.now();
    _inFlight++;
    final cancel = entry.cancel!;
    final epoch = _epoch;

    Uint8List? bytes;
    Object? error;
    try {
      bytes = await _fetcher.fetch(entry.target!, cancelWhen: cancel.future);
    } catch (e) {
      error = e;
    }

    _inFlight--;
    entry.inFlight = false;
    final aborted = cancel.isCompleted || epoch != _epoch;
    entry.cancel = null;
    if (_disposed) return;
    final onScreen = entry.handles.any((h) => h._onScreen);

    if (epoch != _epoch) {
      // Signed out while it was in flight.
      if (entry.handles.isEmpty) {
        _dispose(entry);
      } else {
        entry.queued = onScreen;
      }
    } else if (error == null && bytes != null) {
      _onSuccess(entry);
      _cachePut(entry.key, bytes);
      if (entry.handles.isEmpty) {
        _dispose(entry);
      } else {
        entry.notifier.value =
            GalleryImageState.loaded(_providerFor(entry, bytes));
        if (identical(_entries[entry.key], entry)) _entries.remove(entry.key);
      }
    } else if (entry.handles.isEmpty) {
      if (error is GalleryRateLimited) _backoff(error, entry);
      _dispose(entry);
    } else if (aborted) {
      // We hung up because the tile left the screen, and it is still around:
      // not a failure. It stays loading and is queued again only if it is
      // back on screen.
      entry.queued = onScreen;
    } else if (error is GalleryRateLimited) {
      _backoff(error, entry);
      entry.limits++;
      entry.queued = onScreen;
    } else if (error is GalleryNotFound) {
      // An answer, not a hiccup: fail once, no automatic retry.
      _notFound[entry.key] = clock.now();
      while (_notFound.length > _notFoundMax) {
        _notFound.remove(_notFound.keys.first);
      }
      entry.notifier.value =
          const GalleryImageState.failed(GalleryFailureReason.notFound);
    } else {
      entry.attempts++;
      if (entry.attempts > config.maxRetries) {
        entry.notifier.value =
            const GalleryImageState.failed(GalleryFailureReason.fetchFailed);
      } else {
        entry.queued = onScreen;
        entry.notBefore = clock.now().add(config.retryDelay * entry.attempts);
      }
    }
    _pump();
  }

  /// A request started after the last pause ended got through: the gateway has
  /// recovered, so forget the backoff and let concurrency grow back one step.
  void _onSuccess(_Entry entry) {
    final started = entry.startedAt;
    final end = _lastPauseEnd;
    if (end != null && started != null && started.isBefore(end)) return;
    _rateLimitHits = 0;
    if (_rampLimit < config.maxConcurrent) _rampLimit++;
  }

  void _backoff(GalleryRateLimited e, _Entry entry) {
    final now = clock.now();
    final started = entry.startedAt;
    final sameBurst = (_pausedUntil != null && now.isBefore(_pausedUntil!)) ||
        (started != null &&
            _lastPauseStart != null &&
            started.isBefore(_lastPauseStart!));

    Duration delay;
    final ra = e.retryAfter;
    if (ra != null) {
      delay = ra > config.backoffCap ? config.backoffCap : ra;
    } else {
      final exp = config.backoffBase * math.pow(2, _rateLimitHits).toInt();
      final capped = exp > config.backoffCap ? config.backoffCap : exp;
      final jitterMs =
          (capped.inMilliseconds * 0.25 * _random.nextDouble()).round();
      delay = capped + Duration(milliseconds: jitterMs);
    }

    if (sameBurst) {
      // One burst of 429s is one hit. Honour a longer Retry-After, nothing
      // more.
      if (ra != null && _pausedUntil != null) {
        final until = now.add(delay);
        if (until.isAfter(_pausedUntil!)) {
          _pausedUntil = until;
          _lastPauseEnd = until;
        }
      }
      return;
    }

    _rateLimitHits++;
    _rampLimit = 1;
    final until = now.add(delay);
    _lastPauseStart = now;
    _lastPauseEnd = until;
    _pausedUntil = until;
  }

  // ---- cache ----

  static String _key(String fileId, String txId) => '$fileId/$txId';

  /// Decoded for the largest tile sharing the entry.
  ImageProvider _providerFor(_Entry entry, Uint8List bytes) {
    var w = 0.0, h = 0.0;
    for (final handle in entry.handles) {
      w = math.max(w, handle._request.tileWidthPx);
      h = math.max(h, handle._request.tileHeightPx);
    }
    return _provider(bytes, entry.target!.variant, w, h);
  }

  /// Decodes at the size the tile needs, never smaller than it fills: for a
  /// tile that crops (cover), that is the limiting side, so a panorama is not
  /// blurred. No resize when the stored image is already no bigger.
  ImageProvider _provider(
    Uint8List bytes,
    GalleryVariant variant,
    double tileWidthPx,
    double tileHeightPx,
  ) {
    if (variant.width <= 0 || variant.height <= 0) {
      return ResizeImage(
        MemoryImage(bytes),
        width: math.max(1, tileWidthPx.round()),
        allowUpscaling: false,
      );
    }
    final scale = math.max(
      tileWidthPx / variant.width,
      tileHeightPx / variant.height,
    );
    if (scale >= 1) return MemoryImage(bytes);
    return ResizeImage(
      MemoryImage(bytes),
      width: math.max(1, (variant.width * scale).ceil()),
      allowUpscaling: false,
    );
  }

  Uint8List? _cacheGet(String key) {
    final v = _cache.remove(key);
    if (v != null) _cache[key] = v;
    return v;
  }

  void _cachePut(String key, Uint8List bytes) {
    final old = _cache.remove(key);
    if (old != null) _cacheSize -= old.length;
    if (bytes.length > config.cacheBytes) return;
    _cache[key] = bytes;
    _cacheSize += bytes.length;
    while (_cacheSize > config.cacheBytes && _cache.length > 1) {
      final oldest = _cache.keys.first;
      _cacheSize -= _cache.remove(oldest)!.length;
    }
  }
}
