import 'dart:convert';

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

    try {
      final walletJwk = json.decode(
        utf8.decode(
          await aesGcm.decrypt(
            SecretBox(profile.encryptedWallet, nonce: profileSalt),
            secretKey: profileKdRes.key,
          ),
        ),
      );

      return ProfileLoadDetails(
        details: profile,
        wallet: Wallet.fromJwk(walletJwk),
        key: profileKdRes.key,
      );
    } on SecretBoxAuthenticationError catch (_) {
      throw ProfilePasswordIncorrectException();
    }
  }

  /// Adds the specified profile and returns a profile key that was used to encrypt the user's wallet
  /// and can be used to encrypt the user's drive keys.
  Future<SecretKey> addProfile(
      String username, String password, Wallet wallet) async {
    final profileKdRes = await deriveProfileKey(password);
    final profileSalt = profileKdRes.salt.bytes;

    final walletJson = utf8.encode(json.encode(wallet.toJwk()));
    final encryptedWallet = await aesGcm.encrypt(
      walletJson,
      secretKey: profileKdRes.key,
      nonce: profileSalt,
    );

    await into(profiles).insert(
      ProfilesCompanion.insert(
        id: await wallet.getAddress(),
        username: username,
        encryptedWallet: encryptedWallet.concatenation(nonce: false),
        keySalt: profileSalt,
      ),
    );

    return profileKdRes.key;
  }
}

class ProfileLoadDetails {
  final Profile details;
  final Wallet wallet;
  final SecretKey key;

  ProfileLoadDetails({this.details, this.wallet, this.key});
}
