extension StringExtensions on String {
  String logError() {
    // TODO: Log here with Sentry or whatever we end up using
    // ignore: avoid_print
    print(this);
    return this;
  }
}
