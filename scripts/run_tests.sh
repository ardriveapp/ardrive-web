#!/bin/bash

set -e

echo "Running tests in main app"
flutter pub get
flutter test

echo "Searching for packages..."
for dir in packages/*; do
  if [ -d "$dir" ]; then
    echo "Checking $dir"
    if [ -d "$dir/test" ]; then
      echo "Running tests in $dir"
      cd $dir
      flutter pub get
      flutter analyze
      flutter test
      cd ../..
    else
      echo "No test directory found in $dir, skipping tests"
    fi
  fi
done