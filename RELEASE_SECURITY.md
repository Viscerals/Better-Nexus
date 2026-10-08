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

## Public release checklist

Use this checklist for each explicitly authorized public release. It records a manual workflow; it does not authorize later releases or create a scheduled task. One named release owner coordinates publication and announcements, checks existing receipts first, and prevents duplicate posts.

1. Verify the newest published public test and same-series tags, then select a strictly newer number. Pin the reviewed clean source commit, preserve historical packages, and follow the repository's normal PR and required CI controls. Record the actual tested commit/tree and separate offline validation from native client/server evidence.
2. Build the public package with `--public`; verify tag, label, announced identity, ZIP content, and SHA-256 with the existing release checker. State **EXPERIMENTAL** and the material limitations in release notes. Publish the GitHub release only within the user's explicit authorization, as a prerelease. Verify the remote tag target, prerelease flag, asset name, and checksum of the downloaded asset; retain the release URL and CI receipts.
3. Update the existing GitHub Pages website's version, package download, and release information through its established deployment workflow. Preserve unrelated content. Verify the completed deployment and actual public page content, and record the canonical URL and deployed commit.
4. Prepare the **Discord announcement and a separate actual Ko-fi post** together, using the established destinations and style. Include the verified release and documentation links, experimental labeling, a concise change list, and appropriate caveats. Present the exact drafts and destinations for user review. A Ko-fi link in another announcement does not satisfy the Ko-fi post step.
5. Publish each announcement only after the required explicit approval, using one assigned operator. Check for a prior matching post first. Record separate verified receipts for **GitHub**, **GitHub Pages**, **Discord**, and **Ko-fi**, including destination, message/post URL, version, timestamp, and outcome. An unsent draft or requested action is not a completed publication receipt. Report any remaining destination as pending.

Do not introduce an automation, new integration, credential change, or broader standing permission as part of this checklist. Keep private support evidence and personal recovery data out of public source, packages, notes, and model inputs.

## Incident response

On suspected takeover, unauthorized release, or credential compromise:

- stop publish actions;
- preserve evidence and logs;
- rotate affected credentials;
- remove compromised collaborators/apps;
- notify the maintainer via the private security path and recover safely.
