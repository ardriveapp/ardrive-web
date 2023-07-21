List<List<int>> blockBatches(int minBlock, int maxBlock, int batchSize) {
  List<List<int>> batches = [];

  for (int i = minBlock; i <= maxBlock; i += batchSize) {
    int endBlock = i + batchSize - 1;
    if (endBlock > maxBlock) {
      endBlock = maxBlock;
    }

    batches.add([i, endBlock]);
  }

  return batches;
}
