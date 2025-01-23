part of 'assign_name_bloc.dart';

sealed class AssignNameState extends Equatable {
  const AssignNameState();

  @override
  List<Object?> get props => [];
}

final class AssignNameInitial extends AssignNameState {}

final class LoadingNames extends AssignNameState {}

final class NamesLoaded extends AssignNameState {
  final List<ArNSNameModel> nameModels;
  final ArNSNameModel? selectedName;

  const NamesLoaded({required this.nameModels, this.selectedName});

  @override
  List<Object?> get props => [nameModels, selectedName];

  NamesLoaded copyWith({
    List<ArNSNameModel>? nameModels,
    ArNSNameModel? selectedName,
  }) {
    return NamesLoaded(
      nameModels: nameModels ?? this.nameModels,
      selectedName: selectedName ?? this.selectedName,
    );
  }
}

final class AssignNameEmptyState extends AssignNameState {}

final class UndernamesLoaded extends AssignNameState {
  final List<ArNSNameModel> nameModels;
  final List<ARNSUndername> undernames;
  final ARNSUndername? selectedUndername;
  final ArNSNameModel? selectedName;

  const UndernamesLoaded({
    required this.nameModels,
    required this.undernames,
    required this.selectedUndername,
    required this.selectedName,
  });

  @override
  List<Object?> get props => [
        nameModels,
        selectedName,
        undernames,
        selectedUndername,
      ];

  UndernamesLoaded copyWith({
    List<ARNSUndername>? undernames,
    ARNSUndername? selectedUndername,
    List<ArNSNameModel>? nameModels,
    ArNSNameModel? selectedName,
  }) {
    return UndernamesLoaded(
      nameModels: nameModels ?? this.nameModels,
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
  final ArNSNameModel selectedName;
  final ARNSUndername? selectedUndername;

  const SelectionConfirmed({
    required this.selectedName,
    this.selectedUndername,
  });
}

final class LoadingUndernames extends AssignNameState {}

class SelectionFailed extends AssignNameState {}

final class LoadingNamesFailed extends AssignNameState {}

final class EmptySelection extends AssignNameState {}
