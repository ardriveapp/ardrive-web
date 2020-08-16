import '../arweave/graphql/graphql_api.dart';

class RawEntity {
  final String id;
  final List<TransactionTagsMixin$Tag> tags;
  final Map<String, dynamic> jsonData;

  RawEntity(this.id, this.tags, this.jsonData);

  String getTag(String tagName) {
    final tag = tags.firstWhere((t) => t.name == tagName, orElse: () => null);
    return tag != null ? tag.value : null;
  }
}
