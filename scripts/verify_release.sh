#!/bin/sh
# Usage: verify_release.sh /path/to/pippipgo.app expected-build expected-version
set -eu
[ "$#" -ge 3 ] && [ "$#" -le 4 ] || { echo "Usage: $0 app-path build-number marketing-version [Dev|Prod]" >&2; exit 1; }
case "${4:-Prod}" in
    Prod) environment=prod; display_name=PipPipGo; api=https://api.pippipgo.com; auth=https://auth.pippipgo.com; client=23sk8qfmpotjj40jbnl9tn33em ;;
    Dev) environment=dev; display_name='PipPipGo Dev'; api=https://api-dev.pippipgo.com; auth=https://auth-dev.pippipgo.com; client=5ungc4grbiid7de7rjbh0jn2ff ;;
    *) echo "Archive scheme must be Dev or Prod." >&2; exit 1 ;;
esac
plist="$1/Info.plist"
check() {
    actual=$(/usr/libexec/PlistBuddy -c "Print :$1" "$plist")
    if [ "$actual" != "$2" ]; then
        echo "Release validation failed: $1 does not match the expected value." >&2
        exit 1
    fi
}
check CFBundleIdentifier com.pippipgo.ios
check CFBundleURLTypes:0:CFBundleURLSchemes:0 pippipgo
check CFBundleDisplayName "$display_name"
check AppEnvironment "$environment"
check BackendBaseURL "$api"
check CognitoDomain "$auth"
check CognitoClientID "$client"
check CFBundleVersion "$2"
check CFBundleShortVersionString "$3"
if /usr/libexec/PlistBuddy -c 'Print :NSAppTransportSecurity' "$plist" >/dev/null 2>&1; then
    echo "Release validation failed: unexpected transport exceptions." >&2
    exit 1
fi
# Check the built plist so missing orientation metadata fails before distribution.
python3 - "$plist" <<'PYTHON'
import plistlib
import sys
with open(sys.argv[1], "rb") as source:
    info = plistlib.load(source)
required = {
    "UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown",
    "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight",
}
phone = info.get("UISupportedInterfaceOrientations", [])
ipad = info.get("UISupportedInterfaceOrientations~ipad", phone)
if not phone or not required.issubset(ipad):
    sys.exit("Release validation failed: missing supported orientations for iPad multitasking.")
PYTHON
echo "Verified PipPipGo $3 ($2), $environment API and matching identity."
