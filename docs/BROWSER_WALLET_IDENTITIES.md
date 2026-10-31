# Browser wallet identities (an ArDrive client convention)

This is not part of ArFS. No ArFS entity depends on it, and other ArFS clients do not need it. It is a compatibility contract between ArDrive clients (the web app is the reference implementation): the same Ethereum or Solana account must always give the same Arweave wallet.

For ArFS, the result is an ordinary Arweave wallet. It owns and signs the ArFS entities, and drive keys are derived from it exactly as for any other wallet (see "Drive privacy" in [ArweaveFS.md](ArweaveFS.md)). ardrive-core-js and the ArDrive CLI have no Ethereum or Solana sign-in.

Each derivation below is fixed forever. Changing one byte of a message gives every account made with it another wallet. Keep the messages byte-exact.

## From a signature to a wallet

All three derivations turn a signature into a 12-word BIP-39 phrase the same way: the first 16 bytes of the signature's SHA-256 are the entropy. The phrase becomes an RSA wallet the way a recovery phrase does.

## Solana (Phantom, Solflare)

The wallet signs this message as UTF-8. Its Ed25519 signature (deterministic, RFC 8032) gives the phrase.

```
ArDrive wants to access your account. Only approve this on a gateway you trust (e.g. app.ardrive.io). ArDrive Identity v1
```

## Ethereum, version 1 (with a password)

The password picks the wallet: another password gives another wallet.

1. The wallet signs `Sign message to verify wallet address.` with `personal_sign`. SHA-256 of that signature is the private key of the account's auth Ethereum key. The auth key's Arweave address is the SHA-256 of the 65-byte uncompressed secp256k1 public key (`0x04` followed by the 64-byte X and Y), as base64url without padding. This is `ownerToAddress` applied to the key's owner, the base64url of those 65 bytes.
2. The wallet signs, with `personal_sign`, the UTF-8 bytes of the lowercase hex of SHA-256(`1:<address>:<password>`). Here `1` is the chain ID and `<address>` is the account address as a lowercase `0x` hex string. That signature gives the phrase.
3. At sign-up the Arweave wallet signs the SHA-256 of the step 2 signature. That signature is posted twice, from the Arweave wallet and from the auth key, as each one's first transaction. Sign-in compares both with a fresh one to tell a right password from a wrong one.

## Ethereum, version 2 (no password)

The wallet signs, with `personal_sign`, the UTF-8 bytes of this message, with the address in lowercase. That signature gives the phrase.

```
ArDrive account
Signing this opens your ArDrive account. Only sign it in ArDrive.
It is free and sends no transaction.
Account: 0x<address in lowercase>
Version: 2
```

At sign-up the message is signed twice and the two signatures must be equal. A wallet that signs differently each time gets no account.

Then the auth key (step 1 above) posts the account's marker. It is an ANS-104 data item signed with the auth key (Ethereum signature type).

| Part | Value |
|---|---|
| Tag `App-Name` | `ArDrive` |
| Tag `ArDrive-Account-Version` | `2` |
| Tag `ArDrive-Account-Address` | the account's Arweave address |
| Data | the same Arweave address, UTF-8 |

The marker is not an ArFS entity. It has no `ArFS`, `Entity-Type` or `Drive-Id` tag.

`personal_sign` from an ordinary Ethereum account is deterministic (RFC 6979). Smart-contract and MPC wallets may not be, under either version.

## Telling version 1 from version 2

This section describes what ArDrive clients do. Other behaviour is a client choice.

Sign-in signs the step 1 message, which needs no password. It then reads the transactions of the auth key's Arweave address.

- A marker first: version 2. The account message is signed, and the wallet derived from it must have the marker's address. If it does not, sign-in stops with an error instead of opening another, empty account.
- An untagged transaction first: a version 1 verification record. The password is asked.
- No record: the person chooses between creating a version 2 account and signing in to a version 1 account. A version 1 password with no record to check it against is accepted only if the wallet it derives owns ArFS drives or has any transaction.

A lookup that fails is an error, never "no record". The lookup is the GraphQL query `AccountRecords` (`lib/services/arweave/graphql/queries/AccountRecords.graphql`). It reads only the first 20 transactions of the auth key's address, sorted by block height, oldest first. A key with more than 20 transactions has the rest unread.

## The earliest record decides

The auth key's transactions are read earliest first. A version 1 record made at sign-up predates any marker, so a marker posted later cannot take a version 1 account over. Transactions are ordered by block. A pending one (no block yet) comes after every mined one. Records whose owner is not the auth key's address are ignored.

Known limit (from reading the code, not tested): the step 1 message is a constant, so anyone who can ask the account's wallet to sign it learns the auth key. With it, they can post a record before the account's first sign-up. That can lock the account out of sign-in. It cannot give them the account's Arweave wallet, which comes from a signature only the account can make.
