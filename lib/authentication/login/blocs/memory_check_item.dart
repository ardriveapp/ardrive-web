class MemoryCheckItem {
  const MemoryCheckItem({
    required this.mnemonicWordIndex,
    required this.wordOptions,
    required this.correctWordIndex,
  });

  /// One-based index for word number *
  final int mnemonicWordIndex;

  /// Three options per memory check-item
  final List<String> wordOptions;

  /// Zero-based index of correct word in wordOptions
  final int correctWordIndex;
}
