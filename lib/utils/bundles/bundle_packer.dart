import 'sized_item.dart';

abstract class BundlePacker<T extends SizedItem> {
  Future<List<List<T>>> packItems(List<T> items);
}
