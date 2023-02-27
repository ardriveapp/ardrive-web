import 'dart:convert';

import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';

part 'profile_dao.g.dart';

const keyByteLength = 256 ~/ 8;

class ProfilePasswordIncorrectException implements Exception {}

@DriftAccessor(include: {'../queries/profile_queries.drift'})
class ProfileDao extends DatabaseAccessor<Database> with _$ProfileDaoMixin {
  ProfileDao(Database db) : super(db);

  /// Loads the default profile with the provided password.
  ///
  /// Throws a [ProfilePasswordIncorrectException] if the provided password is incorrect.
  Future<ProfileLoadDetails> loadDefaultProfile(String password) async {
    final profile = await defaultProfile().getSingle();

    final profileSalt = profile.keySalt;
    final profileKdRes = await deriveProfileKey(password, profileSalt);
    //Checks password for both JSON and ArConnect by decrypting stored public key
    String publicKey;
    try {
      publicKey = utf8.decode(
        await aesGcm.decrypt(
          secretBoxFromDataWithGcmMacConcatenation(
            profile.encryptedPublicKey,
            nonce: profileSalt,
          ),
          secretKey: profileKdRes.key,
        ),
      );
    } on SecretBoxAuthenticationError catch (_) {
      throw ProfilePasswordIncorrectException();
    }
    final parsedProfileType = ProfileType.values[profile.profileType];
    switch (parsedProfileType) {
      case ProfileType.json:
        try {
          //Will only decrypt wallet if it's a JSON Profile
          final walletJwk = json.decode(
            utf8.decode(
              await aesGcm.decrypt(
                secretBoxFromDataWithGcmMacConcatenation(
                  profile.encryptedWallet,
                  nonce: profileSalt,
                ),
                secretKey: profileKdRes.key,
              ),
            ),
          );

          //Returning this class doesn't do anything, but it could be useful for debugging
          return ProfileLoadDetails(
            details: profile,
            wallet: Wallet.fromJwk(walletJwk),
            key: profileKdRes.key,
            walletPublicKey: publicKey,
          );
        } on SecretBoxAuthenticationError catch (_) {
          throw ProfilePasswordIncorrectException();
        }
      case ProfileType.arConnect:
        return ProfileLoadDetails(
          details: profile,
          wallet: ArConnectWallet(),
          key: profileKdRes.key,
          walletPublicKey: publicKey,
        );
    }
  }

  /// Adds the specified profile and returns a profile key that was used to encrypt the user's wallet
  /// and can be used to encrypt the user's drive keys.
  Future<SecretKey> addProfile(
    String username,
    String password,
    Wallet wallet,
    ProfileType profileType,
  ) async {
    final profileKdRes = await deriveProfileKey(password);
    final profileSalt = profileKdRes.salt;
    final encryptedWallet = await () async {
      switch (profileType) {
        case ProfileType.json:
          return (await encryptWallet(wallet, profileKdRes))
              .concatenation(nonce: false);
        case ProfileType.arConnect:
          //ArConnect wallet does not contain the jwk
          return Uint8List(0);
      }
    }();
    final publicKey = await wallet.getOwner();
    final encryptedPublicKey = await encryptPublicKey(publicKey, profileKdRes);
    await into(profiles).insert(
      ProfilesCompanion.insert(
        id: await wallet.getAddress(),
        username: username,
        encryptedWallet: encryptedWallet,
        keySalt: profileSalt as Uint8List,
        profileType: profileType.index,
        walletPublicKey: publicKey,
        encryptedPublicKey: encryptedPublicKey.concatenation(nonce: false),
      ),
    );

    return profileKdRes.key;
  }
}

Future<SecretBox> encryptWallet(
  Wallet wallet,
  ProfileKeyDerivationResult profileKdRes,
) async {
  final walletJson = utf8.encode(json.encode(wallet.toJwk()));
  return (await aesGcm.encrypt(
    walletJson,
    secretKey: profileKdRes.key,
    nonce: profileKdRes.salt,
  ));
}

Future<SecretBox> encryptPublicKey(
  String walletPublicKey,
  ProfileKeyDerivationResult profileKdRes,
) async {
  final publicKey = utf8.encode(walletPublicKey);
  return (await aesGcm.encrypt(
    publicKey,
    secretKey: profileKdRes.key,
    nonce: profileKdRes.salt,
  ));
}

class ProfileLoadDetails {
  final Profile details;
  final Wallet wallet;
  final SecretKey key;
  final String walletPublicKey;
  ProfileLoadDetails({
    required this.details,
    required this.wallet,
    required this.key,
    required this.walletPublicKey,
  });
}
