import 'package:arweave/arweave.dart';

Future<List<DataItemResult>> createDataItemResultFromDataItemFiles(
  List<DataItemFile> dataItems,
  Wallet wallet,
) async {
  final List<DataItemResult> dataItemList = [];
  final dataItemCount = 2;
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
