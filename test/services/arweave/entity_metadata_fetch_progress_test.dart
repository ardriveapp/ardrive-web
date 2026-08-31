import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/services/config/app_config.dart';
import 'package:ardrive/sync/domain/models/drive_entity_history.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:artemis/artemis.dart';
import 'package:arweave/arweave.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_utils/mocks.dart';

class _MockArtemisClient extends Mock implements ArtemisClient {}

/// The count the sync reports during its longest phase has to come from inside
/// the fetch loop, one entity at a time.
///
/// `createDriveEntityHistoryFromTransactions` is where a drive's metadata is
/// actually read: one HTTP round trip per revision, `maxConcurrentDataFetches`
/// at a time. Everything else a sync publishes stands still until the whole
/// batch is parsed and written, so a hook that fired per batch - or that was
/// accepted and then not passed to the pool - would look exactly like the
/// frozen line this exists to replace.
void main() {
  const driveId = 'drive-id';
  const ownerAddress = 'owner-address';

  late MockConfigService configService;
  late ArweaveService arweave;

  /// A snapshot transaction: an entity the loop finishes with without asking
  /// the gateway for anything. Deliberately - the count is of entities the
  /// batch is done with, so the one that costs no request still has to land,
  /// or a batch holding a snapshot would stop short of its own total.
  DriveEntityHistoryTransactionModel snapshotTransaction(int i) {
    return DriveEntityHistoryTransactionModel(
      transactionCommonMixin:
          DriveEntityHistory$Query$TransactionConnection$TransactionEdge$Transaction
              .fromJson({
        'id': 'tx-$i',
        'owner': {'address': ownerAddress},
        'tags': <dynamic>[
          {'name': EntityTag.entityType, 'value': EntityTypeTag.snapshot},
        ],
        'block': {'height': 100 + i, 'timestamp': i * 100},
      }),
      cursor: 'cursor-$i',
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});

    configService = MockConfigService();
    when(() => configService.config).thenReturn(AppConfig(
      allowedDataItemSizeForTurbo: 0,
      stripePublishableKey: '',
      maxConcurrentDataFetches: 3,
    ));

    arweave = ArweaveService(
      Arweave(api: ArweaveApi(gatewayUrl: Uri.parse('https://example.test'))),
      MockArDriveCrypto(),
      MockDriveDao(),
      configService,
      artemisClient: _MockArtemisClient(),
    );
  });

  test('fires once per entity in the batch', () async {
    var fetched = 0;

    await arweave.createDriveEntityHistoryFromTransactions(
      [for (var i = 0; i < 7; i++) snapshotTransaction(i)],
      null,
      0,
      driveId: driveId,
      ownerAddress: ownerAddress,
      onEntityFetched: () => fetched++,
    );

    expect(fetched, 7);
  });

  test('an empty batch reports nothing at all', () async {
    // The caller adds the batch's size to its total before the fetch starts,
    // so a hook that fired anyway on an empty batch would push the reported
    // count past the total.
    var fetched = 0;

    await arweave.createDriveEntityHistoryFromTransactions(
      const [],
      null,
      0,
      driveId: driveId,
      ownerAddress: ownerAddress,
      onEntityFetched: () => fetched++,
    );

    expect(fetched, 0);
  });

  test('is optional - a caller that wants no count still gets its history',
      () async {
    final history = await arweave.createDriveEntityHistoryFromTransactions(
      [snapshotTransaction(0)],
      null,
      0,
      driveId: driveId,
      ownerAddress: ownerAddress,
    );

    expect(history, isA<DriveEntityHistory>());
  });
}
