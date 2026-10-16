# PipPipGo iOS CI/CD with Xcode Cloud

The user-requested rename changes the project and bundle ID. Complete the
[rename rollout](ios-rename.md) before reconnecting the workflow or distributing.

## Delivery policy

Use Xcode Cloud's included 25 compute hours per month initially. No paid plan was
purchased. Pull requests run simulator tests. Production releases archive the
`Prod` scheme, upload to App Store Connect, and distribute to an internal
TestFlight group. Submit a tested build for App Review deliberately and choose
manual public release. Uploading a build is not an App Store release.

Repository: `https://github.com/alikian/pippipgo-ios`
Project: `pippipgo.xcodeproj`; app target: `pippipgo`
Bundle ID: `com.pippipgo.ios`; signing team: `U47SMLD234`.

## Versioning

`Configurations/Version.xcconfig` is the single marketing-version source for
Local, Dev and Prod. It initially preserves `1.0`; change it intentionally for a
new release. `CURRENT_PROJECT_VERSION = 1` is the local fallback.

Xcode Cloud owns the increasing build counter. `ci_post_clone.sh` writes its
`CI_BUILD_NUMBER` into ignored `Configurations/CIOverrides.xcconfig`, so test
and archive builds use the same number. Nothing is committed by the build.
For example, cloud builds 42 and 43 produce `1.0 (42)` and `1.0 (43)`.
Local Xcode builds do not increment a counter. Let cloud builds own distributed
build numbers; do not upload a local build with a number already used by Cloud.

Before the first upload, inspect existing builds in App Store Connect. Under
Xcode Cloud → Settings → Build Number, set Next Build Number above the highest
already uploaded number for the current version. This account state has not been
inspected. Do not assume `1` is still available.

## One-time activation in Xcode

The files in this repository are build hooks, not an activated hosted workflow.
Apple's initial Xcode Cloud enrollment is done through Xcode. No Apple credentials,
distribution certificates, App Store Connect API keys or AWS access keys are needed
in these scripts.

1. Sign in to Xcode with the Apple Developer account for team `U47SMLD234`.
   Confirm the App Store Connect app record uses `com.pippipgo.ios`.
2. Publish/merge the CI changes into the branches being built. Open
   `pippipgo.xcodeproj`, select `Prod`, and choose Product → Xcode Cloud →
   Create Workflow. Confirm the product/team and authorize access to the
   `alikian/pippipgo-ios` GitHub repository when Apple requests it.
3. Configure the two workflows below. Choose an available supported Xcode version
   and an iPhone simulator runtime compatible with the app's iOS 17 minimum.
   Record the chosen versions with the first successful cloud run; local validation
   used Xcode 27.0 (27A266a) and iOS 18.5.
4. Keep subscription usage at the included tier. Start with one simulator target
   per workflow and enable automatic cancellation of superseded builds if offered.
5. Run each workflow manually once. Verify test results, the signed archive,
   successful App Store Connect processing, and the installed TestFlight build.

### Workflow: Pull request checks

- Start condition: pull requests targeting `develop` or `main`.
- Scheme: `Dev`.
- Actions: Test on one available iPhone simulator, using scheme configuration.
- No archive or TestFlight post-action. No production identity variable needed.
- Existing unit tests use mocks; this does not prove live backend/device acceptance.

### Workflow: Production TestFlight

- Start condition: changes to `main`, plus manual runs. `develop` stays development.
- Scheme: `Prod` for both Test and Archive; configuration: use scheme settings.
- Prod public identity is checked into `Configurations/Prod.xcconfig`; no workflow identity variable is required. If the legacy `PIPPIPGO_PROD_COGNITO_CLIENT_ID` variable remains set, it must match `23sk8qfmpotjj40jbnl9tn33em`.
- Actions: Test on one iPhone simulator; Archive for iOS with distribution set to
  **TestFlight and App Store** so the tested build remains eligible for App Review.
  Do not select an internal-testing-only distribution option for release candidates.
