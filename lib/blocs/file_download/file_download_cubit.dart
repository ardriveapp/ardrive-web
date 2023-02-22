import 'dart:async';
import 'dart:convert';
import 'dart:developer';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/arfs/repository/arfs_repository.dart';
import 'package:ardrive/core/decrypt.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/app_platform.dart';
import 'package:ardrive/utils/data_size.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:arweave/arweave.dart';
import 'package:async/async.dart';
import 'package:cryptography/cryptography.dart' hide Cipher;
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'file_download_state.dart';
part 'personal_file_download_cubit.dart';
part 'shared_file_download_cubit.dart';

/// [FileDownloadCubit] is the abstract superclass for [Cubit]s that include
/// logic for download user files.
abstract class FileDownloadCubit extends Cubit<FileDownloadState> {
  FileDownloadCubit(FileDownloadState state) : super(state);

  FutureOr<void> abortDownload() {}

  Future<String?> authenticateOwner(
    ArweaveService arweave,
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

        final rawSignature = base64Url.decode(base64Url.normalize(dataTx.signature));
        await dataItem.setSignature(rawSignature);
        
        if (dataItem.id != entityTxId) throw Exception('DataItem txId does not match Entity txId');
        if (!await dataItem.verify()) throw Exception('DataItem signature is invalid');

        // Verified owner
        return owner;
      } catch (e, s) {
        debugPrintStack(stackTrace: s, label: 'Error authenticating DataItem: $e');
        return null;
      }
    } else {
      try {
        final transaction = (await arweave.getTransaction<TransactionStream>(entityTxId))!;
        // Owner claimed by JSON API
        final owner = transaction.owner;

        // Ensure that the data_root matches
        await transaction.processDataStream(authStream, authStreamSize);

        if (transaction.id != entityTxId) throw Exception('Transaction txId does not match Entity txId');
        if (!await transaction.verify()) throw Exception('Transaction signature is invalid');

        // Verified owner
        return owner;
      } catch (e, s) {
        debugPrintStack(stackTrace: s, label: 'Error authenticating Transaction: $e');
        return null;
      }
    }
  }
}
