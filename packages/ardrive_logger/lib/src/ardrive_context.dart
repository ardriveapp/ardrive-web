class ArDriveContext {
  ArDriveContext({
    this.userAddress,
    this.numberOfDrives,
    this.numberOfFiles,
    this.numberOfFolders,
  });

  final String? userAddress;

  final int? numberOfDrives;
  final int? numberOfFiles;
  final int? numberOfFolders;

  // TODO: Add more context variables
  // final bool? isArconnect;
  // final bool? isMetamask;

  ArDriveContext copyWith({
    String? userAddress,
    int? numberOfDrives,
    int? numberOfFiles,
    int? numberOfFolders,
  }) {
    return ArDriveContext(
      userAddress: userAddress ?? this.userAddress,
      numberOfDrives: numberOfDrives ?? this.numberOfDrives,
      numberOfFiles: numberOfFiles ?? this.numberOfFiles,
      numberOfFolders: numberOfFolders ?? this.numberOfFolders,
    );
  }

  @override
  String toString() {
    return 'ArDriveContext(userAddress: $userAddress, numberOfDrives: $numberOfDrives, numberOfFiles: $numberOfFiles, numberOfFolders: $numberOfFolders)';
  }
}
