/// Base class for exceptions that are not tracked by the logger.
///
/// The classes that extend this class automatically will not be logged to Sentry.
abstract class UntrackedException implements Exception {}
