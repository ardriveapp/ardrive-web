import 'package:bloc_test/bloc_test.dart';
import 'package:drive/blocs/blocs.dart';
import 'package:drive/models/models.dart';
import 'package:drive/services/services.dart';
import 'package:mockito/mockito.dart';

class MockArweave extends Mock implements ArweaveService {}

class MockProfileDao extends Mock implements ProfileDao {}

class MockDrivesDao extends Mock implements DrivesDao {}

class MockSyncBloc extends MockBloc<SyncState> implements SyncBloc {}

class MockDrivesBloc extends MockBloc<DrivesState> implements DrivesBloc {}

class MockProfileBloc extends MockBloc<ProfileState> implements ProfileBloc {}
