part of 'upload_cubit.dart';

@immutable
abstract class UploadState extends Equatable {
  @override
  List<Object> get props => [];
}

class UploadPreparationInProgress extends UploadState {}

class UploadPreparationFailure extends UploadState {}

class UploadFileConflict extends UploadState {
  final List<String> conflictingFileNames;

  UploadFileConflict({@required this.conflictingFileNames});

  @override
  List<Object> get props => [conflictingFileNames];
}

class UploadReady extends UploadState {
  final BigInt uploadCost;
  final bool insufficientArBalance;
  final List<FileUploadHandle> files;

  UploadReady(
      {@required this.uploadCost,
      @required this.insufficientArBalance,
      @required this.files});

  @override
  List<Object> get props => [uploadCost, insufficientArBalance, files];
}

class UploadInProgress extends UploadState {
  final List<FileUploadHandle> files;

  final int _equatableBust = DateTime.now().millisecondsSinceEpoch;

  UploadInProgress({this.files});

  @override
  List<Object> get props => [files, _equatableBust];
}

class UploadFailure extends UploadState {}

class UploadComplete extends UploadState {}
