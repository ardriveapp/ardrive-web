import 'package:ardrive/entities/string_types.dart';
import 'package:ardrive/types/winston.dart';

abstract class CommunityOracle {
  Future<Winston> getCommunityWinstonTip(Winston winstonCost);
  Future<ArweaveAddress> selectTokenHolder();
}
