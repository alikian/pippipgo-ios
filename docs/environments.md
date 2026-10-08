> Product-version note (September 27): this document retains operational or historical evidence. Legacy trip/check-in examples describe the previous release. See [traveler-intelligence delivery notes](traveler-intelligence.md) for the rebuilt product.

# Local, Dev and Prod builds

Choose **Local**, **Dev** or **Prod** in Xcode's scheme picker, choose a device,
then Run. A compact badge at the top of the app shows **Environment: Local**, **Environment: Dev** or **Environment: Production**,
including before sign-in. The localized label identifies the configured backend environment; it is not a live server-availability indicator. Each scheme uses its matching configuration for Run, Test, Profile,
Analyze and Archive. This is a build-time choice; switching requires rebuilding
and installing. The old `pippipgo` scheme and Debug/Release configuration names
have been replaced. The project, target and Swift module remain `pippipgo`.

| Scheme | Home-screen name | API base URL | Status |
| --- | --- | --- | --- |
| Local | PipPipGo Local | Simulator: `http://localhost:8765`; device: `http://192.168.0.208:8765` | Uses the Mac backend, existing Cognito and development DynamoDB |
| Dev | PipPipGo Dev | `https://api-dev.pippipgo.com` | Hosted Dev API deployed |
| Prod | PipPipGo | `https://api.pippipgo.com` | Hosted Prod deployed; generated identity configured |

All three now use bundle ID `com.pippipgo.ios` and native URLs `pippipgo://auth/callback` and `pippipgo://auth/logout`. Callback deployment and Apple registration/App Store provisioning are verified; see [rename rollout](ios-rename.md).
They **replace one another** on a device, rather than installing side by side.
The new bundle ID installs separately from the old app and requires a fresh sign-in. Dev and Prod use separate Keychain
service names, so an installed build does not restore another environment's token
set. Browser Google sessions can still be shared.

## Configuration files

- `Configurations/Local.xcconfig`: edit `PIPPIPGO_LAN_HOST` when the Mac address
  changes, and update the matching `NSExceptionDomains` key in
  `pippipgo/Resources/Debug-Info.plist`. Xcode expands values but not plist dictionary
  keys. The simulator override continues to use localhost.
- `Configurations/Dev.xcconfig`: development API origin and app label.
- `Configurations/Prod.xcconfig`: production API origin and app label.
- `Configurations/Common.xcconfig`: shared URL syntax and version includes; no authentication identity.
- `Configurations/DevIdentity.xcconfig`: retained Dev Cognito identity, included by Local and Dev.
- `Configurations/ProdIdentity.xcconfig`: ignored/generated public Prod client ID. Generate it using backend `scripts/export_prod_ios_config.py` after provisioning the isolated Prod foundation. Never put secrets in these files.

Local includes the local-network usage description and narrowly scoped HTTP
exceptions. Dev and Prod use the hosted plist with no HTTP exception or local
network permission description. Runtime validation rejects HTTP or another
host for Dev/Prod; there is no automatic fallback to the Mac backend.

Local and Dev share the retained development foundation. Prod uses `auth.pippipgo.com`
and requires a separate Cognito client. It intentionally fails configuration validation
until the real Prod identity is generated; there is no Dev fallback. See backend
`infra/environments.md` for resource setup and the export command. Do not distribute
an unconfigured Prod build. Historical build evidence below predates this separation.

## Run and verify

```sh
xcodebuild test -project pippipgo.xcodeproj -scheme Local \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
xcodebuild build -project pippipgo.xcodeproj -scheme Dev \
  -destination 'generic/platform=iOS'
xcodebuild archive -project pippipgo.xcodeproj -scheme Prod \
  -destination 'generic/platform=iOS' -archivePath /tmp/PipPipGo-Prod.xcarchive
```

Use an available simulator name/ID and the configured signing team. Prod uses
optimized code with testability disabled for normal builds; if running its unit
tests, pass `ENABLE_TESTABILITY=YES` explicitly for that test build. Local and Dev
use debug compilation settings. Schemes preserve their API selection during
Archive; archiving Local does not turn it into Prod.

Local phones need the Mac backend running, the same LAN and local-network
permission. Start the existing Cognito/DynamoDB harness from the backend checkout:

```sh
uv run python -m scripts.login_test --profile alikianus --region us-west-2 --lan-ip 192.168.0.156
```

## Hosted API prerequisites

Dev HTTPS hosting is deployed on standard ECS Fargate (September 27, 2026);
Prod hosting is deployed; Google is test-user restricted and provider/device acceptance remains pending. Complete device acceptance against Dev.
The client appends existing `/v1/...` API paths, for example
`https://api-dev.pippipgo.com/v1/me` and `https://api.pippipgo.com/v1/me`.
The production API has its own subdomain; the root domain remains available for the
planned website. No parent DNS replacement is needed. Prod infrastructure and live sign-in/API isolation are verified; build configuration
alone does not prove physical-device acceptance.

Before release, verify the chosen identity/data environment and Google sign-in,
refresh, logout, account isolation and trip flows on a physical phone without
the Mac backend. Build/tests alone do not constitute hosted environment acceptance.


## Validation — September 26, 2026

110 tests passed in Local; the 7 environment tests also passed in Dev and Prod.
Prod unit tests explicitly enabled testability; its signed device build used normal
optimized settings. All three signed device builds passed. Inspection of their
built plists and signatures verified the exact backend origins, app labels, shared
Cognito configuration and Local-only HTTP exceptions. Every scheme action,
including Archive, selects its matching environment. These variants were not
installed on a physical phone in this session; hosted API acceptance remains open.

The next check is **5.2a — hosted Dev physical-device acceptance**. See the roadmap for
deployment and physical-device acceptance requirements.

The Dev build was installed on Ali’s iPhone 12 on September 27. Remote launch
reported the device locked; do not count installation as sign-in or trip acceptance.
Local and Dev share development accounts/data. Prod requires its own persistence
and matching Cognito settings before release. Both repositories default to `develop`.


Production was provisioned September 30. Generated public client `23sk8qfmpotjj40jbnl9tn33em` is configured locally; the signed Prod build and eight Prod simulator configuration tests pass. See backend `infra/prod-deployment.md`. No physical installation was performed. Independent Prod provider secrets still require keys.

Xcode Cloud setup, automatic build numbers and Prod identity generation in fresh checkouts are documented in [iOS CI/CD](ios-ci-cd.md).

October 8 environment-badge restoration: reused `BuildEnvironmentIndicator` at the
root above primary screens, including before sign-in. It reads the validated
`AppConfiguration.live.environment` and shows Local, Dev or Production with localized
labels. Signed Local build 30 installed after rechecking Cloud 29. Signing and three
catalog checks passed; Appium confirmed the Local badge in Pip, Profile, Translate
and Trips, and a Translate screenshot was inspected. Current Spanish selection
preserved. No backend deployment required. Full Test was not run.
