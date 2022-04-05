// import 'package:ardrive/utils/split_localizations.dart';

// class Pair {
//   final num a;
//   final num b;

//   Pair({
//     required this.a,
//     required this.b,
//   })

//   bool equals(Pair other) {
//     return other.a == a && other.b == b;
//   };
// };

class TextPartitions {
  final _indexes = Set<int>();
  final String wholeText;

  TextPartitions({
    required this.wholeText,
  }) {
    if (wholeText == '') {
      throw Exception('Text is empty');
    }
    _indexes.add(0);
    _indexes.add(wholeText.length);
  }

  // Widget getWidget() {
  //   return widgetMapper(segment);
  // }

  List<int> get indexes {
    return _indexes.toList();
  }

  int get amount {
    return indexes.length - 1;
  }

  String getSegment(int index) {
    if (index > amount) {
      throw Exception('Index overflow');
    }
    final start = _indexes.elementAt(index);
    final end = _indexes.elementAt(index + 1);
    return wholeText.substring(start, end);
  }

  void setSegment(String segment) {
    final start = wholeText.indexOf(segment);
    final end = start + segment.length;

    if (start == -1) {
      throw Exception('Segment is not present in the text');
    }

    _indexes.add(start);
    _indexes.add(end);
  }
}
