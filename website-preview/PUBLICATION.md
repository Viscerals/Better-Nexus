# Website preview

This directory contains the original Better Nexus documentation preview. It is separate from the runtime addon and describes the published public test.9092. The addon package and download links are unchanged.

The dedicated preview workflow builds only this directory and publishes only the generated static website at `/Better-Nexus/preview/`. It does not package or release the addon. QA reports, private data, and local research snapshots are not part of the website or this source directory.

The custom design, wording, logo, and illustration are original. Dependency notices are preserved in THIRD_PARTY_NOTICES.txt and in the built static distribution.

Build: `python -m pip install -r requirements.lock.txt`, then `python -m mkdocs build --strict` and `python tools/check_site.py`.
