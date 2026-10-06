"""Stage canonical documentation and preserve every former preview route."""
from pathlib import Path
from shutil import copytree, copyfile
import argparse
import html
import json
import os

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / 'site'
PREFIX = '/Better-Nexus/'

parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True)
args = parser.parse_args()
destination = Path(args.output).resolve()
if destination.exists():
    raise SystemExit('Use a fresh staging directory; existing content is never removed.')
copytree(SITE, destination)
legacy = destination / 'preview'
legacy.mkdir()
redirects = []
for source in SITE.rglob('*'):
    if not source.is_file():
        continue
    relative = source.relative_to(SITE)
    target = legacy / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    if source.suffix != '.html':
        copyfile(source, target)
        continue
    route = relative.as_posix()
    if route.endswith('index.html'):
        route = route.removesuffix('index.html')
    canonical = PREFIX + route
    escaped = html.escape(canonical, quote=True)
    target.write_text(
        '<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1">'
        '<title>Better Nexus</title>'
        f'<link rel="canonical" href="https://viscerals.github.io{escaped}">'
        f'<meta http-equiv="refresh" content="0; url={escaped}">'
        '<script>window.location.replace('
        + json.dumps(canonical)
        + '+window.location.search+window.location.hash);</script>'
        f'</head><body><p><a href="{escaped}">Continue to Better Nexus documentation.</a></p>'
        '</body></html>', encoding='utf-8')
    redirects.append({'old': PREFIX + 'preview/' + route, 'canonical': canonical})

metadata = {
    'kind': 'documentation-website',
    'canonical_url': 'https://viscerals.github.io/Better-Nexus/',
    'public_addon_release': 'v1.20.0-beta.1-test.9092',
    'commit': os.environ.get('GITHUB_SHA', 'local'),
    'run_id': os.environ.get('GITHUB_RUN_ID', 'local'),
    'repository': os.environ.get('GITHUB_REPOSITORY', 'Viscerals/Better-Nexus'),
    'preview_compatibility': 'Page redirects preserve query strings and fragments; old assets remain available.'
}
for directory in (destination, legacy):
    (directory / 'deployment.json').write_text(json.dumps(metadata, indent=2), encoding='utf-8')
    (directory / '.nojekyll').touch()
assert len(redirects) == len(list(SITE.rglob('*.html')))
assert (destination / 'index.html').is_file()
print(json.dumps({'output': str(destination), 'redirects': redirects}, indent=2))
