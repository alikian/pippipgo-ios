# Pip greetings, waiting cue and contact details — October 6, 2026

The signed-in Pip tab retains the existing stores and voice session. Automatic greeting now retries when history loading completes, can resume after a 30-minute return from text mode, and guards drafts/focus, pending sends, translation and an explicit-stop cooldown. Initial GPS acquisition is bounded to two seconds, using a fresh existing fix first. If unavailable, Pip can ask for an area; it never substitutes hometown. The backend uses supplied local time for a short day check-in before optional profiling, without asserting daylight, weather or opening hours.

Numbers in typed/voice captions become digit-based telephone links. Conservative conversion covers runs of seven to fifteen spoken single-digit words, not ordinary numeric prose. Contacts supplied directly by place lookup appear with verified digit phone numbers and websites. Dialing remains a user tap and the normal system call flow; no automatic call is made. Non-web/non-telephone schemes are rejected. Place cards provide up to two fresh provider photos, author credit and source links; failed/expired photos do not remove contacts. The backend does not expose API keys or photo resource names to the app.

A local, original four-note synthesized hum plays quietly during sufficiently long live lookups; it is a UI cue, not generated speech in the selected voice. It stops on audible assistant output, user transcript, ending/interruption/error and is bounded to six short phrases. Profile offers an on-device waiting-hum toggle. Only clients advertising `X-Pip-Enrichment: 1` receive additive lookup/place events. Old clients and translation retain their protocol. No model changes.

## Verification and rollout

- `uv run pytest -q`: 408 passed, one skipped; Ruff check and formatting passed.
- Signed Local app and test build passed. Latest Cloud build rechecked as 25; local build remains exactly 26.
- Two new contact/photo tests passed on Sara's physical iPhone (test result dated 12:08 PDT).
- Synthetic live greeting: first audible output 2.26 seconds; “Hi there! Good afternoon! How's your day going so far?” No real user profile was sent for this probe.
- Live local Google lookup returned five public cafés with phone/website and two attributed photos. It initially exposed a truncated 100 KB response; a bounded 1 MB limit and regression test fixed it.
- Local backend restarted with final changes; hosted Dev/Prod deployment is pending. Backend must precede app rollout for lookup cues/cards and updated greetings; legacy clients remain compatible.
- Unlocked-phone retry: the targeted physical microphone capture test executed and passed (one test, zero failures; result bundle 12:14:38 PDT). Normal post-test launch restored the signed-in Pip tab and started voice automatically; screenshot showed “Pip is speaking…” and backend logs confirmed the live socket. Perceived hum quality and a real tap-to-call remain user acceptance checks.

References: [GPT-Live delegation](https://developers.openai.com/api/docs/guides/live-delegation) and [Google Place Photos](https://developers.google.com/maps/documentation/places/web-service/place-photos).
