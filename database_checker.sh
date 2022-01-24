#!/bin/bash
if [ $(git status --porcelain ./lib/models/tables | wc -l) -eq "0" ]; then
    echo "  🟢 Database tables are unchanged."
else
    if [ $(git status --porcelain ./lib/models/database/database.dart | wc -l) -eq "0" ]; then
        echo "  🔴 Database version not updated. Quit"
    else
        echo "  🟢 Database version updated."
    fi
    exit 1
fi
