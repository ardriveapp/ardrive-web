import 'package:ardrive/pst/constants.dart';
import 'package:ardrive/pst/contract_reader.dart';
import 'package:ardrive/pst/pst_contract_data.dart';
import 'package:ardrive/pst/pst_contract_data_builder.dart';

class ContractOracle<T extends ContractReader> {
  final T _contractReader;

  ContractOracle(T contractReader) : _contractReader = contractReader;

  Future<CommunityContractData> getCommunityContract() async {
    final contractState = await _contractReader.readContract(pstTransactionId);
    final contractDataBuilder = CommunityContractDataBuilder(contractState);
    return contractDataBuilder.parse();
  }

  Future<CommunityTipPercentage> getTipPercentageFromContract() async {
    final contractData = await getCommunityContract();
    return contractData.settings.fee / 100;
  }
}
