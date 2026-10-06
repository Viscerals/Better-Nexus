# Better Nexus documentation website

This directory contains the original Better Nexus documentation website. It is separate from the runtime addon and describes the published public test.9092. The addon package and download links are unchanged.

The dedicated website workflow builds only this directory and publishes the generated static website at `/Better-Nexus/`. Former `/Better-Nexus/preview/` page routes redirect to their canonical equivalents; compatibility copies of old asset paths remain available. The workflow does not package or release the addon. QA reports, private data, and local research snapshots are excluded.

The custom design, wording, logo, and illustrations are original. Dependency notices are preserved in THIRD_PARTY_NOTICES.txt and in the built static distribution.

Build: `python -m pip install -r requirements.lock.txt`, then `python -m mkdocs build --strict` and `python tools/check_site.py`. Staging: `python tools/stage_site.py --output pages-artifact`.
