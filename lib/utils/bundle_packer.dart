abstract class BundlePacker<T extends SizedItem> {
  Future<List<List<T>>> packItems(List<T> items);
}

class SizedItem {
  int get size {
    throw UnimplementedError();
  }
}


