import 'dart:convert';

import 'package:ardrive/core/crypto/crypto.dart';
import 'package:ardrive/entities/profile_types.dart';
import 'package:ardrive/models/models.dart';
import 'package:ardrive/services/arconnect/arconnect.dart';
import 'package:ardrive/services/arconnect/arconnect_wallet.dart';
import 'package:arweave/arweave.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

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
    final profileKdRes =
        await compute<Map<String, dynamic>, ProfileKeyDerivationResult>(
            deriveKey, {
      'password': password,
      'salt': profileSalt,
    });

    //Checks password for both JSON and ArConnect by decrypting stored public key
    String publicKey;

    try {
      publicKey = await compute(decodeAndDecryptWithAeGsm, {
        'data': profile.encryptedPublicKey,
        'nonce': profileSalt,
        'key': profileKdRes.key,
      });
    } on SecretBoxAuthenticationError catch (_) {
      throw ProfilePasswordIncorrectException();
    }
    final parsedProfileType = ProfileType.values[profile.profileType];
    switch (parsedProfileType) {
      case ProfileType.json:
        try {
          //Will only decrypt wallet if it's a JSON Profile
          final walletJwk = json.decode(
            await compute(decodeAndDecryptWithAeGsm, {
              'data': profile.encryptedWallet,
              'nonce': profileSalt,
              'key': profileKdRes.key,
            }),
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
          wallet: ArConnectWallet(ArConnectService()),
          key: profileKdRes.key,
          walletPublicKey: publicKey,
        );
    }
  }

  Future<Profile?> getDefaultProfile() async {
    final profile = await (select(profiles)..limit(1)).getSingleOrNull();
    return profile;
  }

  Future<void> deleteProfile() async {
    final profile = await defaultProfile().getSingle();

    await (delete(profiles)..where((p) => p.id.equals(profile.id))).go();
  }

  /// Adds the specified profile and returns a profile key that was used to encrypt the user's wallet
  /// and can be used to encrypt the user's drive keys.
  Future<SecretKey> addProfile(
    String username,
    String password,
    Wallet wallet,
    ProfileType profileType,
  ) async {
    debugPrint('Adding profile $username with type $profileType');

    final profileKdRes =
        await compute<Map<String, dynamic>, ProfileKeyDerivationResult>(
      deriveKey,
      {'password': password},
    );

    debugPrint('Profile key derivation result: $profileKdRes');

    final profileSalt = profileKdRes.salt;
    final encryptedWallet = await () async {
      switch (profileType) {
        case ProfileType.json:
          final encryptedData =
              await compute<Map<String, dynamic>, SecretBox>(encryptWallet, {
            'wallet': wallet,
            'profileKdRes': profileKdRes,
          });

          return encryptedData.concatenation(nonce: false);
        case ProfileType.arConnect:
          //ArConnect wallet does not contain the jwk
          return Uint8List(0);
      }
    }();

    debugPrint('Encrypted wallet finished');

    final publicKey = await wallet.getOwner();

    debugPrint('Public key finished');

    final encryptedPublicKey =
        await compute<Map<String, dynamic>, SecretBox>(encryptPublicKey, {
      'walletPublicKey': publicKey,
      'profileKdRes': profileKdRes,
    });

    debugPrint('Encrypted public key: $encryptedPublicKey');

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

Future<SecretBox> encryptWallet(
  Map<String, dynamic> args,
) async {
  final wallet = args['wallet'] as Wallet;
  final profileKdRes = args['profileKdRes'] as ProfileKeyDerivationResult;

  final walletJson = utf8.encode(json.encode(wallet.toJwk()));
  return (await aesGcm.encrypt(
    walletJson,
    secretKey: profileKdRes.key,
    nonce: profileKdRes.salt,
  ));
}

Future<SecretBox> encryptPublicKey(
  Map<String, dynamic> args,
) async {
  final walletPublicKey = args['walletPublicKey'] as String;
  final profileKdRes = args['profileKdRes'] as ProfileKeyDerivationResult;

  final publicKey = utf8.encode(walletPublicKey);
  return (await aesGcm.encrypt(
    publicKey,
    secretKey: profileKdRes.key,
    nonce: profileKdRes.salt,
  ));
}

Future<String> decodeAndDecryptWithAeGsm(
  Map<String, dynamic> args,
) async {
  ArDriveCrypto crypto = ArDriveCrypto();

  return utf8.decode(
    await aesGcm.decrypt(
      crypto.secretBoxFromDataWithMacConcatenation(
        args['data'] as Uint8List,
        nonce: args['nonce'] as Uint8List,
      ),
      secretKey: args['key'] as SecretKey,
    ),
  );
}

Future<ProfileKeyDerivationResult> deriveKey(
  Map<String, dynamic> args,
) {
  ArDriveCrypto crypto = ArDriveCrypto();

  return crypto.deriveProfileKey(
      args['password'] as String, args['salt'] as List<int>?);
}
