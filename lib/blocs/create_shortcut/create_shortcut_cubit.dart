import 'package:ardrive/blocs/create_shortcut/create_shortcut_state.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/main.dart';
import 'package:ardrive/models/daos/daos.dart';
import 'package:ardrive/models/enums.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/graphql_retry.dart';
import 'package:artemis/artemis.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';
import 'package:uuid/uuid.dart';

class CreateShortcutCubit extends Cubit<CreateShortcutState> {
  CreateShortcutCubit({
    required ArweaveService arweaveService,
    required DriveDao driveDao,
    required Arweave arweave,
  })  : _arweave = arweaveService,
        _driveDao = driveDao,
        _client = arweave,
        super(CreateShortcutInitial());

  final ArweaveService _arweave;
  final Arweave _client;
  final DriveDao _driveDao;
  late GetDataTransaction$Query$Transaction _graphQLResult;

  final form = FormGroup(
    {
      'shortcut': FormControl<String>(
        validators: [Validators.required],
        asyncValidatorsDebounceTime: 500,
      ),
      'fileName': FormControl<String>(
        validators: [Validators.required],
        asyncValidatorsDebounceTime: 500,
      ),
    },
  );

  Future<void> isValid() async {
    try {
      if (form.invalid) {
        return;
      }

      emit(CreateShortcutLoading());
      final txId = form.control('shortcut').value;
      final graphQlClient = GraphQLRetry(
          ArtemisClient('${arweave.client.api.gatewayUrl.origin}/graphql'));

      final result = await graphQlClient.execute(GetDataTransactionQuery(
          variables: GetDataTransactionArguments(txId: txId.toString())));

      if (result.data?.transaction == null) {
        emit(CreateShortcutInvalidTransaction());
        return;
      }

      _graphQLResult = result.data!.transaction!;

      print(_graphQLResult.toJson());
      emit(CreateShortcutValidationSuccess());
    } catch (e) {
      emit(CreateShortcutInvalidTransaction());
    }
  }

  Future<void> createShortcut(
    BuildContext context,
    String folderInViewPath,
    String folderId,
    String driveId,
    SecretKey? driveKey,
  ) async {
    try {
      emit(CreateShortcutLoading());

      await _driveDao.transaction(() async {
        const uuid = Uuid();
        final fileName = form.control('fileName').value.toString();
        print(folderInViewPath);

        final file = FileEntry(
          id: uuid.v4(),
          driveId: driveId,
          name: fileName,
          parentFolderId: folderId,
          path: folderInViewPath,
          size: int.parse(_graphQLResult.data.size),
          lastModifiedDate: DateTime.fromMillisecondsSinceEpoch(
            _graphQLResult.block!.timestamp * 1000,
          ),
          dataTxId: _graphQLResult.id,
          dateCreated: DateTime.now(),
          lastUpdated: DateTime.now(),
        );

        final hasConflictingFiles = await checkConflicts(file, driveId);

        if (hasConflictingFiles) {
          throw ConflictingFileException(fileName);
        }

        final user = (context.read<ProfileCubit>().state as ProfileLoggedIn);

        final wallet =
            (context.read<ProfileCubit>().state as ProfileLoggedIn).wallet;

        final driveKey = await _driveDao.getDriveKey(driveId,
            (context.read<ProfileCubit>().state as ProfileLoggedIn).cipherKey);

        final fileKey =
            driveKey != null ? await deriveFileKey(driveKey, file.id) : null;

        final fileEntity = file.asEntity();

        final tx = await fileEntity.asTransaction()
          ..addTag('Data-Owner', _graphQLResult.owner.address);

        final preparedTx = await _client.transactions.prepare(
          tx,
          wallet,
        );

        await preparedTx.sign(wallet);

        await _arweave.postTx(preparedTx);
        await _driveDao.writeToFile(file);

        fileEntity.txId = tx.id;

        await _driveDao.writeFileEntity(
            fileEntity, '${folderInViewPath}/$fileName');
        await _driveDao.insertFileRevision(
          fileEntity.toRevisionCompanion(
            performedAction: RevisionAction.create,
          ),
        );
      });

      emit(CreateShortcutSuccess());
    } catch (e) {
      print(e.toString());
      if (e is ConflictingFileException) {
        emit(CreateShortcutConflicting(e.fileName));
        return;
      }
      emit(CreateShortcutError());
    }
  }

  Future<bool> checkConflicts(FileEntry file, String driveId) async {
    final fileName = file.name;

    final targetDrive = await _driveDao.driveById(driveId: driveId).getSingle();

    final existingFolderName = await _driveDao
        .foldersInFolderWithName(
          driveId: targetDrive.id,
          parentFolderId: file.parentFolderId,
          name: fileName,
        )
        .map((f) => f.name)
        .getSingleOrNull();

    if (existingFolderName != null) {
      return true;
    }

    final existingFileId = await _driveDao
        .filesInFolderWithName(
          driveId: targetDrive.id,
          parentFolderId: file.parentFolderId,
          name: fileName,
        )
        .map((f) => f.id)
        .getSingleOrNull();

    if (existingFileId != null) {
      return true;
    }

    return false;
  }
}

class ConflictingFileException implements Exception {
  final String fileName;

  ConflictingFileException(this.fileName);
}
