"""Exercise UIKit through XCTest-generated touch and keyboard input."""
import json
import subprocess
import sys


def run(*args, timeout=180):
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT, timeout=timeout)


devices = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '-j'))['devices']
phones = [{**d, 'runtime': runtime} for runtime, items in devices.items() if 'iOS' in runtime
          for d in items if d.get('isAvailable') and 'iPhone' in d['name']]
device = next((d for d in phones if any(name in d['name'] for name in ['SE', 'mini', '16e'])), phones[0])
udid = run('xcrun', 'simctl', 'create', 'NativeTouch-UIAcceptance', device['deviceTypeIdentifier'], device['runtime']).strip()
try:
    print('XCTest device: '+device['name']+' '+udid, flush=True)
    run('xcrun', 'simctl', 'boot', udid)
    try:
        run('xcrun', 'simctl', 'bootstatus', udid, '-b')
    except subprocess.TimeoutExpired:
        print('Re-observing the same cold-booting UI test device', flush=True)
        run('xcrun', 'simctl', 'bootstatus', udid, '-b', timeout=240)
    command = ['xcodebuild', '-project', 'TouchTestApp.xcodeproj', '-scheme', 'NativeSuiteUITests',
               '-destination', 'platform=iOS Simulator,id='+udid, '-derivedDataPath', 'ui-build',
               '-resultBundlePath', 'native-ui-results.xcresult', '-parallel-testing-enabled', 'NO',
               'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'test']
    result = subprocess.run(command, timeout=900)
    sys.exit(result.returncode)
finally:
    subprocess.run(['xcrun', 'simctl', 'shutdown', udid], check=False, capture_output=True, timeout=45)
    subprocess.run(['xcrun', 'simctl', 'delete', udid], check=False, capture_output=True, timeout=45)
