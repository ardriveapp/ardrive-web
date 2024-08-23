part of 'assign_name_bloc.dart';

sealed class AssignNameEvent extends Equatable {
  const AssignNameEvent();

  @override
  List<Object> get props => [];
}

final class LoadNames extends AssignNameEvent {}

final class SelectName extends AssignNameEvent {
  final ARNSRecord name;
  final bool loadUndernames;

  const SelectName(this.name, this.loadUndernames);

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
  final String txId;

  const SelectUndername({
    required this.undername,
    required this.txId,
  });

  @override
  List<Object> get props => [undername];
}

final class ConfirmSelection extends AssignNameEvent {}

final class ReviewSelection extends AssignNameEvent {
  final String txId;

  const ReviewSelection(this.txId);
}
