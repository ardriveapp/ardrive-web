import 'dart:convert';

import 'package:arweave/arweave.dart';
import 'package:bloc/bloc.dart';
import 'package:drive/blocs/blocs.dart';
import 'package:drive/entities/entities.dart';
import 'package:drive/models/models.dart';
import 'package:drive/services/services.dart';
import 'package:meta/meta.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'add_profile_state.dart';

class AddProfileCubit extends Cubit<AddProfileState> {
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

  AddProfileCubit({
    @required ProfileBloc profileBloc,
    @required ProfileDao profileDao,
    @required ArweaveService arweave,
  })  : _profileBloc = profileBloc,
        _profileDao = profileDao,
        _arweave = arweave,
        super(AddProfilePromptWallet());

  void pickWallet(String walletJson) async {
    _wallet = Wallet.fromJwk(json.decode(walletJson));

    _driveTxs = await _arweave.getUniqueUserDriveEntityTxs(_wallet.address);

    emit(AddProfilePromptDetails(isNewUser: _driveTxs.isEmpty));
  }

  void submit() async {
    final username = form.control('username').value;
    final password = form.control('password').value;

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

        await _arweave.getDriveEntity(checkDriveId, checkDriveKey);
      }
    } catch (err) {
      form.control('password').setErrors({'password-incorrect': true});
      return;
    }

    await _profileDao.addProfile(username, password, _wallet);

    _profileBloc.add(ProfileLoad(password));
  }
}
