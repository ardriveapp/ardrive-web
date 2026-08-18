#!/bin/bash
set -e
FL='C:\Users\phili\fvm\versions\3.19.6\bin\flutter.bat'
WT='C:\source\ardrive-web\.claude\worktrees\sharing'
run() { /mnt/c/Windows/System32/cmd.exe /c "cd /d $1 && $FL $2" 2>&1; }

echo "### 1/4 root pub get"
run "$WT" "pub get"
echo "### 2/4 ario_sdk pub get"
run "$WT\\packages\\ario_sdk" "pub get"
echo "### 3/4 ario_sdk codegen"
run "$WT\\packages\\ario_sdk" "pub run build_runner build --delete-conflicting-outputs"
echo "### 4/4 root codegen"
run "$WT" "pub run build_runner build --delete-conflicting-outputs"
echo "### SETUP DONE"
