part of 'retry_upload_cubit.dart';

@immutable
abstract class RetryUploadState extends Equatable {
  @override
  List<Object> get props => [];
}

class RetryUploadPreparationInProgress extends RetryUploadState {}

class RetryUploadInProgress extends RetryUploadState {}

class RetryUploadFailure extends RetryUploadState {}

class RetryUploadComplete extends RetryUploadState {}
