# Update notices and release identity

Offline-verified only. Nothing here was tested in the game client.

## Correction of 2026-09-21: peer versions are not release evidence

Reported on internal test.9028: "A newer Nexus release was reported: 1.96.6 … This report is not verified." Reproduced on test.9029 (`core/Updates.lua`): a peer version in one of two fixed shapes was stored as a peer advisory (`NexusDB.updateAdvisory`), announced in chat, shown in the menu, the popup and the HUD badge, announced again at the next login from saved data, and it replaced bundled release evidence when it was higher. A number chosen by another client never proves that a Better-Nexus release exists.

Now:

- Only release metadata shipped inside the package (`Release.availableVersion`, optional `availableTest`) produces a candidate, a chat notice, the menu and popup text or the HUD badge.
- A peer version is a bounded session diagnostic (`Updates.PeerObservations()`, at most 32 senders, with its shape: `reported = "test" | "stable" | nil`). It is not saved and triggers nothing. Many peers, a higher number or `+test.N` metadata do not change that.
- A peer advisory saved by an earlier build is moved once to `NexusDB.updateAdvisoryQuarantine` (bounded fields, reason "peer report is not release evidence") and never read for a notice. Settings, the preference, dismissals and bundled notices are unchanged.
- Without bundled evidence the status is **unknown** with the configured Releases page: neither "update available" nor "latest".
- Sync peer handling is unchanged: every request with a valid version is accepted as before, and packages still announce their own version.

Limit: Nexus makes no network request, so an installed build learns about a later release only from metadata in its own package, which cannot know future releases. The Releases page link in `/nexus update` and the menu is the way to check. Sections below that describe peer advisories are the design of #78 and are **superseded** where they conflict with this section.

## What was wrong in test.9027

| Place | Defect |
|---|---|
| `logic/Version.lua` | `publishedCandidate` is true only without prerelease or build identifiers, so no beta or test build could ever be a candidate. |
| `core/Updates.lua` | The comparison used `Release.baseVersion` (1.19.5), not the installed build. The only visible candidate was a bundled `Release.availableVersion`, which no package contained. |
| `core/Updates.lua`, `core/Sync.lua` | A peer version was stored and never shown. The announced version had no test number, so test.9027 and a later test build of the same series looked identical. |
| `ui/Panel.lua` | The menu entry was disabled without a bundled candidate, so not even the Releases link was reachable. |

Changing `published`, a label or a parser flag would not have fixed any of these.

## One declared release identity

| Item | Rule | Example |
|---|---|---|
| Release series | `version` in `data/Release.lua` | `1.20.0-beta.1` |
| Package label | `test.<N>-<commit>`, given to `tools/build_package.py --label` | `test.9028-abcdef0` |
| Order inside a series | the number `N`, compared numerically. The commit suffix names the source and never orders. | 9 < 10 < 9999 < 10000 |
| Git tag | `v<version>-test.<N>` | `v1.20.0-beta.1-test.9028` |
| Release asset | `Better-Nexus-test.<N>-<commit>.zip` | |
| Announced to peers | `<version>+test.<N>`, at most 32 bytes, **public test packages only**. Development source states `<version>+dev`, an internal package `<version>+internal`, a stable release the plain version. | `1.20.0-beta.1+test.9028` |
| Shown in game | `<version> test.<N>` | `1.20.0-beta.1 test.9028` |

`tools/build_package.py` makes two declared substitutions in `data/Release.lua`: the label, and the channel (`public-test` with `--public`, otherwise `internal`). `Nexus.ReleaseIdentity()` is the one function that the comparison, the announced version and every visible label read.

| Channel | Meaning | Announces a test number |
|---|---|---|
| `development` | repository source (`buildLabel = "source"`) | no (`+dev`) |
| `internal` | review or internal package | no (`+internal`) |
| `public-test` | package built with `--public` for a public test release | yes |
| `stable` | stable release | no (plain version) |

No tool writes the `stable` channel yet. A stable release needs that one declared substitution added to `tools/build_package.py` when it is planned.

## How a client learns about a newer build

