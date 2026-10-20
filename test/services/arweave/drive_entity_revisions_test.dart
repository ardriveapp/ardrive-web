import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/utils/graphql_retry.dart';
import 'package:ardrive/utils/internet_checker.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:artemis/artemis.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:mocktail/mocktail.dart';

import '../../test_utils/mocks.dart';

class _MockArtemisClient extends Mock implements ArtemisClient {}

class _MockInternetChecker extends Mock implements InternetChecker {}

typedef _Tx
    = DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction;

/// Answers `DriveEntityHistory` one page at a time, and records what it was
/// asked for.
class _PagedRetry extends GraphQLRetry {
  _PagedRetry(this._pages, {this.fails = false})
      : super(_MockArtemisClient(), internetChecker: _MockInternetChecker());

  final List<List<_Tx>> _pages;
  final bool fails;
  final asked = <DriveEntityHistoryArguments>[];

  int _next = 0;

  @override
  Future<GraphQLResponse<T>> execute<T, U extends JsonSerializable>(
    GraphQLQuery<T, U> query, {
    Function(Exception e)? onRetry,
    int maxAttempts = GraphQLRetry.defaultMaxAttempts,
  }) async {
    if (fails) {
      throw Exception('gateway down');
    }

    asked.add(query.variables as DriveEntityHistoryArguments);

    final page = _pages[_next];
    final isLast = _next == _pages.length - 1;
    _next++;

    final data = DriveEntityHistory$Query()
      ..transactions = (DriveEntityHistory$Query$TransactionConnection()
        ..edges = [
          for (final tx in page)
            DriveEntityHistory$Query$TransactionConnection$TransactionEdge()
              ..node = tx
              ..cursor = tx.id,
        ]
        ..pageInfo = (DriveEntityHistory$Query$TransactionConnection$PageInfo()
          ..hasNextPage = !isLast));

    return GraphQLResponse<T>(data: data as T);
  }
}

/// Serves each revision's metadata from a map instead of a gateway, and
/// counts the reads.
class _Service extends ArweaveService {
  _Service(super.client, super.crypto, super.driveDao, super.configService,
      {super.artemisClient});

  Map<String, Uint8List> bodies = {};
  final read = <String>[];

  @override
  Future<Uint8List> getEntityDataFromNetwork({
    required String txId,
    bool largeBody = false,
  }) async {
    read.add(txId);
    final body = bodies[txId];
    if (body == null) {
      throw Exception('404 for $txId');
    }
    return body;
  }
}

