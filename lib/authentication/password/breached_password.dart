import 'dart:async';
import 'dart:convert';

import 'package:ardrive/utils/logger.dart';
import 'package:cryptography/cryptography.dart';
import 'package:http/http.dart' as http;

/// Whether a new password has shown up in a known data breach, from Have I
/// Been Pwned's range API.
///
/// The password never leaves the device. Its SHA-1 is computed here, only the
/// first 5 of its 40 hex characters are sent, and the service answers with
/// every breached hash that starts with them (padded with decoys so the size
/// of the answer says nothing either); the match is made here. This is the
/// service's k-anonymity model: the prefix is shared by hundreds of unrelated
/// passwords.
class BreachedPasswordCheck {
  BreachedPasswordCheck({http.Client? client, this.timeout = _timeout})
      : _client = client ?? http.Client();

  static const _timeout = Duration(seconds: 4);
  static final _api = Uri.parse('https://api.pwnedpasswords.com/range/');

  final http.Client _client;
  final Duration timeout;

  /// True if [password] is in a breach, false if not, and null when the
  /// service could not be asked: the caller then lets it through, so a
  /// service being away never stops someone signing up.
  Future<bool?> isBreached(String password) async {
    try {
      final digest = await Sha1().hash(utf8.encode(password));
      final hex = digest.bytes
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join()
          .toUpperCase();
      final prefix = hex.substring(0, 5);
      final suffix = hex.substring(5);

      // The http package this app resolves (1.2) can't abort a request, so
      // after a timeout the request carries on in the background and its
      // answer is ignored.
      final response = await _client.get(
        _api.resolve(prefix),
        headers: const {'Add-Padding': 'true'},
      ).timeout(timeout);
      if (response.statusCode != 200) return null;

      for (final line in const LineSplitter().convert(response.body)) {
        final parts = line.trim().split(':');
        if (parts.length != 2 || parts[0] != suffix) continue;
        // Decoys added by padding carry a count of 0.
        return (int.tryParse(parts[1]) ?? 0) > 0;
      }
      return false;
    } catch (e) {
      // Never the password or its hash, only that the check was skipped.
      logger.w('Could not check the password against known breaches: '
          '${e.runtimeType}');
      return null;
    }
  }
}
