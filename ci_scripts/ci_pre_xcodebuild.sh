#!/bin/sh
set -eu
: "${CI_XCODEBUILD_ACTION:?Missing Xcode Cloud action}"
# Test workers restore compiled artifacts without checking out the repository.
# Build settings were already prepared during build-for-testing.
if [ "$CI_XCODEBUILD_ACTION" = test-without-building ]; then
    exit 0
fi
: "${CI_PRIMARY_REPOSITORY_PATH:?Run this hook in Xcode Cloud}"
# Recreate overrides for each action so testability cannot leak into an archive.
"$CI_PRIMARY_REPOSITORY_PATH/ci_scripts/ci_post_clone.sh"
if [ "$CI_XCODEBUILD_ACTION" = archive ] && [ "$CI_XCODE_SCHEME" = Local ]; then
    echo "Cloud distribution archives must use the Dev or Prod scheme." >&2
    exit 1
fi
if [ "$CI_XCODE_SCHEME" = Prod ]; then
    case "$CI_XCODEBUILD_ACTION" in
        build-for-testing|test-without-building) testability=YES ;;
        *) testability=NO ;;
    esac
    printf '%s\n' "ENABLE_TESTABILITY = $testability" \
        >> "$CI_PRIMARY_REPOSITORY_PATH/Configurations/CIOverrides.xcconfig"
fi
