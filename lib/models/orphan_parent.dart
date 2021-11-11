import 'orphan.dart';

class OrphanParent {
  String id;
  String? parentFolderId;
  String driveId;
  List<Orphan> orphans;
  OrphanParent({
    required this.id,
    required this.driveId,
    required this.orphans,
    this.parentFolderId,
  });
}
