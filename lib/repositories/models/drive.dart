enum DrivePrivacy { publicReadOnly, private }

class Drive {
  String id;
  String rootFolderId;

  String name;
  DrivePrivacy privacy;

  Drive({this.id, this.rootFolderId, this.name, this.privacy});
}
