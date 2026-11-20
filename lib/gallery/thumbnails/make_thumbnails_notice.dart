import 'package:ardrive/drive_explorer/thumbnail/missing_thumbnails.dart';
import 'package:ardrive/gallery/thumbnails/make_thumbnails_dialog.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/pages/drive_detail/models/data_table_item.dart';
import 'package:ardrive/utils/app_localizations_wrapper.dart';
import 'package:ardrive/utils/key_value_store.dart';
import 'package:ardrive/utils/local_key_value_store.dart';
import 'package:ardrive_ui/ardrive_ui.dart';
import 'package:flutter/material.dart';

/// How many of [items] lack thumbnails: images with none, or only a small
/// one when the gallery needs a larger one.
int imagesNeedingThumbnails(Iterable<ArDriveDataTableItem> items) => items
    .whereType<FileDataTableItem>()
    .where((f) =>
        !f.isHidden &&
        missingThumbnailsOf(
              contentType: f.contentType,
              size: f.size ?? 0,
              variants: f.thumbnail?.variants,
            ) !=
            MissingThumbnails.none)
    .length;

/// Remembers "Not now" per folder, on this device.
class MakeThumbnailsNoticeStore {
  const MakeThumbnailsNoticeStore(this._store);

  final KeyValueStore _store;

  static String keyFor(String folderId) =>
      'gallery_make_thumbnails_dismissed_$folderId';

  Future<bool> isDismissed(String folderId) async {
    try {
      return await _store.getBool(keyFor(folderId)) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> dismiss(String folderId) async {
    try {
      await _store.putBool(keyFor(folderId), true);
    } catch (_) {
      // Hidden for now all the same; it is just not remembered.
    }
  }
}

/// Above a gallery whose images lack thumbnails, for the drive's owner:
/// "18 images here need thumbnails", with Make thumbnails and Not now. Not
/// now hides it for the folder; the folder's menu still offers it.
class MakeThumbnailsNotice extends StatefulWidget {
  const MakeThumbnailsNotice({
    super.key,
    required this.items,
    required this.drive,
    required this.folder,
    this.store,
  });

  final List<ArDriveDataTableItem> items;
  final Drive drive;
  final FolderEntry folder;

  /// Where Not now is remembered; the app's own store when null.
  final KeyValueStore? store;

  @override
  State<MakeThumbnailsNotice> createState() => _MakeThumbnailsNoticeState();
}

class _MakeThumbnailsNoticeState extends State<MakeThumbnailsNotice> {
  // Hidden until the store says otherwise, so a dismissed notice never
  // flashes up.
  bool _dismissed = true;

  @override
  void initState() {
    super.initState();
    _read();
  }

  @override
  void didUpdateWidget(MakeThumbnailsNotice old) {
    super.didUpdateWidget(old);
    if (old.folder.id != widget.folder.id) {
      _dismissed = true;
      _read();
    }
  }

  Future<MakeThumbnailsNoticeStore> _store() async => MakeThumbnailsNoticeStore(
      widget.store ?? await LocalKeyValueStore.getInstance());

  Future<void> _read() async {
    final folderId = widget.folder.id;
    final dismissed = await (await _store()).isDismissed(folderId);
    if (!mounted || folderId != widget.folder.id) return;
    setState(() => _dismissed = dismissed);
  }

  Future<void> _dismiss() async {
    setState(() => _dismissed = true);
    await (await _store()).dismiss(widget.folder.id);
  }

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    final owner = widget.items.any((i) => i.isOwner);
    final count = imagesNeedingThumbnails(widget.items);
    if (!owner || count == 0) return const SizedBox.shrink();
    final l10n = appLocalizationsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: ArDriveSpacing.sm),
      child: ArDriveNotice(
        key: const ValueKey('make-thumbnails-notice'),
        type: ArDriveNoticeType.info,
        message: l10n.makeThumbnailsNotice(count),
        actionLabel: l10n.makeThumbnails,
        onAction: () => showMakeThumbnailsDialog(
          context,
          drive: widget.drive,
          folderId: widget.folder.id,
          folderName: widget.folder.name,
        ),
        dismissLabel: l10n.makeThumbnailsNotNow,
        onDismiss: _dismiss,
      ),
    );
  }
}
