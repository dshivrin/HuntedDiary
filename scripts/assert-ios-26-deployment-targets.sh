#!/bin/sh

set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
project_file=${1:-"$script_dir/../TheHuntedDiary.xcodeproj/project.pbxproj"}

awk '
    BEGIN {
        expected_count = 8
        key_pattern = "^[[:space:]]*(IPHONEOS_DEPLOYMENT_TARGET(\\[[^]]+\\])?|\"IPHONEOS_DEPLOYMENT_TARGET(\\[[^]]+\\])?\")[[:space:]]*="
    }

    /IPHONEOS_DEPLOYMENT_TARGET/ {
        line = $0
        occurrences_on_line = gsub(/IPHONEOS_DEPLOYMENT_TARGET/, "&", line)
        occurrence_count += occurrences_on_line

        if (occurrences_on_line != 1 || line !~ key_pattern) {
            printf "error: %s:%d: could not parse IPHONEOS_DEPLOYMENT_TARGET occurrence: %s\n", FILENAME, FNR, $0 > "/dev/stderr"
            failed = 1
            next
        }

        sub(key_pattern, "", line)
        if (line !~ /^[[:space:]]*[^;]+;[[:space:]]*$/) {
            printf "error: %s:%d: could not parse IPHONEOS_DEPLOYMENT_TARGET occurrence: %s\n", FILENAME, FNR, $0 > "/dev/stderr"
            failed = 1
            next
        }

        sub(/;[[:space:]]*$/, "", line)
        sub(/^[[:space:]]*/, "", line)
        sub(/[[:space:]]*$/, "", line)

        if (line != "26.0") {
            printf "error: %s:%d: found unexpected value %s for IPHONEOS_DEPLOYMENT_TARGET\n", FILENAME, FNR, line > "/dev/stderr"
            failed = 1
        }
    }

    END {
        if (occurrence_count != expected_count) {
            printf "error: expected exactly %d IPHONEOS_DEPLOYMENT_TARGET assignments; found %d in %s\n", expected_count, occurrence_count, FILENAME > "/dev/stderr"
            failed = 1
        }

        if (failed) {
            exit 1
        }

        printf "Verified %d IPHONEOS_DEPLOYMENT_TARGET settings at 26.0.\n", occurrence_count
    }
' "$project_file"
