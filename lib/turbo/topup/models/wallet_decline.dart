/// Whether [error] is the wallet reporting that the person declined the
/// request (EIP-1193 code 4001, ethers' ACTION_REJECTED, Phantom's "User
/// rejected the request").
///
/// The Turbo SDK sends the transaction itself, so a decline reaches the app as
/// a raw script error and not as a wallet exception. A wallet only reports a
/// decline before it signs, so nothing was sent. Any other text, including a
/// failure after a send, is not a decline.
bool isWalletDecline(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('action_rejected') ||
      text.contains('user rejected') ||
      text.contains('user denied') ||
      text.contains('user declined') ||
      text.contains('user_rejected') ||
      // A bare code, not digits inside a longer id or hash.
      RegExp(r'(?<![0-9a-z])4001(?![0-9a-z])').hasMatch(text);
}
