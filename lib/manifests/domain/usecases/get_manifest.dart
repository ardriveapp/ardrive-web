import 'package:ardrive/manifests/domain/models/manifest_result.dart';
import 'package:ardrive/manifests/domain/repositories/manifest_repository.dart';

class GetManifest {
  final ManifestRepository repository;

  GetManifest(this.repository);

  Future<ManifestResult> call(String transactionId) {
    return repository.getManifest(transactionId);
  }
}
