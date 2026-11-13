/// Whether [error] is the wallet reporting that the person declined the
/// request (EIP-1193 code 4001, ethers' ACTION_REJECTED, Phantom's "User
/// rejected the request").
///
/// The Turbo SDK sends the transaction itself, so a decline reaches the app as
/// a raw script error and not as a wallet exception. A wallet only reports a
/// decline before it signs, so nothing was sent. Any other text, including a
/// failure after a send, is not a decline.
///
/// Calling a sent payment a decline would tell someone who paid that no
/// payment was made, so this errs towards false: the SDK's after-send failure
/// is never a decline, and 4001 counts only as an error code, never as a
/// request id, an amount or a port. (A real decline carries the request's
/// hex calldata, so long hex is no sign that anything was sent.)
bool isWalletDecline(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('failed to submit fund transaction')) return false;
  return text.contains('action_rejected') ||
      text.contains('user rejected') ||
      text.contains('user denied') ||
      text.contains('user declined') ||
      text.contains('user_rejected') ||
      _declineCode.hasMatch(text);
}

/// `code: 4001`, `"code": 4001`, `code=4001`, `error: 4001`.
final _declineCode =
    RegExp(r'''(?:code|error)["']?\s*[:=]\s*4001(?![0-9a-z])''');
