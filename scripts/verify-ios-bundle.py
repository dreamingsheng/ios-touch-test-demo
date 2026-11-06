"""Validate the compiled bundle, not merely the source build settings."""
import hashlib
import json
import pathlib
import plistlib
import re
import sys

app = pathlib.Path(sys.argv[1])
with (app / 'Info.plist').open('rb') as handle:
    info = plistlib.load(handle)
assert set(info['UIDeviceFamily']) == {1, 2}, info.get('UIDeviceFamily')
assert info.get('UIRequiresFullScreen') is True
assert info.get('UIStatusBarHidden') is True
expected = {'UIInterfaceOrientationPortrait', 'UIInterfaceOrientationPortraitUpsideDown',
            'UIInterfaceOrientationLandscapeLeft', 'UIInterfaceOrientationLandscapeRight'}
for key in ['UISupportedInterfaceOrientations', 'UISupportedInterfaceOrientations~ipad']:
    assert set(info.get(key, [])) == expected, (key, info.get(key))
web = app / 'Web'
for name in ['index.html', 'app.js', 'style.css', 'icon.svg', 'manifest.webmanifest']:
    source = pathlib.Path('docs') / name
    assert hashlib.sha256((web / name).read_bytes()).digest() == hashlib.sha256(source.read_bytes()).digest(), name
html = (web / 'index.html').read_text()
assert len(re.findall(r'data-mode="[a-z]+"', html)) == 21
assert (app / info['CFBundleExecutable']).is_file()
print(json.dumps({'bundle': str(app), 'version': info['CFBundleShortVersionString'],
                  'build': info['CFBundleVersion'], 'minimumIOS': info['MinimumOSVersion'],
                  'families': info['UIDeviceFamily'], 'offlineModes': 21}, indent=2))
