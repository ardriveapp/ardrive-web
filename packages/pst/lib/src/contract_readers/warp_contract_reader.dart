import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:pst/src/contract_reader.dart';
import 'package:pst/src/implementations/pst_web.dart'
    if (dart.library.io) 'package:pst/src/implementations/pst_stub.dart'
    as implementation;

class WarpContractReader implements ContractReader {
  @override
  Future<dynamic> readContract(TransactionID txId) {
    return implementation.readContract(txId);
  }
}
