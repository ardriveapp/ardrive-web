import 'package:ardrive/models/models.dart';

abstract class SelectedItem<T> {
  final T item;

  SelectedItem({required this.item});

  String get id;
}

class SelectedFile extends SelectedItem<FileWithLatestRevisionTransactions> {
  SelectedFile({
    required FileWithLatestRevisionTransactions file,
  }) : super(item: file);

  @override
  String get id => item.id;
}

class SelectedFolder extends SelectedItem<FolderEntry> {
  SelectedFolder({
    required FolderEntry folder,
  }) : super(item: folder);

  @override
  String get id => item.id;
}
