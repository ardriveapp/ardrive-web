import 'package:ardrive/pst/pst_contract_data.dart';

abstract class ContractOracle {
  Future<CommunityContractData> getCommunityContract();
  Future<CommunityTipPercentage> getTipPercentageFromContract();
}
