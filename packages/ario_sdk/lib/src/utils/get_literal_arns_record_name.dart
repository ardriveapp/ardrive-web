import 'package:ario_sdk/ario_sdk.dart';

String getLiteralARNSRecordName(ARNSUndername undername) {
  if (undername.name == '@') {
    return undername.domain;
  }
  return '${undername.name}_${undername.domain}';
}

