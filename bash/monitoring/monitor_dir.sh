#!/bin/bash

_DIR="$1"

# 'modify' as well
inotifywait -m -e create,delete "${_DIR}" | while read directory events filename; do
    if [[ "$events" == *"CREATE"* ]]; then
        echo "File created: $directory/$filename"
        # Add your actions for file creation here
    elif [[ "$events" == *"DELETE"* ]]; then
        echo "File deleted: $directory/$filename"
        # Add your actions for file deletion here
    fi
done
