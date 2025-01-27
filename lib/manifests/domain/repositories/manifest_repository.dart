import 'package:ardrive/manifests/domain/models/manifest_result.dart';

/// Repository interface for fetching manifests from Arweave.
abstract class ManifestRepository {
  /// Fetches a manifest from Arweave using the provided transaction ID.
  /// Returns a [ManifestResult] containing either the manifest data or a failure.
  Future<ManifestResult> getManifest(String transactionId);
}
