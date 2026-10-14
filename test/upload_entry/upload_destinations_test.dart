import 'package:ardrive/models/models.dart';
import 'package:ardrive/upload_entry/domain/upload_destinations.dart';
import 'package:flutter_test/flutter_test.dart';

Drive _drive(String id, {bool hidden = false}) => Drive(
      id: id,
      rootFolderId: 'root-$id',
      ownerAddress: 'owner',
      name: id,
      privacy: 'private',
      isHidden: hidden,
      dateCreated: DateTime(2026),
      lastUpdated: DateTime(2026),
    );

List<String> _ids(List<Drive> drives) => drives.map((d) => d.id).toList();

/// Where an upload started away from any drive can go, and in what order.
void main() {
  final photos = _drive('photos');
  final website = _drive('website');
  final archive = _drive('archive');

  test('offers the drive used last first, and the rest in their order', () {
    final destinations = uploadDestinations(
      ownedDrives: [archive, photos, website],
      lastSelectedDriveId: 'website',
    );

    expect(_ids(destinations), ['website', 'archive', 'photos']);
  });

  test('keeps the order when the last-used drive is not among them', () {
    // A drive somebody else owns can be the last one opened; it is not a
    // place this wallet can upload to.
    final destinations = uploadDestinations(
      ownedDrives: [archive, photos],
      lastSelectedDriveId: 'shared-with-me',
    );

    expect(_ids(destinations), ['archive', 'photos']);
  });

  test('leaves hidden drives out', () {
    final destinations = uploadDestinations(
      ownedDrives: [photos, _drive('old', hidden: true)],
    );

    expect(_ids(destinations), ['photos']);
  });

  /// Telling somebody whose every drive is hidden to create one would be
  /// telling them something false.
  test('offers hidden drives when they are all the owner has', () {
    final destinations = uploadDestinations(
      ownedDrives: [_drive('old', hidden: true), _drive('older', hidden: true)],
      lastSelectedDriveId: 'older',
    );

    expect(_ids(destinations), ['older', 'old']);
  });

  test('offers nothing when there is nothing', () {
    expect(uploadDestinations(ownedDrives: const []), isEmpty);
  });

  test('does not change the list it was given', () {
    final owned = [archive, photos, website];

    uploadDestinations(ownedDrives: owned, lastSelectedDriveId: 'website');

    expect(_ids(owned), ['archive', 'photos', 'website']);
  });
}
