import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/l11n/validation_messages.dart';
import 'package:ardrive/models/models.dart';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:meta/meta.dart';
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

  ProfileUnlockCubit({
    @required ProfileCubit profileCubit,
    @required ProfileDao profileDao,
  })  : _profileCubit = profileCubit,
        _profileDao = profileDao,
        super(ProfileUnlockInitializing()) {
    () async {
      final existingUsername = await _profileDao
          .selectDefaultProfile()
          .map((p) => p.username)
          .getSingle();
      emit(ProfileUnlockInitial(username: existingUsername));
    }();
  }

  Future<void> submit() async {
    form.markAllAsTouched();

    if (form.invalid) {
      return;
    }

    final String password = form.control('password').value;

    try {
      await _profileDao.loadDefaultProfile(password);
    } catch (err) {
      if (err is ProfilePasswordIncorrectException) {
        form
            .control('password')
            .setErrors({AppValidationMessage.passwordIncorrect: true});
        return;
      }

      rethrow;
    }

    await _profileCubit.unlockDefaultProfile(password);
  }
}
