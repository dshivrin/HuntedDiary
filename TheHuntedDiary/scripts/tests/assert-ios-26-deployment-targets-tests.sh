#!/bin/sh

set -eu

tests_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
assertion="$tests_dir/../assert-ios-26-deployment-targets.sh"
fixtures="$tests_dir/fixtures"
output=$(mktemp)
trap 'rm -f "$output"' EXIT

if ! "$assertion" "$fixtures/exactly-eight.pbxproj" >"$output" 2>&1; then
    cat "$output" >&2
    echo "error: exactly eight iOS 26 assignments should pass" >&2
    exit 1
fi
grep -F "Verified 8 IPHONEOS_DEPLOYMENT_TARGET settings at 26.0." "$output" >/dev/null

if "$assertion" "$fixtures/conditional-obsolete-override.pbxproj" >"$output" 2>&1; then
    echo "error: quoted conditional obsolete override unexpectedly passed" >&2
    exit 1
fi
grep -F 'found unexpected value 18.0' "$output" >/dev/null
grep -F 'expected exactly 8 IPHONEOS_DEPLOYMENT_TARGET assignments; found 9' "$output" >/dev/null

if "$assertion" "$fixtures/incomplete-seven.pbxproj" >"$output" 2>&1; then
    echo "error: incomplete seven-assignment fixture unexpectedly passed" >&2
    exit 1
fi
grep -F 'expected exactly 8 IPHONEOS_DEPLOYMENT_TARGET assignments; found 7' "$output" >/dev/null

if "$assertion" "$fixtures/unparseable-occurrence.pbxproj" >"$output" 2>&1; then
    echo "error: unparseable deployment-setting occurrence unexpectedly passed" >&2
    exit 1
fi
grep -F 'could not parse IPHONEOS_DEPLOYMENT_TARGET occurrence' "$output" >/dev/null

echo "Verified deployment assertion accepts exact coverage and rejects conditional, incomplete, and unparseable settings."
