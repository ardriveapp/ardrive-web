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
