#!/usr/bin/env python3
"""Targeted real-device download regression; reuses the Full Test Appium session."""
import argparse
import base64
import datetime as dt
import json
import os
import re
import time
import uuid

from full_test import Device, STATE


class TourDevice(Device):
    def __init__(self, device, team):
        super().__init__(device, team)
        self.call('POST', '/appium/settings', {'settings': {
            'waitForIdleTimeout': 1, 'animationCoolOffTimeout': .3}})
        self.call('POST', '/execute/sync', {'script': 'mobile: activateApp',
                  'args': [{'bundleId': 'com.pippipgo.ios'}]})

    def tap(self, label, scroll=False):
        attrs = self.find(label, scroll)
        if attrs.get('enabled') != 'true':
            raise AssertionError('Disabled control: ' + label)
        # Tap the visible frame that was just inspected. SwiftUI navigation bars
        # can expose duplicate element handles during presentation transitions.
        self.call('POST', '/execute/sync', {'script': 'mobile: tap', 'args': [{
            'x': float(attrs['x']) + float(attrs['width']) / 2,
            'y': float(attrs['y']) + float(attrs['height']) / 2}]})

    def find(self, label, scroll=False):
        # Scroll above the keyboard. A default full-screen scroll can type
        # into the keyboard or pan the embedded map instead of moving the sheet.
        for attempt in range(10 if scroll else 1):
            try:
                return super().find(label)
            except AssertionError:
                if not scroll or attempt == 9:
                    raise
            source = self.source()
            application = next(e for e in source.iter()
                               if e.tag == 'XCUIElementTypeApplication')
            width = float(application.attrib['width'])
            height = float(application.attrib['height'])
            keyboards = [float(e.attrib['y']) for e in source.iter()
                         if e.tag == 'XCUIElementTypeKeyboard'
                         and e.attrib.get('visible') == 'true']
            start_y = min([height * .65] + [y - 35 for y in keyboards])
            self.call('POST', '/execute/sync', {
                'script': 'mobile: dragFromToForDuration',
                'args': [{'duration': .25, 'fromX': width * .91,
                          'fromY': start_y, 'toX': width * .91, 'toY': 160}]})



def prepare_tour(device, area, timeout, passed):
    device.call('POST', '/execute/sync', {'script': 'mobile: terminateApp',
                'args': [{'bundleId': 'com.pippipgo.ios'}]})
    device.call('POST', '/execute/sync', {'script': 'mobile: activateApp',
                'args': [{'bundleId': 'com.pippipgo.ios'}]})
    device.tap('tab.guide')
    device.tap('liveGuide.createTour', scroll=True)
    try:
        device.find('tourBuilder.adjust')
    except AssertionError:
        pass
    else:
        device.tap('tourBuilder.adjust')
    device.tap('2 hours', scroll=True)
    for mode in ('walking', 'driving', 'rideshare', 'transit'):
        control = 'tourBuilder.transport.' + mode
        selected = 'Selected' in device.find(control, scroll=True).get('traits', '').split(', ')
        if selected != (mode in ('walking', 'driving')):
            device.tap(control)
    for mode in ('walking', 'driving', 'rideshare', 'transit'):
        selected = 'Selected' in device.find('tourBuilder.transport.' + mode).get('traits', '').split(', ')
        if selected != (mode in ('walking', 'driving')):
            raise AssertionError('Transport selection did not match Driving + Walking')
    for control, text in [('tourBuilder.area', area), ('tourBuilder.activities', '')]:
        device.find(control, scroll=True)
        element = device.call('POST', '/element', {'using': 'accessibility id', 'value': control})
        key = element.get('element-6066-11e4-a52e-4f735466cecf') or element['ELEMENT']
        device.call('POST', '/element/' + key + '/clear', {})
        if text:
            device.call('POST', '/element/' + key + '/value', {'text': text})
    try:
        device.tap('Return')
    except AssertionError:
        pass
    device.tap('tourBuilder.create', scroll=True)
    until = time.monotonic() + min(timeout, 180)
    while time.monotonic() < until:
        source = device.source()
        if any(e.attrib.get('name') == 'tourBuilder.adjust' and e.attrib.get('visible') == 'true' for e in source.iter()):
            passed('Create produces a two-hour Driving + Walking tour preview in the requested area')
            return
        if any(e.tag == 'XCUIElementTypeAlert' for e in source.iter()):
            raise AssertionError('Create reported a tour-planning error')
        time.sleep(1)
    raise AssertionError('Create never produced a tour preview')


