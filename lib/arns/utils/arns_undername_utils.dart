import 'dart:convert';

import 'package:ario_sdk/ario_sdk.dart';

ARNSUndername fromJsonDataBase(String json) {
  final Map<String, dynamic> map = jsonDecode(json);
  return ARNSUndernameFactory.create(
    name: map['name'],
    domain: map['domain'],
    transactionId: map['record']['transactionId'],
  );
}
