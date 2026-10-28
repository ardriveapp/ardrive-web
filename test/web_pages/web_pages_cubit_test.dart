import 'dart:async';

import 'package:ardrive/arns/domain/arns_names.dart';
import 'package:ardrive/blocs/profile/profile_cubit.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/publication/data/publication_repository.dart';
import 'package:ardrive/publication/presentation/publications_cubit.dart';
import 'package:ardrive/web_pages/domain/web_page.dart';
import 'package:ardrive/web_pages/presentation/web_pages_cubit.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../test_utils/fake_user.dart';
import '../test_utils/utils.dart';

class _MockPublicationsCubit extends MockCubit<PublicationsState>
    implements PublicationsCubit {}

const _owner = 'address';

Publication _publication(
  String id, {
  required String driveId,
  String? folderId,
  required DateTime at,
}) =>
    Publication([
      PublishedVersion(
        txId: '$id-tx',
        publicationId: id,
        driveId: driveId,
        folderId: folderId,
        publishedAt: at,
      ),
    ]);

void main() {
  late Database db;
  late MockProfileCubit profileCubit;
  late _MockPublicationsCubit publications;

  Future<void> drive(String id, {String owner = _owner, bool public = true}) =>
      db.into(db.drives).insert(DrivesCompanion.insert(
            id: id,
            name: '$id name',
            ownerAddress: owner,
            rootFolderId: '$id-root',
            privacy: public ? DrivePrivacyTag.public : DrivePrivacyTag.private,
          ));

  Future<void> folder(String id, String driveId, String name) =>
      db.into(db.folderEntries).insert(FolderEntriesCompanion.insert(
            id: id,
            driveId: driveId,
            name: name,
            path: '',
            parentFolderId: Value('$driveId-root'),
          ));

  Future<void> file(
    String id,
    String driveId, {
    String? parent,
    bool manifest = true,
    bool hidden = false,
    required DateTime at,
  }) =>
      db.into(db.fileEntries).insert(FileEntriesCompanion.insert(
            id: id,
            driveId: driveId,
            name: '$id name',
            parentFolderId: parent ?? '$driveId-root',
            path: '',
            size: 1,
            lastModifiedDate: at,
            dataTxId: '$id-data',
            dataContentType:
                Value(manifest ? ContentTypeTag.manifest : 'text/html'),
            isHidden: Value(hidden),
            lastUpdated: Value(at),
          ));

  setUp(() {
    db = getTestDb();
    profileCubit = MockProfileCubit();
    whenListen(
      profileCubit,
      const Stream<ProfileState>.empty(),
      initialState: ProfileLoggedIn(user: fakeUserJson, useTurbo: false),
    );
    publications = _MockPublicationsCubit();
  });

  tearDown(() => db.close());

  Future<WebPagesState> loaded(WebPagesCubit cubit) async {
    if (cubit.state.loaded) return cubit.state;
    return cubit.stream.firstWhere((s) => s.loaded);
  }

  test('publications and deployments in one list, newest first', () async {
    await drive('site');
    await drive('blog');
    await folder('docs', 'site', 'Docs');
    await file('app', 'site', at: DateTime(2026, 3));
    await file('guide', 'site', parent: 'docs', at: DateTime(2026, 1));
    whenListen(
      publications,
      const Stream<PublicationsState>.empty(),
      initialState: PublicationsState({
        'blog': DrivePublications(publications: [
          _publication('p-blog', driveId: 'blog', at: DateTime(2026, 2)),
        ]),
        'site': DrivePublications(publications: [
          _publication('p-docs',
              driveId: 'site', folderId: 'docs', at: DateTime(2026, 4)),
        ]),
      }),
    );

    final cubit = WebPagesCubit(
      driveDao: db.driveDao,
      publicationsCubit: publications,
      profileCubit: profileCubit,
    );
    addTearDown(cubit.close);
    final pages = (await loaded(cubit)).pages;

    expect(pages.map((p) => p.id), ['p-docs', 'app', 'p-blog', 'guide']);

    final docs = pages[0];
    expect(docs.kind, WebPageKind.publication);
    expect(docs.title, 'Docs');
    expect(docs.folderName, 'Docs');
    expect(docs.driveName, 'site name');
    expect(docs.dataTxId, 'p-docs-tx');

    final blog = pages[2];
    expect(blog.title, 'blog name');
    expect(blog.folderName, isNull, reason: 'a whole drive');
    expect(blog.openFolderId, 'blog-root');

    final guide = pages[3];
    expect(guide.kind, WebPageKind.deployment);
    expect(guide.title, 'guide name');
    expect(guide.folderName, 'Docs');
    expect(guide.openFolderId, 'docs');
    expect(guide.dataTxId, 'guide-data');
    expect(pages[1].folderName, isNull, reason: 'at the drive root');
  });

  test('hidden files, other files and private or other drives are left out',
      () async {
    await drive('site');
    await drive('secret', public: false);
    await drive('theirs', owner: 'someone else');
    await file('shown', 'site', at: DateTime(2026, 1));
    await file('hidden', 'site', hidden: true, at: DateTime(2026, 1));
    await file('page.html', 'site', manifest: false, at: DateTime(2026, 1));
    await file('private', 'secret', at: DateTime(2026, 1));
    await file('other', 'theirs', at: DateTime(2026, 1));
    whenListen(
      publications,
      const Stream<PublicationsState>.empty(),
      initialState: PublicationsState({
        // Not on this device yet: no name to show for it.
        'unsynced': DrivePublications(publications: [
          _publication('p-x', driveId: 'unsynced', at: DateTime(2026, 1)),
        ]),
      }),
    );

    final cubit = WebPagesCubit(
      driveDao: db.driveDao,
      publicationsCubit: publications,
      profileCubit: profileCubit,
    );
    addTearDown(cubit.close);

    expect((await loaded(cubit)).pages.map((p) => p.id), ['shown']);
  });

  test('waits for publications before it says what is published', () async {
    await drive('site');
    await file('app', 'site', at: DateTime(2026, 1));
    final reading = StreamController<PublicationsState>();
    addTearDown(reading.close);
    whenListen(
      publications,
      reading.stream,
      initialState: const PublicationsState({}, PublicationsStatus.loading),
    );

    final cubit = WebPagesCubit(
      driveDao: db.driveDao,
      publicationsCubit: publications,
      profileCubit: profileCubit,
    );
    addTearDown(cubit.close);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(cubit.state.loaded, isFalse,
        reason: '"nothing published" would be wrong while reading');

    reading.add(PublicationsState({
      'site': DrivePublications(publications: [
        _publication('p-site', driveId: 'site', at: DateTime(2026, 2)),
      ]),
    }, PublicationsStatus.loaded));
    expect((await loaded(cubit)).pages.map((p) => p.id), ['p-site', 'app']);
  });

  test('says when publications could not be read, and asks again', () async {
    await drive('site');
    await file('app', 'site', at: DateTime(2026, 1));
    whenListen(
      publications,
      const Stream<PublicationsState>.empty(),
      initialState: const PublicationsState({}, PublicationsStatus.failed),
    );
    when(() => publications.retry()).thenAnswer((_) async {});

    final cubit = WebPagesCubit(
      driveDao: db.driveDao,
      publicationsCubit: publications,
      profileCubit: profileCubit,
    );
    addTearDown(cubit.close);
    final state = await loaded(cubit);

    expect(state.failed, isTrue);
    expect(state.pages.map((p) => p.id), ['app'],
        reason: 'deployments are local and still listed');
    await cubit.retry();
    verify(() => publications.retry()).called(1);
  });

  test('nothing while signed out', () async {
    await drive('site');
    await file('app', 'site', at: DateTime(2026, 1));
    whenListen(profileCubit, const Stream<ProfileState>.empty(),
        initialState: ProfileLoggingOut());
    whenListen(publications, const Stream<PublicationsState>.empty(),
        initialState: const PublicationsState());

    final cubit = WebPagesCubit(
      driveDao: db.driveDao,
      publicationsCubit: publications,
      profileCubit: profileCubit,
    );
    addTearDown(cubit.close);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(cubit.state, const WebPagesState());
  });

  group('webPageLinkFor', () {
    final deployment = WebPage(
      kind: WebPageKind.deployment,
      id: 'app',
      title: 'App',
      driveId: 'd',
      driveName: 'Site',
      folderName: null,
      openFolderId: 'd-root',
      dataTxId: 'app-data',
      updatedAt: DateTime(2026),
    );
    final publication = WebPage(
      kind: WebPageKind.publication,
      id: 'pub',
      title: 'Blog',
      driveId: 'd',
      driveName: 'Site',
      folderName: null,
      openFolderId: 'd-root',
      dataTxId: 'pub-tx',
      updatedAt: DateTime(2026),
    );
    ArNSManagedName name(List<ArNSNameRecord> records) => ArNSManagedName(
          name: 'maya',
          processId: 'ant',
          role: ArNSRole.owner,
          type: ArNSNameType.permabuy,
          endTimestamp: null,
          undernameLimit: 10,
          records: records,
        );

    WebPageLink link(WebPage page, List<ArNSManagedName> names) =>
        webPageLinkFor(
          page,
          names: names,
          publicationGatewayUrl: 'https://ardrive.net',
          dataGatewayUrl: 'https://arweave.net',
        );

    test('the gateway links when no name points at the page', () {
      expect(link(deployment, const []).url, 'https://arweave.net/app-data');
      expect(link(deployment, const []).label, 'arweave.net/app-data');
      final long = WebPage(
        kind: WebPageKind.deployment,
        id: 'x',
        title: 'X',
        driveId: 'd',
        driveName: 'Site',
        folderName: null,
        openFolderId: 'd-root',
        dataTxId: 'nS7hxbLQmk3W1o9zX2cV4bN5mL6kJ7hG8fD9sA0qWeQ',
        updatedAt: DateTime(2026),
      );
      expect(link(long, const []).label, 'arweave.net/nS7hxb...qWeQ');
      expect(link(publication, const []).url, 'https://ardrive.net/pub-tx/');
      expect(link(publication, const []).label, 'ardrive.net/pub-tx');
    });

    test("a name's host when one of the user's names points at it", () {
      final names = [
        name(const [
          ArNSNameRecord(
            name: 'maya',
            undername: '@',
            transactionId: 'elsewhere',
            ttlSeconds: 300,
          ),
          ArNSNameRecord(
            name: 'maya',
            undername: 'blog',
            transactionId: 'older-version',
            ttlSeconds: 300,
            target: ArNSPublicationItem(
              publicationId: 'pub',
              driveId: 'd',
              folderId: null,
              isLatestVersion: true,
            ),
          ),
          ArNSNameRecord(
            name: 'maya',
            undername: '@',
            transactionId: 'app-data',
            ttlSeconds: 300,
          ),
        ]),
      ];

      expect(link(publication, names).label, 'blog_maya.ar.io');
      expect(link(publication, names).url, 'https://blog_maya.ar.io');
      expect(link(deployment, names).label, 'maya.ar.io');
    });
  });
}
