/// How long gateways may keep the old answer after a name changes
/// (docs/NAMES.md, "Cache time"; Q8, Q16).
enum ArNSCacheTime {
  oneMinute(60),
  fiveMinutes(300),
  fifteenMinutes(900),
  oneHour(3600),
  oneDay(86400);

  const ArNSCacheTime(this.seconds);

  final int seconds;

  /// 5 minutes: Turbo's own default is an hour, so it is always sent.
  static const standard = ArNSCacheTime.fiveMinutes;

  /// The option for [seconds], or null when a record was set elsewhere to a
  /// time ArDrive doesn't offer.
  static ArNSCacheTime? fromSeconds(int seconds) {
    for (final value in values) {
      if (value.seconds == seconds) return value;
    }
    return null;
  }
}

/// When a record change is live everywhere, in seconds: gateways may keep
/// serving the old target for the cache time it had, so a repointed record
/// takes the longer of [previousTtlSeconds] and [ttlSeconds]. A new
/// undername had none: just [ttlSeconds].
int arnsLiveWithinSeconds({required int ttlSeconds, int? previousTtlSeconds}) =>
    previousTtlSeconds != null && previousTtlSeconds > ttlSeconds
        ? previousTtlSeconds
        : ttlSeconds;
