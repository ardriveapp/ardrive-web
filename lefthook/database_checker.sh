#!/bin/bash
if [ $(git diff @{u}...HEAD ./lib/models/tables | wc -l) -eq "0" ]; then
    echo "  🟢 Database tables are unchanged."
    exit 0
else
    previousSchemaPattern='([-][[:space:]]*int get schemaVersion =>[[:space:]]*[[:digit:]]+)'
    currentSchemaPattern='([+][[:space:]]*int get schemaVersion =>[[:space:]]*[[:digit:]]+)'

    databaseSchemaDiff=$(git diff @{u}...HEAD ./lib/models/database/database.dart)

    [[ "${databaseSchemaDiff}" =~ $previousSchemaPattern ]]
    previousSchemaRegexMatch=(${BASH_REMATCH[1]//[[:space:]]/ })
    previousVersion=${previousSchemaRegexMatch[${#previousSchemaRegexMatch[@]} - 1]}
    # Force integer conversion
    previousVersion=$(($previousVersion + 0))
    [[ "${databaseSchemaDiff}" =~ $currentSchemaPattern ]]
    currentSchemaRegexMatch=(${BASH_REMATCH[1]//[[:space:]]/ })
    currentVersion=${currentSchemaRegexMatch[${#currentSchemaRegexMatch[@]} - 1]}
    # Force integer conversion
    currentVersion=$(($currentVersion + 0))

    if [ $currentVersion -lt $previousVersion ]; then
        echo "  🔴 Database version not updated. Quit"
        exit 1
    else
        echo "  🟢 Database version updated from ${previousVersion} to ${currentVersion}."
        exit 0
    fi
fi
