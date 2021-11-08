import 'dart:convert';

import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:bloc/bloc.dart';
import 'package:csv/csv.dart';
import 'package:equatable/equatable.dart';
import 'package:file_selector/file_selector.dart';
import 'package:moor/moor.dart';

part 'data_export_state.dart';

class DataExportCubit extends Cubit<DataExportState> {
  final String driveId;
  final DriveDao _driveDao;
  final ArweaveService _arweave;

  DataExportCubit({
    required this.driveId,
    required DriveDao driveDao,
    required ArweaveService arweave,
  })  : _driveDao = driveDao,
        _arweave = arweave,
        super(DataExportStarting()) {
    exportData();
  }

  void exportData() async {
    emit(DataExportInProgress());

    final files = await _driveDao
        .filesInDriveithRevisionTransactions(driveId: driveId)
        .get();
    final export = <List<String>>[
      [
        'File Id',
        'File Name',
        'Parent Folder ID',
        'Data Transaction ID',
        'Metadata Transaction ID',
        'File Size',
        'Date Created',
        'Last Modified',
        'Direct Download Link'
      ]
    ];

    for (var file in files) {
      final fileContent = <String>[];
      fileContent
        ..add(file.id)
        ..add(file.name)
        ..add(file.parentFolderId)
        ..add(file.dataTx.id)
        ..add(file.metadataTx.id)
        ..add(file.size.toString())
        ..add(file.dateCreated.toString())
        ..add(file.lastModifiedDate.toIso8601String())
        ..add(Uri.parse(
                _arweave.client.api.gatewayUrl.origin + '/${file.dataTx.id}')
            .toString());
      export.add(fileContent);
    }
    final csv = const ListToCsvConverter().convert(export);
    final dataBytes = utf8.encode(csv) as Uint8List;
    emit(DataExportSuccess(
      file: XFile.fromData(
        dataBytes,
        name: 'Export from $driveId ${DateTime.now().toString()}.csv',
        mimeType: 'text/csv',
        length: dataBytes.lengthInBytes,
        lastModified: DateTime.now(),
      ),
    ));
  }
}
