import 'package:ardrive/core/arfs/repository/file_metadata_repository.dart';
import 'package:ardrive/core/arfs/repository/file_metadata_repository_impl.dart';
import 'package:ardrive/core/arfs/use_cases/bulk_import_files.dart';
import 'package:ardrive/core/arfs/use_cases/get_file_metadata.dart';
import 'package:ardrive/core/arfs/use_cases/insert_file_metadata.dart';
import 'package:ardrive/core/arfs/use_cases/verify_parent_folder.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arweave/arweave_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

List<RepositoryProvider> setupBulkImportDependencies(BuildContext context) {
  return [
    RepositoryProvider<FileMetadataRepository>(
      create: (context) => FileMetadataRepositoryImpl(
        context.read<ArweaveService>(),
      ),
    ),
    RepositoryProvider<GetFileMetadata>(
      create: (context) => GetFileMetadata(
        context.read<FileMetadataRepository>(),
      ),
    ),
    RepositoryProvider<InsertFileMetadata>(
      create: (context) => InsertFileMetadata(
        context.read<DriveDao>(),
      ),
    ),
    RepositoryProvider<VerifyParentFolder>(
      create: (context) => VerifyParentFolder(
        context.read<DriveDao>(),
      ),
    ),
    RepositoryProvider<BulkImportFiles>(
      create: (context) => BulkImportFiles(
        verifyParentFolder: context.read<VerifyParentFolder>(),
        insertFileMetadata: context.read<InsertFileMetadata>(),
        driveDao: context.read<DriveDao>(),
        arweaveService: context.read<ArweaveService>(),
      ),
    ),
  ];
}
