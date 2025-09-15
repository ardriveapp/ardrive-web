import { arDriveAnonymousFactory, EntityID } from 'ardrive-core-js';
import Arweave from 'arweave';
import { Command } from 'commander';
import { createPatch } from 'diff';
import fs from 'fs';

export const createDriveCompareCommand = () => {
  const command = new Command('drive-compare');

  command
    .description('Compare drives between two gateways')
    .requiredOption('--drive-id <id>', 'Drive ID to compare')
    .requiredOption('--reference-gateway <url>', 'Reference gateway URL', 'https://arweave.net')
    .requiredOption('--target-gateway <url>', 'Target gateway URL')
    .option('--debug', 'Always show reference and target responses')
    .action(async (options) => {
      const { driveId, referenceGateway, targetGateway, debug } = options;

      console.log('Drive Compare Command');
      console.log(`Drive ID: ${driveId}`);
      console.log(`Reference Gateway: ${referenceGateway}`);
      console.log(`Target Gateway: ${targetGateway}`);

      try {
        const parseGateway = (url: string) => {
          const u = new URL(url);
          return {
            host: u.hostname,
            port: u.port,
            protocol: u.protocol.slice(0, -1) as 'https' | 'http',
            timeout: 600000
          };
        };

        const refConfig = parseGateway(referenceGateway);
        const targetConfig = parseGateway(targetGateway);

        const arweaveRef = Arweave.init(refConfig);
        const arweaveTarget = Arweave.init(targetConfig);

        const arDriveRef = arDriveAnonymousFactory({ arweave: arweaveRef });
        const arDriveTarget = arDriveAnonymousFactory({ arweave: arweaveTarget });

        const entityDriveId = new EntityID(driveId);

        const driveRef = await arDriveRef.getPublicDrive({ driveId: entityDriveId });
        const driveTarget = await arDriveTarget.getPublicDrive({ driveId: entityDriveId });

        const contentsRef = await arDriveRef.listPublicFolder({ folderId: driveRef.rootFolderId, maxDepth: 100, includeRoot: true });
        const contentsTarget = await arDriveTarget.listPublicFolder({ folderId: driveTarget.rootFolderId, maxDepth: 100, includeRoot: true });

        // Sort contents by name
        contentsRef.sort((a, b) => a.entityId.toString().localeCompare(b.entityId.toString()));
        contentsTarget.sort((a, b) => a.entityId.toString().localeCompare(b.entityId.toString()));

        if (debug) {
          console.log('Reference drive:', driveRef);
          console.log('Target drive:', driveTarget);
          console.log('Reference contents:', contentsRef);
          console.log('Target contents:', contentsTarget);
        }

        // check items in each collection for duplicates as well as missing items
        const [refIds, duplicates] = contentsRef.reduce((acc, item) => {
          const [ids, dupes] = acc;
          const entityId = item.entityId.toString();
          if (ids.has(entityId)) {
            dupes.add(entityId);
          } else {
            ids.add(entityId);
          }
          return acc;
        }, [new Set<string>(), new Set<string>()]);

        const [targetIds, targetDupes] = contentsTarget.reduce((acc, item) => {
          const [ids, dupes] = acc;
          const entityId = item.entityId.toString();
          if (ids.has(entityId)) {
            dupes.add(entityId);
          } else {
            ids.add(entityId);
          }
          return acc;
        }, [new Set<string>(), new Set<string>()]);

        const missingIds = new Set([...refIds].filter((id) => !targetIds.has(id)));
        const extraIds = new Set([...targetIds].filter((id) => !refIds.has(id)));

        fs.writeFileSync('missing-ids.json', JSON.stringify([...missingIds], null, 2));
        fs.writeFileSync('extra-ids.json', JSON.stringify([...extraIds], null, 2));
        fs.writeFileSync('duplicate-ids.json', JSON.stringify([...duplicates], null, 2));
        fs.writeFileSync('target-duplicate-ids.json', JSON.stringify([...targetDupes], null, 2));

        // console.log('Missing IDs:', missingIds);
        // console.log('Extra IDs:', extraIds);
        // console.log('Duplicate IDs:', duplicates);
        // console.log('Target duplicate IDs:', targetDupes);

        // JSON check
        const refJson = JSON.stringify(contentsRef, null, 2);
        const targetJson = JSON.stringify(contentsTarget, null, 2);

        console.log(`Reference JSON length: ${refJson.length}`);
        console.log(`Target JSON length: ${targetJson.length}`);

        // write reference.json and target.json files
        fs.writeFileSync('reference.json', refJson);
        fs.writeFileSync('target.json', targetJson);

        const MAX_DIFF_SIZE = 1000000; // 1MB limit for diff computation

        if (refJson.length > MAX_DIFF_SIZE || targetJson.length > MAX_DIFF_SIZE) {
          console.log('JSON sizes too large for detailed diff. Contents likely differ.');
          return;
        }

        if (refJson === targetJson) {
          console.log('Drive contents match.');
        } else {
          console.log('Drive contents differ:');
          console.log('Starting diff computation...');
          const patch = createPatch('drive-contents', refJson, targetJson);
          console.log('Diff computation completed.');
          console.log(patch);
        }
      } catch (error) {
        console.error('Error comparing drives:', (error as Error).message, error);
      }
    });

  return command;
}
