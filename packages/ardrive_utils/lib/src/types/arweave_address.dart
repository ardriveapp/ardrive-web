import 'package:equatable/equatable.dart';

RegExp addressRegExp = RegExp('^[a-zA-Z0-9_-]{43}\$');

typedef ArweaveAddressType = ArweaveAddress;

class ArweaveAddress extends Equatable {
  final String _addr;

  ArweaveAddress(String addr) : _addr = addr {
    if (!addressRegExp.hasMatch(addr)) {
      throw InvalidAddress();
    }
  }

  @override
  List<Object?> get props => [_addr];

  @override
  String toString() {
    return _addr;
  }

  static bool isValid(String addr) {
    return addressRegExp.hasMatch(addr);
  }
}

class InvalidAddress implements Exception {
  @override
  String toString() {
    return 'Arweave addresses must be 43 characters in length with characters in the following set: [a-zA-Z0-9_-]';
  }
}
