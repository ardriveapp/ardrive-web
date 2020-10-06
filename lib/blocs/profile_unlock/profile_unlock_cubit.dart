import 'package:bloc/bloc.dart';
import 'package:drive/blocs/blocs.dart';
import 'package:drive/models/models.dart';
import 'package:meta/meta.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'profile_unlock_state.dart';

class ProfileUnlockCubit extends Cubit<ProfileUnlockState> {
  final form = FormGroup({
    'password': FormControl(
      validators: [Validators.required],
    ),
  });

  final ProfileBloc _profileBloc;
  final ProfileDao _profileDao;

  ProfileUnlockCubit({
    @required ProfileBloc profileBloc,
    @required ProfileDao profileDao,
  })  : _profileBloc = profileBloc,
        _profileDao = profileDao,
        super(ProfileUnlockInitial());

  void submit() async {
    if (form.valid) {
      final String password = form.control('password').value;

      try {
        await _profileDao.loadDefaultProfile(password);
      } catch (err) {
        if (err is ProfilePasswordIncorrectException) {
          form.control('password').setErrors({'password-incorrect': true});
          return;
        }

        rethrow;
      }

      _profileBloc.add(ProfileLoad(password));
    }
  }
}
