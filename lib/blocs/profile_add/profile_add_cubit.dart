import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive/services/authentication/biometric_authentication.dart';
import 'package:ardrive/services/services.dart';
import 'package:ardrive/utils/app_platform.dart';
import 'package:ardrive/utils/key_value_store.dart';
import 'package:ardrive/utils/secure_key_value_store.dart';
import 'package:arweave/arweave.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'profile_add_state.dart';

const profileQueryMaxRetries = 6;

class ProfileAddCubit extends Cubit<ProfileAddState> {
  final ProfileCubit _profileCubit;
  final ProfileDao _profileDao;
  final ArweaveService _arweave;
  final BiometricAuthentication _biometricAuthentication;
  ProfileAddCubit(
      {required ProfileCubit profileCubit,
      required ProfileDao profileDao,
      required ArweaveService arweave,
      required BuildContext context,
      required BiometricAuthentication biometricAuthentication})
      : _profileCubit = profileCubit,
        _profileDao = profileDao,
        _biometricAuthentication = biometricAuthentication,
        _arweave = arweave,
        super(ProfileAddPromptWallet());

  final arconnect = ArConnectService();

  late FormGroup form;
  late Wallet _wallet;
  late ProfileType _profileType;
  late List<TransactionCommonMixin> _driveTxs;

  String? _lastKnownWalletAddress;

  bool isArconnectInstalled() {
    return arconnect.isExtensionPresent();
  }

  ProfileType? getProfileType() => _profileType;

  Future<void> promptForWallet() async {
    if (_profileType == ProfileType.arConnect) {
      await arconnect.disconnect();
    }
    emit(ProfileAddPromptWallet());
  }

  Future<void> pickWallet(Wallet wallet) async {
    emit(ProfileAddUserStateLoadInProgress());
    _profileType = ProfileType.json;
    _wallet = wallet;

    try {
      _driveTxs = await _arweave.getUniqueUserDriveEntityTxs(
        await _wallet.getAddress(),
        maxRetries: profileQueryMaxRetries,
      );
    } catch (e) {
      emit(ProfileAddFailure());
      return;
    }

    if (_driveTxs.isEmpty) {
      emit(ProfileAddOnboardingNewUser());
    } else {
      emit(ProfileAddPromptDetails(isExistingUser: true));
      setupForm(withPasswordConfirmation: false);
    }
  }

  Future<void> pickWalletFromArconnect() async {
    try {
      await arconnect.connect();
      emit(ProfileAddUserStateLoadInProgress());
      _profileType = ProfileType.arConnect;

      if (!(await arconnect.checkPermissions())) {
        emit(ProfileAddFailure());
        return;
      }
      _wallet = ArConnectWallet();
      _lastKnownWalletAddress = await _wallet.getAddress();

      try {
        _driveTxs = await _arweave.getUniqueUserDriveEntityTxs(
          _lastKnownWalletAddress!,
          maxRetries: profileQueryMaxRetries,
        );
      } catch (e) {
        emit(ProfileAddFailure());
        return;
      }

      if (_driveTxs.isEmpty) {
        emit(ProfileAddOnboardingNewUser());
      } else {
        emit(ProfileAddPromptDetails(isExistingUser: true));
        setupForm(withPasswordConfirmation: false);
      }
    } catch (e) {
      emit(ProfileAddFailure());
    }
  }

  Future<void> completeOnboarding() async {
    emit(ProfileAddPromptDetails(isExistingUser: false));
    setupForm(withPasswordConfirmation: true);
  }

  void setupForm({required bool withPasswordConfirmation}) {
    form = FormGroup(
      {
        'username': FormControl(validators: [Validators.required]),
        'password': FormControl(validators: [Validators.required]),
        if (withPasswordConfirmation) 'passwordConfirmation': FormControl(),
        if (withPasswordConfirmation)
          'agreementConsent':
              FormControl<bool>(validators: [Validators.requiredTrue]),
      },
      validators: [
        if (withPasswordConfirmation)
          _mustMatch('password', 'passwordConfirmation'),
      ],
    );
  }

  Future<void> submit() async {
    try {
      // form.markAllAsTouched();

      // if (form.invalid) {
      //   return;
      // }

      // Clean up any data from previous sessions
      await _profileCubit.deleteTables();

      if (_profileType == ProfileType.arConnect &&
          (_lastKnownWalletAddress != await arconnect.getWalletAddress() ||
              !(await arconnect.checkPermissions()))) {
        //Wallet was switched or deleted before login from another tab

        emit(ProfileAddFailure());
        return;
      }
      final previousState = state;
      emit(ProfileAddInProgress());

      // final username = form.control('username').value.toString().trim();
      final username = 'thiago';

      // final String password = form.control('password').value;
      final String password = '123';

      final privateDriveTxs = _driveTxs.where(
          (tx) => tx.getTag(EntityTag.drivePrivacy) == DrivePrivacy.private);

      // Try and decrypt one of the user's private drive entities to check if they are entering the
      // right password.
      if (privateDriveTxs.isNotEmpty) {
        final checkDriveId = privateDriveTxs.first.getTag(EntityTag.driveId)!;

        final checkDriveKey = await deriveDriveKey(
          _wallet,
          checkDriveId,
          password,
        );
        DriveEntity? privateDrive;
        try {
          privateDrive = await _arweave.getLatestDriveEntityWithId(
            checkDriveId,
            checkDriveKey,
            profileQueryMaxRetries,
          );
        } catch (e) {
          emit(ProfileAddFailure());
          return;
        }

        // If the private drive could not be decoded, the password is incorrect.
        if (privateDrive == null) {
          form
              .control('password')
              .setErrors({AppValidationMessage.passwordIncorrect: true});

          // Reemit the previous state so form errors can be shown again.
          emit(previousState);

          return;
        }
      }

      await _profileDao.addProfile(username, password, _wallet, _profileType);

      final platform = SystemPlatform.platform;

      if (platform == 'Android' || platform == 'iOS') {
        _savePasswordOnSecureStore(password);
      }

      await _profileCubit.unlockDefaultProfile(password, _profileType);
    } catch (e) {
      await _profileCubit.logoutProfile();
    }
  }

  Future<void> _savePasswordOnSecureStore(String password) async {
    KeyValueStore store = SecureKeyValueStore(const FlutterSecureStorage());

    store.putString('password', password);
  }

  ValidatorFunction _mustMatch(String controlName, String matchingControlName) {
    return (AbstractControl control) {
      final form = control as FormGroup;

      final formControl = form.control(controlName);
      final matchingFormControl = form.control(matchingControlName);

      if (formControl.value != matchingFormControl.value) {
        matchingFormControl.setErrors({'mustMatch': true});

        // Do not mark the matching form control as touched like the default `mustMatch` validator does.
        // matchingFormControl.markAsTouched();
      } else {
        matchingFormControl.setErrors({});
      }

      return null;
    };
  }
}
