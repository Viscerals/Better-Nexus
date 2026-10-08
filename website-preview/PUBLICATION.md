# Better Nexus documentation website

This directory contains the original Better Nexus documentation website. It is separate from the runtime addon and describes the published experimental public test.9093. Release identity and download links are recorded in `release-source.json`; historical notes remain available.

The dedicated website workflow builds only this directory and publishes the generated static website at `/Better-Nexus/`. Former `/Better-Nexus/preview/` page routes redirect to their canonical equivalents; compatibility copies of old asset paths remain available. The workflow does not package or release the addon. QA reports, private data, and local research snapshots are excluded.

The custom design, wording, logo, and illustrations are original. Dependency notices are preserved in THIRD_PARTY_NOTICES.txt and in the built static distribution.

Build: `python -m pip install -r requirements.lock.txt`, then `python -m mkdocs build --strict` and `python tools/check_site.py`. Staging: `python tools/stage_site.py --output pages-artifact`.

For each authorized published release, refresh `release-source.json` from the actual GitHub release metadata, then update the current version, package name, source revision, checksum, download links and release highlights. Preserve historical notes and unrelated website content. Commit the bounded update on the existing `docs/site-preview-20261006` branch; its existing push workflow builds, validates and deploys the canonical site. Validation and `deployment.json` read the recorded release identity rather than a fixed test number. Verify the completed workflow and the actual public version/download before recording success. This adds no credentials, permissions, services or independent release trigger.

Follow the repository's [manual public release checklist](https://github.com/Viscerals/Better-Nexus/blob/main/RELEASE_SECURITY.md#public-release-checklist) for GitHub, this website, the separately approved Discord announcement and an actual separate Ko-fi post, with one owner and verified receipts for each destination.