def exercise(device, timeout, passed, delete=False):
    # Require a prepared tour so this test never submits arbitrary AI prompts,
    # changes location permissions, or edits the traveler's organizer records.
    print('STEP: Locate download controls', flush=True)
    device.find('tourBuilder.download', scroll=True)
    device.find('tourBuilder.name', scroll=True)
    name = 'Offline UI ' + uuid.uuid4().hex[:10]
    element = device.call('POST', '/element', {
        'using': 'accessibility id', 'value': 'tourBuilder.name'})
    key = element.get('element-6066-11e4-a52e-4f735466cecf') or element['ELEMENT']
    device.call('POST', '/element/' + key + '/clear', {})
    device.call('POST', '/element/' + key + '/value', {'text': name})
    # The default tour-name keyboard has Return, not a Done key. Submit it
    # before scrolling so gestures do not pan the map behind the keyboard.
    try:
        device.tap('Return')
    except AssertionError:
        pass
    print('STEP: Download named tour', flush=True)
    device.tap('tourBuilder.download', scroll=True)
    until = time.monotonic() + timeout
    success = 'Ready Offline. Pip’s stories and OpenAI voice are downloaded.'
    failures = ('The complete voice tour could not be downloaded. Please try again online.',
                'Offline stories are not available for every stop in this tour.',
                'The road map could not be downloaded. Please try again online.',
                'A tour stop could not be independently sourced for offline use. Try another tour.')
    while time.monotonic() < until:
        source = device.source()
        labels = {el.attrib.get('label') for el in source.iter()}
        failure = next((message for message in failures if message in labels), None)
        if failure:
            raise AssertionError('Download reported failure before saving: ' + failure)
        if success in labels or any(el.attrib.get('name') == 'tourBuilder.downloadComplete' for el in source.iter()):
            break
        time.sleep(1)
    else:
        raise AssertionError('Download never reported Ready Offline within the timeout')
    passed('Download finishes without a reported error')
    print('STEP: Check My Tours', flush=True)
    device.tap('Done')
    device.tap('liveGuide.myTours', scroll=True)
    device.wait(name)
    device.tap(name)
    device.wait('myTours.start')
    device.find('tour.downloadComplete', scroll=True)
    device.find('For offline navigation, download the area separately in Apple Maps.', scroll=True)
    screenshot = STATE / 'offline-tour-ready-latest.png'
    screenshot.write_bytes(base64.b64decode(device.call('GET', '/screenshot')))
    print('Download screenshot:', screenshot, flush=True)
    passed('Named download appears in My Tours with complete status and Apple Maps instructions')
    device.call('POST', '/execute/sync', {'script': 'mobile: terminateApp',
                'args': [{'bundleId': 'com.pippipgo.ios'}]})
    device.call('POST', '/execute/sync', {'script': 'mobile: activateApp',
                'args': [{'bundleId': 'com.pippipgo.ios'}]})
    # Guide is a tab in the current installed UI; it need not be the launch tab.
    try:
        device.tap('tab.guide')
    except AssertionError:
        pass
    device.wait('liveGuide.myTours')
    device.tap('liveGuide.myTours')
    device.wait(name)
    device.tap(name)
    device.wait('myTours.start')
    device.find('tour.downloadComplete', scroll=True)
    passed('Downloaded tour survives app relaunch and offers Start Tour')
    if delete:
        verify_deletion(device, name, passed)
    return name


def exercise_online_navigation(device, area, timeout, passed):
    prepare_tour(device, area, timeout, passed)
    device.tap('tourBuilder.start', scroll=True)
    device.wait('tour.activeName')
    try:
        until = time.monotonic() + 45
        while time.monotonic() < until:
            controls = [e.attrib for e in device.source().iter() if e.attrib.get('visible') == 'true']
            if any(a.get('name') == 'tour.nextTurn' and a.get('label') for a in controls):
                passed('Online Apple MapKit turn instructions appear inside PipPipGo')
                return
            if any(a.get('label') == 'Navigation is unavailable. Try again online.' for a in controls):
                raise AssertionError('Apple MapKit could not resolve or route to the parking stop')
            time.sleep(.5)
        raise AssertionError('Online turn instructions never appeared')
    finally:
        stop_tour(device)


def stop_tour(device):
    """End Tour asks for confirmation."""
    device.tap('liveGuide.enabled', scroll=True)
    device.tap('tour.stopConfirm')


