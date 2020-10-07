import 'dart:convert';

import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'profile_add_state.dart';

class ProfileAddCubit extends Cubit<ProfileAddState> {
  final form = FormGroup({
    'username': FormControl(validators: [Validators.required]),
    'password': FormControl(
      validators: [Validators.required],
    ),
  });

  Wallet _wallet;
  List<TransactionCommonMixin> _driveTxs;

  final ProfileBloc _profileBloc;
  final ProfileDao _profileDao;
  final ArweaveService _arweave;

  ProfileAddCubit({
    @required ProfileBloc profileBloc,
    @required ProfileDao profileDao,
    @required ArweaveService arweave,
  })  : _profileBloc = profileBloc,
        _profileDao = profileDao,
        _arweave = arweave,
        super(ProfileAddPromptWallet());

  Future<void> pickWallet(String walletJson) async {
    _wallet = Wallet.fromJwk(json.decode(walletJson));

    _driveTxs = await _arweave.getUniqueUserDriveEntityTxs(_wallet.address);

    emit(ProfileAddPromptDetails(isNewUser: _driveTxs.isEmpty));
  }

  Future<void> submit() async {
    if (form.invalid) {
      return;
    }

    final String username = form.control('username').value;
    final String password = form.control('password').value;

    try {
      final privateDriveTxs = _driveTxs.where(
          (tx) => tx.getTag(EntityTag.drivePrivacy) == DrivePrivacy.private);

      // Try and decrypt one of the user's private drive entities to check if they are entering the
      // right password.
      if (privateDriveTxs.isNotEmpty) {
        final checkDriveId = privateDriveTxs.first.getTag(EntityTag.driveId);

        final checkDriveKey = await deriveDriveKey(
          _wallet,
          checkDriveId,
          password,
        );

        await _arweave.tryGetFirstDriveEntityWithId(
          checkDriveId,
          checkDriveKey,
        );
      }
    } catch (err) {
      if (err is EntityTransactionParseException) {
        form.control('password').setErrors({'password-incorrect': true});
        return;
      }

      rethrow;
    }

    await _profileDao.addProfile(username, password, _wallet);

    _profileBloc.add(ProfileLoad(password));
  }
}
