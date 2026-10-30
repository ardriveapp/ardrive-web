import 'package:ardrive/manifests/data/repositories/manifest_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../test_utils/mocks.dart';

/// An error with no toString of its own: in a release build its text is
/// "Instance of 'minified:Xy'".
class _Opaque implements Exception {}

/// The failure's message is what the import dialog shows, so it never carries
/// an exception's text; the log does.
void main() {
  test('a manifest that cannot be fetched says so in words', () async {
    final arweave = MockArweaveService();
    when(() => arweave.getInfoOfTxToBePinned(any())).thenThrow(_Opaque());
    final repository = ManifestRepositoryImpl(arweave, MockDownloadService());

    final result = await repository.getManifest('tx');

    expect(result.failure, isNotNull);
    expect(result.failure!.message, isNot(contains('Instance of')));
    expect(
      result.failure!.message,
      'The manifest could not be fetched. Check your connection and try '
      'again.',
    );
  });
}
