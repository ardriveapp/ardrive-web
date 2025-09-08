#!/usr/bin/env node

import { Command } from 'commander';
import { diffLines } from 'diff';
import * as fs from 'fs';
import { GraphQLClient, gql } from 'graphql-request';
import * as path from 'path';

const owner = 'N4h8M9A9hasa3tF47qQyNvcKjm4APBKuFs7vqUVm-SI';
const fileId = 'e4ef007d-d44b-430a-9a20-6f55e560aeea';
const driveId = '87082af3-741d-4620-a556-06b3e41c3d88';
const privateDriveId = 'caae3a63-6adb-4266-85bc-0e072b631cf4';
const dataTxId = 'QsSJfMlY92kg3lFNEudnaQcZbrEubpXEIRAVlal4L7U';
const dataTxId2 = 'LdZMi_m0dWbj3te2GFgrLkBoPnj9Zm4eEzA99FrM-yQ';

// keys are file names, values are parameters to pass in for each query
const queries:Record<string, any> = {
  "AllFileEntitiesWithId": { fileId, owner, after: null, lastBlockHeight: 1000000 },
  "DriveEntityHistory": { driveId, after: null, minBlockHeight: null, maxBlockHeight: null, ownerAddress: owner, entityType: "folder" },
  "DriveEntityHistoryWithEntityTypeFilter": { driveId, after: null, minBlockHeight: null, maxBlockHeight: null, ownerAddress: owner },
  "DriveSignatureForDrive": { owner, driveId: privateDriveId },
  "FirstDriveEntityWithIdOwner": { driveId, after: null },
  "FirstFileEntityWithIdOwner": { fileId, after: null },
  "FirstTxBlockHeightForWallet": { owner },
  "FirstTxForWallet": { owner},
  "InfoOfTransactionsToBePinned": { transactionIds: [dataTxId, dataTxId2] },
  "InfoOfTransactionToBePinned": { txId: dataTxId },
  "LatestDriveEntityWithId": { driveId, owner, after: null },
  "LatestFileEntityWithId": { fileId, owner, after: null },
  "LicenseAssertions": { transactionIds: [dataTxId] },   // TODO: Verify these are correct params to check
  "LicenseDataBundled": { transactionIds: [dataTxId] },   // TODO: Verify these are correct params to check
  "PendingTxFees": { walletAddress: owner },
  "SingleTransaction": { txId: dataTxId },
  "SnapshotEntityHistory": { driveId, after: null, lastBlockHeight: 1749673, ownerAddress: owner },
  "TransactionsAtHeight": { owner: "vh-NTHVvlKZqRxc8LyyTNok65yQ55a_PJ1zWLb9G2JI", height: 1000000 },
  "TransactionStatuses": { transactionIds: [dataTxId, dataTxId2] },
  "UserDriveEntities": { owner, after: null },
}


const program = new Command();

program
  .name('ardrive-gql-verify')
  .description('Verify ArDrive GraphQL requests between reference and target gateways')
  .version('1.0.0')
  .option('--reference-gateway <url>', 'Reference gateway URL', 'https://arweave.net')
  .option('--target-gateway <url>', 'Target gateway URL')
  .option('--wallet <path>', 'Path to Arweave JWK JSON wallet')
  .option('--debug', 'Always show reference and target responses')
  .action(async (options) => {
    const { referenceGateway, targetGateway, wallet, debug } = options;

    console.log(`Reference Gateway: ${referenceGateway}`);
    console.log(`Target Gateway: ${targetGateway}`);
    if (wallet) {
      console.log(`Wallet: ${wallet}`);
      // Load wallet if needed
    }

    // Path to .graphql files relative to this script
    const queriesDir = path.join(__dirname, '../../lib/services/arweave/graphql/queries');

    if (!fs.existsSync(queriesDir)) {
      console.error(`Queries directory not found: ${queriesDir}`);
      process.exit(1);
    }

    // Load the TransactionCommon fragment
    const fragmentPath = path.join(__dirname, '../../lib/services/arweave/graphql/fragments/TransactionCommon.graphql');
    const transactionCommonFragment = fs.existsSync(fragmentPath) ? fs.readFileSync(fragmentPath, 'utf-8') : '';

    const referenceClient = new GraphQLClient(`${referenceGateway}/graphql`);
    const targetClient = new GraphQLClient(`${targetGateway}/graphql`);

    for (const [queryName, params] of Object.entries(queries)) {
      const queryPath = path.join(__dirname, '../../lib/services/arweave/graphql/queries', `${queryName}.graphql`);

      if (!fs.existsSync(queryPath)) {
        console.error(`Query file not found: ${queryPath}`);
        continue;
      }

      let query = fs.readFileSync(queryPath, 'utf-8');

      // If the query uses TransactionCommon fragment, prepend the fragment definition
      if (query.includes('...TransactionCommon') && transactionCommonFragment) {
        query = transactionCommonFragment + '\n\n' + query;
      }

      try {
        console.log(`\nVerifying query: ${queryName}`);
        const referenceResult = await referenceClient.request(gql`${query}`, params);
        const targetResult = await targetClient.request(gql`${query}`, params);

        // Compare results using diff for better output
        const referenceJson = JSON.stringify(referenceResult, null, 2);
        const targetJson = JSON.stringify(targetResult, null, 2);

        const diffs = diffLines(referenceJson, targetJson);
        const hasDifferences = diffs.some((diff: any) => diff.added || diff.removed);

        if (!hasDifferences) {
          console.log(`✓ Match for ${queryName}`);
          if (debug) {
            console.log(`Reference (${referenceGateway}):`, referenceJson);
            console.log(`Target (${targetGateway}):`, targetJson);
          }
        } else {
          console.log(`✗ Mismatch for ${queryName}`);

          // Show diff output
          console.log('Differences:');
          diffs.forEach((part: any, index: number) => {
            if (part.added) {
              console.log(`\x1b[32m+ ${part.value}\x1b[0m`); // Green for additions
            } else if (part.removed) {
              console.log(`\x1b[31m- ${part.value}\x1b[0m`); // Red for removals
            } else {
              // Show context for unchanged parts (first few lines)
              if (index < 5) {
                const lines = part.value.split('\n').slice(0, 3);
                console.log(`  ${lines.join('\n  ')}`);
              }
            }
          });

          if (debug) {
            console.log(`Reference (${referenceGateway}):`, referenceJson);
            console.log(`Target (${targetGateway}):`, targetJson);
          }
        }
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        console.error(`Error with ${queryName}:`, message);
      }
    }
  });

program.parse();
