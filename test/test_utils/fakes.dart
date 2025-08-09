import 'package:ardrive/blocs/blocs.dart';
import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/entities.dart';
import 'package:ardrive/sync/domain/cubit/sync_cubit.dart';
import 'package:cryptography/cryptography.dart';
import 'package:mocktail/mocktail.dart';

class SyncStateFake extends Fake implements SyncState {}

class ProfileStateFake extends Fake implements ProfileState {}

class DrivesStateFake extends Fake implements DrivesState {}

class FakeDriveEntity extends Fake implements DriveEntity {}

class FakeDriveKey extends Fake implements DriveKey {}

class FakeSecretKey extends Fake implements SecretKey {}
