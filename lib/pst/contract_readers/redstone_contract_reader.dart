import 'package:ardrive/pst/contract_reader.dart';
import 'package:ardrive/types/transaction_id.dart';
import 'package:ardrive_http/ardrive_http.dart';

const cacheUrl = 'https://d2440r7x1v6779.cloudfront.net/cache/state';

class RedstoneContractReader implements ContractReader {
  @override
  Future<dynamic> readContract(TransactionID txId) async {
    final apiUrl = '$cacheUrl/$txId';
    final response = await ArDriveHTTP().getJson(apiUrl);

    return response.data['state'];
  }
}