/// A drive's own history, read for a drive not synced on this device.
///
/// It is shown in the drive's activity tab exactly as a sync would record it,
/// so it has to come out in sync's order and leave out what sync leaves out.
/// And it is all or nothing: without its first revision, the second would
/// read as the drive's creation.
void main() {
  const driveId = 'drive-id';
  const owner = 'owner-address';
  const block = 1500000;

  late MockArDriveCrypto crypto;
  late _Service service;

  _Tx driveTx(
    String id, {
    required int? height,
    required int unixTime,
    String txOwner = owner,
    bool cipherIv = false,
  }) =>
      _Tx()
        ..id = id
        ..owner = (TransactionCommonMixin$Owner()..address = txOwner)
        ..block = height == null
            ? null
            : (TransactionCommonMixin$Block()
              ..height = height
              ..timestamp = 0)
        ..tags = [
          TransactionCommonMixin$Tag()
            ..name = EntityTag.arFs
            ..value = '0.15',
          TransactionCommonMixin$Tag()
            ..name = EntityTag.entityType
            ..value = 'drive',
          TransactionCommonMixin$Tag()
            ..name = EntityTag.driveId
            ..value = driveId,
          TransactionCommonMixin$Tag()
            ..name = EntityTag.drivePrivacy
            ..value =
                cipherIv ? DrivePrivacyTag.private : DrivePrivacyTag.public,
          TransactionCommonMixin$Tag()
            ..name = EntityTag.unixTime
            ..value = '$unixTime',
          if (cipherIv)
            TransactionCommonMixin$Tag()
              ..name = EntityTag.cipherIv
              ..value = 'iv',
        ];

  Uint8List body(String name, {bool isHidden = false}) =>
      Uint8List.fromList(utf8.encode(jsonEncode({
        'name': name,
        'rootFolderId': 'root-id',
        'isHidden': isHidden,
      })));

  _Service serviceWith(List<List<_Tx>> pages, {bool fails = false}) {
    service.graphQLRetry = _PagedRetry(pages, fails: fails);
    return service;
  }

  Future<List<String>?> namesFor(List<List<_Tx>> pages) async {
    final revisions = await serviceWith(pages)
        .getDriveEntityRevisions(driveId, ownerAddress: owner);
    return revisions?.map((r) => r.name!).toList();
  }

  setUp(() {
    final configService = MockConfigService();
    when(() => configService.config).thenReturn(AppConfig(
      allowedDataItemSizeForTurbo: 0,
      stripePublishableKey: '',
      maxConcurrentDataFetches: 3,
    ));

    crypto = MockArDriveCrypto();
    service = _Service(
      Arweave(api: ArweaveApi(gatewayUrl: Uri.parse('https://example.test'))),
      crypto,
      MockDriveDao(),
      configService,
      artemisClient: _MockArtemisClient(),
    );
  });

  test('asks for this drive\'s own revisions, by its owner', () async {
    service.bodies = {'a': body('Photos')};
    final retry = _PagedRetry([
      [driveTx('a', height: block, unixTime: 1)],
    ]);
    service.graphQLRetry = retry;

    await service.getDriveEntityRevisions(driveId, ownerAddress: owner);

    expect(retry.asked.single.driveId, driveId);
    expect(retry.asked.single.ownerAddress, owner);
    expect(retry.asked.single.entityType, EntityTypeTag.drive);
  });

  test('comes back oldest first, in the chain\'s order', () async {
    service.bodies = {
      'create': body('Photos'),
      'rename': body('Pics'),
      'hide': body('Pics', isHidden: true),
      'pending': body('Pictures'),
    };

    // Listed out of order and across pages: one block's transactions in any
    // order the gateway likes, a later block, and one not mined yet.
    final names = await namesFor([
      [
        driveTx('pending', height: null, unixTime: 1),
        driveTx('hide', height: block + 1, unixTime: 5),
      ],
      [
        driveTx('rename', height: block, unixTime: 300),
        driveTx('create', height: block, unixTime: 200),
      ],
    ]);

    expect(names, ['Photos', 'Pics', 'Pics', 'Pictures']);
  });

  test('carries each revision\'s time and hidden flag', () async {
    service.bodies = {
      'create': body('Photos'),
      'hide': body('Photos', isHidden: true),
    };

    final revisions = await serviceWith([
      [
        driveTx('create', height: block, unixTime: 1700000000),
        driveTx('hide', height: block + 1, unixTime: 1700000100),
      ],
    ]).getDriveEntityRevisions(driveId, ownerAddress: owner);

    expect(revisions!.map((r) => r.isHidden), [false, true]);
    expect(
      revisions.first.createdAt,
      DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
    );
    expect(revisions.map((r) => r.txId), ['create', 'hide']);
  });

  test('is nothing when the history cannot be listed', () async {
    final revisions = await serviceWith([], fails: true)
        .getDriveEntityRevisions(driveId, ownerAddress: owner);

    expect(revisions, isNull);
  });

  /// Without its first revision the second would read as the creation.
  test('is nothing when any revision cannot be read', () async {
    service.bodies = {'rename': body('Pics')};

    final names = await namesFor([
      [
        driveTx('create', height: block, unixTime: 1),
        driveTx('rename', height: block, unixTime: 2),
      ],
    ]);

    expect(names, isNull);
  });

  test('leaves out a revision that does not parse, as sync does', () async {
    service.bodies = {
      'create': body('Photos'),
      'broken': Uint8List.fromList(utf8.encode('not json')),
      'rename': body('Pics'),
    };

    final names = await namesFor([
      [
        driveTx('create', height: block, unixTime: 1),
        driveTx('broken', height: block, unixTime: 2),
        driveTx('rename', height: block, unixTime: 3),
      ],
    ]);

    expect(names, ['Photos', 'Pics']);
  });

  test('leaves out a revision signed by anyone else', () async {
    service.bodies = {
      'create': body('Photos'),
      'spoof': body('Not yours'),
    };

    final names = await namesFor([
      [
        driveTx('create', height: block, unixTime: 1),
        driveTx('spoof', height: block, unixTime: 2, txOwner: 'someone-else'),
      ],
    ]);

    expect(names, ['Photos']);
  });

  /// One failure decides the answer, so the reads still to start are not
  /// made: they would only be thrown away.
  test('stops reading at the first failure', () async {
    service.bodies = {
      for (var i = 1; i < 20; i++) 'tx-$i': body('Name $i'),
    };

    final names = await namesFor([
      [
        for (var i = 0; i < 20; i++)
          driveTx('tx-$i', height: block + i, unixTime: i + 1),
      ],
    ]);

    expect(names, isNull);
    // tx-0 fails; only the reads already started alongside it run.
    expect(service.read.length, lessThanOrEqualTo(3));
  });

  test('reads nothing once it is told to stop', () async {
    service.bodies = {'a': body('Photos')};
    final retry = _PagedRetry([
      [driveTx('a', height: block, unixTime: 1)],
      [driveTx('b', height: block + 1, unixTime: 2)],
    ]);
    service.graphQLRetry = retry;

    final revisions = await service.getDriveEntityRevisions(
      driveId,
      ownerAddress: owner,
      isCancelled: () => true,
    );

    expect(revisions, isNull);
    expect(retry.asked, hasLength(1), reason: 'no second page');
    expect(service.read, isEmpty);
  });

  test('reads nothing past its limit, and says so', () async {
    final names = await namesFor([
      [
        for (var i = 0; i <= ArweaveService.maxDriveRevisionsRead; i++)
          driveTx('tx-$i', height: block, unixTime: i),
      ],
    ]);

    expect(names, isNull);
    expect(service.read, isEmpty);
  });

  group('a private drive', () {
    final driveKey = SecretKey(List.filled(32, 9));

    setUpAll(() {
      registerFallbackValue(SecretKey([]));
      registerFallbackValue(Uint8List(0));
      registerFallbackValue(_Tx());
    });

    test('is decrypted with the key it is given', () async {
      service.bodies = {
        'create': Uint8List.fromList([1, 2, 3])
      };
      when(() => crypto.decryptEntityJson(any(), any(), any()))
          .thenAnswer((_) async => {'name': 'Secret', 'rootFolderId': 'root'});

      final revisions = await serviceWith([
        [driveTx('create', height: block, unixTime: 1, cipherIv: true)],
      ]).getDriveEntityRevisions(
        driveId,
        ownerAddress: owner,
        driveKey: driveKey,
      );

      expect(revisions!.single.name, 'Secret');
      final key = verify(
        () => crypto.decryptEntityJson(any(), any(), captureAny()),
      ).captured.single;
      expect(identical(key, driveKey), isTrue);
    });

    /// No IV, nothing to decrypt with: sync skips it without a request.
    test('skips a revision with no IV without reading it', () async {
      service.bodies = {
        'create': Uint8List.fromList([1, 2, 3])
      };
      when(() => crypto.decryptEntityJson(any(), any(), any()))
          .thenAnswer((_) async => {'name': 'Secret', 'rootFolderId': 'root'});

      final revisions = await serviceWith([
        [
          driveTx('create', height: block, unixTime: 1, cipherIv: true),
          driveTx('broken', height: block, unixTime: 2),
        ],
      ]).getDriveEntityRevisions(
        driveId,
        ownerAddress: owner,
        driveKey: driveKey,
      );

      expect(revisions!.map((r) => r.txId), ['create']);
      expect(service.read, ['create']);
    });
  });
}
