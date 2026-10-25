# Release Security

## Core principles

Release authority remains a human and repository control function; AI assistance does not replace review, merge, or branch protections.

## Required local controls

Checked-in policy files should be validated together with GitHub branch protections and review controls:

- `.github/CODEOWNERS` for policy/release-critical ownership;
- `tools/build_package.py --check` for archive content and TOC checks, and `tools/release_check.py` for release identity consistency (label, version, tag, asset, announced identity, checksums). The earlier `tools/Test-ReleasePolicy.ps1` belonged to the archived PowerShell quality gate and is not in this repository;
- `tools/check_release_notes.py` for a read-only branding check of one release-notes file (`tools/release_notes_selftest.py` exercises it offline). The file must start with the complete canonical prefix of `docs/RELEASE_NOTES_TEMPLATE.md`, must not repeat that prefix, and must carry nonempty release-specific notes in place of the body placeholder. The checker also refuses a template prefix that differs from its pinned hash. It compares bytes, so the file must be UTF-8 without a byte-order mark; LF and CRLF line endings are both accepted. It exits 0 with `PASS`, 1 with `FAIL` lines, or 2 when the file or the template cannot be read. It writes, fetches and publishes nothing. It does not compare a recorded commit or SHA-256 with an asset, and it does not by itself verify a published release;
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
3. record commit, artifact SHA-256, and validation outcome in the release-specific notes. Write them after the build in a notes file outside the checkout, and check that file with `tools/check_release_notes.py` (public release checklist, step 2);
4. publish only as an explicit human-authorized step. No workflow reacts to a tag, a release, a branch push or an archive tag. After publication verify the prerelease flag, the tag target, the asset name and the downloaded checksum, and check the persisted release body (public release checklist, step 2).

Only a package built with `--public` announces its test number to other clients. Internal and review packages must never be built with `--public`.

## Public release checklist

Use this checklist for each explicitly authorized public release. It records a manual workflow; it does not authorize later releases or create a scheduled task. One named release owner coordinates publication and announcements, checks existing receipts first, and prevents duplicate posts.

1. Verify the newest published public test and same-series tags, then select a strictly newer number. Pin the reviewed clean source commit, preserve historical packages, and follow the repository's normal PR and required CI controls. Record the actual tested commit/tree and separate offline validation from native client/server evidence.
2. Build, check and publish the GitHub release in this order. Keep the release notes in a file outside the checkout, so that the package is built from a clean tree and no release-specific notes file enters source. These are manual steps: no workflow or tool in this repository fetches or checks a published release body on its own.
   1. From the clean checkout of the pinned reviewed commit, build the public package with `--public`. Then verify tag, label, announced identity, ZIP content and SHA-256 with `tools/release_check.py`, as in Offline checks above.
   2. Write the release notes as one UTF-8 file without a byte-order mark (LF or CRLF line endings), outside the checkout. Begin it with the complete branded prefix, copied unchanged: all of `docs/RELEASE_NOTES_TEMPLATE.md` before `{{release_specific_body}}`. This keeps the banner, the two centered taglines, the four live badges, the four project buttons, the immutable asset/license links and the live-badge disclaimer. Below the prefix, in place of the placeholder, write the release-specific notes. State **EXPERIMENTAL** and the material limitations, and record the exact artifact commit, the asset name, its SHA-256 from the previous step and the validation outcome.
   3. Immediately before the authorized publication, run `python tools/check_release_notes.py NOTES_FILE` from the pinned checkout. Replace `NOTES_FILE` with the full path of the final notes file, and quote the path if it contains spaces. The checker compares the file with that checkout's template. Publish only after it exits 0 and prints `PASS`; a `FAIL` (exit 1) or an unreadable file (exit 2) blocks publication. Any edit of the file after a run needs a new run, so that the last run covers the exact bytes that are published. The checker checks only the branding and the presence of release-specific notes. Compare the recorded commit, asset name and SHA-256 with the outputs of the previous steps by reading them.
   4. Publish the GitHub release only within the user's explicit authorization, as a prerelease, using the content of the checked file unchanged as its body. Verify the remote tag target, prerelease flag, asset name, and checksum of the downloaded asset.
   5. Read the persisted body back. Retrieve the release body as GitHub stored it (its Markdown source, not the rendered page), save it outside the checkout as a UTF-8 file without a byte-order mark, and run the same command on that saved file. Its line endings may differ from those of the published file; LF and CRLF are both accepted. Repeat this readback after any later edit of the release body. A `FAIL` or an unreadable body leaves the GitHub receipt incomplete: report it as pending, and change the body only within the user's explicit authorization.
   6. With the GitHub receipt and the retained CI receipts, record the exact tag and release URL, the time each persisted body was observed, and the checker result of each readback.
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
