import 'package:bloc_test/bloc_test.dart';
import 'package:drive/blocs/blocs.dart';
import 'package:drive/models/models.dart';
import 'package:drive/services/services.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group('ProfileAddCubit', () {
    ArweaveService arweave;
    ProfileDao profileDao;
    ProfileBloc profileBloc;
    ProfileAddCubit profileAddCubit;

    setUp(() {
      arweave = MockArweave();
      profileDao = MockProfileDao();
      profileBloc = MockProfileBloc();

      profileAddCubit = ProfileAddCubit(
          profileBloc: profileBloc, profileDao: profileDao, arweave: arweave);
    });

    blocTest<ProfileAddCubit, ProfileAddState>(
      'does not attempt to add a profile when submitted without a valid form',
      build: () => profileAddCubit,
      act: (bloc) {
        bloc.form.value = {'password': ''};
        bloc.submit();
      },
      verify: (_) {
        verifyZeroInteractions(profileDao);
        verifyZeroInteractions(profileBloc);
      },
    );
  });
}
