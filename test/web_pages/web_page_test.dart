import 'package:ardrive/models/models.dart';
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/publication/domain/publication_config.dart';
import 'package:ardrive/web_pages/domain/web_page.dart';
import 'package:flutter_test/flutter_test.dart';

final _drive = Drive(
  id: 'site',
  rootFolderId: 'site-root',
  ownerAddress: 'owner',
  name: 'Website',
  privacy: 'public',
  isHidden: false,
  dateCreated: DateTime(2026),
  lastUpdated: DateTime(2026),
);

FileEntry _file(String id, String name, {String? contentType}) => FileEntry(
      id: id,
      driveId: _drive.id,
      name: name,
      parentFolderId: _drive.rootFolderId,
      path: '',
      size: 1,
      lastModifiedDate: DateTime(2026),
      dataContentType: contentType,
      dataTxId: '$id-data',
      isHidden: false,
      dateCreated: DateTime(2026),
      lastUpdated: DateTime(2026),
    );

Publication _filePage(String fileId) => Publication([
      PublishedVersion(
        txId: 'p-$fileId-tx',
        publicationId: 'p-$fileId',
        driveId: _drive.id,
        scope: PublicationFileScope(fileId),
        publishedAt: DateTime(2026, 3),
      ),
    ]);

/// A file page's row carries its file's type, for the explorer's icon.
void main() {
  List<WebPage> compose(List<FileEntry> files) => composeWebPages(
        publications: [for (final file in files) _filePage(file.id)],
        deployments: const [],
        drives: {_drive.id: _drive},
        folders: const {},
        files: {for (final file in files) file.id: file},
      );

  test("a file page carries its file's content type", () {
    final pages = compose([
      _file('poster', 'permaman_detailed.png', contentType: 'image/png'),
    ]);

    expect(pages.single.contentType, 'image/png');
  });

  test('an older upload with no content type is typed from its name', () {
    final pages = compose([
      _file('a', 'permaman_detailed.png'),
      _file('b', 'theme.mp3', contentType: ''),
    ]);

    expect(
      {for (final page in pages) page.title: page.contentType},
      {'permaman_detailed.png': 'image/png', 'theme.mp3': 'audio/mpeg'},
    );
  });
}
