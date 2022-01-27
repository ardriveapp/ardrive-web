#!/bin/bash
if [ $(git diff @{u}...HEAD ./lib/models/tables| wc -l) -eq "0" ]; then
    echo "  🟢 Database tables are unchanged."
    exit 0;
else
    if [ $(git diff @{u}...HEAD ./lib/models/database/database.dart | wc -l) -eq "0" ]; then
        echo "  🔴 Database version not updated. Quit"
        exit 1;
    else
        echo "  🟢 Database version updated."
        exit 0;
    fi
fi
