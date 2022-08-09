import 'package:ardrive/pst/contract_reader.dart';
import 'package:ardrive/types/transaction_id.dart';
import 'package:mocktail/mocktail.dart';

class ContractReaderStub extends Mock implements ContractReader {
  @override
  Future readContract(TransactionID txId);
}
