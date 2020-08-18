import 'package:arweave/arweave.dart';
import 'package:drive/repositories/entities/constants.dart';

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
