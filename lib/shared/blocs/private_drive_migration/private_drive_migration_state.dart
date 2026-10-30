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

/// The sign-in password doesn't make this drive's key: its own password is
/// asked for. [wrongPassword] after one that didn't either.
final class PrivateDriveMigrationNeedsPassword
    extends PrivateDriveMigrationState {
  const PrivateDriveMigrationNeedsPassword({
    required this.drive,
    this.wrongPassword = false,
  });

  final Drive drive;
  final bool wrongPassword;

  @override
  List<Object> get props => [drive, wrongPassword];
}
