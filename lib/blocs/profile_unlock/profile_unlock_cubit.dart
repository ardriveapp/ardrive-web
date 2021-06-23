import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/profileTypes.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arconnect/arconnect.dart' as arconnect;
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
import 'package:moor/moor.dart';
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

  ProfileType profileType;
  String walletAddressOnLoad;

  ProfileUnlockCubit({
    @required ProfileCubit profileCubit,
    @required ProfileDao profileDao,
    @required ArweaveService arweave,
  })  : _profileCubit = profileCubit,
        _profileDao = profileDao,
        _arweave = arweave,
        super(ProfileUnlockInitializing()) {
    () async {
      final profile = await _profileDao.defaultProfile().getSingle();
      walletAddressOnLoad = profile.id;
      profileType = profile.profileType == ProfileType.ArConnect.index
          ? ProfileType.ArConnect
          : ProfileType.JSON;
      emit(ProfileUnlockInitial(username: profile.username));
    }();
  }
  // Validate the user's password by loading and decrypting a private drive.
  Future<void> verifyPasswordArconnect(String password) async {
    final profile = await _profileDao.defaultProfile().getSingle();

    // Nothing to do if the wallet is not ArConnect
    if (profile.profileType != ProfileType.ArConnect.index) {
      return;
    }

    final signature = arconnect.getSignature;
    final privateDrive = await _arweave.getAnyPrivateDriveEntity(await profile.id, password, signature);
    if (privateDrive == null) {
      throw ProfilePasswordIncorrectException();
    }
  }

  Future<void> submit() async {
    form.markAllAsTouched();

    if (form.invalid) {
      return;
    }

    if (profileType == ProfileType.ArConnect &&
        walletAddressOnLoad != await arconnect.getWalletAddress()) {
      //Wallet was switched or deleted before login from another tab
      emit(ProfileUnlockFailure());
      return;
    }
    final String password = form.control('password').value;

    try {
      if (profileType == ProfileType.ArConnect) {
        await verifyPasswordArconnect(password);
      }
      //Store profile key so other private entities can be created and loaded
      await _profileDao.loadDefaultProfile(password);
      await _profileCubit.unlockDefaultProfile(password, ProfileType.JSON);
    } on ProfilePasswordIncorrectException catch (_) {
      form
          .control('password')
          .setErrors({AppValidationMessage.passwordIncorrect: true});

      return;
    }
  }
}
