part of 'pin_file_bloc.dart';

abstract class PinFileEvent extends Equatable {
  const PinFileEvent();
}

class FiledsChanged extends PinFileEvent {
  final String name;
  final String id;

  const FiledsChanged({required this.name, required this.id});

  @override
  List<Object> get props => [name, id];

  @override
  String toString() => 'FiledChanged { name :$name, id :$id }';
}

class PinFileSubmitted extends PinFileEvent {
  final String name;
  final String id;

  const PinFileSubmitted({required this.name, required this.id});

  @override
  List<Object> get props => [name, id];

  @override
  String toString() => 'PinFileSubmitted { name :$name, id :$id }';
}
