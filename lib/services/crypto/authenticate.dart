import 'package:ardrive/services/arweave/graphql/graphql_api.graphql.dart';
import 'package:ardrive/utils/data_size.dart';
import 'package:arweave/arweave.dart';
import 'package:arweave/utils.dart';
import 'package:async/async.dart';
import 'package:flutter/foundation.dart';

import '../arweave/arweave_service.dart';

/// Service for authenticating a transaction
class Authenticate {
  final ArweaveService _arweaveService;

  Authenticate(this._arweaveService);

  /// Authenticate the owner of an entity
  Future<String?> authenticateOwner(
    Stream<Uint8List> authStream,
    int authStreamSize,
    String entityTxId,
    TransactionCommonMixin dataTx,
  ) async {
    final dataTxIsBundled = dataTx.bundledIn != null;
    if (dataTxIsBundled) {
      try {
        // Owner claimed by GraphQL query
        final owner = dataTx.owner.key;

        // No stream support for DataItems, so buffer all the data
        if (authStreamSize > const MiB(500).size) throw Exception('Stream oversized for DataItem');
        final dataItemData = await collectBytes(authStream);

        // Construct DataItem manually from the GraphQL data
        final dataItem = DataItem.withBlobData(
          owner: owner,
          target: dataTx.recipient,
          nonce: dataTx.anchor,
          tags: [],
          data: dataItemData,
        );
        
        // GraphQL returns tags in the correct order so just add them all
        for (final tag in dataTx.tags) {
          dataItem.addTag(tag.name, tag.value);
        }

        await dataItem.setSignature(dataTx.signature);
        
        if (dataItem.id != entityTxId) throw Exception('DataItem txId does not match Entity txId');
        if (!await dataItem.verify()) throw Exception('DataItem signature is invalid');

        // Verified owner
        return await ownerToAddress(dataItem.owner);
      } catch (e, s) {
        debugPrintStack(stackTrace: s, label: 'Error authenticating DataItem: $e');
        return null;
      }
    } else {
      try {
        final transaction = (await _arweaveService.getTransaction<TransactionStream>(entityTxId))!;

        // Ensure that the data_root matches
        await transaction.processDataStream(authStream, authStreamSize);

        if (transaction.id != entityTxId) throw Exception('Transaction txId does not match Entity txId');
        if (!await transaction.verify()) throw Exception('Transaction signature is invalid');

        // Verified owner
        return await ownerToAddress(transaction.owner!);
      } catch (e, s) {
        debugPrintStack(stackTrace: s, label: 'Error authenticating Transaction: $e');
        return null;
      }
    }
  }
}
