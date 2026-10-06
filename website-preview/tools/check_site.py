"""Validate static output without changing source or contacting a service."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote
import json
import sys

ROOT = Path(__file__).resolve().parents[1]
SITE = ROOT / 'site'

class Page(HTMLParser):
    def __init__(self, text):
        super().__init__()
        self.ids, self.refs, self.h1s = set(), [], 0
        self.feed(text)

    def handle_starttag(self, tag, attrs):
        data = dict(attrs)
        if 'id' in data:
            self.ids.add(data['id'])
        if tag == 'h1':
            self.h1s += 1
        for key in ('href', 'src'):
            if key in data:
                self.refs.append(data[key])

pages = {p: Page(p.read_text(encoding='utf-8')) for p in SITE.rglob('*.html')}
errors, checked, external = [], 0, set()
for file, page in pages.items():
    if file.name != '404.html' and page.h1s != 1:
        errors.append(f'{file.relative_to(SITE)}: expected 1 h1, got {page.h1s}')
    for ref in page.refs:
        url = urlsplit(ref)
        if url.netloc == 'viscerals.github.io' and url.path.startswith('/Better-Nexus/'):
            url = urlsplit(url.path + ('#' + url.fragment if url.fragment else ''))
        if url.scheme or url.netloc:
            if url.scheme in ('https', 'http'):
                external.add(ref)
            continue
        path = unquote(url.path)
        if path.startswith('/Better-Nexus/'):
            target = (SITE / path.removeprefix('/Better-Nexus/')).resolve()
        else:
            target = (file.parent / path).resolve() if path else file
        if target.is_dir():
            target /= 'index.html'
        if not target.is_relative_to(SITE):
            errors.append(f'{file.relative_to(SITE)}: escapes site: {ref}')
            continue
        if not target.exists():
            errors.append(f'{file.relative_to(SITE)}: missing {ref}')
            continue
        if url.fragment and target.suffix == '.html' and unquote(url.fragment) not in pages[target].ids:
            errors.append(f'{file.relative_to(SITE)}: missing anchor {ref}')
        checked += 1

for file in SITE.rglob('*'):
    if file.suffix in ('.html', '.js', '.css', '.json', '.svg'):
        text = file.read_text(encoding='utf-8')
        for bad in ('test.9093', 'test.9094', 'ebb-hero', 'Lzra2000', 'ACSJPB'):
            if bad in text:
                errors.append(f'{file.relative_to(SITE)}: unwanted token {bad}')

release = json.loads((ROOT / 'release-source.json').read_text(encoding='utf-8'))
download_html = (SITE / 'releases/index.html').read_text(encoding='utf-8')
assert release['tag_name'] == 'v1.20.0-beta.1-test.9092'
for asset in release['assets']:
    if asset['browser_download_url'] not in download_html:
        errors.append('Download asset does not match recorded public release')
if not (SITE / '.nojekyll').exists():
    errors.append('Missing GitHub Pages .nojekyll marker')

result = {'html_pages': len(pages), 'local_references_checked': checked,
          'external_urls': sorted(external), 'errors': errors}
(ROOT / 'qa').mkdir(exist_ok=True)
(ROOT / 'qa/link-check.json').write_text(json.dumps(result, indent=2), encoding='utf-8')
print(json.dumps({k:v for k,v in result.items() if k != 'external_urls'}, indent=2))
sys.exit(bool(errors))
