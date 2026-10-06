from pathlib import Path
from shutil import copyfile

def on_post_build(config):
    # Prevent Jekyll processing when these static files are later used by Pages.
    Path(config['site_dir'], '.nojekyll').touch()
    notice = Path(__file__).resolve().parents[1] / 'THIRD_PARTY_NOTICES.txt'
    copyfile(notice, Path(config['site_dir'], notice.name))
