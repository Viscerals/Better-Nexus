# Repository consolidation record (2026-09-21)

One record of how `main` became the single maintained development line. It
lists the adopted source, the path map, every older branch and pull request with
its exact SHA and disposition, and where each tip is preserved. It does not
declare the beta stable, and it does not claim that any open bug is fixed.

## 1. Source selection

| Item | Value |
|---|---|
| `main` before consolidation | `8cf798dd3af8adfc786c58f6707bc743745181a6` |
| Adopted prototype source | commit `6fac3893bd5db9e0fdceeab102991a382869b6b7`, tree `ec4c85125796c288e2ba2d4bfeb1005e161a3e29` |
| Why this commit | `1600d88` has an independent review PASS. `6fac389` has no stand-alone verdict: the later review of `d80375f` (FAIL because of later commits) confirmed in its question 7 that `6fac389` answers all five open items of the `1600d88` review. Complete offline suite on the exact export: 113 listed, 113 pass (local LuaJIT 2.1, reference archive present). |
| Public beta (unchanged) | `test.9027-3f1cd20`: commit `3f1cd20bc1b5f83fe2d25d8c398117332b2c374b`, tree `47857c3a25d6c03e2bc64553d8ccc66f9a841ede`, tag `v1.20.0-beta.1-test.9027`, ZIP SHA-256 `8f8295404d7fce2833e4af054d335610fe9b74323a4abd7b667594dcb75e2727`. `main` adopts a commit that is 2 commits newer on the same prototype line. `main` is source, not a published build. |
| Excluded, unfinished | Prototype commits `f808ca6..60aa206` (Share role preservation, persistent Share status, Advisor tab attachment). Two independent reviews returned FAIL (last: two P2 items open). Preserved on the remote as `archive/prototype-history-60aa206`. Plan: continue it as a short-lived branch from the new `main` after the merge. |
| Installed client build | Not inspected for this task. |

The prototype line and old `main` have no common Git ancestor. `main` was not
force-pushed and no fast-forward was fabricated: the source arrived as one
explicit adoption commit on top of `8cf798d`, through a pull request. The
resulting `main` commit and tree are new. They are not the release commit, and
no existing ZIP was relabelled. The original prototype history stays reachable
under the references in section 4.

## 2. Path map

| Path | Source | Note |
|---|---|---|
| `Nexus.toc`, `core/`, `data/`, `logic/`, `ui/`, `third_party/` | adopted commit | Runtime. Byte-identical Git blobs (verified per file). `logic/Relay.lua` of old `main` is removed; the adopted `Nexus.toc` does not load it. |
| `tests/prototype/` | adopted commit | Current offline suite and harness. |
| `tests/harness.lua`, `tests/run_*.lua` (75 files) | removed | 1.19-era suite for the replaced runtime. It cannot run against the adopted runtime. It stays in history (`archive/main-pre-consolidation-8cf798d`, and the newer stack suite under `archive/pr-stack-test19-tip-eb190c5`). |
| `tools/run_prototype_tests.py`, `tools/prototype_lua54.py` | adopted commit | Maintained test tools. (A third, which prepared an external comparison archive, was retired on 2026-09-24 with those comparisons.) |
| `docs/` (35 files), `README-PROTOTYPE.md`, `THIRD_PARTY.md` | adopted commit | Historical prototype documents are kept as history. On 2026-09-24, 15 prototype-phase reports and receipts that described a retired offline comparison with an outside addon were removed from the current tree; they remain unchanged in Git history. Three files (`README-PROTOTYPE.md`, `docs/P1_5_1_TERMINOLOGY_STATUS.json`, `docs/P1_5_1_TERMINOLOGY_STATUS.md`) were stored with CRLF on the prototype line; `.gitattributes` of `main` stores them with LF. They are equal after that normalization. No other adopted file differs. |
| `AI_POLICY.md`, `LICENSE.md`, `UPSTREAM.md` | both | Byte-identical on both lines. |
| `.github/` issue forms, `CODEOWNERS`, PR template, `.gitattributes`, `.gitignore`, `CHANGELOG.md`, `CONTRACTS.md`, `RELEASE_SECURITY.md`, `SECURITY.md`, `SUPPORT.md` | old `main` | Retained unchanged. `CONTRACTS.md` describes the 1.19/stack-era contracts and is kept as a historical reference. |
| `README.md`, `CONTRIBUTING.md` | old `main`, adapted | Current status, beta download, limitations, clean-checkout test and package commands, branch-from-`main` workflow. |
| `.github/workflows/ci.yml`, `tools/ci_check.py`, `tools/build_package.py`, this file | new | See section 3. |

