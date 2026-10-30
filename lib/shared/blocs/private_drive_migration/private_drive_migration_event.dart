part of 'private_drive_migration_bloc.dart';

sealed class PrivateDriveMigrationEvent extends Equatable {
  const PrivateDriveMigrationEvent();

  @override
  List<Object> get props => [];
}

final class PrivateDriveMigrationStartEvent extends PrivateDriveMigrationEvent {
  const PrivateDriveMigrationStartEvent();
}

final class PrivateDriveMigrationCloseEvent extends PrivateDriveMigrationEvent {
  const PrivateDriveMigrationCloseEvent();
}

final class PrivateDriveMigrationCheck extends PrivateDriveMigrationEvent {
  const PrivateDriveMigrationCheck();
}

/// The drive's own password, asked for by [PrivateDriveMigrationNeedsPassword],
/// or null to skip that drive.
final class PrivateDriveMigrationPasswordEntered
    extends PrivateDriveMigrationEvent {
  const PrivateDriveMigrationPasswordEntered(this.password);

  final String? password;

  @override
  List<Object> get props => [password ?? ''];
}
