enum DrivePrivacy { public, publicReadOnly, private }

class Drive {
  String id;
  String rootId;

  String name;
  DrivePrivacy privacy;

  Drive({this.id, this.rootId, this.name, this.privacy});
}
