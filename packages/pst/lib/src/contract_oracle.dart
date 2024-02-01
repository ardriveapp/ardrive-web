import 'package:pst/src/constants.dart';
import 'package:pst/src/contract_reader.dart';
import 'package:pst/src/pst_contract_data.dart';
import 'package:pst/src/pst_contract_data_builder.dart';

class ContractOracle<T extends ContractReader> {
  final T _contractReader;

  ContractOracle(T contractReader) : _contractReader = contractReader;

  Future<CommunityContractData> getCommunityContract() async {
    try {
      final contractState =
          await _contractReader.readContract(pstTransactionId);
      final contractDataBuilder = CommunityContractDataBuilder(contractState);
      return contractDataBuilder.build();
    } catch (_) {
      rethrow;
    }
  }

  Future<CommunityTipPercentage> getTipPercentageFromContract() async {
    final contractData = await getCommunityContract();
    return contractData.settings.fee / 100;
  }
}
