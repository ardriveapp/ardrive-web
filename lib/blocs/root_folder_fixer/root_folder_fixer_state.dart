part of 'root_folder_fixer_cubit.dart';

@immutable
abstract class RootFolderFixerState extends Equatable {
  @override
  List<Object> get props => [];
}

class RootFolderFixerInitial extends RootFolderFixerState {}

class RootFolderFixerInProgress extends RootFolderFixerState {}

class RootFolderFixerSuccess extends RootFolderFixerState {}

class RootFolderFixerFailure extends RootFolderFixerState {}

class RootFolderFixerWalletMismatch extends RootFolderFixerState {}
