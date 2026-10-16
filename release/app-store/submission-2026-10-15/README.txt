PipPipGo — App Store submission images
Prepared October 15, 2026. English (en-US).

UPLOAD THESE PNGS
iphone-medium: 6 native iPhone 16 Pro screenshots, 1206 x 2622.
iphone-large: 6 additional native iPhone 16 Pro Max screenshots, 1320 x 2868.
ipad-13: 6 native iPad Pro 13-inch screenshots, 2064 x 2752.
Use the numbered order within each group. Do not upload this gallery or contact sheets.

APP ICON
app-icon/AppIcon-1024.png is the existing production 1024 x 1024 RGB icon.
The app icon is normally delivered through the app build's asset catalog.
App-preview videos and promotional artwork are optional and are not included.
This package targets the iOS/iPadOS app, not separate Mac, Watch, TV or Vision apps.

CAPTURE AND VALIDATION
Native portrait simulator captures from the current source views. No image was
resized, stretched, retouched or composited for upload. Fully opaque alpha
channels were removed losslessly; all upload PNGs are RGB. Dimensions and hashes
are listed in assets.json. Apple Maps attribution remains visible.

An isolated screenshot-only build uses com.pippipgo.screenshots. Fictional
profiles, trips, conversations, translations and a sample Santa Monica tour are
injected into actual app views. Native modal presentation is retained for tour
screens. Public Santa Monica map tiles and Apple route previews may load from
Apple; no real traveler data or live backend/OpenAI requests were used. The
capture shell opens existing screens directly and suppresses Dev badges. It is
not shipped and does not prove provider/device acceptance or release readiness.
No release build number was assigned and no App Store upload was performed.

Before submission, pair these images with a build containing the depicted UI.
Dev/Prod backend rollout for area/activity tour support remains separate.

REQUIREMENTS CHECKED
https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
https://developer.apple.com/help/app-store-connect/manage-app-information/add-an-app-icon

REPRODUCE
Run capture/prepare.py, build the returned isolated project with Dev for arm64
simulator and PRODUCT_BUNDLE_IDENTIFIER=com.pippipgo.screenshots, then run
capture/capture.py BUILD_DIRECTORY SIMULATOR_UUID SIZE_GROUP for each device.
Run capture/package.py after captures finish (requires Pillow).
