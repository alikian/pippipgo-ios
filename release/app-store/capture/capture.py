"""Capture the current production views from the isolated screenshot app."""
from pathlib import Path
import subprocess
import time
import sys
import os

build = Path(sys.argv[1])
device = sys.argv[2]
bundle = 'com.pippipgo.screenshots'
size_group = sys.argv[3] if len(sys.argv) > 3 else 'iphone-medium'
out = Path(__file__).resolve().parent.parent / 'submission-2026-10-15' / size_group
out.mkdir(parents=True, exist_ok=True)

def sim(*args, check=True):
    return subprocess.run(['xcrun', 'simctl', *args], check=check)

sim('bootstatus', device, '-b')
sim('install', device, str(build / 'Build/Products/Dev-iphonesimulator/pippipgo.app'))
sim('status_bar', device, 'override', '--time', '9:41', '--dataNetwork', 'wifi', '--wifiMode', 'active', '--wifiBars', '3', '--batteryState', 'charged', '--batteryLevel', '100')
try:
    for index, screen in enumerate(['explore', 'create', 'tour', 'chat', 'translate', 'trips'], 1):
        requested = os.environ.get('PIPPIPGO_CAPTURE_SCENES', '').split(',')
        if requested != [''] and screen not in requested:
            continue
        sim('terminate', device, bundle, check=False)
        sim('launch', device, bundle, screen)
        time.sleep(14)
        sim('io', device, 'screenshot', str(out / f'{index:02d}-{screen}.png'))
        print(f'Captured {size_group}: {screen}', flush=True)
finally:
    sim('terminate', device, bundle, check=False)
    sim('status_bar', device, 'clear', check=False)
print(out)
