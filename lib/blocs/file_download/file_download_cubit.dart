import 'dart:async';
import 'dart:typed_data';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/constants.dart';
import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/mime_lookup.dart';
import 'package:bloc/bloc.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:http/http.dart' as http;
import 'package:moor/moor.dart';

import '../../entities/file_entity.dart';

part 'file_download_state.dart';
part 'personal_file_download_cubit.dart';
part 'shared_file_download_cubit.dart';

/// [FileDownloadCubit] is the abstract superclass for [Cubit]s that include
/// logic for download user files.
abstract class FileDownloadCubit extends Cubit<FileDownloadState> {
  FileDownloadCubit(FileDownloadState state) : super(state);

  void abortDownload() {}
}
