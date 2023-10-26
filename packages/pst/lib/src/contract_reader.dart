import 'package:ardrive_utils/ardrive_utils.dart';

abstract class ContractReader {
  Future<dynamic> readContract(TransactionID txId);
}
