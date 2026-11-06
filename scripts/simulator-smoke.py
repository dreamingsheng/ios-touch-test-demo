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
modes = re.findall(r'data-mode="([a-z]+)"', pathlib.Path('docs/index.html').read_text())
assert len(modes) == 21

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
        container = pathlib.Path(run('xcrun', 'simctl', 'get_app_container', udid, bundle, 'data').strip())
        documents = container / 'Documents'
        layout_file = documents / 'layout-evidence.json'
        print('Launching '+device['name'], flush=True)
        # This is a fresh device: there is no prior app to terminate.
        try:
            launched = run('xcrun', 'simctl', 'launch', udid, bundle, '--offline-suite', '--smoke-evidence', timeout=120)
        except subprocess.TimeoutExpired:
            processes = run('xcrun', 'simctl', 'spawn', udid, 'launchctl', 'list', timeout=30)
            if bundle not in processes: raise
            launched = 'Launch command timed out; app process verified live'
        for attempt in range(60):
            if layout_file.exists(): break
            time.sleep(1)
        assert layout_file.exists(), 'App did not produce initial native layout evidence'
        name = device['name'].replace(' ', '-').replace('(', '').replace(')', '')
        cases = [(False, mode, False) for mode in modes] + [(True, mode, False) for mode in modes]
        # Automatic game entry must request landscape itself, separately from
        # explicitly rotated portrait/landscape compatibility checks.
        cases += [(True, 'moba', True), (True, 'aim', True)]
        for landscape, mode, automatic in cases:
            sequence = ('automatic-' if automatic else '')+('landscape' if landscape else 'portrait')+'-'+mode
            (documents / 'smoke-command.json').write_text(json.dumps({'sequence': sequence, 'mode': mode, 'orientation': 'automatic' if automatic else ('landscape' if landscape else 'portrait')}))
            layout = None
            last_observed = None
            for attempt in range(90):
                try:
                    observed = json.loads(layout_file.read_text())
                    if observed.get('requestSequence') == sequence:
                        last_observed = observed
                        if observed.get('layoutStable'):
                            layout = observed
                            break
                except (OSError, ValueError): pass
                time.sleep(.5)
            if last_observed:
                (output / f'{name}-{sequence}.json').write_text(json.dumps(last_observed, indent=2))
            assert layout is not None, f'No stable evidence for {sequence}: {last_observed}'
            assert layout['activeMode'] == mode and layout['modeCount'] == 21 and expected_version in layout['title'], layout
            viewport = layout['viewport']
            assert (viewport['width'] > viewport['height']) == landscape, layout
            assert layout['orientation'] in ([3, 4] if landscape else [1, 2]), layout
            assert layout['implementation'] == 'UIKit' and layout['statusBarHidden'] is True, layout
            inset, stage = layout['safeInsets'], layout['stage']
            assert stage['top'] == 0 and stage['left'] == 0 and stage['right'] == viewport['width'] and stage['bottom'] == viewport['height'], layout
            menu = layout['menu']
            assert menu['top'] >= inset['top'] and menu['bottom'] <= viewport['height'] - inset['bottom'], layout
            assert menu['left'] >= inset['left'] and menu['right'] <= viewport['width'] - inset['right'], layout
            assert abs(layout['app']['width']-viewport['width']) <= 1 and abs(layout['app']['height']-viewport['height']) <= 1, layout
            assert abs(layout['body']['width']-viewport['width']) <= 1, layout
            screenshot = output / f'{name}-{sequence}.png'
            run('xcrun', 'simctl', 'io', udid, 'screenshot', str(screenshot))
            width, height = struct.unpack('>II', screenshot.read_bytes()[16:24])
            (output / (screenshot.stem + '.json')).write_text(json.dumps(layout, indent=2))
            evidence.append({'device': device['name'], 'landscape': landscape, 'mode': mode, 'pixels': [width, height], 'viewport': viewport, 'file': str(screenshot), 'launch': launched.strip()})
            (output / 'results.json').write_text(json.dumps(evidence, indent=2))
            print('Verified '+device['name']+' '+sequence, flush=True)
    finally:
        subprocess.run(['xcrun', 'simctl', 'shutdown', udid], check=False, capture_output=True, timeout=45)
        subprocess.run(['xcrun', 'simctl', 'delete', udid], check=False, capture_output=True, timeout=45)
print(json.dumps(evidence, indent=2))
