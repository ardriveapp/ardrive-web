import 'package:ardrive/models/models.dart';

/// The drives an upload started away from any drive can go to, in the order
/// to offer them.
///
/// [ownedDrives] is the wallet's own drives only. Nobody can add to a drive
/// somebody else owns, and offering one would end at an upload the network
/// refuses.
///
/// Hidden drives are left out, because hiding a drive is asking not to see it.
/// Unless every owned drive is hidden: then they are all the owner has, and
/// telling them to create a drive would be telling them something false.
///
/// The drive used last goes first, the way My Drive is where an upload lands
/// by default elsewhere. The rest keep the order they arrive in, which is the
/// drives cubit's name order.
List<Drive> uploadDestinations({
  required List<Drive> ownedDrives,
  String? lastSelectedDriveId,
}) {
  final visible = ownedDrives.where((drive) => !drive.isHidden).toList();
  final destinations = visible.isNotEmpty ? visible : List.of(ownedDrives);

  final lastUsed =
      destinations.indexWhere((drive) => drive.id == lastSelectedDriveId);

  if (lastUsed > 0) {
    destinations.insert(0, destinations.removeAt(lastUsed));
  }

  return destinations;
}