Not imported: any `.git` directory, evidence directories, review packets,
receipts, caches, installed addon copies, SavedVariables, native client
extracts, or local machine paths.

## 3. Checks for contributors and CI

- `python tools/ci_check.py`: fails on a duplicate, missing or unlisted test
  file, on any FAIL or TIMEOUT, and on any listed test without a result row.
  No test count is hard-coded. Every listed test runs from the checkout; a
  NOT RUN row fails the check and is never counted as passed.
- `python tools/build_package.py --check` / `--label <label>`: package content
  rule of the published test.9027 package (84 files there), TOC compatibility,
  and an archive that is reproducible on one platform and zlib build. The
  compressed bytes differ between zlib builds (for example Linux CI and Windows
  Python 3.14), so compare checksums only between builds from the same
  environment. It never publishes.
- `.github/workflows/ci.yml` runs both on pull requests and on pushes to `main`
  only. It has no tag, release or schedule trigger and retains no archive.
- Not carried over: the PowerShell/Node quality gate of the old stack
  (`quality-gate.yml`, `release-policy.yml`, 243/245-runner requirements, the
  duplicate Fengari runtime). Those files exist only on the archived stack.
- `main` is protected by ruleset "Protect main" (pull request required, review
  threads resolved, no deletion, no force push). The ruleset has no required
  status check, so none had to be replaced. The ruleset was not changed.

## 4. Old references, exact tips and preservation

Archive tags are plain Git tags. No workflow reacts to tags. Release tags were
not moved.

| Archive tag | Tip | Preserves |
|---|---|---|
| `archive/main-pre-consolidation-8cf798d` | `8cf798dd3af8adfc786c58f6707bc743745181a6` | old `main` (also an ancestor of new `main`) |
| `archive/pr-stack-test19-tip-eb190c5` | `eb190c5afbccf73e1aff73f91d07769c81b74ade` | heads of #10, #53, #54, #57, #61, #67, #68, #69, #70, #71 (all are ancestors of this tip). This tip is also the stated foundation of the prototype (`THIRD_PARTY.md`). |
| `archive/pr-stack-wp5-wp7-9a538a1` | `9a538a102e62d523954e38b9c03ba84baf67e60a` | heads of #58, #59, #60 |
| `archive/pr71-wishlist-owned-confirmation-4dc3b39` | `4dc3b39e4e9187d08d7ac1607086d7e7ac30e4f5` | one commit on top of `eb190c5` |
| `archive/community-off-followup-88a1c05` | `88a1c0590ec6c5c7d70988bd578da26d62c27f92` | contributor work after `v1.20.0-beta.3.community-off` |
| `archive/prototype-history-60aa206` | `60aa2068ea3e0ff86638b206bf2b69595a3ce892` | whole prototype line: published `3f1cd20`, adopted `6fac389`, unfinished `f808ca6..60aa206` |

