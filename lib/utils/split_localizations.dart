import 'package:ardrive/utils/text_partitions.dart';

typedef WidgetFactory<T> = T Function(String text);

List<T> splitTranslationsWithMultipleStyles<T>({
  required String originalText,
  required WidgetFactory defaultMapper,
  required Map<String, WidgetFactory> parts,
  T? separator,
}) {
  final partitions = TextPartitions(wholeText: originalText);

  /// Add the specified parts first
  parts.forEach((stringSegment, mapper) {
    partitions.setSegment(stringSegment);
  });

  final mappedParts = <T>[];

  final numSegments = partitions.amount;
  for (int segmentIndex = 0; segmentIndex < numSegments; segmentIndex++) {
    final segment = partitions.getSegment(segmentIndex);
    final customMapper = parts[segment];
    if (customMapper == null) {
      /// It's not a custom part, use default mapper
      mappedParts.add(defaultMapper(segment));
    } else {
      /// It's a given part, use specified mapper
      mappedParts.add(customMapper(segment));
    }
    if (separator != null && segmentIndex + 1 < numSegments) {
      mappedParts.add(separator);
    }
  }

  return mappedParts;
}
