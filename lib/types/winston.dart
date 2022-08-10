import 'package:equatable/equatable.dart';

class Winston extends Equatable {
  final BigInt _amount;

  @override
  List<Object?> get props => [_amount];

  Winston(BigInt amount) : _amount = amount {
    if (amount < BigInt.zero || !amount.isValidInt) {
      throw InvalidWinstonValue();
    }
  }

  Winston plus(Winston winston) {
    return Winston(_amount + winston._amount);
  }

  Winston minus(Winston winston) {
    return Winston(_amount - winston._amount);
  }

  Winston times(Winston winston) {
    return Winston(_amount * winston._amount);
  }

  Winston dividedBy(
    Winston winston, {
    RoundStrategy round = RoundStrategy.roundCeil,
  }) {
    double nonRounded = _amount / winston._amount;
    // BigInt.from always rounds down the doubles
    switch (round) {
      case RoundStrategy.roundCeil:
        return Winston(BigInt.from(nonRounded + 1));
      case RoundStrategy.roundDown:
        return Winston(BigInt.from(nonRounded));
      default:
        throw NoSuchRoundStrategy();
    }
  }

  bool isGreaterThan(Winston winston) {
    return _amount > winston._amount;
  }

  bool isLessThan(Winston winston) {
    return _amount < winston._amount;
  }

  @override
  String toString() {
    return '${_amount.toInt()}';
  }

  BigInt get value {
    return _amount;
  }

  static Winston maxWinston(Winston a, Winston b) {
    return a._amount > b._amount ? a : b;
  }
}

enum RoundStrategy {
  roundDown,
  roundCeil,
}

class InvalidWinstonValue implements Exception {
  @override
  String toString() {
    return 'Winston value should be a non-negative integer!';
  }
}

class NoSuchRoundStrategy implements Exception {
  @override
  String toString() {
    return 'No such round strategy!';
  }
}
