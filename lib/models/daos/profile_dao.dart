import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:arweave/arweave.dart';
import 'package:moor/moor.dart';
import 'package:pointycastle/export.dart';

import '../models.dart';

part 'profile_dao.g.dart';

const keyByteLength = 256 ~/ 8;

@UseDao(tables: [Profiles])
class ProfileDao extends DatabaseAccessor<Database> with _$ProfileDaoMixin {
  ProfileDao(Database db) : super(db);

  Future<List<Profile>> getProfiles() => select(profiles).get();

  Future<void> addProfile(
      String username, String password, Wallet wallet) async {
    final random = Random.secure();
    final salt =
        Uint8List.fromList(List.generate(128 ~/ 8, (_) => random.nextInt(256)));

    final kdf = PBKDF2KeyDerivator(HMac.withDigest(SHA256Digest()))
      ..init(Pbkdf2Parameters(salt, 20000, 256));

    final keyOutput = Uint8List(keyByteLength);
    kdf.deriveKey(utf8.encode(password), 0, keyOutput, 0);

    final walletKey = KeyParameter(keyOutput);

    final encrypter = GCMBlockCipher(AESFastEngine())
      ..init(true, AEADParameters(walletKey, 16 * 8, salt, null));

    final walletJson = json.encode(wallet.toJwk());
    final encryptedWallet = encrypter.process(utf8.encode(walletJson));

    await into(profiles).insert(
      ProfilesCompanion.insert(
        id: wallet.address,
        username: username,
        encryptedWallet: encryptedWallet,
        walletSalt: salt,
      ),
    );
  }
}
