import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:ario_sdk/ario_sdk.dart';
import 'package:flutter/foundation.dart';
import 'package:pst/pst.dart';
import 'package:pst/src/utils.dart';

class ArDriveContractTokenHolderSelector implements TokenHolderSelector {
  final ArioSDK _arioSDK;

  ArDriveContractTokenHolderSelector(this._arioSDK);

  @override
  Future<ArweaveAddress> selectTokenHolder({double? testingRandom}) async {
    try {
      final holders = await _arioSDK.getAllTokenHolders();

      debugPrint('Holders: $holders');

      final randomHolder =
          weightedRandom(holders, testingRandom: testingRandom);

      if (randomHolder == null) {
        throw CouldNotDetermineTokenHolder();
      }

      debugPrint('Selected token holder: $randomHolder');

      return randomHolder;
    } catch (e) {
      debugPrint('Error selecting token holder: $e');
      throw CouldNotDetermineTokenHolder();
    }
  }
}