def wait_active(device, name):
    until = time.monotonic() + 20
    while time.monotonic() < until:
        controls = [e.attrib for e in device.source().iter() if e.attrib.get('visible') == 'true']
        title = next((a for a in controls if a.get('name') == 'tour.activeName'), None)
        if title and title.get('label') == name and not any(a.get('name') == 'myTours.options' for a in controls):
            return
        time.sleep(.5)
    raise AssertionError('Saved-tour detail did not dismiss to the active named tour')


def wait_saved_navigation(device, phase, passed):
    until = time.monotonic() + 60
    while time.monotonic() < until:
        controls = [e.attrib for e in device.source().iter() if e.attrib.get('visible') == 'true']
        if any(a.get('name') == 'tour.nextTurn' and a.get('label') for a in controls):
            device.find('tour.routeCard')
            if any(a.get('name') == 'panel.handle' for a in controls):
                raise AssertionError('Active tour still exposes the sheet handle')
            passed(phase + ' downloaded tour shows an in-app Apple route and turn instructions')
            return
        if any(a.get('label') == 'Navigation is unavailable. Try again online.' for a in controls):
            raise AssertionError('Apple routing failed for the saved tour')
        time.sleep(.5)
    raise AssertionError('Saved tour never displayed its in-app Apple route and turn instructions')


def exercise_saved(device, name, passed, handoff=False, navigation=False):
    """Exercise an explicitly named downloaded QA tour without modifying other tours."""
    try:
        device.tap('tab.guide')
    except AssertionError:
        pass
    device.tap('liveGuide.myTours', scroll=True)
    device.tap(name, scroll=True)
    device.find('tour.downloadComplete', scroll=True)
    device.tap('tour.sources', scroll=True)
    device.wait('Wikipedia contributors')
    device.find('tour.sourceLicense.CC-BY-SA-4.0', scroll=True)
    passed('Saved tour exposes article attribution and bundled licenses')
    device.tap('tour.sourcesDone')
    # A previous test may have left a checkpoint; Start Again is explicit.
    try:
        device.find('myTours.start')
    except AssertionError:
        device.tap('myTours.restart', scroll=True)
    else:
        device.tap('myTours.start')
    wait_active(device, name)
    device.find('tour.openAppleMaps', scroll=True)
    passed('Starting a saved tour dismisses My Tours, shows its name and offers Apple Maps')
    if navigation:
        wait_saved_navigation(device, 'Starting', passed)
    stop_tour(device)
    device.tap('liveGuide.myTours', scroll=True)
    device.tap(name, scroll=True)
    device.find('myTours.resume', scroll=True)
    device.find('myTours.restart', scroll=True)
    passed('Stopping saves progress and offers Resume Tour and Start Again')
    device.tap('myTours.resume')
    wait_active(device, name)
    passed('Resume Tour returns to the active named tour')
    if navigation:
        wait_saved_navigation(device, 'Resuming', passed)
    if handoff:
        device.tap('tour.openAppleMaps', scroll=True)
        until = time.monotonic() + 20
        while time.monotonic() < until:
            state = device.call('POST', '/execute/sync', {'script': 'mobile: queryAppState',
                                'args': [{'bundleId': 'com.apple.Maps'}]})
            if state == 4:
                break
            time.sleep(.5)
        else:
            raise AssertionError('Apple Maps did not enter the foreground')
        until = time.monotonic() + 20
        while time.monotonic() < until:
            state = device.call('POST', '/execute/sync', {'script': 'mobile: queryAppState',
                                'args': [{'bundleId': 'com.pippipgo.ios'}]})
            if state in (2, 3):
                break
            time.sleep(.5)
        else:
            raise AssertionError('PipPipGo did not remain in the background')
        device.call('POST', '/execute/sync', {'script': 'mobile: activateApp',
                    'args': [{'bundleId': 'com.pippipgo.ios'}]})
        wait_active(device, name)
        passed('Apple Maps opens while PipPipGo remains in background and returns to the named tour')
    stop_tour(device)
    return name


