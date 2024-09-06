import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/services/services.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'profile_add_state.dart';

class ProfileAddCubit extends Cubit<ProfileAddState> {
  ProfileAddCubit({
    required BiometricAuthentication biometricAuthentication,
  }) : super(ProfileAddPromptWallet());

  final arconnect = ArConnectService();

  late FormGroup form;
  late ProfileType _profileType;

  ProfileType getProfileType() => _profileType;

  Future<void> promptForWallet() async {
    if (_profileType == ProfileType.arConnect) {
      await arconnect.disconnect();
    }
    emit(ProfileAddPromptWallet());
  }
}
