#!/usr/bin/env python3
"""On-demand Appium regression runner. Never scheduled; preserves app data."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import signal
import subprocess
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
STATE = ROOT / '.full-test'
BASE = 'http://127.0.0.1:4723'
LANGUAGES = ['Chinese', 'Japanese', 'Korean', 'Vietnamese', 'Filipino', 'Tagalog',
             'Farsi', 'Turkish', 'Arabic', 'Russian', 'Italian', 'French', 'English']
MANUAL = [
    'Google sign-in, token refresh, sign-out and account switching with test accounts',
    'Create/edit/save/reopen/delete disposable trips and companions; multi-destination hotels and transport',
    'Save profile, voice and personalization changes; verify persistence and restore baseline',
    'Offline retry, conflict review, account isolation and late-response handling',
    'Receipt import, calendar permissions/import/conflicts and location allow/deny',
    'Talk to Pip: Siri start, greeting, interruption, end commands and transcript retention',
    'Translation accuracy and audible output in both directions; headphones/Bluetooth and 30-second silence',
    'Voice preview sound quality and selected voice in a fresh live session',
    'Delete account ONLY with an explicitly approved disposable account',
]


def request(method, path, body=None, timeout=90):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, method=method,
                                 headers={'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return json.load(response)['value']
    except urllib.error.HTTPError as exc:
        # Do not include returned UI trees or account data in reports.
        value = json.loads(exc.read()).get('value', {})
        raise RuntimeError(value.get('error', 'Appium request failed')) from exc


def ready():
    try:
        return request('GET', '/status', timeout=2).get('ready', False)
    except (OSError, ValueError, RuntimeError):
        return False


def setup():
    STATE.mkdir(exist_ok=True)
    if ready():
        return
    env = dict(os.environ, DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
    with (STATE / 'server.log').open('ab') as log:
        process = subprocess.Popen(['appium', '--address', '127.0.0.1', '--port', '4723',
                                    '--log-level', 'warn'], env=env, stdin=subprocess.DEVNULL,
                                   stdout=log, stderr=log, start_new_session=True)
    (STATE / 'server.pid').write_text(str(process.pid))
    for _ in range(30):
        if ready():
            return
        if process.poll() is not None:
            raise RuntimeError('Appium failed to start; inspect .full-test/server.log')
        time.sleep(1)
    raise RuntimeError('Appium startup timed out')


class Device:
    def __init__(self, device, team):
        setup()
        saved = STATE / 'session.json'
        if saved.exists():
            self.sid = json.loads(saved.read_text())['id']
            try:
                self.call('GET', '/source')
                return
            except (OSError, RuntimeError):
                saved.unlink(missing_ok=True)
        caps = {'platformName': 'iOS', 'appium:automationName': 'XCUITest',
                'appium:udid': device, 'appium:bundleId': 'com.pippipgo.ios',
                'appium:noReset': True, 'appium:fullReset': False,
                'appium:shouldTerminateApp': False, 'appium:useNewWDA': False,
                'appium:xcodeOrgId': team, 'appium:xcodeSigningId': 'Apple Development',
                'appium:updatedWDABundleId': 'com.pippipgo.WebDriverAgentRunner',
                'appium:allowProvisioningDeviceRegistration': True,
                'appium:derivedDataPath': str(STATE / 'wda'),
                'appium:newCommandTimeout': 0}
        result = request('POST', '/session', {'capabilities': {'alwaysMatch': caps}}, timeout=300)
        self.sid = result['sessionId']
        saved.write_text(json.dumps({'id': self.sid}))

    def call(self, method, path, body=None):
        return request(method, '/session/' + self.sid + path, body)

    def source(self):
        return ET.fromstring(self.call('GET', '/source'))

    def find(self, label, scroll=False):
        for attempt in range(6 if scroll else 1):
            for el in self.source().iter():
                a = el.attrib
                if a.get('visible') == 'true' and label in (a.get('name'), a.get('label')):
                    return a
            if scroll and attempt < 5:
                self.call('POST', '/execute/sync', {'script': 'mobile: scroll',
                                                   'args': [{'direction': 'up' if attempt == 0 else 'down'}]})
        raise AssertionError('Missing visible control: ' + label)

    def tap(self, label, scroll=False):
        attrs = self.find(label, scroll)
        if attrs.get('enabled') != 'true':
            raise AssertionError('Disabled control: ' + label)
        predicate = 'visible == true AND (name == %s OR label == %s)' % (json.dumps(label), json.dumps(label))
        element = self.call('POST', '/element', {'using': '-ios predicate string', 'value': predicate})
        key = element.get('element-6066-11e4-a52e-4f735466cecf') or element.get('ELEMENT')
        self.call('POST', '/element/' + key + '/click', {})

    def wait(self, label, seconds=20):
        until = time.monotonic() + seconds
        while time.monotonic() < until:
            try:
                return self.find(label)
            except AssertionError:
                time.sleep(.5)
        raise AssertionError('Timed out waiting for: ' + label)

    def close_editor(self):
        self.tap('Cancel')
        # No save requests: dismiss only an unsaved draft created by this test.
        labels = [el.attrib.get('label') for el in self.source().iter()]
        if 'Discard changes' in labels:
            self.tap('Discard changes')

    def stop_audio(self):
        for label in ['Stop translating', 'End voice conversation']:
            try:
                self.tap(label)
            except AssertionError:
                pass


def run(args):
    report = {'name': 'Full Test', 'started_at': dt.datetime.now(dt.timezone.utc).isoformat(),
              'checks': [], 'manual_or_test_account_required': MANUAL,
              'coverage': 'Automated safe regression plus explicit manual/test-account checklist; not complete acceptance.'}
    device = None
    def check(name, action):
        action()
        report['checks'].append({'name': name, 'status': 'passed'})
        print('PASS:', name, flush=True)
    try:
        device = Device(args.device, args.team)
        device.call('POST', '/execute/sync', {'script': 'mobile: activateApp',
                                             'args': [{'bundleId': 'com.pippipgo.ios'}]})
        device.stop_audio()
        check('Signed-in navigation', lambda: [device.find(x) for x in ['Pip', 'Translate', 'Profile', 'Language']])
        device.tap('Language')
        check('Interface language choices accessible', lambda: (device.find('English'), device.find('فارسی')))
        device.tap('Profile')
        check('Trips tile opens', lambda: (device.tap('profile.trips'), device.wait('Trips')))
        check('New trip editor opens', lambda: (device.tap('Add trip'), device.wait('Trip')))
        device.close_editor()
        device.tap('BackButton')
        device.tap('Profile')
        for tile, title, close in [('Travel style', 'My travel style', 'Cancel'),
                                   ('Bookings', 'Booking receipt', 'Close'),
                                   ('Calendars', 'Calendars', 'Done')]:
            check(tile + ' opens', lambda tile=tile, title=title: (device.tap(tile, True), device.wait(title)))
            device.tap(close)
        check('Companions opens', lambda: (device.tap('Companions', True), device.wait('Add companion')))
        check('New companion editor opens', lambda: (device.tap('Add companion'), device.wait('Companion')))
        device.close_editor()
        device.tap('BackButton')
        check('Personalization folder accessible', lambda: (device.tap('About you', True), device.wait('profile.savedDetails')))
        device.tap('BackButton')
        check('Nearby opens', lambda: (device.tap('Nearby', True), device.wait('Nearby')))
        device.tap('BackButton')
        device.tap('Pip’s voice', True)
        for voice in ['Ballad', 'Coral', 'Sage', 'Ash', 'Verse']:
            def preview(voice=voice):
                device.find('Select ' + voice + ' voice')
                device.tap('Preview ' + voice + ' voice', True)
                device.wait('Stop ' + voice + ' voice preview', 3)
                device.wait('Preview ' + voice + ' voice', 15)
            check(voice + ' preview starts and finishes', preview)
        check('Voice Save & Done available', lambda: device.find('Save & Done'))
        device.tap('Cancel')
        check('Settings account controls accessible', lambda: (device.tap('Settings', True), device.find('Sign out'), device.find('account.delete')))
        device.tap('BackButton')
        device.tap('Pip')
        device.stop_audio()
        check('Conversation history opens', lambda: (device.tap('pip.history'), device.wait('Conversations')))
        device.tap('Done')
        device.tap('Translate')
        check('Translation controls available', lambda: [device.find(x) for x in ['You speak', 'They speak', 'Swap languages', 'Start translation', 'Headphone mode']])
        device.tap('You speak')
        def languages():
            labels = [el.attrib.get('label') for el in device.source().iter()]
            if not all(lang in labels for lang in LANGUAGES):
                raise AssertionError('Translation language menu is incomplete')
        check('All 13 translation languages present', languages)
        # Selecting the existing checkmark keeps the saved language unchanged.
        device.tap('checkmark', True)
        device.tap('Translation settings')
        check('Translation settings accessible', lambda: (device.find('Headphone mode'), device.find('Done')))
        device.tap('Done')
        device.tap('Start translation')
        check('Translation connects and microphone starts', lambda: device.wait('Translating — take turns speaking', 30))
        device.tap('Stop translating')
        check('Translation stop restores controls', lambda: [device.find(x) for x in ['Start translation', 'You speak', 'They speak']])
        report['result'] = 'automated_checks_passed_manual_checks_pending'
    except Exception as exc:
        report['result'] = 'blocked_or_failed'
        report['checks'].append({'name': 'Run stopped', 'status': 'failed', 'detail': str(exc)[:300]})
        print('STOPPED:', str(exc), flush=True)
    finally:
        if device:
            try:
                device.stop_audio()
            except Exception:
                report['cleanup'] = 'Could not confirm audio stopped; check the phone.'
        report['finished_at'] = dt.datetime.now(dt.timezone.utc).isoformat()
        STATE.mkdir(exist_ok=True)
        stamp = dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        path = STATE / ('report-' + stamp + '.json')
        path.write_text(json.dumps(report, indent=2))
        print('Report:', path)
        print('Appium and its reusable session remain available. Use teardown explicitly when needed.')
    return 0 if report['result'].startswith('automated_checks_passed') else 1


def teardown():
    saved = STATE / 'session.json'
    if saved.exists():
        sid = json.loads(saved.read_text())['id']
        try:
            request('DELETE', '/session/' + sid)
        except (OSError, RuntimeError):
            pass
        saved.unlink(missing_ok=True)
    pidfile = STATE / 'server.pid'
    if pidfile.exists():
        pid = int(pidfile.read_text())
        command = subprocess.run(['ps', '-p', str(pid), '-o', 'command='], capture_output=True, text=True).stdout
        if 'appium' in command and '--port 4723' in command:
            os.kill(pid, signal.SIGTERM)
        pidfile.unlink(missing_ok=True)
    print('Owned session/server stopped; helper build and app data preserved.')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Full Test — on-demand only')
    parser.add_argument('command', choices=['run', 'setup', 'status', 'teardown'])
    parser.add_argument('--device', default=os.environ.get('PPG_TEST_DEVICE', '00008140-000C50463A08801C'))
    parser.add_argument('--team', default=os.environ.get('PPG_TEST_TEAM', 'U47SMLD234'))
    args = parser.parse_args()
    if args.command == 'run':
        raise SystemExit(run(args))
    if args.command == 'setup':
        setup()
        print('Appium ready; no app tests run.')
    if args.command == 'status':
        print('Appium ready:', ready())
        print('Saved session:', (STATE / 'session.json').exists())
    if args.command == 'teardown':
        teardown()
