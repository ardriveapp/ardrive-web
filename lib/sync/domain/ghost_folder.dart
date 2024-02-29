class GhostFolder {
  String folderId;
  String driveId;
  bool isHidden;

  GhostFolder({
    required this.folderId,
    required this.driveId,
    this.isHidden = false,
  });
}
