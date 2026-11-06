"""Create small review sheets; retain original PNGs as the primary evidence."""
import base64
import html
import json
import pathlib
import subprocess

root = pathlib.Path('simulator-evidence')
results = root / 'results.json'
if not results.exists():
    print('No completed simulator captures available for previews')
    raise SystemExit(0)
output = root / 'previews'
output.mkdir(exist_ok=True)
items = json.loads(results.read_text())
for index, item in enumerate(items):
    source = pathlib.Path(item['file'])
    target = output / (source.stem + '.jpg')
    options = ['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '60', '-Z', '720']
    if (item['pixels'][0] > item['pixels'][1]) != item['landscape']:
        layout = json.loads(source.with_suffix('.json').read_text())
        options += ['-r', '270' if layout.get('orientation') == 3 else '90']
    subprocess.run(options + [str(source), '--out', str(target)], check=True, capture_output=True)
for landscape in [False, True]:
    cards = []
    for item in items:
        if item['landscape'] != landscape:
            continue
        source = pathlib.Path(item['file'])
        target = output / (source.stem + '.jpg')
        picture = base64.b64encode(target.read_bytes()).decode()
        title = html.escape(item['device']+' · '+item['mode'])
        cards.append('<figure><img src="data:image/jpeg;base64,'+picture+'"><figcaption>'+title+'</figcaption></figure>')
    name = 'landscape' if landscape else 'portrait'
    columns = '2' if landscape else '4'
    page = '<!doctype html><meta charset="utf-8"><title>Native simulator '+name+'</title><style>body{margin:16px;background:#ddd;font:14px sans-serif}main{display:grid;grid-template-columns:repeat('+columns+',1fr);gap:14px}figure{margin:0;background:white;padding:5px}img{display:block;width:100%;height:auto}figcaption{padding:8px}</style><p>Native simulator '+name+' · Original screenshots are retained separately. Review previews have been resized and rotated for reading.</p><main>'+''.join(cards)+'</main>'
    (output / (name+'.html')).write_text(page)
print('Created review previews for '+str(len(items))+' native captures')
