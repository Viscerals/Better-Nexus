# Release Security

## Core principles

Release authority remains a human and repository control function; AI assistance does not replace review, merge, or branch protections.

## Required local controls

Checked-in policy files should be validated together with GitHub branch protections and review controls:

- `.github/CODEOWNERS` for policy/release-critical ownership;
- `tools/build_package.py --check` for archive content and TOC checks, and `tools/release_check.py` for release identity consistency (label, version, tag, asset, announced identity, checksums). The earlier `tools/Test-ReleasePolicy.ps1` belonged to the archived PowerShell quality gate and is not in this repository;
- branch and PR review rules configured in GitHub settings.

## Required release archive contents

Release archives must include, in the top-level `Nexus` folder:

- `Nexus.toc`
- `LICENSE.md`
- `AI_POLICY.md`
- `UPSTREAM.md`

`RELEASE_SECURITY.md`, `SECURITY.md`, and `README.md` are required in source but are not substitutes for the three mandatory archive files.

## Offline checks

Before release:

1. verify the source commit is reviewed and clean;
2. build with `python tools/build_package.py --label test.<N>-<commit> --public` and run `python tools/release_check.py --label ... --zip ... --tag ... --sums ... --require-newer` (see `docs/UPDATE_NOTICES.md`);
3. record commit, artifact SHA-256, and validation outcome in release notes;
4. publish only as an explicit human-authorized step. No workflow reacts to a tag, a release, a branch push or an archive tag. After publication verify the prerelease flag, the tag target, the asset name and the downloaded checksum.

Only a package built with `--public` announces its test number to other clients. Internal and review packages must never be built with `--public`.

## Incident response

On suspected takeover, unauthorized release, or credential compromise:

- stop publish actions;
- preserve evidence and logs;
- rotate affected credentials;
- remove compromised collaborators/apps;
- notify the maintainer via the private security path and recover safely.
