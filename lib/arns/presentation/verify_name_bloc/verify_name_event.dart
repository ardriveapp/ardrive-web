part of 'verify_name_bloc.dart';

sealed class VerifyNameEvent extends Equatable {
  const VerifyNameEvent();

  @override
  List<Object> get props => [];
}

final class VerifyName extends VerifyNameEvent {
  final String fileId;

  const VerifyName({required this.fileId});

  @override
  List<Object> get props => [fileId];
}
