import 'dart:async';

addDebounce(Function() function) async {
  return Timer(const Duration(milliseconds: 500), function);
}
