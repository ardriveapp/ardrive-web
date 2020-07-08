class Folder {
  String id;
  String name;
  List<FolderEntry> entries;

  Folder({this.name});
}

class FolderEntry {
  String id;
  bool isSubfolder;
  bool isHidden;
}
