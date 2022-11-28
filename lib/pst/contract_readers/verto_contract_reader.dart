import 'package:ardrive/pst/contract_reader.dart';
import 'package:ardrive/types/transaction_id.dart';
import 'package:ardrive_network/ardrive_network.dart';

const cacheUrl = 'https://v2.cache.verto.exchange';

class VertoContractReader implements ContractReader {
  @override
  Future<dynamic> readContract(TransactionID txId) async {
    final apiUrl = '$cacheUrl/$txId';
    final response = await ArdriveNetwork().getJson(apiUrl);

    return response.data['state'];
  }
}