- Post-action: TestFlight Internal Testing, select the intended internal tester
  group, and run distribution only when all required actions succeed.
- Keep public release manual in App Store Connect. Do not add automatic App Review
  submission as part of this initial workflow.

The checked-in `Prod.xcconfig` contains only the verified public Cognito client ID. A missing, development or unexpected identity stops the build; generated `ProdIdentity.xcconfig` is no longer included.
The hooks reject Local cloud archives. Dev archives are allowed for development TestFlight testing and validate the Dev API, identity and display name; Prod archives validate Production configuration. Production unit-test actions enable
`@testable` support; archive actions explicitly disable it. The post-archive hook
checks the actual app plist for the Prod API, Prod authentication identity, bundle
ID, display name, version/build and absence of transport exceptions. A failure
must keep the workflow failed and prevent TestFlight distribution.

## First-release acceptance

- Verify cloud build numbers increase and the TestFlight version/build match.
- Verify the Prod archive targets `https://api.pippipgo.com` and
  `https://auth.pippipgo.com`, never development identity or storage.
- Complete the physical-device scenario in `docs/simple-travel-organizer.md`,
  including sign-in, account isolation, organizer operations and conflict handling.
- Follow backend `infra/prod-deployment.md` for launch limitations: Google consent
  is still Testing, the Prod Places key is not configured, and production phone
  acceptance is separate from mocked tests and provider inference checks.
- Complete store metadata, screenshots, privacy disclosures, review access and
  export-compliance answers before submitting for App Review.

## Local verification

```sh
python3 scripts/test_ci.py
xcodebuild test -project pippipgo.xcodeproj -scheme Prod \
  -destination 'platform=iOS Simulator,name=iPhone 16' ENABLE_TESTABILITY=YES
xcodebuild archive -project pippipgo.xcodeproj -scheme Prod \
  -destination 'generic/platform=iOS' -archivePath /tmp/PipPipGo-Prod.xcarchive
scripts/verify_release.sh /tmp/PipPipGo-Prod.xcarchive/Products/Applications/pippipgo.app 1 1.0
```

Use an installed simulator and an unused output path. For local production builds,
generate the public identity from backend `scripts/export_prod_ios_config.py` first.
The cloud hooks are intended for a disposable checkout; do not run them in your
normal checkout because they write ignored cloud-only configuration.

## Historical CI preparation evidence — before the iOS identity rename

The signed archive below used the former `com.pipgogo.ios` identity. It does not
prove signing or App Store availability for `com.pippipgo.ios`.

- Ten isolated hook tests passed, including missing/Dev identity, malformed build
  numbers, fresh checkout, test-to-archive testability reset, invalid archive
  metadata and failed-build handling.
- All 88 Prod simulator tests passed with explicit testability enabled.
- Eight configuration tests also passed in a fresh checkout using only the cloud
  hooks to enable testability, with the next build number `43`.
- Signed archive from a fresh temporary checkout passed: `1.0 (42)`, Prod API
  and Cognito identity verified, `ENABLE_TESTABILITY=NO`, and strict code-signature
  validation passed. This is a local Apple Development signature; cloud distribution
  signing and App Store validation remain unverified.
- Hosted workflow enrollment, cloud signing/upload, TestFlight delivery, existing
  App Store build-number inspection and physical-device acceptance remain pending.
  The computer-use runtime could not start because the configured workspace path
  `/Users/alikianzadeh/git/pipgogo-ios` is a symlink; the real checkout is
  `/Users/alikianzadeh/git/pippipgo-ios`. No Apple account setting was changed.

## Apple references