1. A public test package states `<version>+test.<N>` in the **existing** version field of its ordinary Sync request (`WLRQ`). No packet gains a field. The `+…` part is SemVer build metadata: standard precedence ignores it, so every other user of `logic/Version.lua` is unaffected.
2. The receiving client validates the request exactly as before (`SyncInbound`), then hands the parsed version to `Updates.Observe`.
3. A peer can report only two fixed shapes: a stable release `X.Y.Z` (no prerelease, no build metadata) or a public test build `X.Y.Z-<alpha|beta|rc>.<n>+test.<N>`. Every other valid version is kept as a bounded diagnostic observation only: a prerelease without a public test number (older published lines such as `1.20.0-beta.3.community-off`, internal packages, development checkouts, test.9027 itself), free-form prerelease text, a commit or any other build metadata. The shown text is rebuilt from numbers and those fixed words, so no text chosen by a peer reaches chat, the menu, the popup or saved data.
4. The observer compares against the installed identity: release series by SemVer precedence, then `N` inside the same series. Same or older builds and the old stable line produce nothing.
5. *(Superseded 2026-09-21: no peer advisory is created or shown; see the correction section.)* Earlier design — a newer build became a **peer advisory**: "A newer Nexus test build was reported: … You have … Check GitHub Releases before updating. This report is not verified." One chat notice per new target per session; none after the user opened the notice (the last eight seen targets are remembered); at most three update chat lines per session, and per kind (test build, stable release) eight quick stored changes and then one per five minutes. A peer that raises its number in every request cannot fill the chat or the saved data, false test reports cannot stop a stable report, and the bound is never a full stop: after the first eight changes of a kind in a session, one further change of that kind is recorded per five minutes. A single honest report that arrives inside such a window is not queued, so under a continued flood by one peer it can be missed until the flood stops or the next session starts. After the third chat line the menu and `/nexus update` stay current; the next chat line comes in the next session.
6. The menu, `/nexus update`, the popup and Help show the installed build, the channel, the state and the locally configured Releases page. They work during loading, with no peer, no report and no Community catalog.

Trusted evidence is only release metadata shipped inside the package (`Release.availableVersion`, optional `availableTest`). It keeps the wording "New Nexus test build available: …". A peer version never becomes that: not by a high number, not by many agreeing peers, not by `+test.N` metadata, not by a peer's own `published` flag. Since 2026-09-21 a peer version is not stored and produces no notice at all (correction section above); the only saved peer state is the one-time quarantine record of an advisory saved by an earlier build. It holds no peer name, no peer text and no link. The only link ever shown is `Release.releasesUrl`, checked against the fixed GitHub Releases form.

Preferences: update notices on/off (unchanged setting), and stable + test builds (default on any beta or test installation) or stable only (default on a stable installation). Stable-only users are never shown a test build. Nobody is shown the old stable line as an upgrade from a newer beta.

## Limits — what this cannot do

- **No evidence means unknown, not latest.** A client learns about a newer build only from release metadata in its own package. Otherwise the status reads "Update status unknown" with the Releases page. Nexus makes no network request, polls nothing and cannot read GitHub. Versions stated by other players' clients are not used.
- A fixed file inside an old ZIP cannot learn a later release. Changing a GitHub release page or metadata in a new ZIP does not update old clients.
- A peer can state any valid version, also a false high one. Since 2026-09-21 that is only a bounded session diagnostic (`Updates.PeerObservations()`): no notice, no saved state, no effect on bundled evidence.
- `release_check.py --require-newer` compares with tags of the same release series only, and it needs the tags in the clone (`git fetch --tags`; it fails when the clone has no tags). It cannot know about other published lines.
- A development checkout (`buildLabel = "source"`) has no test number, so bundled metadata cannot place it inside its own release series. A newer series or a stable release in bundled metadata is still compared.
- **Rollout.** Installed clients cannot learn about a later release by themselves: every update is a manual download from the Releases page. Internal test.9028 and test.9029 packages still show peer-reported notices (the defect corrected here); public test.9027 and older clients show none. Old immutable assets are not rewritten.

## One-time transition announcement (not sent yet)

To be posted by the maintainer, once, on Discord and in the GitHub release notes of the first corrected public test package. Replace the bracketed parts. Do not post it before that release exists.

> **Nexus [version] test.[N] — manual update.**
> Nexus cannot tell you that a newer build exists: it does not check GitHub, and it does not treat versions stated by other players' clients as releases. `/nexus update` and the menu always show your installed build and open the Releases page; check there for new builds. Nexus never downloads or installs anything.
> Download: [release link]. Close WoW, back up `Interface/AddOns/Nexus` and `WTF`, replace the `Nexus` folder. Checksum: see `SHA256SUMS.txt`.

## Release steps that stay manual

`python tools/build_package.py --label test.<N>-<commit> --public`, then `python tools/release_check.py --label … --zip … --tag … --sums … --require-newer`. Creating the tag, the prerelease, the asset upload and any announcement remain explicit, human-authorized steps ([RELEASE_SECURITY.md](../RELEASE_SECURITY.md)). After publication, verify on GitHub that the release is a prerelease (not a draft, not "latest" stable), that the tag points at the packaged commit, and that the downloaded asset matches `SHA256SUMS.txt`. No workflow in this repository reacts to a tag, a release, a branch or an archive tag; `tools/release_selftest.py` in CI proves that the checks fail where they must.
