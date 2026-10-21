part of 'open_drive_cubit.dart';

/// The states of the "Open a drive" dialog, in the order a reader meets them.
sealed class OpenDriveState extends Equatable {
  const OpenDriveState();

  /// Whether **Open drive** does anything right now.
  bool get canOpen => false;

  @override
  List<Object?> get props => [];
}

/// Nothing typed yet, or text that may still turn into something.
class OpenDriveInitial extends OpenDriveState {
  const OpenDriveInitial();
}

/// Text that is neither a link nor an ID, called out once the field is left.
class OpenDriveUnrecognisedInput extends OpenDriveState {
  const OpenDriveUnrecognisedInput();
}

class OpenDriveLookingUp extends OpenDriveState {
  const OpenDriveLookingUp();
}

class OpenDriveNotFound extends OpenDriveState {
  const OpenDriveNotFound();
}

class OpenDriveNetworkError extends OpenDriveState {
  const OpenDriveNetworkError();
}

/// A public drive, ready to open.
class OpenDrivePublic extends OpenDriveState {
  const OpenDrivePublic({required this.driveId, required this.name});

  final String driveId;
  final String name;

  @override
  bool get canOpen => true;

  @override
  List<Object?> get props => [driveId, name];
}

/// A private drive. Ready to open once [name] is known, which happens when a
/// key has been accepted.
class OpenDrivePrivate extends OpenDriveState {
  const OpenDrivePrivate({
    required this.driveId,
    this.name,
    this.keyRejected = false,
    this.validating = false,
    this.prefilledKey,
  });

  final String driveId;

  /// The drive's name, known only once a key decrypted its entity.
  final String? name;

  /// The last key typed did not open the drive.
  final bool keyRejected;

  /// A key is being checked against the gateway.
  final bool validating;

  /// The key the pasted link carried, to show in the field.
  final String? prefilledKey;

  bool get keyAccepted => name != null;

  @override
  bool get canOpen => keyAccepted;

  OpenDrivePrivate copyWith({
    required String? name,
    required bool keyRejected,
    bool? validating,
  }) =>
      OpenDrivePrivate(
        driveId: driveId,
        name: name,
        keyRejected: keyRejected,
        validating: validating ?? this.validating,
        prefilledKey: prefilledKey,
      );

  @override
  List<Object?> get props =>
      [driveId, name, keyRejected, validating, prefilledKey];
}

/// A link to a file or a transaction rather than a drive. Both have pages a
/// visitor can already see; the button hands the route to the router.
class OpenDriveOtherLink extends OpenDriveState {
  const OpenDriveOtherLink({required this.route, required this.isFile});

  final AppRoutePath route;
  final bool isFile;

  @override
  bool get canOpen => true;

  @override
  List<Object?> get props => [route, isFile];
}

class OpenDriveOpening extends OpenDriveState {
  const OpenDriveOpening();
}

/// The drive row is written. What the router needs to show it.
class OpenDriveOpened extends OpenDriveState {
  const OpenDriveOpened({
    required this.driveId,
    this.folderId,
    this.driveKey,
    this.rawDriveKey,
  });

  final String driveId;
  final String? folderId;
  final DriveKey? driveKey;
  final String? rawDriveKey;

  @override
  List<Object?> get props => [driveId, folderId, rawDriveKey];
}

class OpenDriveFailure extends OpenDriveState {
  const OpenDriveFailure();
}
