import 'package:ardrive/utils/key_value_store.dart';

/// How a folder's contents are shown: the table, or the photo gallery.
enum ExplorerViewMode { list, gallery }

/// Remembers the view per drive, on this device.
///
/// Per drive, so a photo drive opens as a gallery and a work drive as a list.
/// One key per drive in the app's key-value store, next to the explorer's
/// other local choices (columns, rows per page).
class ExplorerViewModeStore {
  const ExplorerViewModeStore(this._store);

  final KeyValueStore _store;

  static String keyFor(String driveId) => 'drive_detail_view_mode_$driveId';

  /// The saved view for [driveId]; the list when none, or an unknown value.
  Future<ExplorerViewMode> read(String driveId) async {
    try {
      final stored = await _store.getString(keyFor(driveId));
      return ExplorerViewMode.values.firstWhere(
        (mode) => mode.name == stored,
        orElse: () => ExplorerViewMode.list,
      );
    } catch (_) {
      return ExplorerViewMode.list;
    }
  }

  /// A list is the default, so choosing it forgets the entry.
  Future<void> write(String driveId, ExplorerViewMode mode) async {
    try {
      if (mode == ExplorerViewMode.list) {
        await _store.remove(keyFor(driveId));
      } else {
        await _store.putString(keyFor(driveId), mode.name);
      }
    } catch (_) {
      // The view still switches; it just is not remembered.
    }
  }
}
