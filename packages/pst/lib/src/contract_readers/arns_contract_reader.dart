import 'package:ardrive_http/ardrive_http.dart';
import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:pst/pst.dart';
import 'package:pst/src/constants.dart';

class ARNSContractReader implements ContractReader {
  @override
  Future<dynamic> readContract(TransactionID txId) async {
    final apiUrl = '$arnsCacheUrl/$txId';
    final response = await ArDriveHTTP().getJson(apiUrl);

    return response.data['state'];
  }
}
