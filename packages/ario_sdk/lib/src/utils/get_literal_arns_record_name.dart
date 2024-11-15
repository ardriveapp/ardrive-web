import 'package:ario_sdk/ario_sdk.dart';

String getLiteralARNSRecordName(ARNSUndername undername) {
  if (undername.name == '@') {
    return undername.domain;
  }
  return '${undername.name}_${undername.domain}';
}

/// Splits an ARNS record name into its literal name and domain.
/// If the name is not in the format [name]_[domain], it returns [name] and null.
(String, String?) splitArNSRecordName(String name) {
  if (name.contains('_')) {
    return (name.split('_').first, name.split('_').last);
  }

  return (name, null);
}
//
