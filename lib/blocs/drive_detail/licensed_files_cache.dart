/// Whether each drive has a licensed file, read once per drive and kept.
///
/// The read scans the drive's files, and a folder's contents are reloaded on
/// every write a sync makes, so asking on each reload scanned the drive over
/// and over. It is read when a drive opens and again only after something
/// that can change the answer: a sync that finished, or a write such as
/// adding a license. A read that fails is not kept, so the next asks again.
class LicensedFilesCache {
  LicensedFilesCache(this._read);

  final Future<bool> Function(String driveId) _read;
  final _byDrive = <String, bool>{};

  /// The answer for [driveId]: the kept one, or a fresh read. False when the
  /// read fails: whether to offer a column is not worth failing a folder over.
  Future<bool> hasLicensedFiles(String driveId) async {
    final kept = _byDrive[driveId];
    if (kept != null) return kept;

    try {
      return _byDrive[driveId] = await _read(driveId);
    } catch (_) {
      return false;
    }
  }

  /// Forgets every answer, so each drive is read again when next asked.
  void forget() => _byDrive.clear();
}
