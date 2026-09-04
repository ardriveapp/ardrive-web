#!/usr/bin/env node

import { Command } from 'commander';
import { createDriveCompareCommand } from './commands/drive-compare';
import { createVerifyCommand } from './commands/verify';

const program = new Command();

program
  .name('ardrive-gql')
  .description('ArDrive GraphQL verification and comparison tool')
  .version('1.0.0');

// Add commands
program.addCommand(createVerifyCommand());
program.addCommand(createDriveCompareCommand());

program.parse();
