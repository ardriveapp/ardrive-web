import 'package:equatable/equatable.dart';

class Winston extends Equatable {
  final BigInt _amount;

  @override
  List<Object?> get props => [_amount];

  Winston(BigInt amount) : _amount = amount {
    if (amount < BigInt.zero) {
      throw InvalidWinstonValue();
    }
  }

  operator +(Winston other) {
    return Winston(_amount + other._amount);
  }

  operator -(Winston other) {
    return Winston(_amount - other._amount);
  }

  operator *(Winston other) {
    return Winston(_amount * other._amount);
  }

  operator >(Winston other) {
    return _amount > other._amount;
  }

  operator <(Winston other) {
    return _amount < other._amount;
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

class InvalidWinstonValue extends Equatable implements Exception {
  @override
  String toString() {
    return 'Winston value should be a non-negative integer!';
  }

  @override
  List<Object?> get props => [];
}

class NoSuchRoundStrategy extends Equatable implements Exception {
  @override
  String toString() {
    return 'No such round strategy!';
  }

  @override
  List<Object?> get props => [];
}
