#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_file=${1:-"$script_dir/../TheHuntedDiary.xcodeproj/project.pbxproj"}

awk '
    BEGIN {
        expected_count = 6
        key_pattern = "^[[:space:]]*TARGETED_DEVICE_FAMILY[[:space:]]*="
    }

    /TARGETED_DEVICE_FAMILY/ {
        line = $0
        occurrences_on_line = gsub(/TARGETED_DEVICE_FAMILY/, "&", line)
        occurrence_count += occurrences_on_line

        if (occurrences_on_line != 1 || line !~ key_pattern) {
            printf "error: %s:%d: could not parse TARGETED_DEVICE_FAMILY occurrence: %s\n", FILENAME, FNR, $0 > "/dev/stderr"
            failed = 1
            next
        }

        sub(key_pattern, "", line)
        if (line !~ /^[[:space:]]*[^;]+;[[:space:]]*$/) {
            printf "error: %s:%d: could not parse TARGETED_DEVICE_FAMILY occurrence: %s\n", FILENAME, FNR, $0 > "/dev/stderr"
            failed = 1
            next
        }

        sub(/;[[:space:]]*$/, "", line)
        sub(/^[[:space:]]*/, "", line)
        sub(/[[:space:]]*$/, "", line)
        if (line ~ /^".*"$/) {
            sub(/^"/, "", line)
            sub(/"$/, "", line)
        }

        if (line != "1,2") {
            printf "error: %s:%d: found unexpected value %s for TARGETED_DEVICE_FAMILY\n", FILENAME, FNR, line > "/dev/stderr"
            failed = 1
        }
    }

    END {
        if (occurrence_count != expected_count) {
            printf "error: expected exactly %d TARGETED_DEVICE_FAMILY assignments; found %d in %s\n", expected_count, occurrence_count, FILENAME > "/dev/stderr"
            failed = 1
        }

        if (failed) {
            exit 1
        }

        printf "Verified %d TARGETED_DEVICE_FAMILY settings at 1,2.\n", occurrence_count
    }
' "$project_file"
