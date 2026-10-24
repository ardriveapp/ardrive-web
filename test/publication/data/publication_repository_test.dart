import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:flutter_test/flutter_test.dart';

PublishedVersion _v(String tx, String id,
        {int? height, int time = 0, String? folder}) =>
    PublishedVersion(
      txId: tx,
      publicationId: id,
      driveId: 'd',
      folderId: folder,
      publishedAt: DateTime.fromMillisecondsSinceEpoch(time * 1000),
      minedAtHeight: height,
    );

void main() {
  test('versions group by publication, newest first: pending, then height', () {
    final publications = groupPublications([
      _v('a1', 'A', height: 10, time: 1),
      _v('a3', 'A', time: 3),
      _v('a2', 'A', height: 20, time: 2),
      _v('b1', 'B', height: 15, time: 1, folder: 'f'),
    ]);
    expect(publications.map((p) => p.id), ['A', 'B']);
    expect(publications.first.versions.map((v) => v.txId), ['a3', 'a2', 'a1']);
    expect(publications.first.earlier.map((v) => v.txId), ['a2', 'a1']);
    expect(publications.last.folderId, 'f');
  });

  test('a tie in a block goes to the later Unix-Time', () {
    final p = groupPublications([
      _v('x', 'A', height: 10, time: 1),
      _v('y', 'A', height: 10, time: 2),
    ]).single;
    expect(p.latest.txId, 'y');
  });

  test('a version with another scope is not a version of that publication', () {
    final p = groupPublications([
      _v('first', 'A', height: 1),
      _v('moved', 'A', height: 2, folder: 'elsewhere'),
    ]).single;
    expect(p.versions.map((v) => v.txId), ['first']);
  });
}
