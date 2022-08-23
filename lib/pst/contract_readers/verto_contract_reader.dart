import 'dart:convert';

import 'package:ardrive/pst/contract_reader.dart';
import 'package:ardrive/types/transaction_id.dart';
import 'package:http/http.dart' as http;

const cacheUrl = 'v2.cache.verto.exchange';

class VertoContractReader implements ContractReader {
  @override
  Future<dynamic> readContract(TransactionID txId) async {
    final apiUrl = Uri.https(cacheUrl, '$txId');
    final response = await http.get(apiUrl);
    final data = response.body;
    final Map dataAsJson = jsonDecode(data);

    return dataAsJson['state'];
  }
}
