import 'package:bloc/bloc.dart';
import 'package:drive/blocs/blocs.dart';
import 'package:drive/models/models.dart';
import 'package:meta/meta.dart';
import 'package:reactive_forms/reactive_forms.dart';

part 'unlock_profile_state.dart';

class UnlockProfileCubit extends Cubit<UnlockProfileState> {
  final form = FormGroup({
    'password': FormControl(
      validators: [Validators.required],
    ),
  });

  final ProfileBloc _profileBloc;
  final ProfileDao _profileDao;

  UnlockProfileCubit({
    @required ProfileBloc profileBloc,
    @required ProfileDao profileDao,
  })  : _profileBloc = profileBloc,
        _profileDao = profileDao,
        super(UnlockProfileInitial());

  void submit() async {
    if (form.valid) {
      final password = form.control('password').value;

      try {
        // Try and load the user's profile to check if they are using the right password.
        await _profileDao.getDefaultProfile(password);
      } catch (_) {
        form.control('password').setErrors({'password-incorrect': true});
        return;
      }

      _profileBloc.add(ProfileLoad(password));
    }
  }
}
