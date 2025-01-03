import 'package:ardrive/utils/key_value_store.dart';
import 'package:ardrive/utils/logger.dart';

abstract class ProfileLogoRepository {
  Future<String?> getProfileLogoTxId(String walletAddress);
  Future<void> setProfileLogoTxId(String walletAddress, String txId);

  factory ProfileLogoRepository(KeyValueStore keyValueStore) {
    return ProfileLogoRepositoryImpl(
      keyValueStore: keyValueStore,
    );
  }
}

class ProfileLogoRepositoryImpl implements ProfileLogoRepository {
  final KeyValueStore _keyValueStore;

  ProfileLogoRepositoryImpl({
    required KeyValueStore keyValueStore,
  }) : _keyValueStore = keyValueStore;

  @override
  Future<String?> getProfileLogoTxId(String walletAddress) async {
    final lastSet =
        await _keyValueStore.getString('profile_logo_last_set_$walletAddress');

    if (lastSet != null &&
        DateTime.now()
            .isBefore(DateTime.parse(lastSet).add(const Duration(hours: 1)))) {
      logger.d('Getting profile logo tx id from cache');
      return _keyValueStore.getString('profile_logo_tx_id_$walletAddress');
    }

    return null;
  }

  @override
  Future<void> setProfileLogoTxId(String walletAddress, String txId) async {
    // set last time the profile logo was set
    await _keyValueStore.putString(
      'profile_logo_last_set_$walletAddress',
      DateTime.now().toIso8601String(),
    );

    await _keyValueStore.putString(
      'profile_logo_tx_id_$walletAddress',
      txId,
    );
  }
}
