import 'dart:convert';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/profileTypes.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arconnect/arconnect.dart' as arconnect;
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:meta/meta.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'profile_add_state.dart';

class ProfileAddCubit extends Cubit<ProfileAddState> {
  FormGroup form;

  Wallet _wallet;
  ProfileType profileType;
  String walletAddressOnLoad;
  List<TransactionCommonMixin> _driveTxs;

  final ProfileCubit _profileCubit;
  final ProfileDao _profileDao;
  final ArweaveService _arweave;
  ProfileAddCubit({
    @required ProfileCubit profileCubit,
    @required ProfileDao profileDao,
    @required ArweaveService arweave,
    @required BuildContext context,
  })  : _profileCubit = profileCubit,
        _profileDao = profileDao,
        _arweave = arweave,
        super(ProfileAddPromptWallet());

  bool isArconnectInstalled() {
    return arconnect.isExtensionPresent();
  }

  Future<void> promptForWallet() async {
    if (isArconnectInstalled()) {
      await arconnect.disconnect();
    }
    emit(ProfileAddPromptWallet());
  }

  Future<void> pickWallet(String walletJson) async {
    emit(ProfileAddUserStateLoadInProgress());

    _wallet = Wallet.fromJwk(json.decode(walletJson));
    _driveTxs =
        await _arweave.getUniqueUserDriveEntityTxs(await _wallet.getAddress());

    if (_driveTxs.isEmpty) {
      emit(ProfileAddOnboardingNewUser());
    } else {
      emit(ProfileAddPromptDetails(isExistingUser: true));
      setupForm(withPasswordConfirmation: false);
    }
  }

  Future<void> pickWalletFromArconnect() async {
    try {
      emit(ProfileAddUserStateLoadInProgress());
      profileType = ProfileType.ArConnect;

      await arconnect.connect();
      if (!await arconnect.checkPermissions()) {
        emit(ProfileAddFailiure());
        return;
      }

      walletAddressOnLoad = await arconnect.getWalletAddress();

      _driveTxs =
          await _arweave.getUniqueUserDriveEntityTxs(walletAddressOnLoad);

      if (_driveTxs.isEmpty) {
        emit(ProfileAddOnboardingNewUser());
      } else {
        emit(ProfileAddPromptDetails(isExistingUser: true));
        setupForm(withPasswordConfirmation: false);
      }
    } catch (e) {
      emit(ProfileAddFailiure());
    }
  }

  Future<void> completeOnboarding() async {
    emit(ProfileAddPromptDetails(isExistingUser: false));
    setupForm(withPasswordConfirmation: true);
  }

  void setupForm({bool withPasswordConfirmation}) {
    form = FormGroup(
      {
        'username': FormControl(validators: [Validators.required]),
        'password': FormControl(validators: [Validators.required]),
        if (withPasswordConfirmation) 'passwordConfirmation': FormControl(),
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
    form.markAllAsTouched();

    if (form.invalid) {
      return;
    }
    await _profileCubit.checkForWalletMismatch();
    if (profileType == ProfileType.ArConnect &&
        walletAddressOnLoad != await arconnect.getWalletAddress()) {
      //Wallet was switched or deleted before login from another tab
      emit(ProfileAddFailiure());
      return;
    }
    final previousState = state;
    emit(ProfileAddInProgress());

    final username = form.control('username').value.toString().trim();
    final String password = form.control('password').value;

    final privateDriveTxs = _driveTxs.where(
        (tx) => tx.getTag(EntityTag.drivePrivacy) == DrivePrivacy.private);

    // Try and decrypt one of the user's private drive entities to check if they are entering the
    // right password.
    if (privateDriveTxs.isNotEmpty) {
      final checkDriveId = privateDriveTxs.first.getTag(EntityTag.driveId);
      final signature = _wallet != null ? _wallet.sign : arconnect.getSignature;

      final checkDriveKey = await deriveDriveKey(
        signature,
        checkDriveId,
        password,
      );

      final privateDrive = await _arweave.getLatestDriveEntityWithId(
        checkDriveId,
        checkDriveKey,
      );

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
    if (_wallet != null) {
      await _profileDao.addProfile(username, password, _wallet);
    } else {
      final walletAddress = await arconnect.getWalletAddress();
      final walletPublicKey = await arconnect.getPublicKey();
      await _profileDao.addProfileArconnect(
        username,
        password,
        walletAddress,
        walletPublicKey,
      );
    }
    await _profileCubit.unlockDefaultProfile(password, profileType);
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