| Branch (before) | Tip | Pull request | Disposition |
|---|---|---|---|
| `refactor/nexus-1.20-test17` | `03870e75254848c941dcd3534a9c79a90a644fe3` | #10 | Superseded. The 1.20 runtime refactor is the base of the prototype; its outcome is retained in `main` by content, not by ancestry. Branch redundant after archive. |
| `bugfix/test19-wp2-canonical-authority` | `7c95911a7d8584d46a62f2aca20268affef4cfcf` | #53 | Same. |
| `bugfix/test19-wp3-realm-persistence` | `e674f033cc51494a382191b987c9a99cb6827f4a` | #54 | Same. |
| `bugfix/test19-wp4-exact-wishlist-evidence` | `e70de8a7582d0146cc6746677084b3f4a270290b` | #57 | Same. |
| `bugfix/test19-wp5-historical-dps-authority-and-real-paired-summari` | `8f5d28008935cef2d973b800167695ab50e0f70b` | #58 | Superseded by #61, as the body of #61 states. |
| `bugfix/test19-wp5-…-replacement-a79f32507697` | `b758ca053da6feea764c5948fcebf4fb6b23ee98` | #61 | Superseded; in the stack under `eb190c5`. |
| `bugfix/test19-wp6-build-hash-buckets-erase-build-id-type-and-can-r` | `5e1a6e20eba497d5950fd4faa4de83f52daf97f3` | #59 | Old ancestry not merged. Its typed-ID hash material is present in `main` (`core/BuildHashCache.lua`, `core/SyncCompatibility.lua`). The current suite covers it offline with `typed_hash`. The old stack's own two regression files are not carried. Issue #40 is reconciled separately, with that evidence. |
| `bugfix/test19-wp7-hud-progress-labels-quality-4-as-q4-instead-of-l` | `9a538a102e62d523954e38b9c03ba84baf67e60a` | #60 | Old ancestry not merged. Its fix is NOT in `main`: `core/MainViewModel.lua` still has no `[4]="Legendary"`. Issue #38 stays open. |
| `bugfix/test19-tooling-matt-pocock-github-tracker` | `4f2138b72edc778fabc55049b251a3872f5d4cbe` | #67 | Superseded. Its agent tooling is not carried to `main`. |
| `bugfix/test19-sync-trust-24-27-31` | `6f6204dc9e94b0339f2c9cbacf0c5de8b98a539f` | #68 | Superseded; in the stack under `eb190c5`. Issues #24, #27, #31 stay open; no closure is claimed. |
| `review/package-b-wave3-7efbd260` | `7efbd2608b8f016bd405692e8669c5082a508d14` | #69 | Historical review path. Closed as superseded, not as an accepted candidate. Findings are not claimed fixed. |
| `test/usable-beta-ci-portability` | `55640b2af055d93614862599ff02ea2f32bd06b0` | #70 | Same. |
| `review/native-tester-fixes` | `eb190c5afbccf73e1aff73f91d07769c81b74ade` | #71 | Same. |
| `publish/test.9027-3f1cd20` | `3f1cd20bc1b5f83fe2d25d8c398117332b2c374b` | — | Redundant: the tip is the immutable release tag `v1.20.0-beta.1-test.9027`. |
| `fix/pr71-wishlist-owned-confirmation` | `4dc3b39e4e9187d08d7ac1607086d7e7ac30e4f5` | — | KEPT. Its editor-draft part is in `main` (`core/WishlistController.lua`). Its owned-response cache part (`CurrentOwnedResponse` in `core/GameAdapter.lua`) is not found in `main`. Not verified as redundant. |
| `codex/community-off-followup` | `88a1c0590ec6c5c7d70988bd578da26d62c27f92` | — | KEPT. Contributor work (merged PR #9 on that line) that is on no other branch. |

Branch deletion happens only after `main` is established, after the matching
pull request is closed, and after the remote tip is rechecked against this table.
Pull-request discussion and `refs/pull/<n>/head` remain on GitHub.

## 5. Issues

The consolidation pull request closes no issue. A bug report is closed only
with a commit and evidence, stated in that issue.

- #50, #51: the later user contract is "no inferred future offers": Nexus does
  not predict guaranteed future Echo rolls from any build type. Implementation
  and offline evidence: `docs/9020_SYNC_AND_NO_GUARANTEE.md`, tests
  `rolling_no_guarantee`, `rolling_no_guarantee_runtime`, `policy_compare`. The
  earlier Snapshot-guarantee wording stays in those issues as history.
- #49 (ordinary automation's Orb guard) is separate from the later Orb spending
  feature and stays open, as do native-confirmation items.
- #38: not fixed in `main` (see #60 above). #40: fix present and covered offline
  by `typed_hash` (see #59 above); native confirmation is not claimed.
- Current limitations that stay tracked: outgoing Share losing permanent roles,
  prolonged local preparation of a Share, two-account peer transfer, remote
  withdrawal, test-record cleanup, Advisor tab attachment. Incoming rejection of
  impossible builds (#22) is a different defect from outgoing Share role loss.
- Milestone `1.20.0-beta.1-test.19` is reused as the one next-beta milestone.

## 6. After consolidation

Start every new branch from `main`. Open focused pull requests against `main`.
Release tags are immutable. Native game-client validation remains a separate,
explicitly authorized step.
