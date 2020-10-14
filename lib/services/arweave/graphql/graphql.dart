import 'package:ardrive/entities/entities.dart';

import 'graphql_api.dart';

export 'graphql_api.dart';

extension TransactionMixinExtensions on TransactionCommonMixin {
  String getTag(String tagName) =>
      tags.firstWhere((t) => t.name == tagName, orElse: () => null)?.value;

  DateTime getCommitTime() => DateTime.fromMillisecondsSinceEpoch(
      int.parse(getTag(EntityTag.unixTime)));
}
