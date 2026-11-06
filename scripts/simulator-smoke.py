"""Boot actual available iPhone/iPad simulators and capture app launch evidence."""
import json
import pathlib
import struct
import re
import subprocess
import sys
import time

app = pathlib.Path(sys.argv[1]).resolve()
output = pathlib.Path('simulator-evidence')
output.mkdir(exist_ok=True)
bundle = 'com.example.TouchTestDemo'
expected_version = re.search(r'Touch Test <small>(v\d+)</small>', pathlib.Path('docs/index.html').read_text()).group(1)

def run(*args, timeout=180):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT, timeout=timeout)

devices = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '-j'))['devices']
available = [{**device, 'runtime': runtime} for runtime, items in devices.items() if 'iOS' in runtime
             for device in items if device.get('isAvailable')]
phones = [d for d in available if 'iPhone' in d['name']]
tablets = [d for d in available if 'iPad' in d['name']]
assert len(phones) >= 2 and tablets, 'Need at least two iPhone models and one iPad runtime'
small = next((d for d in phones if any(n in d['name'] for n in ['SE', 'mini', '16e'])), phones[0])
large = next((d for d in phones if 'Max' in d['name'] and d['udid'] != small['udid']),
             next(d for d in phones if d['udid'] != small['udid']))
categories = {'small': small, 'large': large, 'tablet': tablets[0]}
selected = [categories[sys.argv[2]]] if len(sys.argv) > 2 else list(categories.values())
evidence = []
for device in selected:
    udid = run('xcrun', 'simctl', 'create', 'TouchTest-'+device['name'], device['deviceTypeIdentifier'], device['runtime']).strip()
    try:
        print('Booting fresh simulator: '+device['name'], flush=True)
        run('xcrun', 'simctl', 'boot', udid)
        try:
            run('xcrun', 'simctl', 'bootstatus', udid, '-b')
        except subprocess.TimeoutExpired:
            # Observe the same cold-booting device again; do not restart it on a timeout.
            print('Cold boot still pending; rechecking same simulator '+udid, flush=True)
            run('xcrun', 'simctl', 'bootstatus', udid, '-b', timeout=240)
        run('xcrun', 'simctl', 'install', udid, str(app))
        for landscape in [False, True]:
            container = pathlib.Path(run('xcrun', 'simctl', 'get_app_container', udid, bundle, 'data').strip())
            layout_file = container / 'Documents' / 'layout-evidence.json'
            layout_file.unlink(missing_ok=True)
            arguments = ['--offline-suite', '--smoke-evidence'] + (['--landscape'] if landscape else [])
            print('Launching '+device['name']+(' landscape' if landscape else ' portrait'), flush=True)
            subprocess.run(['xcrun', 'simctl', 'terminate', udid, bundle], capture_output=True, timeout=30)
            try:
                launched = run('xcrun', 'simctl', 'launch', udid, bundle, *arguments, timeout=90)
            except subprocess.TimeoutExpired:
                # A CLI observation timeout is not evidence that the app stopped.
                processes = run('xcrun', 'simctl', 'spawn', udid, 'launchctl', 'list', timeout=30)
                if bundle not in processes: raise
                launched = 'simctl launch observation timed out; app process verified live'
            time.sleep(6)
            processes = run('xcrun', 'simctl', 'spawn', udid, 'launchctl', 'list')
            assert bundle in processes, f'App exited after launch: {device["name"]}: {launched}'
            name = device['name'].replace(' ', '-').replace('(', '').replace(')', '')
            screenshot = output / f'{name}-{"landscape" if landscape else "portrait"}.png'
            run('xcrun', 'simctl', 'io', udid, 'screenshot', str(screenshot))
            width, height = struct.unpack('>II', screenshot.read_bytes()[16:24])
            for attempt in range(30):
                if layout_file.exists(): break
                time.sleep(1)
            layout = json.loads(layout_file.read_text())
            assert layout['modeCount'] == 21 and expected_version in layout['title'], layout
            viewport = layout['viewport']
            assert (viewport['width'] > viewport['height']) == landscape, layout
            assert layout['orientation'] in ([3, 4] if landscape else [1, 2]), layout
            inset = layout['safeInsets']
            assert layout['header']['top'] >= inset['top'] + 3, layout
            assert layout['nav']['bottom'] <= viewport['height'] - inset['bottom'] - 3, layout
            assert layout['stage']['left'] >= inset['left'] + 3, layout
            assert layout['stage']['right'] <= viewport['width'] - inset['right'] - 3, layout
            (output / (screenshot.stem + '.json')).write_text(json.dumps(layout, indent=2))
            evidence.append({'device': device['name'], 'landscape': landscape,
                             'pixels': [width, height], 'viewport': viewport, 'file': str(screenshot), 'launch': launched.strip()})
            (output / 'results.json').write_text(json.dumps(evidence, indent=2))
    finally:
        subprocess.run(['xcrun', 'simctl', 'shutdown', udid], check=False, capture_output=True, timeout=45)
        subprocess.run(['xcrun', 'simctl', 'delete', udid], check=False, capture_output=True, timeout=45)
print(json.dumps(evidence, indent=2))
