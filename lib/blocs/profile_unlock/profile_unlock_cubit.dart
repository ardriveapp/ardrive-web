import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/utils/key_value_store.dart';
import 'package:ardrive/utils/secure_key_value_store.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'profile_unlock_state.dart';

class ProfileUnlockCubit extends Cubit<ProfileUnlockState> {
  final form = FormGroup({
    'password': FormControl(
      validators: [Validators.required],
    ),
  });

  final ProfileCubit _profileCubit;
  final ProfileDao _profileDao;
  final ArweaveService _arweave;
  final BiometricAuthentication _biometricAuthentication;
  late Profile _profile;

  late ProfileType _profileType;
  String? _lastKnownWalletAddress;

  ProfileUnlockCubit(
      {required ProfileCubit profileCubit,
      required ProfileDao profileDao,
      required ArweaveService arweave,
      required BiometricAuthentication biometricAuthentication})
      : _profileCubit = profileCubit,
        _profileDao = profileDao,
        _biometricAuthentication = biometricAuthentication,
        _arweave = arweave,
        super(ProfileUnlockInitializing()) {
    () async {
      _profile = await _profileDao.defaultProfile().getSingle();
      _lastKnownWalletAddress = _profile.id;
      _profileType = _profile.profileType == ProfileType.arConnect.index
          ? ProfileType.arConnect
          : ProfileType.json;
      checkBiometrics();
    }();
  }

  final arconnect = ArConnectService();

  // Validate the user's password by loading and decrypting a private drive.
  Future<void> verifyPasswordArconnect(String password) async {
    final profile = await _profileDao.defaultProfile().getSingle();
    final privateDrive = await _arweave.getAnyPrivateDriveEntity(
        profile.id, password, ArConnectWallet(arconnect));
    if (privateDrive == null) {
      throw ProfilePasswordIncorrectException();
    }
  }

  Future<void> submit() async {
    form.markAllAsTouched();

    if (form.invalid) {
      return;
    }
    await _validateWallet();

    final String password = form.control('password').value;

    await _login(password);
  }

  Future<void> checkBiometrics() async {
    emit(ProfileUnlockInitial(username: _profile.username, autoFocus: false));

    final isEnabled = await _biometricAuthentication.isEnabled();

    if (isEnabled) {
      emit(ProfileUnlockWithBiometrics());
    }
  }

  Future<void> unlockWithStoredPassword(
    BuildContext context, {
    bool needBiometrics = true,
  }) async {
    final KeyValueStore store =
        SecureKeyValueStore(const FlutterSecureStorage());
    try {
      final storedPassword = await store.getString('password');

      if (storedPassword == null) {
        usePasswordLogin();
        return;
      }

      bool authenticated = false;

      if (needBiometrics) {
        authenticated =
            // ignore: use_build_context_synchronously
            await _biometricAuthentication.authenticate(context);
      }

      if (authenticated || !needBiometrics) {
        _login(storedPassword);
      } else {
        usePasswordLogin();
      }
    } catch (e) {
      if (e is BiometricException) {
        emit(ProfileUnlockBiometricFailure(e));
        return;
      }
      emit(ProfileUnlockFailure());
    }
  }

  void usePasswordLogin() {
    emit(
      ProfileUnlockInitial(username: _profile.username, autoFocus: true),
    );
  }

  Future<void> _login(String password) async {
    try {
      //Store profile key so other private entities can be created and loaded
      await _profileDao.loadDefaultProfile(password);

      final isEnabled = await _biometricAuthentication.isEnabled();

      if (isEnabled) {
        final secureStorage = SecureKeyValueStore(const FlutterSecureStorage());

        secureStorage.putString('password', password);
      }
    } on ProfilePasswordIncorrectException catch (_) {
      form
          .control('password')
          .setErrors({AppValidationMessage.passwordIncorrect: true});

      return;
    }

    await _profileCubit.unlockDefaultProfile(password, _profileType);
  }

  Future<void> _validateWallet() async {
    if (_profileType == ProfileType.arConnect &&
        _lastKnownWalletAddress != await arconnect.getWalletAddress()) {
      //Wallet was switched or deleted before login from another tab
      emit(ProfileUnlockFailure());
      return;
    }
  }
}
