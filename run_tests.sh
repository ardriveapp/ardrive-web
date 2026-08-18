#!/bin/bash
# Runs the main-app test suite in this worktree via the pinned Windows Flutter SDK.
# Usage: bash run_tests.sh [extra flutter test args...]
FL='C:\Users\phili\fvm\versions\3.19.6\bin\flutter.bat'
WT='C:\source\ardrive-web\.claude\worktrees\sharing'
/mnt/c/Windows/System32/cmd.exe /c "cd /d $WT && $FL test $*" 2>&1
