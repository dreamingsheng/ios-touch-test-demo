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
media = app / 'Media'
assert media.is_dir() and not (app / 'Web').exists()
assert not list(app.rglob('*.html')), 'Native IPA must not contain an HTML test application'
for source in pathlib.Path('docs/assets').rglob('*'):
    if source.is_file():
        assert hashlib.sha256((media / source.relative_to('docs/assets')).read_bytes()).digest() == hashlib.sha256(source.read_bytes()).digest(), str(source)
assert (app / info['CFBundleExecutable']).is_file()
assert b'NativeSuiteController' in (app / info['CFBundleExecutable']).read_bytes()
print(json.dumps({'bundle': str(app), 'version': info['CFBundleShortVersionString'],
                  'build': info['CFBundleVersion'], 'minimumIOS': info['MinimumOSVersion'],
                  'families': info['UIDeviceFamily'], 'nativeEntry': True,
                  'mediaFiles': sum(p.is_file() for p in media.rglob('*'))}, indent=2))
