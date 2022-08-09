import 'dart:convert';

import 'package:ardrive/pst/contract_reader.dart';
import 'package:ardrive/types/transaction_id.dart';
import 'package:http/http.dart' as http;

const cacheUrl = 'https://d2440r7x1v6779.cloudfront.net';
const path = 'cache/state';

class RedstoneContractReader extends ContractReader {
  @override
  Future<dynamic> readContract(TransactionID txId) async {
    final apiUrl = Uri.https(cacheUrl, '/$path/$txId');
    final response = await http.post(apiUrl);
    final data = response.body;
    final Map dataAsJson = jsonDecode(data);

    return dataAsJson['state'];
  }
}
