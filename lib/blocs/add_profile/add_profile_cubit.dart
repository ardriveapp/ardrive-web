import 'dart:convert';

import 'package:arweave/arweave.dart';
import 'package:bloc/bloc.dart';
import 'package:drive/blocs/blocs.dart';
import 'package:drive/models/models.dart';
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

  Wallet get wallet => _wallet;
  Wallet _wallet;

  final ProfileBloc _profileBloc;
  final ProfileDao _profileDao;

  AddProfileCubit(
      {@required ProfileBloc profileBloc, @required ProfileDao profileDao})
      : _profileBloc = profileBloc,
        _profileDao = profileDao,
        super(AddProfileState.promptWallet);

  void setWallet(String walletJson) {
    _wallet = Wallet.fromJwk(json.decode(walletJson));
    emit(AddProfileState.promptDetails);
  }

  void submit() async {
    final username = form.control('username').value;
    final password = form.control('password').value;

    await _profileDao.addProfile(username, password, wallet);

    _profileBloc.add(ProfileLoad(password));
  }
}
