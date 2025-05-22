part of 'private_drive_migration_bloc.dart';

sealed class PrivateDriveMigrationState extends Equatable {
  const PrivateDriveMigrationState();

  @override
  List<Object> get props => [];
}

final class PrivateDriveMigrationVisible extends PrivateDriveMigrationState {}

final class PrivateDriveMigrationHidden extends PrivateDriveMigrationState {}

final class PrivateDriveMigrationComplete extends PrivateDriveMigrationState {}

final class PrivateDriveMigrationInProgress extends PrivateDriveMigrationState {
  final Drive inProgressDrive;

  const PrivateDriveMigrationInProgress({
    required this.inProgressDrive,
  });

  @override
  List<Object> get props => [
        inProgressDrive,
      ];
}

final class PrivateDriveMigrationFailed extends PrivateDriveMigrationState {
  final String error;

  const PrivateDriveMigrationFailed({required this.error});

  @override
  List<Object> get props => [error];
}
