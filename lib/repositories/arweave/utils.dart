import 'package:arweave/arweave.dart';
import 'package:drive/repositories/entities/constants.dart';

import 'graphql/graphql_api.dart';

extension TransactionUtils on Transaction {
  void addApplicationTags() {
    addTag(EntityTag.appName, 'drive');
    addTag(EntityTag.appVersion, '0.10.0');
    addTag(
        EntityTag.unixTime, DateTime.now().millisecondsSinceEpoch.toString());
  }

  void addJsonContentTypeTag() {
    addTag(EntityTag.contentType, 'application/json');
  }
}

extension TransactionMixinExtensions on TransactionCommonMixin {
  String getTag(String tagName) =>
      tags.firstWhere((t) => t.name == tagName, orElse: () => null)?.value;

  DateTime getCommitTime() => DateTime.fromMillisecondsSinceEpoch(
      int.parse(getTag(EntityTag.unixTime)));
}
