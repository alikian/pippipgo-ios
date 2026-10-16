# Apple Watch companion

PipPipGo now includes a paired Apple Watch app (watchOS 10 or later). It is a
remote for the signed-in iPhone app, with three controls:

- **Explore** starts Explore Freely; **Stop exploring** stops it.
- **Skip** stops the current guide announcement, including pending announcement
  audio. It does not skip a tour stop or interrupt a live Pip conversation.
- **Talk to Pip** starts the existing iPhone conversation; **End conversation**
  ends it. Speak into the Watch microphone; replies play on the iPhone speaker
  or its connected headphones.

Starting Explore or Talk to Pip requires PipPipGo to be open and active on the
paired iPhone, signed in, with AI sharing consent accepted. Microphone permission is requested on the Watch; the phone does not capture
microphone audio for a Watch-started conversation. Location permission remains on the phone. The watch displays an instruction to
open the phone when a start is rejected in the background. Once an Explore
session is running, Skip and Stop can reach the background iPhone through
WatchConnectivity, subject to Apple's reachability and background execution.
The existing app stops a live voice session when it goes into the background;
this companion does not change that behavior. The Watch app must remain visible
while recording. Standalone cellular operation is not supported.

A planned tour cannot be replaced or stopped by Explore controls. Finish it on
the iPhone first. Commands are live messages with replies, not queued transfers;
a delayed tap never starts audio after a reconnect. Requests expire after ten
seconds, carry a per-account/consent session identifier, and are deduplicated by
request ID. The watch times out after eight seconds without automatically
resending. A timeout means the outcome is unknown; reconnect to obtain state
before trying again. State refreshes every five seconds while the watch app is
visible. The phone only pushes changed control state or a requested refresh.
Transient PCM16 mono 24 kHz microphone chunks are relayed over live
WatchConnectivity messages with bounded buffering and one packet in flight.
Packets are scoped to the start request and account/consent session, expire
after two seconds and reject out-of-order/replayed sequence numbers. No audio
files or queued transfers are used. No credentials, location, names or transcripts
are sent to the watch. Disconnect, leaving the Watch app, account changes and
ending the session release capture; the phone audio watchdog ends stalled input.

## Xcode setup and release

The `pippipgoWatch` single-target watchOS app is embedded by the existing
Local/Dev/Prod iPhone target. Bundle ID: `com.pippipgo.ios.watchkitapp`; companion:
`com.pippipgo.ios`. Local/Dev/Prod share `Configurations/Common.xcconfig` and the
same marketing/build versions as the phone. The icon reuses the existing
production artwork. Watch strings have entries for all 14 app localizations.
The watch follows its device language.

Use Xcode's **Watch** scheme on a watch simulator paired with an iPhone simulator.
Install/run the matching iPhone **Dev** build first. For distribution, archive
the existing **Prod** scheme so its dependency embeds the watch app. Do not use
the Watch scheme as an Xcode Cloud workflow: the existing cloud hooks accept
only Local/Dev/Prod. Xcode automatic signing must register/provision the new watch
bundle with team `U47SMLD234`; no Apple registration or signing was performed in
this Linux workspace.

No backend changes or deployment are required. No build number was changed and
no app build was prepared: Xcode Cloud's latest build number could not be
verified here. Before preparing a new build, verify that number and use exactly
that number plus one, per AGENTS.md.

## Verification

Available in this workspace:

```sh
python3 scripts/test_watch_project.py -v
git diff --check
```

The project checks parse the Xcode project, validate all object references,
embedding, source membership, pairing, Local/Dev/Prod configuration, version
inheritance, icon dimensions, localization coverage and the Watch scheme.
`WatchCommandGateTests` in the iPhone unit-test target cover account/session
changes, signed-out/consent rejection, expired/future requests, foreground-only
starts, existing-tour protection, Skip availability and protocol encoding.

The existing `python3 scripts/test_ci.py` suite passed 13 of 14 cases here; its
archive verification case cannot run because Linux has no
`/usr/libexec/PlistBuddy`. This is an environment limitation, not a passing check.

Swift compilation, those XCTest cases, signing, paired simulator navigation and
real-device audio have **not** run here: Swift/Xcode and Apple runtimes are not
installed. Required acceptance on a paired iPhone/Watch:

1. Sign in and accept setup on iPhone; launch Watch; Explore starts once, repeated
   taps do not restart it, and Stop restores idle state on both devices.
2. During an announcement, Skip immediately stops audio without advancing the
   tour stop. With no announcement the control is disabled.
3. Talk to Pip requests Watch microphone permission and starts once. Speak with
   the phone out of microphone range and verify captions capture Watch speech;
   replies play on the phone/headphones. Deny permission, leave the Watch app,
   disconnect, and End: capture and the phone session stop. Restart and verify
   fresh audio only; translation/busy states reject starts.
4. Lock/background iPhone: starts instruct the user to open it, existing Explore
   announcements continue, and Skip/Stop work while the session is reachable.
5. Disconnect/reconnect, timeout, switch account, revoke consent, sign out and
   switch paired watches: old taps never execute and controls recover after a
   fresh response. Do not use real-account destructive actions to test this.
6. Open a planned tour: Explore controls cannot replace/stop it. Check small and
   large watch sizes, VoiceOver, large text, scrolling, and right-to-left layouts.
7. Archive Prod and verify embedded watch signing, matching versions, icon,
   TestFlight installation and the paired-device launch before release.
