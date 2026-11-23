import 'package:ardrive/core/upload/domain/repository/upload_repository.dart';
import 'package:ardrive_uploader/ardrive_uploader.dart';
import 'package:flutter_test/flutter_test.dart';

ThumbnailUploadMetadata uploaded(String name, String txId, int w, int h) =>
    ThumbnailUploadMetadata(
      contentType: 'image/jpeg',
      height: h,
      width: w,
      size: w * h,
      relatesTo: 'data-tx',
      name: name,
      originalFileId: 'file',
    )..setTxId = txId;

void main() {
  test('every variant an upload made is recorded, small first', () {
    final thumbnail = thumbnailOfUpload([
      uploaded('small', 'tx-small', 100, 66),
      uploaded('large', 'tx-large', 512, 338),
    ])!;
    expect(thumbnail.variants.map((v) => v.txId), ['tx-small', 'tx-large']);
    expect(thumbnail.variants.last.width, 512);
    expect(thumbnail.variants.last.name, 'large');
  });

  test('no thumbnails, no thumbnail', () {
    expect(thumbnailOfUpload(null), isNull);
    expect(thumbnailOfUpload(const []), isNull);
  });
}
