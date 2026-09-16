# Retired bundled catalog

`BundledBuilds-1.19.4-reference.lua` is the unchanged 504-build historical
catalog from candidate `09d9ff36a1be5d5abe91a627876d4bcd230a5df0`.
It is reference and regression-test data only. It is not current-patch advice.
It is outside `Nexus.toc` and the package manifest. Never copy it into a release
to populate an empty catalog.

The user retired this catalog on 2026-09-16 because it predates multiple patches.
`data/BundledBuilds.lua` now starts empty. Existing saved builds, Wishlists,
received Community records and DPS data are not deleted or rewritten by this
data-only change. Old records can therefore still exist in an existing profile
or arrive through normal Sync; removing the bundled seed does not certify them.

## Replacement catalog

No verified current-patch input has been supplied. Do not relabel the old rows
as current or extract a player's full SavedVariables by default. Collect only
opt-in builds with their client/patch identity and validation provenance. Use
the existing exporter on a reviewed, public-safe input after those facts exist.
Its structural validation alone does not establish gameplay validity.

The empty seed is reproducible with the existing exporter:

```text
node tools/export-bundled-builds.js --input tests/fixtures/empty-community-catalog.lua --output data/BundledBuilds.lua --report build/empty-community-catalog.json --source-version 1.20.0-beta.1
```

Large-data tests explicitly load the retired reference so their original
assertions and workloads remain active. Empty-release behavior is checked
separately by `tests/run_bundled_catalog_retirement.lua`.
