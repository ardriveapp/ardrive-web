import 'package:ardrive_utils/ardrive_utils.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pst/src/contract_reader.dart';

class ContractReaderStub extends Mock implements ContractReader {
  @override
  Future readContract(TransactionID txId);
}
