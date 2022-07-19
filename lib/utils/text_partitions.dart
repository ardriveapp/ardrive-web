class TextPartitions {
  final _indexes = <int>{};
  final String wholeText;

  TextPartitions({
    required this.wholeText,
  }) {
    if (wholeText == '') {
      throw Exception('Text is empty');
    }

    /// Set the beginning and end indexes of the whole text
    setSegment(wholeText);
  }

  List<int> get indexes {
    final indexesAsList = _indexes.toList()..sort();
    return indexesAsList;
  }

  int get amount {
    return indexes.length - 1;
  }

  String getSegment(int index) {
    if (index > amount) {
      throw Exception('Index overflow');
    }
    final sortedIndexes = indexes;
    final start = sortedIndexes.elementAt(index);
    final end = sortedIndexes.elementAt(index + 1);
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
