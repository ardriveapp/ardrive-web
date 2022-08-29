import 'package:ardrive/types/transaction_id.dart';

abstract class ContractReader {
  Future<dynamic> readContract(TransactionID txId);
}
