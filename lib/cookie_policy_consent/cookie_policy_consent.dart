import 'package:ardrive/utils/constants.dart';
import 'package:ardrive/utils/local_key_value_store.dart';

class ArDriveCookiePolicyConsent {
  LocalKeyValueStore? _localKeyValueStore;

  ArDriveCookiePolicyConsent([
    LocalKeyValueStore? testLocalKeyValueStore,
  ]) {
    if (testLocalKeyValueStore != null) {
      _localKeyValueStore = testLocalKeyValueStore;
    }
  }

  // verify if the user accepted the cookie policy
  Future<bool> hasAcceptedCookiePolicy() async {
    final hasAccepted = (await _store()).getBool(hasAcceptedCookiePolicyKey);

    return hasAccepted ?? false;
  }

  // set the cookie policy as accepted
  Future<void> acceptCookiePolicy() async {
    (await _store()).putBool(hasAcceptedCookiePolicyKey, true);
  }

  Future<LocalKeyValueStore> _store() async {
    if (_localKeyValueStore != null) {
      return _localKeyValueStore!;
    } else {
      _localKeyValueStore = await LocalKeyValueStore.getInstance();
      return _localKeyValueStore!;
    }
  }
}
