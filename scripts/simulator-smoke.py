"""Boot actual available iPhone/iPad simulators and capture app launch evidence."""
import json
import pathlib
import struct
import subprocess
import sys
import time

app = pathlib.Path(sys.argv[1]).resolve()
output = pathlib.Path('simulator-evidence')
output.mkdir(exist_ok=True)
bundle = 'com.example.TouchTestDemo'

def run(*args, timeout=180):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT, timeout=timeout)

devices = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '-j'))['devices']
available = [device for runtime, items in devices.items() if 'iOS' in runtime
             for device in items if device.get('isAvailable')]
phones = [d for d in available if 'iPhone' in d['name']]
tablets = [d for d in available if 'iPad' in d['name']]
assert len(phones) >= 2 and tablets, 'Need at least two iPhone models and one iPad runtime'
small = next((d for d in phones if any(n in d['name'] for n in ['SE', 'mini', '16e'])), phones[0])
large = next((d for d in phones if 'Max' in d['name'] and d['udid'] != small['udid']),
             next(d for d in phones if d['udid'] != small['udid']))
selected = [small, large, tablets[0]]
evidence = []
for device in selected:
    udid = device['udid']
    try:
        if device['state'] != 'Booted': run('xcrun', 'simctl', 'boot', udid)
        run('xcrun', 'simctl', 'bootstatus', udid, '-b')
        run('xcrun', 'simctl', 'install', udid, str(app))
        for landscape in [False, True]:
            arguments = ['--offline-suite'] + (['--landscape'] if landscape else [])
            launched = run('xcrun', 'simctl', 'launch', '--terminate-running-process', udid, bundle, *arguments)
            time.sleep(6)
            processes = run('xcrun', 'simctl', 'spawn', udid, 'launchctl', 'list')
            assert bundle in processes, f'App exited after launch: {device["name"]}: {launched}'
            name = device['name'].replace(' ', '-').replace('(', '').replace(')', '')
            screenshot = output / f'{name}-{"landscape" if landscape else "portrait"}.png'
            run('xcrun', 'simctl', 'io', udid, 'screenshot', str(screenshot))
            width, height = struct.unpack('>II', screenshot.read_bytes()[16:24])
            if landscape: assert width > height, f'Landscape request failed: {device["name"]} {width}x{height}'
            evidence.append({'device': device['name'], 'landscape': landscape,
                             'pixels': [width, height], 'file': str(screenshot), 'launch': launched.strip()})
            (output / 'results.json').write_text(json.dumps(evidence, indent=2))
    finally:
        subprocess.run(['xcrun', 'simctl', 'shutdown', udid], check=False, capture_output=True)
print(json.dumps(evidence, indent=2))
