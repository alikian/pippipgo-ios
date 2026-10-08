# PipPipGo — traveler-intelligence rebuild

## Authoritative scope

The current September 28, 2026 scope is the [simple travel organizer](docs/simple-travel-organizer.md) and [roadmap](ROADMAP.md): traveler profile, companions and multi-destination trips with hotels and plane/train/car transport. This supersedes the September 27 traveler-intelligence requirements as the active product scope. Preserve the historical requirements and implementation evidence.

Preserve Google/Cognito authentication, ECS/DynamoDB, account ownership and existing data. Keep AI credentials and the configured OpenAI model, while the core organizer works without AI calls. Optional Ask Pip uses backend `prompt.md`; chat messages/history and the traveler profile may be sent to OpenAI, not saved companions or trips. Chat can revise discussed plans but cannot silently modify organizer data. Never infer sensitive needs.

The latest user-selected model is OpenAI GPT-6 Luna (selected September 29, 2026) through the direct OpenAI Responses API. Use a server-side
OpenAI API key from Secrets Manager or the local environment; no provider credentials belong in the iOS bundle. Do not substitute
a model without user instruction. Record model agreement/access, IAM deployment, live inference,
mocked tests and physical-device acceptance separately.

Live voice was requested September 28, 2026: use `gpt-live-1` for Talk to Pip, with GPT-6 Luna for Responses delegation and typed chat. Keep voice credentials on the backend; audio is transient. At the September 29 admin-viewer request, the backend now retains future typed/voice transcripts and exact available LLM context for the read-only admin viewer; previous voice sessions cannot be recovered. Live voice includes saved trips and companions as read-only context (requested September 29, 2026), including each trip’s selected companions. See `docs/live-voice.md` for rollout and acceptance evidence.

## Project time tracking

Maintain one identical `TIME_LOG.md` in both repositories. Capture session start/end and known
pauses, contributor and milestone. Count cross-repository work only once. Codex elapsed session
time is not human labor. Keep estimates and unknown historical time separate. Never invent exact
durations or create a scheduled time-tracking automation. Mirror roadmap milestone updates.

## Engineering rules

Read the other repository's AGENTS.md before modifying it. Preserve server-derived ownership,
immutable retry body/key/version, explicit conflict review, account-switch reset/late-response
fences, account-deletion disable markers and retained AWS data. New journey/memory/traveler records
are separate from legacy product records. Legacy data is retained, not automatically migrated.
Manage AWS infrastructure with the backend CloudFormation templates. Coordinate app/API rollout;
the simplified app requires `/v1/travel-organizer` before device rollout.

Backend checks: `uv run pytest -q`, `uv run ruff check app scripts tests`, and
`uv run ruff format --check app scripts tests`. iOS uses Local/Dev/Prod schemes; run relevant
simulator tests and signed builds. Mocked tests/builds do not prove live provider or device acceptance.
Use the multi-destination acceptance scenario in docs/simple-travel-organizer.md for the active scope. Prior AI/location/hardware milestones are deferred.

## Retained authentication and infrastructure references

- Display the app name as `PipPipGo` in all user-facing UI, app display names, and documentation. Use lowercase `pippipgo` for repository names, checkout paths, public domains and new documentation examples. When documenting existing technical identifiers, Xcode project/scheme names, bundle IDs, URL schemes, environment variables or infrastructure resources, use their exact configured spelling; do not imply a runtime rename through documentation edits. The requested public domain is now `pippipgo.com`; domain migration is deployed at `auth-dev.pippipgo.com`.
- The user owns `pipgogo.com` and `pippipgo.com`; the latter is registered at GoDaddy and delegated to AWS Route 53 zone `Z04005221I5Q1A2V5ZO9R`. Active sign-in domain: `https://auth-dev.pippipgo.com`. The certificate, Google redirect, and new custom domain are deployed. The old custom sign-in domain was removed; the AWS prefix domain remains available. See backend `infra/auth-dev-migration.md` for the current cutover and `infra/pippipgo-migration.md` for the historical migration.
- The Cognito custom sign-in domain is `https://auth-dev.pippipgo.com`, deployed through CloudFormation. Historical Step 1 verification on the old domain passed: iPhone sign-in, session restoration, refresh after expiry and logout; live Chrome two-account trip isolation and refresh-token revocation. Evidence and test boundaries are recorded in backend `docs/auth-verification.md`.
- Use `https://auth-dev.pippipgo.com` for new sign-in, token, and logout requests. The original hosted domain remains available for rollback:
  `https://pipgogo-e771ebb0-b949-11f1-8d17-06798145e65d.auth.us-west-2.amazoncognito.com`.
- Development API: `https://api-dev.pippipgo.com`, deployed through the existing CloudFormation hosting/delivery stacks. The old `dev.pippipgo.com` alias was removed. iOS Dev, the admin viewer and deployment scripts use the new API hostname; Local still uses the Mac backend.
- The Cognito user pool is `us-west-2_qPlEDatlA`; the public app client ID is `5ungc4grbiid7de7rjbh0jn2ff`.
- A custom hosted domain does not change the JWT issuer: `https://cognito-idp.us-west-2.amazonaws.com/us-west-2_qPlEDatlA`.
- User-requested iOS rename (September 30): source now uses `pippipgo.xcodeproj`, `com.pippipgo.ios` and `pippipgo://auth/callback` / `pippipgo://auth/logout`. User-approved Apple registration/App Store provisioning and additive Cognito callback deployment completed September 30; both environments accept old/new redirects. New-product Xcode Cloud enrollment and physical-device OAuth acceptance remain pending. Keep legacy `pipgogo://` callbacks for installed apps; see iOS `docs/ios-rename.md`. Historical AWS resource identifiers remain unchanged.

