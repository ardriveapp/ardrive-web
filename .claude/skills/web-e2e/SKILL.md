---
name: web-e2e
description: Test the ArDrive web app as a user would, in a real browser logged in with the team's test wallet, without spending. Use whenever asked to check something end to end in the browser - the current branch (`/web-e2e`), a pull request or branch, a link, an area of the app ("the upload dialog"), or the release checklist on staging (`/web-e2e release`).
---

# Test the web app in the browser

Whatever follows `/web-e2e` says what to test, and none of it is required.
No ticket or PR number is needed.

| Given | Test |
|---|---|
| Nothing | The current branch's changes against `dev` |
| A pull request (number or link) | That PR's changes |
| A branch name | That branch's changes against `dev` |
| A link to a build | Whatever the request names, on that build |
| `release` | The release checklist, on staging |
| Words ("the upload dialog", "sharing") | That area of the app, on staging |

Only ask when the request could mean two different things.

`docs/WEB_E2E_TESTING.md` is the manual: rules, setup, running, recipes and
quirks. Read all of it before you start. Its rules beat anything here.

## 1. Check you can run

- `~/.config/ardrive-e2e/env` exists. Check with `test -f`; never open, print
  or copy it. If it's missing, stop and ask for the test wallet's credentials.
- `tool/web_e2e/node_modules` exists, or run `npm install` there.
- No other `launch.js` is running (`ps -eo pid,comm,args`). If one is, it may
  belong to another session: ask before stopping it.

## 2. Pick the build

- **A branch, or nothing:** if the branch has an open pull request, use that
  PR's preview (below). Otherwise build it locally and serve it, as the guide
  describes.
- **A PR:** its preview. The URL is in the github-actions comment:
  `gh api repos/ardriveapp/ardrive-web/issues/<n>/comments --jq '.[] | select(.user.login=="github-actions[bot]") | .body'`.
  If the comment is missing or older than the PR's last commit, the preview
  isn't ready: say so and stop. A PR already merged into another branch can
  still be tested, if its preview matches its last commit.
- **`release`, or an area of the app:** https://staging.ardrive.io.
- **A link:** that build.

## 3. Write the test plan before you test

For a change (a PR, a branch, or the current branch):

1. Read what it's for (the PR description, or the commit messages) and its
   diff (`gh pr diff <n>`, or `git diff origin/dev...<branch>`).
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

For an area of the app: read the code behind it, list what a user can do
there and the states it distinguishes, and add the checklist journeys that
touch it.

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
