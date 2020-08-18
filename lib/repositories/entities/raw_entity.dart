import '../arweave/graphql/graphql_api.dart';

class RawEntity {
  final String txId;
  final String owner;
  final int blockHeight;
  final List<TransactionTagsMixin$Tag> tags;
  final Map<String, dynamic> jsonData;

  RawEntity(
      {this.txId, this.owner, this.blockHeight, this.tags, this.jsonData});

  String getTag(String tagName) {
    final tag = tags.firstWhere((t) => t.name == tagName, orElse: () => null);
    return tag != null ? tag.value : null;
  }
}
