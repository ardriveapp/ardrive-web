part of 'assign_name_bloc.dart';

sealed class AssignNameEvent extends Equatable {
  const AssignNameEvent();

  @override
  List<Object> get props => [];
}

final class LoadNames extends AssignNameEvent {
  final bool updateARNSRecords;

  const LoadNames({
    this.updateARNSRecords = true,
  });
}

final class SelectName extends AssignNameEvent {
  final ANTRecord name;

  const SelectName(this.name);

  @override
  List<Object> get props => [name];
}

final class LoadUndernames extends AssignNameEvent {
  const LoadUndernames();

  @override
  List<Object> get props => [];
}

final class SelectUndername extends AssignNameEvent {
  final ARNSUndername undername;

  const SelectUndername({
    required this.undername,
  });

  @override
  List<Object> get props => [undername];
}

final class ConfirmSelectionAndUpload extends AssignNameEvent {}

final class ConfirmSelection extends AssignNameEvent {}
