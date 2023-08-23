part of 'pin_file_bloc.dart';

abstract class PinFileEvent extends Equatable {
  const PinFileEvent();
}

class FieldsChanged extends PinFileEvent {
  final String name;
  final String id;

  const FieldsChanged({required this.name, required this.id});

  @override
  List<Object> get props => [name, id];

  @override
  String toString() => 'FiledChanged { name :$name, id :$id }';
}

class PinFileCancel extends PinFileEvent {
  const PinFileCancel();

  @override
  List<Object> get props => [];

  @override
  String toString() => 'PinFileCancel';
}

class PinFileSubmit extends PinFileEvent {
  const PinFileSubmit();

  @override
  List<Object> get props => [];

  @override
  String toString() => 'PinFileSubmitted';
}