- [Configure the first workflow](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow)
- [Custom build hooks](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts)
- [Cloud environment variables](https://developer.apple.com/documentation/xcode/environment-variable-reference)
- [Cloud build numbering](https://developer.apple.com/documentation/xcode/setting-the-next-build-number-for-xcode-cloud-builds)
- [Distribution workflow](https://developer.apple.com/documentation/xcode/creating-a-workflow-that-builds-your-app-for-distribution)

## Prod email/password release — October 2, 2026

The sign-in chooser now supports Google or native Cognito username/password in Prod as well as Dev. `pippipgo-prod-foundation` was updated without replacing the pool/client. An isolated checkout of the authentication changes passed 93 Prod simulator tests and a signed archive with verified Prod metadata. The active Default cloud workflow was inspected and uses Prod for Build and Archive, the verified public client, App Store Connect distribution, and internal TestFlight group Pips. Email confirmation/recovery and device acceptance remain separate from form inspection and mocked tests. See backend `docs/email-password-signup.md` for infrastructure evidence.


### Development TestFlight

Select scheme `Dev` for a Dev archive. No `PIPPIPGO_PROD_COGNITO_CLIENT_ID` variable is required. The archive hook checks Dev API/authentication and `PipPipGo Dev` display name. Use internal testing distribution for Dev builds; select `Prod` for public release candidates.

## XCUITest simulator setup — October 15, 2026

`pippipgoUITests` is an XCUITest target exercising the actual signed-out app:
welcome actions, entering the guest disclosure, cancelling it, and reopening it.
Screenshots are attached to each UI test result. These tests do not sign in,
change organizer data, or call AI. Use a dedicated signed-out simulator.
Authenticated organizer UI coverage and real-device acceptance remain separate.

All shared schemes use the default `PipPipGo.xctestplan`, which includes the unit
and UI targets and disables parallel execution of each target. No test-only
app authentication bypass is added.

Live App Store Connect inspection confirmed the current `pippipgo` product is
already enrolled, with separate Dev and Prod workflows; the older pending
activation notes above are historical. Latest build observed before local
validation was 96. Local simulator validation used a command-line build override
of 97; the checked-in release number was not changed. Cloud builds continue to
use `CI_BUILD_NUMBER` from Apple's counter.

The Dev workflow now has a **required Test - iOS** action, scheme **Dev**, test
option **Use Scheme Setting**, destination **iPhone 16**, runtime **Latest from
Selected Xcode** (currently iOS 27.0). Its existing develop trigger and archive /
internal TestFlight configuration remain in place. Prod workflow is unchanged.
The new test target runs in hosted builds only after these repository changes
are available on the selected branch. Saving a workflow does not prove a cloud
run passed.

Local invocation (replace the destination with a dedicated simulator UUID and
verify the latest cloud number before assigning a build override):

```sh
xcodebuild test -project pippipgo.xcodeproj -scheme Dev \
  -testPlan PipPipGo -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -parallel-testing-enabled NO
```

No backend deployment is required for this test setup.

Validation: project plist and scheme/test-plan parsing passed; 13 CI hook tests
passed. On a dedicated iPhone 16 / iOS 18.6 simulator, 167 unit tests passed on
rerun. The first unit run had a transient failure in the existing
`organizerRetryFreezesBodyAndResetsSession` test; it was not removed or weakened.
An Apple test-runner Mach -308 crash required a fresh UI run. These are local
simulator results, not hosted-run or physical-device acceptance.
The corrected 2 XCUITests passed with zero failures; result bundle:
`/tmp/pippipgo-xcuitest-results-3` (temporary local artifact).

Hosted validation build **97** was started manually using the Dev workflow from
`codex/xcuitest-cloud`, commit `1cfb174`. Build URL:
https://appstoreconnect.apple.com/teams/e889b4eb-d539-4efa-9a6c-a1ad9fe29ef7/xcode-cloud/products/54c196ed-32dc-430b-8e5f-e299eb841cfc/builds/115fd622-b655-4fd5-9581-b8ea207d46a3/summary
Initial status was Queued; do not interpret this as a passing hosted test result.

Build 97 compiled the app and both test targets, but the simulator worker failed
before running tests: `CI_PRIMARY_REPOSITORY_PATH` is absent during
`test-without-building`. The pre-build hook now exits successfully for that phase,
using the already compiled artifacts instead of trying to regenerate source
configuration. A regression test reproduces the worker's missing checkout/build
variables; all 14 CI hook tests pass. No test assertion was disabled.
