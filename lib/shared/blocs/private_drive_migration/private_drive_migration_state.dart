part of 'private_drive_migration_bloc.dart';

sealed class PrivateDriveMigrationState extends Equatable {
  const PrivateDriveMigrationState();

  @override
  List<Object> get props => [];
}

final class PrivateDriveMigrationVisible extends PrivateDriveMigrationState {}

final class PrivateDriveMigrationHidden extends PrivateDriveMigrationState {}

final class PrivateDriveMigrationInProgress extends PrivateDriveMigrationState {
  final List<Drive> drivesRequiringMigration;
  final Set<Drive> completed;

  const PrivateDriveMigrationInProgress({
    required this.drivesRequiringMigration,
    required this.completed,
  });

  @override
  List<Object> get props => [
        drivesRequiringMigration,
        completed,
      ];
}

final class PrivateDriveMigrationFailed extends PrivateDriveMigrationState {
  final String error;

  const PrivateDriveMigrationFailed({required this.error});

  @override
  List<Object> get props => [error];
}
