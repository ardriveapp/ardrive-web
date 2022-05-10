import 'dart:convert';

import 'package:ardrive/models/models.dart';
import 'package:bloc/bloc.dart';
import 'package:csv/csv.dart';
import 'package:equatable/equatable.dart';
import 'package:file_selector/file_selector.dart';
import 'package:moor/moor.dart';

part 'data_export_state.dart';

class DataExportCubit extends Cubit<DataExportState> {
  final String driveId;
  final DriveDao _driveDao;
  final String _gatewayURL;

  DataExportCubit({
    required this.driveId,
    required DriveDao driveDao,
    required String gatewayURL,
  })  : _driveDao = driveDao,
        _gatewayURL = gatewayURL,
        super(DataExportInitial());

  Future<String> getFilesInDriveAsCSV(String driveId) async {
    final files = await _driveDao
        .filesInDriveWithRevisionTransactions(driveId: driveId)
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
        ..add(file.lastModifiedDate.toString())
        ..add(Uri.parse(_gatewayURL + '/${file.dataTx.id}').toString());
      export.add(fileContent);
    }
    return const ListToCsvConverter().convert(export);
  }

  Future<void> exportData() async {
    emit(const DataExportInProgress());

    final dataBytes =
        utf8.encode((await getFilesInDriveAsCSV(driveId))) as Uint8List;
    emit(DataExportSuccess(
      file: XFile.fromData(
        dataBytes,
        // FIXME: context is not available here. Internationalization cannot be applied
        // name: appLocalizationsOf(context).exportFromCSV(driveId, DateTime.now().toString()),
        name: 'Export from $driveId ${DateTime.now().toString()}.csv',
        mimeType: 'text/csv',
        length: dataBytes.lengthInBytes,
        lastModified: DateTime.now(),
      ),
    ));
  }
}
