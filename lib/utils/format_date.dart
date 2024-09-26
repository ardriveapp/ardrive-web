import 'package:intl/intl.dart';

String formatDateToUtcString(DateTime date) {
  String formattedDate =
      '${DateFormat('yyyy-MM-dd HH:mm:ss').format(date.toUtc())} GMT+0';

  return formattedDate;
}
