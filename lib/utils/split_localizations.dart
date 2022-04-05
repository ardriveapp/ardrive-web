import 'package:ardrive/utils/text_partitions.dart';
import 'package:flutter/material.dart';

typedef widgetFactory = Widget Function(String text);

// class partition {
//   final String segment;
//   final widgetFactory widgetMapper;
//   late num index;

//   partition({
//     required wholeText,
//     required this.segment,
//     required this.widgetMapper,
//   }) {
//     index = wholeText.indexOf(segment);
//   }

//   Widget getWidget() {
//     return widgetMapper(segment);
//   }
// }

List<Widget> splitTranslationsWithMultipleStyles(
  String originalText,
  widgetFactory defaultMapper,
  Map<String, widgetFactory> parts,
) {
  final partitions = TextPartitions(wholeText: originalText);

  /// Add the specified parts first
  parts.forEach((stringSegment, mapper) {
    partitions.setSegment(stringSegment);
  });

  final widgets = <Widget>[];

  final numSegments = partitions.amount;
  for (var segmentIndex = 0; segmentIndex < numSegments; segmentIndex++) {
    final segment = partitions.getSegment(segmentIndex);
    final customMapper = parts[segment];
    if (customMapper == null) {
      /// It's not a custom part, use default mapper
      widgets.add(defaultMapper(segment));
    } else {
      /// It's a given part, use specified mapper
      widgets.add(customMapper(segment));
    }
  }

  return widgets;
}
