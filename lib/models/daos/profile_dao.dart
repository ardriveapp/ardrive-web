import 'dart:convert';

import 'package:ardrive/services/services.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:moor/moor.dart';

import '../models.dart';

part 'profile_dao.g.dart';

const keyByteLength = 256 ~/ 8;

class ProfilePasswordIncorrectException implements Exception {}

@UseDao(tables: [Profiles])
class ProfileDao extends DatabaseAccessor<Database> with _$ProfileDaoMixin {
  ProfileDao(Database db) : super(db);

  SimpleSelectStatement<Profiles, Profile> selectDefaultProfile() =>
      select(profiles);

  /// Loads the default profile with the provided password.
  ///
  /// Throws a [ProfilePasswordIncorrectException] if the provided password is incorrect.
  Future<ProfileLoadDetails> loadDefaultProfile(String password) async {
    final profile = await selectDefaultProfile().getSingle();

    if (profile == null) {
      return null;
    }

    final profileSalt = Nonce(profile.keySalt);
    final profileKdRes = await deriveProfileKey(password, profileSalt);

    try {
      final walletJwk = json.decode(
        utf8.decode(
          await aesGcm.decrypt(
            profile.encryptedWallet,
            secretKey: profileKdRes.key,
            nonce: profileSalt,
          ),
        ),
      );

      return ProfileLoadDetails(
        details: profile,
        wallet: Wallet.fromJwk(walletJwk),
        key: profileKdRes.key,
      );
    } on MacValidationException catch (_) {
      throw ProfilePasswordIncorrectException();
    }
  }

  Future<List<Profile>> getProfiles() => select(profiles).get();

  /// Adds the specified profile and returns a profile key that was used to encrypt the user's wallet
  /// and can be used to encrypt the user's drive keys.
  Future<SecretKey> addProfile(
      String username, String password, Wallet wallet) async {
    final profileKdRes = await deriveProfileKey(password);

    final walletJson = utf8.encode(json.encode(wallet.toJwk()));
    final encryptedWallet = await aesGcm.encrypt(
      walletJson,
      secretKey: profileKdRes.key,
      nonce: Nonce(profileKdRes.salt.bytes),
    );

    await into(profiles).insert(
      ProfilesCompanion.insert(
        id: wallet.address,
        username: username,
        encryptedWallet: encryptedWallet,
        keySalt: profileKdRes.salt.bytes,
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
