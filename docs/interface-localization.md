# Interface language — October 8, 2026

The existing `pip.language` preference drives the interface in all 13 requested
languages: Chinese, Japanese, Korean, Vietnamese, Filipino, Tagalog, Farsi, Turkish,
Arabic, Russian, Italian, French and English. Existing Spanish is retained as a
fourteenth interface choice. Translation conversation languages remain a separate
setting. The earlier seven-language pass is recorded below as historical evidence.

- Filled missing string-catalog translations, preserving all existing translations.
- Dynamic menu titles, profile destinations, voice/translation states, budget labels,
  errors and accessibility labels explicitly use localized keys.
- Strings constructed outside SwiftUI use the selected language's resource bundle
  and locale rather than the device's default language.
- Names, saved trip details, calendar entries and conversation content remain verbatim.
- Persian keeps the existing right-to-left layout. No account state or editor model
  is recreated to change languages.

New translations were drafted through the existing configured GPT-6 Luna backend
credential path using only app interface strings. No user records were supplied.
Native-speaker editorial review remains outstanding. Apple-owned permission dialogs,
photo/calendar pickers and external sign-in pages can follow the system/app language
settings; the in-app language setting cannot override every external interface.

## Validation

The final catalog contains 695 entries in all seven interface languages. Xcode
extraction found zero missing keys. All existing translations were preserved.
Three offline catalog checks and five focused physical-device language tests passed
(including six parameterized language cases); final signing verification passed.
Local build 30 was installed by the physical-device test run.

`python3 -m unittest discover -s tests/localization -v` checks complete language
coverage, format arguments and core-menu translations. Xcode language tests check
packaged resources, language fallback/layout direction and interpolation retaining
user names/destinations. These are focused checks, not the on-demand Full Test.

Initial device run: all three new language tests passed. The broader existing
`AppConfigurationTests` suite found two stale assertions in
`builtBundleMatchesConfigurationAndTransportPolicy`: it assumes a simulator's
localhost and the previous LAN address 192.168.0.156. The physical Local build uses
192.168.0.208. Those unrelated assertions were not changed.

Latest Cloud build 29 was verified successful in Xcode before setting local build 30.
No backend deployment is required for this interface update. Hosted Dev/Prod are
unchanged; earlier translation-inactivity rollout remains a separate task.

Physical Appium checks: all seven language choices switched core Profile icon labels
and bottom tabs; Persian settings/sign-out/delete labels were localized and a
screenshot confirmed right-to-left Profile layout. French voice selection/preview,
tone, Cancel and Save & Done labels were localized. French translation controls and
settings/privacy text were localized. Original English selection restored; no saved
profile, trip, voice or translation-pair settings changed. The full on-demand suite
was not run. A first navigation pass was interrupted when the phone switched apps;
focused checks were resumed after returning to PipPipGo.

Apple-provided accessibility labels such as Sheet Grabber and Tab Bar can remain in
the phone's system language. Native-speaker translation review and exhaustive visual
inspection of every screen/language/font-size combination remain separate acceptance.

## Completion for the requested 13 languages

Added Korean, Vietnamese, Filipino, Tagalog, Turkish, Arabic and Russian. All 13
translation languages now have matching interface choices; existing Spanish remains
available, making 14 interface choices. All 695 catalog entries have resources for
each interface choice. Arabic, like Persian, uses right-to-left layout.

Xcode canonicalizes the resource code `tl` to `fil`. Tagalog keeps its saved/API code
`tl` but uses a separate `fil-PH` resource and locale so both choices remain distinct.
Filipino retains `fil`. The application language picker and explicit bundle lookups
use this mapping; translation-pair codes and persisted choices are unchanged.

Backend voice language mapping was extended to the seven added languages so a new
Pip conversation does not default to English. The Local backend was restarted and
readiness passed before the phone update. Hosted Dev/Prod deployment is required for
this voice mapping and remains pending; deploy backend before a hosted app rollout.
The backend suite passed 490 tests with one skipped, and Ruff lint/format passed.
No models, endpoints, credentials or data structures changed.

New translations are machine-drafted and await native-speaker editorial review.
The common borrowed term “Profile” is explicitly retained in Filipino/Tagalog;
resource-presence checks distinguish this from a missing translation.

Final validation: the three offline catalog checks passed; Xcode extraction found
zero missing keys. Signing verification passed. Latest Cloud 29 was reverified in
Xcode; the required Cloud+1 local build number remains 30. The completed Local app
was installed. Six focused physical-device language tests passed, including 13
parameterized resource cases and coverage of every translation-language choice.
An initial test exposed Xcode's tl/fil canonicalization and was fixed before this
pass. A device-lock/install synchronization failure was resolved by a fresh test
run against the installed app. These results do not claim spoken-language fluency
acceptance or native editorial review. Full Test was not run.

Final Appium acceptance: all 13 requested choices switched the core Profile icons
and bottom tabs on the iPhone. Filipino and Tagalog voice sheets each displayed
their respective Save & Done text; Arabic voice-sheet labels passed and the Arabic
Profile screenshot showed right-to-left layout without clipped headings. English
was restored, voice was stopped, and no saved profile/trip/voice choices changed.
All focused tests are finished; the reusable Appium service/helper remains idle.

Environment badge labels added in all 14 interface choices; catalog now has 698 entries.
