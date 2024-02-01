import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:arweave/arweave.dart';
import 'package:pst/src/community_oracle.dart';
import 'package:pst/src/pst.dart';

export 'enums.dart';

class PstService {
  final CommunityOracle _communityOracle;

  PstService({required CommunityOracle communityOracle})
      : _communityOracle = communityOracle;

  /// Returns a randomly selected address for the holder of the app PST weighted by their holdings.
  Future<ArweaveAddress> getWeightedPstHolder() =>
      _communityOracle.selectTokenHolder();

  Future<Winston> getPSTFee(BigInt uploadCost) async {
    return _getPSTFee(uploadCost);
  }

  Future<Winston> _getPSTFee(BigInt uploadCost) async {
    return await _communityOracle
        .getCommunityWinstonTip(Winston(uploadCost))
        .catchError((_) => Winston(BigInt.zero),
            test: (err) => err is UnimplementedError);
  }

  Future<void> addCommunityTipToTx(Transaction tx) async {
    tx.addTag(TipType.tagName, TipType.dataUpload);
    tx.setTarget((await getWeightedPstHolder()).toString());
    tx.setQuantity((await getPSTFee(tx.reward)).value);
  }
}
