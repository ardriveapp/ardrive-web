import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';

Future<List<DataItemResult>> createDataItemResultFromDataItemFiles(
  List<DataItemFile> dataItems,
  Wallet wallet,
) async {
  final List<DataItemResult> dataItemList = [];
  final dataItemCount = dataItems.length;
  for (var i = 0; i < dataItemCount; i++) {
    final dataItem = dataItems[i];
    await createDataItemTaskEither(
      wallet: wallet,
      dataStream: dataItem.streamGenerator,
      dataStreamSize: dataItem.dataSize,
      target: dataItem.target,
      anchor: dataItem.anchor,
      tags: dataItem.tags,
    ).map((dataItem) => dataItemList.add(dataItem)).run();
  }

  return dataItemList;
}

List<Tag> getBundleTags(
  AppInfoServices appInfoServices,
  List<Tag>? customBundleTags,
) {
  return [
    ...appTags(appInfoServices),
    Tag(EntityTag.tipType, 'data upload'),
    if (customBundleTags != null) ...customBundleTags,
  ];
}

List<Tag> appTags(
  AppInfoServices appInfoServices,
) {
  final appInfo = appInfoServices.appInfo;

  final appVersion = Tag(EntityTag.appVersion, appInfo.version);
  final appPlatform = Tag(EntityTag.appPlatform, appInfo.platform);
  final unixTime = Tag(
    EntityTag.unixTime,
    (DateTime.now().millisecondsSinceEpoch ~/ 1000).toString(),
  );
  final appName = Tag(EntityTag.appName, appInfo.appName);

  return [
    appName,
    appPlatform,
    appVersion,
    unixTime,
  ];
}
