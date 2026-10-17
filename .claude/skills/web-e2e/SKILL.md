---
name: web-e2e
description: Test the ArDrive web app as a user would, in a real browser logged in with the team's test wallet, without spending. Use to test a pull request (`/web-e2e 2274`), to run the release checklist on staging (`/web-e2e release`), or whenever asked to check a change end to end in the browser.
---

# Test the web app in the browser

Argument: a PR number, or `release`. With neither, ask which.

`docs/WEB_E2E_TESTING.md` is the manual: rules, setup, running, recipes and
quirks. Read all of it before you start. Its rules beat anything here.

## 1. Check you can run

- `~/.config/ardrive-e2e/env` exists. Check with `test -f`; never open, print
  or copy it. If it's missing, stop and ask for the test wallet's credentials.
- `tool/web_e2e/node_modules` exists, or run `npm install` there.
- No other `launch.js` is running (`ps -eo pid,comm,args`). If one is, it may
  belong to another session: ask before stopping it.

## 2. Pick the build

- **A PR:** its preview. The URL is in the github-actions comment:
  `gh api repos/ardriveapp/ardrive-web/issues/<n>/comments --jq '.[] | select(.user.login=="github-actions[bot]") | .body'`.
  If the comment is missing or older than the PR's last commit, the preview
  isn't ready: say so and stop. A PR already merged into another branch can
  still be tested, if its preview matches its last commit.
- **`release`:** https://staging.ardrive.io.

## 3. Write the test plan before you test

For a PR:

1. Read the PR description and `gh pr diff <n>`.
2. List each change a user could see or feel.
3. For each change, cover:
   - its normal path;
   - every state the code distinguishes. Look for the branches in the diff:
     errors, empty, not enough balance, loading, cancel, retry, too big, free
     versus paid;
   - light and dark mode, where it's visual.
4. Add the journeys from the guide's release checklist that touch the same
   area, as regression checks.
5. Mark anything you can't test here, and why. For example: needs testnet
   credits, needs a real AR spend, or mobile only.

For `release`: the plan is the guide's release checklist, as it stands.

## 4. Run it

Follow the guide: start `launch.js` with `APP_URL`, run `login.js`, sync on a
new profile, then use `step.js`. Read every screenshot before the next click.
When something unexpected shows up (a different dialog, a jump to another
drive), record it as a finding and carry on.

## 5. Report

Reply with:

- **Build:** URL, and the commit it was built from.
- **Plan and results:** one row per plan item. Pass, fail or not tested, and
  the screenshot path. One line on what you saw when it isn't a pass.
- **Bugs found:** in this change, and separately anything outside its scope.
- **Spending:**
  - `BLOCKED` lines from `net.log`, if any;
  - `chaos_report.py` output, if any wallet-paid uploads ran;
  - the wallet's AR balance before and after (`node balance.js`).

Send the key screenshots to the requester. Post on the PR only if asked to.

## 6. Clean up

Stop what you started (`launch.js`, `chaos_gateway.py`, any web server) by
PID. Leave the browser profile in place: the next run reuses its login and
sync.
