// ArNS reads for the names page and picker, and the controller's direct
// record writes (docs/NAMES.md, "Protocol"). Owners' writes go through
// Turbo from Dart; only a controller signs and pays the Solana fee here.

import { ANT, SolanaANTReadable } from '@ar.io/sdk';
import {
  address,
  createSolanaRpcSubscriptions,
  getTransactionDecoder,
  getTransactionEncoder,
} from '@solana/kit';

import { requireConnectedAddress, signTransactionBytes } from './wallet.js';

const APEX = '@';

/**
 * Every name the address owns or controls, from its ACL (point lookups, no
 * program scan).
 */
export async function getArNSNamesForAddress(ctx, owner) {
  const items = [];
  let cursor;
  do {
    const page = await ctx.ario().getArNSRecordsForAddress({
      address: owner,
      limit: 1000,
      cursor,
    });
    items.push(...page.items);
    cursor = page.hasMore ? page.nextCursor : undefined;
  } while (cursor);

  return JSON.stringify(
    items.map((r) => ({
      name: r.name,
      processId: r.processId,
      type: r.type,
      startTimestamp: r.startTimestamp,
      endTimestamp: r.endTimestamp ?? null,
      undernameLimit: r.undernameLimit,
    })),
  );
}

function antReadable(ctx, processId) {
  return new SolanaANTReadable({
    rpc: ctx.rpc(),
    processId,
    ...(ctx.antProgramId() ? { antProgramId: address(ctx.antProgramId()) } : {}),
  });
}

/** Owner, controllers and the apex record of many ANTs in a few calls. */
export async function getANTSummaries(ctx, processIdsJson) {
  const ids = JSON.parse(processIdsJson);
  if (ids.length === 0) return JSON.stringify({});

  const summaries = await antReadable(ctx, ids[0]).getANTSummaries(ids);
  const out = {};
  for (const [id, s] of Object.entries(summaries)) {
    out[id] = {
      processId: s.processId,
      name: s.name,
      ticker: s.ticker,
      owner: s.owner,
      controllers: s.controllers,
      apexRecord: s.apexRecord ? record(APEX, s.apexRecord) : null,
    };
  }
  return JSON.stringify(out);
}

function record(undername, r) {
  return {
    undername,
    transactionId: r.transactionId,
    ttlSeconds: r.ttlSeconds,
  };
}

/** Every record of one ANT, the apex included as '@'. */
export async function getANTRecords(ctx, processId) {
  const records = await antReadable(ctx, processId).getRecords();
  return JSON.stringify(
    Object.entries(records).map(([undername, r]) => record(undername, r)),
  );
}

// --- Controller writes -----------------------------------------------------

/**
 * A kit signer backed by the connected wallet. "Modifying" because wallets
 * such as Phantom may rewrite the message (compute budget, guards); the SDK
 * sends whatever comes back.
 */
function walletSigner(ctx) {
  const encoder = getTransactionEncoder();
  const decoder = getTransactionDecoder();

  return {
    address: address(requireConnectedAddress()),
    async modifyAndSignTransactions(transactions) {
      const signed = [];
      for (const tx of transactions) {
        const bytes = await signTransactionBytes(
          new Uint8Array(encoder.encode(tx)),
          ctx.chain(),
        );
        const decoded = decoder.decode(bytes);
        signed.push(
          tx.lifetimeConstraint
            ? { ...decoded, lifetimeConstraint: tx.lifetimeConstraint }
            : decoded,
        );
      }
      return signed;
    },
  };
}

async function writableAnt(ctx, processId) {
  return ANT.init({
    processId,
    rpc: ctx.rpc(),
    rpcSubscriptions: createSolanaRpcSubscriptions(
      ctx.rpcUrl().replace(/^http/, 'ws'),
    ),
    signer: walletSigner(ctx),
    // Explicit, so the SDK never signs against a program read from the asset.
    antProgramId: address(ctx.antProgramIdOrDefault()),
  });
}

/** Sets a record with the connected wallet's own transaction; returns its id. */
export async function setRecordAsController(
  ctx,
  processId,
  undername,
  transactionId,
  ttlSeconds,
) {
  const ant = await writableAnt(ctx, processId);
  const result =
    undername === APEX
      ? await ant.setBaseNameRecord({ transactionId, ttlSeconds })
      : await ant.setUndernameRecord({ undername, transactionId, ttlSeconds });
  return result.id;
}

export async function removeRecordAsController(ctx, processId, undername) {
  if (undername === APEX) {
    // The ANT has no instruction to delete the apex record; a main name is
    // pointed at the placeholder page instead.
    throw new Error('The main record cannot be removed');
  }
  const ant = await writableAnt(ctx, processId);
  const result = await ant.removeUndernameRecord({ undername });
  return result.id;
}

export async function getSolBalanceLamports(ctx, owner) {
  const { value } = await ctx.rpc().getBalance(address(owner)).send();
  return value.toString();
}

/**
 * What a controller's write costs in lamports. `workflow` is 'set-record'
 * (creates the record, so rent), 'edit-record' (fees only) or
 * 'remove-record' (rent comes back).
 */
export async function estimateControllerFee(
  ctx,
  processId,
  workflow,
  undername,
) {
  const estimate = await antReadable(ctx, processId).getGasEstimate({
    workflow,
    undername,
  });
  return JSON.stringify({
    totalLamports: estimate.totalLamports,
    feeLamports: estimate.feeLamports,
    rentLamports: estimate.rentLamports,
    rentReclaimedLamports: estimate.rentReclaimedLamports ?? 0,
  });
}
