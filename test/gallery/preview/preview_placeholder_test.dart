import 'dart:typed_data';

import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/entities/file_entity.dart';
import 'package:ardrive/gallery/image_loader/gallery_image_loader.dart';
import 'package:ardrive/gallery/preview/preview_placeholder.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/arweave/data_gateway_fallback.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../explorer/gallery_test_items.dart';

class _Loader extends Mock implements GalleryImageLoader {}

class _Thumbnails extends Mock implements ThumbnailRepository {}

class _Arweave extends Mock implements ArweaveService {}

class _Fallback extends Mock implements DataGatewayFallback {}

class _Client extends Mock implements Arweave {}

void main() {
  setUpAll(() {
    registerFallbackValue(_Client());
    registerFallbackValue(DateTime(2026));
  });

  late _Loader loader;
  late _Thumbnails thumbnails;
  late _Arweave arweave;
  late _Fallback fallback;
  late _Client client;

  setUp(() {
    loader = _Loader();
    thumbnails = _Thumbnails();
    arweave = _Arweave();
    fallback = _Fallback();
    client = _Client();
    when(() => arweave.gatewayFallback).thenReturn(fallback);
    when(() => arweave.client).thenReturn(client);
    when(() => loader.cachedBytes(any(), any())).thenReturn(null);
  });

  Variant v(String tx, int w, {int size = 40000}) =>
      Variant(name: 'x', txId: tx, size: size, width: w, height: w);

  Future<Uint8List?> source(
    List<Variant>? variants, {
    bool isPrivate = false,
  }) =>
      previewPlaceholderFor(
        fileItem('p', variants: variants),
        isPrivate: isPrivate,
        loader: loader,
        thumbnails: thumbnails,
        arweave: arweave,
      );

  test('the gallery\'s own copy, largest first, costs nothing', () async {
    when(() => loader.cachedBytes('p', 'large'))
        .thenReturn(Uint8List.fromList([1]));
    expect(await source([v('small', 100), v('large', 512)]), [1]);
    verifyNever(() => fallback.fetchDataAtMost(any(), any(),
        maxBytes: any(named: 'maxBytes')));
  });

  test('otherwise one small fetch of the largest thumbnail, capped', () async {
    when(() => fallback.fetchDataAtMost('large', client,
            maxBytes: previewPlaceholderMaxBytes))
        .thenAnswer((_) async => Uint8List.fromList([2]));
    expect(await source([v('small', 100), v('large', 512)]), [2]);
  });

  test('a private one is fetched and decrypted the thumbnails\' way', () async {
    when(() => thumbnails.fetchPrivateVariantBytes(
          fileId: 'p',
          driveId: any(named: 'driveId'),
          txId: 'large',
          size: any(named: 'size'),
          fileName: any(named: 'fileName'),
          lastModifiedDate: any(named: 'lastModifiedDate'),
        )).thenAnswer((_) async => Uint8List.fromList([3]));
    expect(await source([v('large', 512)], isPrivate: true), [3]);
  });

  test('nothing for a photo with no thumbnail, or one too big to be quick',
      () async {
    expect(await source(null), isNull);
    expect(await source([v('big', 512, size: previewPlaceholderMaxBytes + 1)]),
        isNull);
    verifyNever(() => fallback.fetchDataAtMost(any(), any(),
        maxBytes: any(named: 'maxBytes')));
  });

  test('a failed fetch is no thumbnail, not an error', () async {
    when(() => fallback.fetchDataAtMost(any(), any(),
        maxBytes: any(named: 'maxBytes'))).thenThrow(Exception('down'));
    expect(await source([v('large', 512)]), isNull);
  });
}