## Custom-domain implementation notes

- Manage AWS infrastructure through the backend CloudFormation templates so it remains reproducible.
- Cognito custom domains require an ACM certificate in `us-east-1`, even though this user pool is in `us-west-2`, plus DNS validation and a DNS record pointing to Cognito's CloudFront target.
- Verify the parent domain has the DNS A record Cognito requires. Do not replace existing website or mail DNS records to satisfy this requirement.
- Add the custom domain's `/oauth2/idpresponse` URL to the Google Web OAuth client's authorized redirects before switching sign-in traffic.
- Coordinate the Cognito hosted URL in the backend login-test configuration and iOS app configuration; verify Google sign-in, code exchange, refresh, logout, and backend token verification after migration.
- Never place Google client secrets or AWS credentials in source files or the iOS app. The Google secret lives in Secrets Manager at `pipgogo/dev/google-oauth`.
- Active DNS: `pippipgo.com` is registered at GoDaddy and delegated to Route 53 zone `Z04005221I5Q1A2V5ZO9R`. Active certificate stack `pippipgo-auth-dev-certificate` in `us-east-1` manages the `auth-dev.pippipgo.com` certificate. Retained stack `pippipgo-auth-certificate` manages the previous certificate and root A alias to the public website (`d75zotckwfi5s.cloudfront.net`), configured through `ParentWebsiteDomainName`. The parent A record remains a Cognito prerequisite. Public React pages are live at `https://pippipgo.com` and `/privacy`; infrastructure is in backend `infra/web-hosting.yaml` and deployment evidence is in `infra/web-hosting.md`. Coordinate future website DNS changes with the retained root-record stack. The old `pipgogo-auth-certificate` stack and `pipgogo.com` zone remain retained for recovery.

Reference: https://docs.aws.amazon.com/cognito/latest/developerguide/cognito-user-pools-add-custom-domain.html

## iOS references

Backend project: `/Users/alikianzadeh/git/pippipgo-backend`. Read its `docs/api.md`, `docs/deployment.md`, and `docs/v1-scope.md` for the API contract and current scope. `Configurations/DevIdentity.xcconfig` supplies the custom hosted sign-in URL `https://auth-dev.pippipgo.com`. Rebuild/install the app to pick up this change.

## Dev/Prod isolation

Use CloudFormation `Environment=dev` or `prod`. Dev retains its existing pool/table/secrets. Prod must use `pippipgo-prod-foundation`, `pippipgo-prod-data`, its own Cognito/Google clients and `pippipgo/prod/*` secrets. Prod domains are `auth.pippipgo.com`, `api.pippipgo.com`, and `admin.pippipgo.com`. Prod is provisioned: pool `us-west-2_vZsutuirK`, public client `23sk8qfmpotjj40jbnl9tn33em`. Use backend `infra/prod-deployment.md` for evidence/launch limitations and `infra/environments.md` for reproducible setup. Google consent remains Testing. Prod Places/Routes/Weather now use a dedicated restricted Google key in `pippipgo/prod/google-places` (October 2, 2026); live backend tool checks passed with Prod credentials, while production phone retry remains pending. Prod OpenAI uses its own restricted key in `pippipgo/prod/openai`, within the existing PipPipGo OpenAI project; rotate before the console expiration date October 30, 2026. Live translation audio and GPT-6 Luna inference passed; physical-device acceptance remains separate. iOS Local/Dev use `Configurations/DevIdentity.xcconfig`; Prod uses a generated, ignored `ProdIdentity.xcconfig` and must never inherit Dev credentials. No root DNS migration or Dev data replacement is required.


## Deployment reporting and iOS build numbers

- Always explicitly mention when a change requires backend deployment. State whether it is still pending or has been completed, identify the environment, and mention any required backend-before-app rollout order.
- Before setting an iOS build number or preparing an app build, check the latest PipPipGo build number in Xcode Cloud and set the new build number to exactly that number plus one. Use the build number (`CFBundleVersion` / `CURRENT_PROJECT_VERSION`), not the marketing version. Do not rely on a stale local number or guess; if the current cloud number cannot be verified, report that limitation before claiming the build number is correct.

## Web app — October 4, 2026

The user requested full mobile-friendly web functionality: Prod is `https://pippipgo.com/app`; Dev is `https://dev.pippipgo.com/app`, a separately hosted web app. APIs remain api.pippipgo.com and api-dev.pippipgo.com. The previously removed Dev API alias is now reused solely for the Dev website. Preserve environment isolation and additive mobile/admin callbacks. See backend infra/web-hosting.md for rollout and acceptance boundaries.

## On-demand Full Test

When the user asks to run the **Full Test**, use `python3 scripts/full_test.py run` and `docs/full-test.md`. Never schedule it or run it solely because app code changed. Reuse its local Appium server/session/helper between runs. Explicit `teardown` is for requested cleanup or before rebuilding/reinstalling the tested app. Preserve real user data; report manual/test-account coverage separately. Do not equate automated navigation success with complete acceptance.
