Future<T> runExclusiveAcrossTabs<T>(String name, Future<T> Function() body) =>
    body();
