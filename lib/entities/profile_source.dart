enum ProfileSourceType {
  standalone,
  ethereumSignature,
}

class ProfileSource {
  final ProfileSourceType type;
  final String? address;

  ProfileSource({
    required this.type,
    this.address,
  });
}
