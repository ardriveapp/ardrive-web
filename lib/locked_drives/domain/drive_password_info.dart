import 'dart:convert';

/// The byte strings a typed drive password may have been turned into when
/// the drive was made, in the order to try them.
///
/// The drive key's HKDF `info` is the password's bytes. ArDrive web has always
/// used its UTF-8 bytes. core-js - and so the CLI and desktop - encodes it
/// twice: the `utf8` package turns it into a string of UTF-8 bytes, one
/// character per byte, and `futoin-hkdf` encodes that string as UTF-8 again.
/// For ASCII both give the same bytes. For anything else they differ: "ä" is
/// `c3 a4` here and `c3 83 c2 a4` there, so a drive made by the CLI with such a
/// password never opened on web.
///
/// So a password with a non-ASCII character gets a second candidate, the
/// double-encoded form, tried only after the plain one fails. Never used to
/// make a new drive: this is for reading what already exists.
List<List<int>> drivePasswordInfos(String password) {
  final plain = utf8.encode(password);

  if (!password.codeUnits.any((unit) => unit > 0x7f)) {
    return [plain];
  }

  return [plain, coreJsPasswordInfo(password)];
}

/// The `info` core-js derives a drive key with: the password's UTF-8 bytes,
/// read as Latin-1 characters, encoded as UTF-8 again. See
/// [drivePasswordInfos].
List<int> coreJsPasswordInfo(String password) =>
    utf8.encode(String.fromCharCodes(utf8.encode(password)));
