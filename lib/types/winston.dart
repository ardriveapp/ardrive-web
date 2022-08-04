import 'package:equatable/equatable.dart';

class Winston extends Equatable {
  final int _amount;

  @override
  List<Object?> get props => [_amount];

  Winston(int amount) : _amount = amount {
    if (amount < 0) {
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
    switch (round) {
      case RoundStrategy.roundCeil:
        return Winston(nonRounded.ceil());
      case RoundStrategy.roundDown:
        return Winston(nonRounded.floor());
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
    return '$_amount';
  }

  int get asInteger {
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
