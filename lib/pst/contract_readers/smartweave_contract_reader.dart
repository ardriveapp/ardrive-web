import 'package:ardrive/pst/contract_reader.dart';
import 'package:ardrive/services/pst/implementations/pst_web.dart'
    if (dart.library.io) 'package:ardrive/services/pst/implementations/pst_stub.dart'
    as implementation;
import 'package:ardrive/types/transaction_id.dart';

class SmartweaveContractReader extends ContractReader {
  @override
  Future<dynamic> readContract(TransactionID txId) async {
    return implementation.readContract(txId);
  }
}
