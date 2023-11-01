import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:pst/src/constants.dart';
import 'package:pst/src/contract_reader.dart';

class VertoContractReader implements ContractReader {
  @override
  Future<dynamic> readContract(TransactionID txId) async {
    final apiUrl = '$vertoCacheUrl/$txId';
    final response = await ArDriveHTTP().getJson(apiUrl);

    return response.data['state'];
  }
}
