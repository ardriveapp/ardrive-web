import 'dart:async';

Future<dynamic> debounce(Function() function) async {
  return Timer(const Duration(milliseconds: 500), function);
}
