# Prototype provenance

## Nexus / Better-Nexus

Runtime foundation: user-supplied `Better-Nexus-internal-test-eb190c5-exact.zip`,
SHA-256 `35b92525eb589c7c26a9a44c25d86363f818ad7b1f2915b67cc995d6dcb9924c`.
Published reference: Viscerals/Better-Nexus commit
`eb190c5afbccf73e1aff73f91d07769c81b74ade`.

The local source repository imports that archive with CRLF normalized to LF.
Its import commit is therefore not falsely identified as the original upstream
Git commit. Original LICENSE.md, UPSTREAM.md and AI_POLICY.md are preserved.
The prototype is produced for the project's authorized user; it grants no new
rights over the project's upstream material.

## EchoWeaver (Nexus rolling and Orb engine)

EchoWeaver is the name of the rolling and Orb engine maintained in this
repository: `logic/EchoWeaver.lua` (ordinary rolling), and `logic/OrbPolicy.lua`,
`core/OrbAdapter.lua`, `core/OrbRuntime.lua` and `ui/OrbPanel.lua` (Orb mode).
Its base strategy was reimplemented independently from the observed behavior
of a separately distributed Echo-picker addon that the user supplied, archive
SHA-256 `d471335ce243a7c0a42b1c2b22434bc757dca1ba40b852e8ded2545d7902190e`:
for ordinary rolling the action order, tie breakers and reason codes, and for
Orb mode the source, target and fallback rules. Nexus's own rules on top of it
are documented in `CONTRACTS.md` and `docs/ROLLING_ORB_REVIEW_EADFF8A.md`.
During the prototype phase the behavior was also compared offline with that
addon; that comparison is retired (2026-09-24). No source, UI, assets or database of that
addon are in this repository or in the installable package. The supplied
archive contains no license or notice file; no notice obligation from it
applies here. No claim of mathematical optimality or native validation is made.

Compatibility exception: `A.RivalDetected()` in `core/GameAdapter.lua` detects
that separately distributed addon by its exact addon name and slash-command key,
so Nexus pauses automation while another picker may own the same server
actions. These two identifiers are detection keys, not Nexus names;
`tests/prototype/rival_picker_detection.lua` keeps the protection tested.

## ChatThrottleLib

Mikk's ChatThrottleLib is published as public-domain software by its project.
Classic-client reference inspected: WoWUIDev/Ace3 commit
`5f34ac009746e4cc16cc867ea743efa01997c0a7`,
`AceComm-3.0/ChatThrottleLib.lua`, version 21 (2009-08-07).

The included file is explicitly a compact private compatibility adaptation of
that scheduling/API design, NOT an exact official upstream release. It keeps
priority rings, byte pacing, post-zone/low-frame-rate clamping, global traffic
accounting and callback shape, while handling local call failure and remaining
private if no compatible global library exists. It does not overwrite a global
library. The prototype uses a compatible existing global CTL where available.

Reference source:
https://github.com/WoWUIDev/Ace3/blob/5f34ac009746e4cc16cc867ea743efa01997c0a7/AceComm-3.0/ChatThrottleLib.lua

No new license restriction is asserted on the public-domain-derived portion.
Full official-library/native transport acceptance remains unproven.

## EchoWeaver Orb mode: game calls and Nexus adaptations

The Orb mode files named above are Nexus code. No Lua implementation, UI,
assets or database of the separately distributed addon is included, and its
archive is no longer used by any test.

Game API calls used: `OrbService.IsStateKnown/GetCharges/IsOfferPending/
ConfirmSpend/RequestCharges` and the PerkService choice, granted, locked,
selection, and refresh calls. No action probe or speculative
spending API is used. Presence/shape checks do not establish native compatibility.

Nexus adaptations are intentional: exact quality and role-aware targets; a
separately confirmed per-run source pool and cap; explicit opt-in recycling;
conservative same-ID permanent-copy exclusion; usable partial runs rather than
requiring enough source capacity for every remaining target; fresh response plus
charge/diff reconciliation; persistence of passive unresolved-operation evidence;
stricter no-replay behavior for ambiguous spending/selection; and no ordinary
Automation restart. These adaptations are not a claim of byte-for-byte or
unconditional behavioral equivalence.
