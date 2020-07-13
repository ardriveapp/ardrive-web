part of 'upload_bloc.dart';

@immutable
abstract class UploadState {}

class UploadInitial extends UploadState {}

class UploadInProgress extends UploadState {}