def verify_deletion(device, name, passed):
    if not re.fullmatch(r'Offline UI [a-f0-9]{10}', name):
        raise AssertionError('Deletion is limited to uniquely named UI-test tours')

    def request_delete():
        # New build exposes a visible button; older installed builds have a menu.
        try:
            device.find('myTours.delete', scroll=True)
        except AssertionError:
            device.tap('myTours.options')
            device.wait('Delete')
            device.tap('Delete')
        else:
            device.tap('myTours.delete')
        device.wait('Delete this tour?')

    def tap_alert(label):
        element = device.call('POST', '/element', {
            'using': 'xpath',
            'value': "//XCUIElementTypeAlert//XCUIElementTypeButton[@name='" + label + "']"})
        key = element.get('element-6066-11e4-a52e-4f735466cecf') or element['ELEMENT']
        device.call('POST', '/element/' + key + '/click', {})

    device.find(name)
    request_delete()
    tap_alert('Cancel')
    device.find(name)
    device.find('myTours.delete')
    passed('Cancelling deletion keeps the test tour available')
    request_delete()
    tap_alert('Delete')
    until = time.monotonic() + 15
    while time.monotonic() < until:
        visible = [e.attrib for e in device.source().iter() if e.attrib.get('visible') == 'true']
        if not any(name in (a.get('name'), a.get('label')) or a.get('label') == 'Delete this tour?' for a in visible):
            break
        time.sleep(.5)
    else:
        raise AssertionError('Confirmed deletion did not finish in the UI')
    passed('Confirmed deletion removes the test tour from the UI')
    device.call('POST', '/execute/sync', {'script': 'mobile: terminateApp',
                'args': [{'bundleId': 'com.pippipgo.ios'}]})
    device.call('POST', '/execute/sync', {'script': 'mobile: activateApp',
                'args': [{'bundleId': 'com.pippipgo.ios'}]})
    try:
        device.tap('tab.guide')
    except AssertionError:
        pass
    device.wait('liveGuide.myTours')
    device.tap('liveGuide.myTours')
    device.wait('My Tours')
    if any(name in (e.attrib.get('name'), e.attrib.get('label'))
           for e in device.source().iter()):
        raise AssertionError('Deleted test tour returned after relaunch')
    passed('Confirmed deletion removes the test tour across app relaunch')


def run(args):
    report = {'name': 'Offline tour UI regression', 'checks': [],
              'started_at': dt.datetime.now(dt.timezone.utc).isoformat(),
              'limitations': 'Airplane-mode listening, real movement, screen-lock and car audio require physical acceptance.'}
    def passed(name):
        report['checks'].append({'name': name, 'status': 'passed'})
        print('PASS:', name, flush=True)
    try:
        device = TourDevice(args.device, args.team)
        if args.online_navigation:
            if not args.create_area:
                raise ValueError('--online-navigation requires --create-area')
            report['coverage'] = 'Real Create and online in-app Apple navigation UI; no download'
            exercise_online_navigation(device, args.create_area, args.timeout, passed)
        elif args.saved_tour:
            report['coverage'] = 'Existing named package UI; does not prove Create/Download UI'
            report['test_tour_name'] = exercise_saved(device, args.saved_tour, passed, args.maps_handoff, args.saved_navigation)
        else:
            if args.create_area:
                prepare_tour(device, args.create_area, args.timeout, passed)
            report['coverage'] = 'Real Create/Download and persistence UI' if args.create_area else 'Real prepared-tour download and persistence UI'
            report['test_tour_name'] = exercise(device, args.timeout, passed, args.delete)
        report['status'] = 'passed'
    except (AssertionError, OSError, RuntimeError, ValueError) as exc:
        report['status'] = 'blocked_or_failed'
        report['error'] = str(exc)
    STATE.mkdir(exist_ok=True)
    path = STATE / ('offline-tour-' + dt.datetime.now(dt.timezone.utc).strftime('%Y%m%dT%H%M%S%fZ') + '.json')
    path.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))
    print('Report:', path)
    return 0 if report['status'] == 'passed' else 1


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device', default=os.environ.get('PPG_TEST_DEVICE', '00008140-000C50463A08801C'))
    parser.add_argument('--team', default=os.environ.get('PPG_TEST_TEAM', 'U47SMLD234'))
    parser.add_argument('--timeout', type=int, default=900)
    parser.add_argument('--delete', action='store_true', help='Also test cancel/delete on the new UI-test tour only')
    parser.add_argument('--saved-tour', help='Test source access and start/resume of this named saved QA tour')
    parser.add_argument('--maps-handoff', action='store_true', help='With --saved-tour, also open Apple Maps and return')
    parser.add_argument('--saved-navigation', action='store_true', help='With --saved-tour and internet, verify in-app Apple routes after Start and Resume')
    parser.add_argument('--create-area', help='First create a two-hour Driving + Walking tour in this area using the simulator/device GPS')
    parser.add_argument('--online-navigation', action='store_true', help='With --create-area, test online turn instructions instead of downloading')
    raise SystemExit(run(parser.parse_args()))
