#!/bin/sh
set -eu
: "${CI_XCODEBUILD_EXIT_CODE:?Missing Xcode Cloud result}"
[ "$CI_XCODEBUILD_EXIT_CODE" = 0 ] || exit "$CI_XCODEBUILD_EXIT_CODE"
[ "${CI_XCODEBUILD_ACTION:-}" = archive ] || exit 0
: "${CI_PRIMARY_REPOSITORY_PATH:?Missing repository path}"
: "${CI_ARCHIVE_PATH:?Missing cloud archive}"
: "${CI_BUILD_NUMBER:?Missing cloud build number}"
version=$(sed -n 's/^MARKETING_VERSION = //p' "$CI_PRIMARY_REPOSITORY_PATH/Configurations/Version.xcconfig")
"$CI_PRIMARY_REPOSITORY_PATH/scripts/verify_release.sh" \
    "$CI_ARCHIVE_PATH/Products/Applications/pippipgo.app" "$CI_BUILD_NUMBER" "$version" "$CI_XCODE_SCHEME"
