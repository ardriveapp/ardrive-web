// The address an AR.IO gateway serves a transaction's own bytes from, and the
// only origin ArDrive will let an untrusted transaction render itself on.
//
// A gateway answers `https://{gateway}/{txId}` with a `302` to
// `https://{base32(txId)}.{gateway}/{txId}`: one origin per transaction, by
// construction. That redirect exists for exactly the reason this file does -
// so that a transaction which turns out to be a web page cannot read anything
// belonging to the site that linked to it. `app.ardrive.io` keeps a recipient's
// access key in `sessionStorage` (`docs/FILE_SHARING_REDESIGN_PLAN.md` §4.3),
// which is what makes the distinction load-bearing rather than decorative.
//
// The subdomain is computed here rather than followed as a redirect so that
// nothing is ever pointed at the bare gateway origin first, where every
// transaction would share one origin while the redirect is in flight.
//
// This is `getSandboxSubdomain` from `package:arweave` - which that package
// does not export - reimplemented rather than reached for through
// `package:arweave/src/…`, which the `implementation_imports` lint forbids.

import 'dart:convert';
import 'dart:typed_data';

import 'package:ardrive/utils/validate_arweave_id.dart';

/// RFC 4648 base32, lower case - the alphabet a gateway's sandbox subdomain
/// uses, which is also the only alphabet a DNS label can carry.
const String _base32Alphabet = 'abcdefghijklmnopqrstuvwxyz234567';

/// The 32 raw bytes behind [txId], or `null` when it is not a transaction id.
///
/// The `/view/{txId}` route hands this an arbitrary string from an arbitrary
/// link, and every later step - the gateway request, the sandbox subdomain, the
/// page's own chrome - is built from it. The route parser already rejects an id
/// that is not one; this checks again anyway, because the alternative is a
/// function that will happily build a URL out of `evil.example.com`.
Uint8List? decodeTransactionId(String txId) {
  if (!isArweaveTransactionID(txId)) {
    return null;
  }

  try {
    // 43 base64url characters need one `=` to reach a multiple of four.
    return base64Url.decode('$txId=');
  } catch (_) {
    return null;
  }
}

/// The DNS label a gateway serves [txId] from, or `null` for a malformed id.
String? arweaveSandboxSubdomain(String txId) {
  final bytes = decodeTransactionId(txId);

  if (bytes == null) {
    return null;
  }

  return _base32Encode(bytes);
}

/// `https://{base32(txId)}.{gateway}/{txId}`, or `null` when [txId] is not a
/// transaction id.
///
/// [gatewayUrl] comes from the configured data gateway, never from a constant:
/// a deployment behind a private gateway must not silently reach out to
/// arweave.net.
String? arweaveSandboxUrl({
  required String txId,
  required Uri gatewayUrl,
}) {
  final subdomain = arweaveSandboxSubdomain(txId);

  if (subdomain == null || gatewayUrl.host.isEmpty) {
    return null;
  }

  // `hasPort` is true for an explicit port only, so a plain `https://host`
  // gateway does not grow a `:443` that no gateway would ever be reached at.
  final port = gatewayUrl.hasPort ? ':${gatewayUrl.port}' : '';

  return '${gatewayUrl.scheme}://$subdomain.${gatewayUrl.host}$port/$txId';
}

String _base32Encode(Uint8List bytes) {
  final encoded = StringBuffer();

  var accumulator = 0;
  var bits = 0;

  for (final byte in bytes) {
    accumulator = (accumulator << 8) | byte;
    bits += 8;

    while (bits >= 5) {
      bits -= 5;
      encoded.write(_base32Alphabet[(accumulator >> bits) & 0x1f]);
    }
  }

  if (bits > 0) {
    // The trailing partial group, padded with zero bits. The `=` padding RFC
    // 4648 would add is dropped: a DNS label cannot carry it, and every
    // gateway omits it too.
    encoded.write(_base32Alphabet[(accumulator << (5 - bits)) & 0x1f]);
  }

  return encoded.toString();
}
