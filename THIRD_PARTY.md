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

## LoadoutPilot

Behavioral reference: user-supplied LoadoutPilot (6).zip, version 1.3.6,
patch 103, build P103-V1.3.6-LEVEL80-ONE-SHOT-20260825.
SHA-256: `d471335ce243a7c0a42b1c2b22434bc757dca1ba40b852e8ded2545d7902190e`.

`logic/WishlistPilot.lua` is an independent behavioral implementation, not a
copy of the external addon or its UI/assets. The differential harness runs the
supplied reference separately on synthetic inputs. Original LoadoutPilot source
and assets are not redistributed in the installable package. No claim of
mathematical optimality, universal equivalence on malformed input, or native
Nexus validation is made. Nexus-specific input, setting, Snapshot and action
safety adaptations are documented in the prototype README.

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

## P1.5 Memory-mode reference and independent integration

`logic/OrbPolicy.lua`, `core/OrbAdapter.lua`, `core/OrbRuntime.lua`, and
`ui/OrbPanel.lua` are new Nexus implementations informed by the supplied
`Memory/MemoryMode.lua`, `UI/MemoryPanel.lua`, integration and runtime modules.
No LoadoutPilot Lua implementation, UI, assets, or database is included in this
installable archive. The supplied archive remains an external test reference.

Reference API calls are `OrbService.IsStateKnown/GetCharges/IsOfferPending/
ConfirmSpend/RequestCharges` and the documented-in-reference PerkService choice,
granted, locked, selection, and refresh calls. No action probe or speculative
spending API is used. Presence/shape checks do not establish native compatibility.

Nexus adaptations are intentional: exact quality and role-aware targets; a
separately confirmed per-run source pool and cap; explicit opt-in recycling;
conservative same-ID permanent-copy exclusion; usable partial runs rather than
requiring enough source capacity for every remaining target; fresh response plus
charge/diff reconciliation; persistence of passive unresolved-operation evidence;
stricter no-replay behavior for ambiguous spending/selection; and no ordinary
Automation restart. These adaptations are not a claim of byte-for-byte or
unconditional behavioral equivalence.
