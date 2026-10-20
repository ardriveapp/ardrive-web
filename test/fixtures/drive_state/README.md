# Drive State conformance fixtures

These are Drive State artifacts built by this app's own producer, plus copies
mutated into every malformed shape a reader must refuse. Each fixture records
the outcome this app's importer gives it. A second reader, such as
ardrive-core-js, copies this directory and must reach the same outcome on every
fixture. On each fixture this app uses, it must also read the same rows.

`test/drive_state/conformance/golden_fixtures.dart` builds them, and
`golden_fixtures_test.dart` checks them on every run.

## Regenerate

Run the following command:

```sh
DRIVE_STATE_WRITE_FIXTURES=1 flutter test test/drive_state/conformance/golden_fixtures_test.dart
```

On Windows, set the variable with `set DRIVE_STATE_WRITE_FIXTURES=1&&` before
the command.

Everything is deterministic except gzip's timestamp. A regenerated fixture has
the same payload, tags and outcome but not the same sealed bytes, so copy the
checked-in `.bin` files rather than regenerating them elsewhere.

## A fixture

Each fixture is two files:

- **`NAME.bin`**: the transaction's data, exactly as a gateway serves it.
- **`NAME.json`**: everything else.

| Field | Meaning |
| --- | --- |
| `name`, `description` | What the fixture is and what it tests |
| `body` | The `.bin` file's name |
| `transaction.id` | The transaction id. Never fetched |
| `transaction.owner` | The transaction's owner, as an indexer reports it |
| `transaction.tags` | The tags, in the order the producer wrote them. Where a name repeats, the first value wins |
| `reader.driveId`, `reader.ownerAddress`, `reader.privacy` | What the reading client already holds about the drive |
| `reader.driveKey` | The drive key, as base64url without padding, or `null` for a public drive. A test key, never a real drive's |
| `reader.syncedToBlock` | The height the client has already synced the drive to |
| `payloadSha256` | SHA-256 of the SQLite file inside the body, where a reader can reach it |
| `expected.outcome` | This app's `DriveStateOutcome`, by name |
| `expected.detail` | This app's reason, for people. Not part of conformance |
| `expected.tables` | Every table of the payload, rows in `rowid` order, when the outcome is `used` |

Outcome names are this app's enum names. ardrive-core-js spells them in kebab
case: `integrityFailed` is `integrity-failed`.

## What a reader must do with them

For every fixture:

1. Build the client state from `reader`.
2. Read `body` as the data of a transaction with `transaction.owner` and
   `transaction.tags`.
3. Reach `expected.outcome`.

When the outcome is `used`, the reader must also read the same drive, folder
and file rows as `expected.tables`.

`ghost-parent` is `used` here because this app gives a file whose parent no
table carries a placeholder folder. A reader that holds no state, such as a
listing, may instead leave that file out of the listing, as it would if it
synced the drive from GraphQL.
