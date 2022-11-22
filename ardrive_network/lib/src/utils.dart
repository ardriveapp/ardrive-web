void checkIsJsonAndAsBytesParams(isJson, asBytes) {
  if (isJson && asBytes) {
    throw ArgumentError(
      'It\'s not possible to use isJson and asBytes together.',
    );
  }
}
