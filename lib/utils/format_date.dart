import 'package:ardrive/utils/logger.dart';
import 'package:intl/intl.dart';

String formatDate(DateTime date) {
  String formattedDate = DateFormat('MMM d yyyy hh:mm:ss a').format(date);

  // Get the time zone offset in hours
  int offsetInHours = date.timeZoneOffset.inHours;

  // Format the time zone offset
  String timeZoneOffset =
      'GMT${offsetInHours >= 0 ? '+$offsetInHours' : '$offsetInHours'}';

  // Combine the formatted date and time with the time zone
  String finalString = '$formattedDate ($timeZoneOffset)';

  logger.d(finalString); // Outputs: Sep 25 2024 09:47:25 AM (GMT-3)

  return finalString;
}
