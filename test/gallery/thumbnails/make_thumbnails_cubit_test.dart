import 'dart:async';

import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/blocs/upload/models/upload_review_summary.dart';
import 'package:ardrive/blocs/upload/upload_cubit.dart' show UploadMethod;
import 'package:ardrive/core/upload/metadata_write_cost.dart';
import 'package:ardrive/drive_explorer/thumbnail/missing_thumbnails.dart';
import 'package:ardrive/drive_explorer/thumbnail/repository/thumbnail_repository.dart';
import 'package:ardrive/gallery/thumbnails/make_thumbnails_cubit.dart';
import 'package:ardrive/turbo/services/upload_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/utils.dart';

class _MockThumbnails extends Mock implements ThumbnailRepository {}

class _MockCostReader extends Mock implements MetadataWriteCostReader {}

UploadReviewSummary summary({required bool free, bool covered = true}) =>
    UploadReviewSummary(
      method: UploadMethod.turbo,
      isFree: free,
      priceUnavailable: false,
      isCovered: covered,
      overFreeAllowance: !free,
      offersPaymentChoice: false,
      usesLegacySelector: false,
      creditsCost: BigInt.zero,
      creditsBalance: BigInt.zero,
      usdCost: null,
      arCost: BigInt.zero,
    );

void main() {
  late _MockThumbnails thumbnails;
  late _MockCostReader costReader;
  late MockProfileCubit profile;
  late List<List<int>> priced;

  setUp(() {
    thumbnails = _MockThumbnails();
    costReader = _MockCostReader();
    profile = MockProfileCubit();
    priced = [];
    when(() => profile.state)
        .thenReturn(ProfileLoggedIn(user: getTestUser(), useTurbo: true));
    registerFallbackValue(getTestUser().wallet);
    registerFallbackValue(BigInt.zero);
    when(() => thumbnails.hasNothingToAdd(any())).thenReturn(false);
    when(() => costReader.read(
          itemSizes: any(named: 'itemSizes'),
          wallet: any(named: 'wallet'),
          walletBalance: any(named: 'walletBalance'),
          refusedByTurbo: any(named: 'refusedByTurbo'),
        )).thenAnswer((i) async {
      priced.add(i.namedArguments[#itemSizes] as List<int>);
      return MetadataWriteCost(summary(free: true));
    });
  });

  MakeThumbnailsCubit cubit(Map<String, MissingThumbnails> images,
          {bool isPrivate = false,
          Future<Map<String, MissingThumbnails>> Function()? find}) =>
      MakeThumbnailsCubit(
        isPrivate: isPrivate,
        findImages: find ?? () async => images,
        thumbnails: thumbnails,
        costReader: costReader,
        profileCubit: profile,
      );

  test('nothing to do when every image has its thumbnails', () async {
    final c = cubit(const {});
    await c.load();
    expect(c.state.phase, MakeThumbnailsPhase.nothingToDo);
    verifyNever(() => costReader.read(
          itemSizes: any(named: 'itemSizes'),
          wallet: any(named: 'wallet'),
          walletBalance: any(named: 'walletBalance'),
        ));
  });

  test('prices what each image lacks, and is ready', () async {
    final c = cubit(const {
      'a': MissingThumbnails.all,
      'b': MissingThumbnails.large,
    });
    await c.load();
    expect(c.state.phase, MakeThumbnailsPhase.ready);
    expect(c.state.total, 2);
    expect(c.state.summary!.isFree, isTrue);
    expect(priced.single, [
      ...estimatedItemSizes(MissingThumbnails.all),
      ...estimatedItemSizes(MissingThumbnails.large),
    ]);
  });

  test('makes every one, counting them as they land', () async {
    when(() => thumbnails.uploadThumbnail(fileId: any(named: 'fileId')))
        .thenAnswer((_) async => true);
    final c = cubit(const {
      'a': MissingThumbnails.all,
      'b': MissingThumbnails.all,
      'c': MissingThumbnails.large,
    });
    await c.load();
    final made = <int>[];
    final sub = c.stream.listen((s) => made.add(s.made));
    await c.start();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();
    expect(c.state.phase, MakeThumbnailsPhase.done);
    expect(c.state.made, 3);
    expect(made, containsAllInOrder([1, 2, 3]));
    for (final id in ['a', 'b', 'c']) {
      verify(() => thumbnails.uploadThumbnail(fileId: id)).called(1);
    }
  });

  test('does not start unless the price is covered', () async {
    when(() => costReader.read(
              itemSizes: any(named: 'itemSizes'),
              wallet: any(named: 'wallet'),
              walletBalance: any(named: 'walletBalance'),
              refusedByTurbo: any(named: 'refusedByTurbo'),
            ))
        .thenAnswer((_) async =>
            MetadataWriteCost(summary(free: false, covered: false)));
    final c = cubit(const {'a': MissingThumbnails.all});
    await c.load();
    await c.start();
    expect(c.state.phase, MakeThumbnailsPhase.ready);
    verifyNever(() => thumbnails.uploadThumbnail(fileId: any(named: 'fileId')));
  });

  test('Stop lets the one under way finish and keeps it; no new one starts',
      () async {
    final first = Completer<bool>();
    when(() => thumbnails.uploadThumbnail(fileId: 'a'))
        .thenAnswer((_) => first.future);
    when(() => thumbnails.uploadThumbnail(fileId: any(named: 'fileId')))
        .thenAnswer((i) => i.namedArguments[#fileId] == 'a'
            ? first.future
            : Future.value(true));
    // Private: one at a time.
    final c = cubit(const {
      'a': MissingThumbnails.all,
      'b': MissingThumbnails.all,
      'c': MissingThumbnails.all,
    }, isPrivate: true);
    await c.load();
    final run = c.start();
    await Future<void>.delayed(Duration.zero);
    c.stop();
    expect(c.state.phase, MakeThumbnailsPhase.stopping);
    first.complete(true);
    await run;
    expect(c.state.phase, MakeThumbnailsPhase.done);
    expect(c.state.stopped, isTrue);
    expect(c.state.made, 1);
    verifyNever(() => thumbnails.uploadThumbnail(fileId: 'b'));
  });

  test('a payment refusal ends the run and says so; what was made stays',
      () async {
    when(() => thumbnails.uploadThumbnail(fileId: any(named: 'fileId')))
        .thenAnswer((i) => i.namedArguments[#fileId] == 'a'
            ? Future.value(true)
            : Future.error(TurboPaymentRequiredException()));
    final c = cubit(const {
      'a': MissingThumbnails.all,
      'b': MissingThumbnails.all,
      'c': MissingThumbnails.all,
    }, isPrivate: true);
    await c.load();
    await c.start();
    expect(c.state.phase, MakeThumbnailsPhase.done);
    expect(c.state.paymentRequired, isTrue);
    expect(c.state.made, 1);
    verifyNever(() => thumbnails.uploadThumbnail(fileId: 'c'));
  });

  test('other failures are counted and the rest carry on', () async {
    when(() => thumbnails.uploadThumbnail(fileId: any(named: 'fileId')))
        .thenAnswer((i) => i.namedArguments[#fileId] == 'b'
            ? Future.error(Exception('gateway'))
            : Future.value(true));
    final c = cubit(const {
      'a': MissingThumbnails.all,
      'b': MissingThumbnails.all,
      'c': MissingThumbnails.all,
    });
    await c.load();
    await c.start();
    expect(c.state.made, 2);
    expect(c.state.failed, 1);
    expect(c.state.paymentRequired, isFalse);
  });

  test('an image that gave nothing more is not counted as made', () async {
    when(() => thumbnails.uploadThumbnail(fileId: any(named: 'fileId')))
        .thenAnswer((i) async => i.namedArguments[#fileId] != 'tiny');
    final c = cubit(const {
      'a': MissingThumbnails.all,
      'tiny': MissingThumbnails.large,
    });
    await c.load();
    await c.start();
    expect(c.state.made, 1);
    expect(c.state.nothingToAdd, 1);
    expect(c.state.failed, 0);
  });

  test('images already found to give nothing more are not offered again',
      () async {
    when(() => thumbnails.hasNothingToAdd('tiny')).thenReturn(true);
    final c = cubit(const {
      'a': MissingThumbnails.all,
      'tiny': MissingThumbnails.large,
    });
    await c.load();
    expect(c.state.total, 1);
  });

  test('a folder that cannot be read ends, saying so, not on a spinner',
      () async {
    final c = cubit(const {}, find: () => Future.error(Exception('db')));
    await c.load();
    expect(c.state.phase, MakeThumbnailsPhase.done);
    expect(c.state.loadFailed, isTrue);
  });

  test('closed while working, it starts nothing new', () async {
    final first = Completer<bool>();
    when(() => thumbnails.uploadThumbnail(fileId: any(named: 'fileId')))
        .thenAnswer((i) => i.namedArguments[#fileId] == 'a'
            ? first.future
            : Future.value(true));
    final c = cubit(const {
      'a': MissingThumbnails.all,
      'b': MissingThumbnails.all,
    }, isPrivate: true);
    await c.load();
    final run = c.start();
    await Future<void>.delayed(Duration.zero);
    await c.close();
    first.complete(true);
    await run;
    verifyNever(() => thumbnails.uploadThumbnail(fileId: 'b'));
  });
}
