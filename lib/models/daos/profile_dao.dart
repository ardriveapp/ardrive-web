import 'dart:convert';

import 'package:ardrive/entities/profileTypes.dart';
import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:moor/moor.dart';

import '../database/database.dart';

part 'profile_dao.g.dart';

const keyByteLength = 256 ~/ 8;

class ProfilePasswordIncorrectException implements Exception {}

@UseDao(include: {'../queries/profile_queries.moor'})
class ProfileDao extends DatabaseAccessor<Database> with _$ProfileDaoMixin {
  ProfileDao(Database db) : super(db);

  /// Loads the default profile with the provided password.
  ///
  /// Throws a [ProfilePasswordIncorrectException] if the provided password is incorrect.
  Future<ProfileLoadDetails> loadDefaultProfile(String password) async {
    final profile = await defaultProfile().getSingle();

    final profileSalt = profile.keySalt;
    final profileKdRes = await deriveProfileKey(password, profileSalt);
    var walletJwk;
    try {
      //Will only decrypt wallet if it's a JSON Profile
      if (profile.encryptedWallet.isNotEmpty) {
        walletJwk = json.decode(
          utf8.decode(
            await aesGcm.decrypt(
              secretBoxFromDataWithMacConcatenation(
                profile.encryptedWallet,
                nonce: profileSalt,
              ),
              secretKey: profileKdRes.key,
            ),
          ),
        );
      }
      //Checks password for both JSON and ArConnect by decrypting stored public key
      final publicKey = utf8.decode(
        await aesGcm.decrypt(
          secretBoxFromDataWithMacConcatenation(
            profile.encryptedPublicKey,
            nonce: profileSalt,
          ),
          secretKey: profileKdRes.key,
        ),
      );

      //Returning this class doesn't do anything, but it could be useful for debugging
      return ProfileLoadDetails(
        details: profile,
        wallet: profile.encryptedWallet.isNotEmpty
            ? Wallet.fromJwk(walletJwk)
            : null,
        key: profileKdRes.key,
        walletPublicKey: publicKey,
      );
    } on SecretBoxAuthenticationError catch (_) {
      throw ProfilePasswordIncorrectException();
    }
  }

  /// Adds the specified profile and returns a profile key that was used to encrypt the user's wallet
  /// and can be used to encrypt the user's drive keys.
  Future<SecretKey> addProfile(
    String username,
    String password,
    Wallet wallet,
  ) async {
    final profileKdRes = await deriveProfileKey(password);
    final profileSalt = profileKdRes.salt;
    final encryptedWallet = await encryptWallet(wallet, profileKdRes);
    final publicKey = await wallet.getOwner();
    final encryptedPublicKey = await encryptPublicKey(publicKey, profileKdRes);
    await into(profiles).insert(
      ProfilesCompanion.insert(
        id: await wallet.getAddress(),
        username: username,
        encryptedWallet: encryptedWallet.concatenation(nonce: false),
        keySalt: profileSalt,
        profileType: ProfileType.JSON.index,
        walletPublicKey: publicKey,
        encryptedPublicKey: encryptedPublicKey.concatenation(nonce: false),
      ),
    );

    return profileKdRes.key;
  }

  Future<SecretKey> addProfileArconnect(
    String username,
    String password,
    String walletAddress,
    String walletPublicKey,
  ) async {
    final profileKdRes = await deriveProfileKey(password);
    final profileSalt = profileKdRes.salt;
    final encryptedPublicKey =
        await encryptPublicKey(walletPublicKey, profileKdRes);

    await into(profiles).insert(
      ProfilesCompanion.insert(
        id: walletAddress,
        username: username,
        encryptedWallet: Uint8List(0),
        keySalt: profileSalt,
        profileType: ProfileType.ArConnect.index,
        walletPublicKey: walletPublicKey,
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
    this.details,
    this.wallet,
    this.key,
    this.walletPublicKey,
  });
}
