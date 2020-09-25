part of 'add_profile_bloc.dart';

@immutable
abstract class AddProfileState {}

class AddProfileInitial extends AddProfileState {}

class AddProfileInProgress extends AddProfileState {}

class AddProfileSuccessful extends AddProfileState {}
