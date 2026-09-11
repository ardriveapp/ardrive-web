import 'package:ardrive/turbo/topup/models/crypto_token.dart';
import 'package:equatable/equatable.dart';

/// Credits found on the wallet a user signed in with, which cannot pay for this
/// upload.
///
/// Signing in with Phantom or MetaMask does not make the ArDrive account a
/// Solana or Ethereum account. The signature derives a deterministic Arweave
/// wallet and that is the account. Turbo keeps a separate balance per chain, so
/// credits bought in Turbo's own console against the sign-in wallet land on that
/// chain's account, and ArDrive, which only ever asks about Arweave, sees
/// nothing.
///
/// The money is not lost and nothing is miscredited. Two systems are describing
/// different accounts, and until this existed neither of them said so: the app
/// answered "insufficient balance" and offered to sell more credits to somebody
/// who had already bought them.
///
/// Nothing here is spendable. Turbo bills the account that signs the upload, so
/// these stay put until their owner shares them across to the Arweave address.
/// This exists to say where they are, not to spend them.
class SourceWalletCredits extends Equatable {
  const SourceWalletCredits({
    required this.balance,
    required this.sourceAddress,
    required this.walletType,
    required this.arweaveAddress,
  });

  /// What the sign-in wallet's Turbo account holds, in winston credits.
  ///
  /// Only ever constructed when this is greater than zero: an empty account
  /// somewhere else is not news, and saying so would turn an ordinary
  /// out-of-credits message into a puzzle.
  final BigInt balance;

  /// The address the credits are on, as the user knows it from their wallet.
  final String sourceAddress;

  /// Which chain [sourceAddress] belongs to, so the message can name it.
  final WalletType walletType;

  /// The address ArDrive actually spends from, which is what the credits have
  /// to be shared with.
  final String arweaveAddress;

  @override
  List<Object?> get props => [
        balance,
        sourceAddress,
        walletType,
        arweaveAddress,
      ];
}
