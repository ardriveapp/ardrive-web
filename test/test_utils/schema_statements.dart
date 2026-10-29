import 'package:drift/drift.dart';

/// Counts the schema statements a database's migration issues, and lets a
/// test stop the migration at one of them.
///
/// Schema statements are drift's `runCustom`: every `CREATE`, `ALTER`,
/// `DROP` and `PRAGMA` a migration issues. drift runs the migration on the
/// executor it hands to `beforeOpen`, which an interceptor does not see on its
/// own, so this wraps that one too.
class SchemaStatements extends QueryInterceptor {
  SchemaStatements({this.at, this.instead});

  /// The statement to stop at, counting from 1, or null to only count.
  final int? at;

  /// What happens in place of statement [at]: a failure, or a future that
  /// never completes because the test killed the database underneath.
  final Future<void> Function(String statement)? instead;

  var count = 0;

  @override
  Future<bool> ensureOpen(QueryExecutor executor, QueryExecutorUser user) =>
      executor.ensureOpen(_InterceptedUser(user, this));

  @override
  Future<void> runCustom(
      QueryExecutor executor, String statement, List<Object?> args) {
    if (++count == at) return instead!(statement);
    return super.runCustom(executor, statement, args);
  }
}

class _InterceptedUser implements QueryExecutorUser {
  _InterceptedUser(this._inner, this._interceptor);

  final QueryExecutorUser _inner;
  final QueryInterceptor _interceptor;

  @override
  int get schemaVersion => _inner.schemaVersion;

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) =>
      _inner.beforeOpen(executor.interceptWith(_interceptor), details);
}
