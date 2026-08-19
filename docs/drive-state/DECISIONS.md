# Drive state artifact — implementation decisions

Binding decisions taken to make the work dispatchable. Each closes an open
question from `docs/DRIVE_STATE_ARTIFACT.md` §10. **These are the coordinator's
calls, not settled protocol** — every one is reversible before the format is
published to chain, and each is flagged for human review.

| # | Question | Decision | Why, and what it costs |
|---|---|---|---|
| D1 | Section format | **JSON, gzipped.** A top-level object of named sections; section `rows` holds the exported tables. | Dart and TypeScript read it natively with no new dependency, and gzip recovers the verbosity (measured 5.2x). A binary format would be smaller but needs a spec, a codec on both sides, and buys little once compressed. Revisit only if profiling says parse time dominates. |
| D2 | Revision depth | ~~Current state only~~ → **REVERSED. The payload carries `drive_revisions`, `folder_revisions`, `file_revisions` — every revision, not the newest per entity — and `licenses`. `network_transactions` is *derived* on import rather than carried.** | The original reasoning — "covers everything the explorer renders" — was simply false, and I did not check it. `filesInFolderWithLicenseAndRevisionTransactions` (`lib/models/queries/drive_queries.drift:108`), the query the explorer actually uses, **INNER JOINs** `network_transactions` twice through a `file_revisions` subquery. A file with no revision row yields NULL on the ON condition and is dropped. An artifact carrying entries alone would import 41,000 files and show **zero** of them, in every folder — and it would not heal, because the import advances the watermark past the range whose revisions would have satisfied the join. Found by the import audit; verified against the query. Note the size measurement in the proposal (34.63 MiB) already modelled entries **plus** revisions plus network transactions, so this reversal costs nothing against the published numbers — it was D2 that departed from what was measured. Three refinements taken while implementing it. **Depth: every revision.** Measured on the 42k-file drive: 39,878 entities, 1.05 revisions each, 4.7% with more than one, max 4 — so the whole history costs ~5% more rows and keeps what the file details panel shows. **`network_transactions` is regenerated, not serialised.** It is four columns and fully derivable from the revisions, and it has no `driveId`, so publishing it would publish rows about the user's other drives to everyone holding this drive's key; the importer rebuilds it through `lib/sync/utils/network_transaction_utils.dart`, the same helpers sync uses, with one correction — a data transaction lands `confirmed` rather than the helpers' `pending`, because an artifact's coverage claim is the producer's own synced watermark and importing 42,000 pending rows would both paint every file as pending and queue a confirmation query per transaction. **`licenses` travels too.** Its join is a LEFT JOIN, so a missing row hides no file — it silently drops the licence the user attached to their own. `Entity-Count` is unchanged and still counts entities (folders + files + the drive); a revision is a version of an entity, not another one. |
| D3 | Production trigger | **Explicit user action only** in v1. No automatic publishing. | Publishing is permanent, costs money, and must never happen from a sync that reported skipped entities. An explicit action makes that precondition checkable and keeps the safety rail intact. |
| D4 | Who pays | **Whichever upload path the user already has** — Turbo credits or AR. No new payment surface. | Follows the transport-independence rule (§4.4). |
| D5 | Above the GCM boundary | **Refuse to produce**, with a clear reason, rather than split. | Multi-part authentication needs its own manifest integrity design. Refusing is honest and safe; a drive that large falls back to snapshots, which is today's behaviour. Deferred, not decided against. |
| D6 | ArNS naming | **Not wired in v1.** Discovery is GraphQL by `Entity-Type` + `Drive-Id` + owner. | The ArNS path is the acceleration, not the mechanism, and it depends on an undername convention that needs checking against the ARIO spec. Building discovery behind an interface leaves it a drop-in later. |
| D7 | Export safety mechanism | **Typed projection + schema-drift test** for v1, not database views. | Views need a schema migration on a live database whose fixtures are stale at v19 — the wrong thing to land unattended. A projection naming its columns is functionally equivalent today; the drift test is what makes it hold. **Views remain the target**; this is a deliberate deferral, recorded so it is not forgotten. |
| D8 | Upload | **Built and tested, never executed by the loop.** | Framework safety rail: the loop spends nothing and publishes nothing. |

## Scope boundary for this branch

**In:** export, serialise, sign, compress, encrypt, and the exact inverse;
the ArFS entity and its tags; discovery by GraphQL; import into a sandbox and
merge; sync composition; observability; UI to trigger creation and to show what
a sync used. Tests at every layer.

**Out, deliberately:** executing an upload (D8), ArNS (D6), database views (D7),
multi-part artifacts (D5), public drives (proposal §2.6).

## Non-negotiables for every lane

1. **No key material may leave the database.** `profiles` is never read.
   `drives` is read column-wise, excluding `encryptedKey`, `driveKeyGenerated`,
   `keyEncryptionIv`. A test must fail if the schema grows a column the
   projection would pick up.
2. **Every failure is a fallback.** No path may fail a drive because an artifact
   was bad. Unknown version, bad signature, failed decrypt, count mismatch —
   log an enumerated reason and sync normally.
3. **No regressions.** The full suite is the gate, not the touched files.
4. **Nothing is uploaded, published, tagged or released by any agent.**
