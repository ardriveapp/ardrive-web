part of 'verify_name_bloc.dart';

sealed class VerifyNameState extends Equatable {
  const VerifyNameState();

  @override
  List<Object?> get props => [];
}

final class VerifyNameInitial extends VerifyNameState {}

final class VerifyNameLoading extends VerifyNameState {}

final class VerifyNameEmpty extends VerifyNameState {}

final class VerifyNameSuccess extends VerifyNameState {
  final ArnsRecord undername;

  const VerifyNameSuccess({required this.undername});

  @override
  List<Object?> get props => [undername];
}

final class VerifyNameFailure extends VerifyNameState {}
