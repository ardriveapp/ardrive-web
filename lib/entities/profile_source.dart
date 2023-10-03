import 'package:equatable/equatable.dart';

enum ProfileSourceType {
  standalone,
  ethereumSignature,
}

class ProfileSource extends Equatable {
  final ProfileSourceType type;
  final String? address;

  const ProfileSource({
    required this.type,
    this.address,
  });

  @override
  List<Object?> get props => [type, address];
}
