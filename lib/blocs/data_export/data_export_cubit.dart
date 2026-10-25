import 'dart:convert';

import 'package:ardrive/core/arfs/repository/folder_repository.dart';
import 'package:ardrive/models/models.dart';
import 'package:csv/csv.dart';
import 'package:drift/drift.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

part 'data_export_state.dart';

const _fileIdColumnName = 'File Id';
const _fileNameColumnName = 'File Name';
const _parentFolderIdColumnName = 'Parent Folder ID';
const _parentFolderNameColumnName = 'Parent Folder Name';
const _dataTransactionIdColumnName = 'Data Transaction ID';
const _metadataTransactionIdColumnName = 'Metadata Transaction ID';
const _fileSizeColumnName = 'File Size';
const _dateCreatedColumnName = 'Date Created';
const _lastModifiedColumnName = 'Last Modified';
const _directDownloadLinkColumnName = 'Direct Download Link';
const _statusColumnName = 'Status';

class DataExportCubit extends Cubit<DataExportState> {
  final String driveId;
  final DriveDao _driveDao;
  final FolderRepository _folderRepository;
  final String _gatewayURL;

  DataExportCubit({
    required this.driveId,
    required DriveDao driveDao,
    required String gatewayURL,
    required FolderRepository folderRepository,
  })  : _driveDao = driveDao,
        _gatewayURL = gatewayURL,
        _folderRepository = folderRepository,
        super(DataExportInitial());

  bool get _isStopped => isClosed || state is DataExportAborted;

  /// The drive's files as CSV rows. Stops early, returning what it has, once
  /// the export is cancelled: a lookup already running finishes, but no other
  /// starts.
  Future<String> getFilesInDriveAsCSV(String driveId) async {
    final files = await _driveDao
        .filesInDriveWithRevisionTransactions(driveId: driveId)
        .get();
    final export = <List<String>>[
      [
        _fileIdColumnName,
        _fileNameColumnName,
        _parentFolderIdColumnName,
        _parentFolderNameColumnName,
        _dataTransactionIdColumnName,
        _metadataTransactionIdColumnName,
        _fileSizeColumnName,
        _dateCreatedColumnName,
        _lastModifiedColumnName,
        _directDownloadLinkColumnName,
        _statusColumnName,
      ]
    ];

    final Map<String, String> folderNames = {};

    for (var file in files) {
      if (_isStopped) break;

      final fileContent = <String>[];

      final parentFolder = await _folderRepository.getLatestFolderRevisionInfo(
          driveId, file.parentFolderId);

      if (parentFolder != null) {
        folderNames[file.parentFolderId] = parentFolder.name;
      }

      fileContent
        ..add(file.id)
        ..add(file.name)
        ..add(file.parentFolderId)
        ..add(folderNames[file.parentFolderId] ?? '')
        ..add(file.dataTx.id)
        ..add(file.metadataTx.id)
        ..add(file.size.toString())
        ..add(file.dateCreated.toString())
        ..add(file.lastModifiedDate.toString())
        ..add(Uri.parse('$_gatewayURL/${file.dataTx.id}').toString())
        ..add(file.dataTx.status.toString());
      export.add(fileContent);
    }
    return const ListToCsvConverter().convert(export);
  }

  Future<void> exportData() async {
    emit(const DataExportInProgress());

    try {
      /// FIXME: context is not available here. Internationalization cannot be applied
      /// name: appLocalizationsOf(context).exportFromCSV(driveId, DateTime.now().toString()),
      final fileName = 'Export from $driveId ${DateTime.now().toString()}.csv';
      final dataBytes = utf8.encode((await getFilesInDriveAsCSV(driveId)));

      // Cancelled while the rows were read: the dialog is gone, and nothing
      // is saved.
      if (_isStopped) return;

      emit(
        DataExportSuccess(
          bytes: dataBytes,
          fileName: fileName,
          mimeType: 'text/csv',
          lastModified: DateTime.now(),
        ),
      );
    } catch (e) {
      if (_isStopped) return;
      emit(DataExportFailure());
    }
  }

  /// Stops the export. A result that arrives afterwards is dropped.
  void abort() {
    if (!isClosed) emit(DataExportAborted());
  }

  /// The file was made but could not be saved, such as a refused download.
  void reportSaveFailure() {
    if (!isClosed) emit(DataExportFailure());
  }
}
