# PipPipGo iOS identity rename — September 30, 2026

The user explicitly requested replacing the remaining iOS `pipgogo` names with
`pippipgo` during App Store/Xcode Cloud setup. The visible name remains **PipPipGo**
(with Local/Dev suffixes for those environments).

## Renamed source

- Project: `pippipgo.xcodeproj`; module/target/product: `pippipgo` / `pippipgo.app`.
- Source/test folders: `pippipgo`, `pippipgoTests`; app entry: `pippipgoApp`.
- Bundle IDs: `com.pippipgo.ios` and `com.pippipgo.ios.tests`.
- Build settings: `PIPPIPGO_*`, including the generated public Prod identity.
- Native callback/logout: `pippipgo://auth/callback`, `pippipgo://auth/logout`.
- Keychain namespace: `com.pippipgo.ios.authentication`, still separated by environment.
- Shared Local/Dev/Prod schemes, CI hooks, archive checks and active setup docs updated.

Xcode's recent test-signing team and scheme edits were preserved. Its hardcoded
“PipPipGo Dev” display name on all configurations was restored to per-environment
configuration so Prod displays PipPipGo and Local displays PipPipGo Local.

## Compatibility and evidence boundaries

A new bundle ID is a separate iOS app installation, not an update of the old app.
Old installed apps and their local data are not deleted. Sign in again in the new
app; saved backend data remains tied to the existing Cognito account in the same
environment. No users, tables, client IDs or provider secrets were changed.

Backend `infra/persistence.yaml` adds the new callback/logout alongside the
configured legacy URLs. The old `pipgogo://` URLs remain accepted for existing
installations. Existing AWS resource names and historical documentation are not
renamed. The backend exporter now emits the renamed iOS build-setting key.

The previous Xcode Cloud enrollment manifest is preserved under
`docs/archive/2026-09-30-pipgogo-xcode-cloud-manifest.json`. It belongs to the old
product; enroll the new project/product and let Xcode create its new manifest.
Do not invent or reuse cloud product IDs for the new bundle ID.

## Validation

- 88 Prod simulator tests and 10 CI safeguard tests passed.
- Unsigned Prod archive succeeded; actual archive bundle ID, display name, version,
  callback scheme, production API and public Cognito identity checked.
- Backend: 307 tests passed, one skipped; Ruff check and format passed.
- cfn-lint reports the existing W1030 warning for the optional certificate ARN's
  empty default; the same warning reproduces against the pre-change template.
- Initial unsigned validation did not establish Apple signing/registration. The
  approved follow-up below verifies these; full OAuth exchange, phone acceptance
  and TestFlight distribution remain unverified.

## Approved activation — completed September 30

The user explicitly approved Apple registration/provisioning and both Cognito
change-set executions after the initial automatic-review blocks.

- `pipgogo-dev-foundation` and `pippipgo-prod-foundation` reached UPDATE_COMPLETE.
  Both change sets modified only MobileClient callback/logout allowlists, without
  replacement. Existing user pools, clients, data and legacy URLs were retained.
- Live `/oauth2/authorize` redirected to Google for both `pipgogo://` and
  `pippipgo://` on both custom domains. Live `/logout` redirected to the exact
  corresponding native URL. Prod initially returned redirect_mismatch during
  propagation; the final checks passed for both schemes on both environments.
  These checks are not a full authenticated code exchange or physical-device test.
- Signed Prod archive and strict signature validation passed for `com.pippipgo.ios`.
- App Store distribution export succeeded locally. Its embedded profile is
  `iOS Team Store Provisioning Profile: com.pippipgo.ios`, with explicit application
  identifier `U47SMLD234.com.pippipgo.ios`, no device list and get-task-allow=false.
  This confirms Apple registered the explicit app ID and provisioned distribution.
- Local output: `/tmp/pippipgo-renamed-distribution/pippipgo.ipa` (temporary).
  The export did not upload a build, create an App Store Connect app record, or
  publish a release. Test-bundle registration was not required for the archive.

## Remaining rollout

1. Open `pippipgo.xcodeproj` after publishing this branch. Enroll the new product
   in Xcode Cloud, select shared scheme `Prod`, and configure the public production
   identity variable as described in `ios-ci-cd.md`. Let Xcode generate its new
   enrollment manifest; the old workflow refers to `pipgogo.xcodeproj`.
2. Create the App Store Connect record with display name **PipPipGo** and select
   registered bundle ID `com.pippipgo.ios` under signing team `U47SMLD234`.
3. Complete new-app device sign-in, refresh/logout and organizer acceptance, then
   configure archive/TestFlight distribution. Backend accounts remain unchanged;
   the new installation requires a fresh sign-in.

October 15 follow-up: live App Store Connect inspection confirms the renamed
`pippipgo` product is enrolled, with Dev and Prod workflows and latest observed
build 96. See `ios-ci-cd.md` for the added required Dev simulator Test action.
The earlier pending-enrollment checklist above is historical.
