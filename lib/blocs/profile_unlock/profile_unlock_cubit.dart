import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/entities/profileTypes.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arconnect/arconnect.dart' as arconnect;
import 'package:ardrive/services/arweave/arweave.dart';
import 'package:ardrive/services/crypto/keys.dart';
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

  List<TransactionCommonMixin> _driveTxs;

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
      final profile = await _profileDao.defaultProfile().getSingle();
      if (profile.profileType == ProfileType.ArConnect.index) {
        //Loads all drive transactions
        _driveTxs =
            await _arweave.getUniqueUserDriveEntityTxs(await profile.id);
        //Filters private drives from drive transactions
        final privateDriveTxs = _driveTxs.where(
            (tx) => tx.getTag(EntityTag.drivePrivacy) == DrivePrivacy.private);
        if (privateDriveTxs.isNotEmpty) {
          //Get a single drive id to test decryption
          final checkDriveId = privateDriveTxs.first.getTag(EntityTag.driveId);
          //Gets a signature with an empty message
          final signature = arconnect.getSignature;
          //Derive drive devryption key from signature, drive id and password
          final checkDriveKey = await deriveDriveKey(
            signature,
            checkDriveId,
            password,
          );

          //Load and decrypt the drive
          final privateDrive = await _arweave.getLatestDriveEntityWithId(
            checkDriveId,
            checkDriveKey,
          );

          // If the private drive could not be decoded, the password is incorrect.
          if (privateDrive == null) {
            form
                .control('password')
                .setErrors({AppValidationMessage.passwordIncorrect: true});

            form
                .control('password')
                .setErrors({AppValidationMessage.passwordIncorrect: true});

            return;
          }
        }
      }
      //Store profile key so other private entities can be created and loaded
      await _profileDao.loadDefaultProfile(password);
    } on ProfilePasswordIncorrectException catch (_) {
      form
          .control('password')
          .setErrors({AppValidationMessage.passwordIncorrect: true});

      return;
    }

    await _profileCubit.unlockDefaultProfile(password, ProfileType.JSON);
  }
}
