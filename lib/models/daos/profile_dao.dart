import 'dart:convert';

import 'package:arweave/arweave.dart';
import 'package:drive/services/services.dart';
import 'package:moor/moor.dart';
import 'package:pointycastle/export.dart';

import '../models.dart';

part 'profile_dao.g.dart';

const keyByteLength = 256 ~/ 8;

@UseDao(tables: [Profiles])
class ProfileDao extends DatabaseAccessor<Database> with _$ProfileDaoMixin {
  ProfileDao(Database db) : super(db);

  Future<List<Profile>> getProfiles() => select(profiles).get();

  /// Adds the specified profile and returns a profile key that was used to encrypt the user's wallet
  /// and can be used to encrypt the user's drive keys.
  Future<CipherKey> addProfile(
      String username, String password, Wallet wallet) async {
    final profileKdRes = await deriveProfileKey(password);

    final encrypter = GCMBlockCipher(AESFastEngine())
      ..init(true,
          AEADParameters(profileKdRes.key, 16 * 8, profileKdRes.salt, null));

    final walletJson = json.encode(wallet.toJwk());
    final encryptedWallet = encrypter.process(utf8.encode(walletJson));

    await into(profiles).insert(
      ProfilesCompanion.insert(
        id: wallet.address,
        username: username,
        encryptedWallet: encryptedWallet,
        keySalt: profileKdRes.salt,
      ),
    );

    return profileKdRes.key;
  }
}
