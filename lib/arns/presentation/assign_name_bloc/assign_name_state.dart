part of 'assign_name_bloc.dart';

sealed class AssignNameState extends Equatable {
  const AssignNameState();

  @override
  List<Object?> get props => [];
}

final class AssignNameInitial extends AssignNameState {}

final class LoadingNames extends AssignNameState {}

final class NamesLoaded extends AssignNameState {
  final List<ANTRecord> names;
  final ANTRecord? selectedName;

  const NamesLoaded({required this.names, this.selectedName});

  @override
  List<Object?> get props => [names, selectedName];

  NamesLoaded copyWith({
    List<ANTRecord>? names,
    ANTRecord? selectedName,
  }) {
    return NamesLoaded(
      names: names ?? this.names,
      selectedName: selectedName ?? this.selectedName,
    );
  }
}

final class AssignNameEmptyState extends AssignNameState {}

final class UndernamesLoaded extends AssignNameState {
  final List<ANTRecord> names;
  final ANTRecord selectedName;
  final List<ARNSUndername> undernames;
  final ARNSUndername? selectedUndername;

  const UndernamesLoaded({
    required this.names,
    required this.undernames,
    required this.selectedUndername,
    required this.selectedName,
  });

  @override
  List<Object?> get props => [
        names,
        selectedName,
        undernames,
        selectedUndername,
      ];

  UndernamesLoaded copyWith({
    List<ANTRecord>? names,
    ANTRecord? selectedName,
    List<ARNSUndername>? undernames,
    ARNSUndername? selectedUndername,
  }) {
    return UndernamesLoaded(
      names: names ?? this.names,
      selectedName: selectedName ?? this.selectedName,
      undernames: undernames ?? this.undernames,
      selectedUndername: selectedUndername ?? this.selectedUndername,
    );
  }
}

final class ConfirmingSelection extends AssignNameState {}

final class NameAssignedWithSuccess extends AssignNameState {
  final String address;
  final String arAddress;

  const NameAssignedWithSuccess(
      {required this.address, required this.arAddress});
}

final class SelectionConfirmed extends AssignNameState {
  final ANTRecord selectedName;
  final ARNSUndername? selectedUndername;

  const SelectionConfirmed({
    required this.selectedName,
    this.selectedUndername,
  });
}

final class LoadingUndernames extends AssignNameState {}

class SelectionFailed extends AssignNameState {}

final class EmptySelection extends AssignNameState {}
