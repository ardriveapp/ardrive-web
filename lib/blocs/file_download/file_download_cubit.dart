import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/arfs/entities/arfs_entities.dart';
import 'package:ardrive/core/arfs/repository/arfs_repository.dart';
import 'package:ardrive/core/decrypt.dart';
import 'package:ardrive/core/download_service.dart';
import 'package:ardrive/entities/entities.dart' as entities;
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/app_platform.dart';
import 'package:ardrive/utils/data_size.dart';
import 'package:ardrive_io/ardrive_io.dart';
import 'package:cryptography/cryptography.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;

import '../../models/daos/drive_dao/drive_dao.dart';

part 'file_download_state.dart';
part 'personal_file_download_cubit.dart';
part 'shared_file_download_cubit.dart';

/// [FileDownloadCubit] is the abstract superclass for [Cubit]s that include
/// logic for download user files.
abstract class FileDownloadCubit extends Cubit<FileDownloadState> {
  FileDownloadCubit(FileDownloadState state) : super(state);

  FutureOr<void> abortDownload() {}
}
