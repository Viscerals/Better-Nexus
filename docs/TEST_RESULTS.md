# P1.4 current verification

All **29 prototype-specific scripts** pass under Lua 5.4 with test-only
compatibility shims. The five added scripts cover the current-lock default,
the supplied 250-mio import, fresh-module persistence, loading UI, and actual
local recommendation/action paths while shared preparation is held pending.

Prior manual-role tests explicitly select the retained manual mode; their
assertions are unchanged. The existing 10,000-case planner comparison, evidence,
transport, and all eight startup regressions remain. Runtime inventory is now
72 TOC Lua files. Native WoW/LuaJIT, upstream full CI, and independent review
were **not run**. See `P1_4_CURRENT_LOCKS_LOADING_REPORT.md` and the delivered
source/package JSON reports for exact evidence.

Earlier sections below are historical results for their stated versions.

---

# Current test evidence: P1.3

The following sections retain historical P1/P1.1 results. For this build, use
`P1_3_SOURCE_TEST_RESULTS.json` (24 scripts) and `LOCK_ROLE_FIX_REPORT.md`.
The four new role suites include 100 named checks in the first three and an
additional actual export/import script. Package test results are supplied
separately after source freeze.

---

# Prototype P1 test record

## What actually ran

11 prototype-specific scripts passed in **Lua 5.4 with test-only Lua 5.1 API
compatibility shims**, using the installed system library through ctypes.
This was not LuaJIT, native WoW, or the original 245-runner suite. No independent
model review or public CI pass is claimed.

The 71 TOC Lua files compiled and the complete addon initialized in a synthetic
WoW/Ebonhold environment. Representative Wishlist, Community, Leaderboard,
diagnostics and command entry points were exercised with synthetic state.
The reachable runtime-closure check reported a maximum of 60 non-environment
upvalues. This is not a complete proof of all possible Lua 5.1 dynamic closures.

## Passing scripts

| Script | Coverage and result |
|---|---|
| parse | 71 TOC Lua files compiled under the stated test interpreter |
| boot | Full TOC, synthetic initialization, build/status commands, auto OFF |
| wishlist | 22 checks: real controller/key/upload adapter, 79+6 save/reopen, unchanged retry, edited-draft cancellation, dialog token, exact-quality variants, invalid inputs |
| ownership | 7 checks: notification -> actual adapter revisions -> real automation projection cache, confirmed-empty and stale controls |
| typed_hash | 8 checks: typed build/tombstone IDs, deterministic order, cache/fallback material parity |
| transport | 24 checks: legacy/negotiated directed routing, bounded CTL use, combat blocks, occupied library, unknown peer, expiry fallback, coexistence shapes |
| automation | 13 checks: actual planner-to-Freeze submission, index translation, pending-action protection, preferences, Orb guards |
| manual_sync | 5 checks: real command/lifecycle/wire request, legacy discovery, no send in combat, resumption |
| diagnostics | 40 checks: cooperative stable snapshots, concurrent history replacement, lossless UTF-8 paging, real export completion |
| features | 31 checks: feature modules, UI opening/filtering, world transition state, default manual mode, runtime closures |
| planner_reference | 10,000 generated inputs compared with supplied LoadoutPilot 1.3.6/103 for action, ID, index, reason, deficit and feasibility; four Nexus bridge controls |

The reference comparisons concern the normalized planner on those inputs, not
all malformed states or the complete live external addon. Nexus-specific safety
and settings adaptations are separate. No optimality claim is made.

## Before/after proof

The same three focused assertions failed against an isolated copy of the original
user-supplied test.28 runtime and passed on this prototype:

- Wishlist retry after draft edit must cancel instead of mixing drafts.
- Fresh confirmed-empty ownership must invalidate the cached unsynced projection.
- Numeric and string build identities must not share canonical hash material.

See BASELINE_REPRODUCTIONS.json for preserved output. The frozen user artifacts
were not edited. Earlier intermediate harness/setup mistakes were corrected
before this final run; they are not counted as product expected-red evidence.

## Limits

No game login, installed-client change, live SavedVariables access, resource
spending, real network traffic, combat capture, backup recovery, native timing,
or controlled-peer convergence occurred. Existing architectural deferrals are
not converted into passes. Full feature presence is not live feature acceptance.

The transport includes a disclosed private CTL-v21-derived compatibility fallback,
not a byte-identical official CTL distribution. Real-client/global-library
coexistence and end-to-end synchronization require volunteer testing.

Machine-readable exact runtime-file hashes and complete outputs appear in
PROTOTYPE_TEST_RESULTS.json. Final package identity appears in the external
package manifest. Packaging changes only the supported Release.buildLabel field.

## P1.1 hotfix evidence

The original P1 archive reproduces six synchronized locked Echoes plus an
evidence-pending candidate, refused editor, and `invalid wishlist` assignment.
The same synthetic source/provider/controller scenario passes on P1.1.

`tests/prototype/lock_evidence.lua` has 96 assertions covering exact 79+6
pre-association resolution, editor/export/assignment, save/reopen, unavailable
and malformed locks, active mismatch, stale clicks, fallback provenance,
inactive associations, copy subtraction, unchanged source data, and lock-only
notification recovery. Already-owned targets are correctly stored as fulfilled.

The complete 12-script prototype suite also passes, including the 10,000-case
LoadoutPilot comparison. Runtime remains Lua 5.4 with test-only compatibility
shims. A target-local Lupa install was attempted but network name resolution was
unavailable; it supplied no additional runtime or validation evidence. No LuaJIT,
plain Lua 5.1, original full inventory, independent reviewer, or native WoW result
is claimed. Intermediate fixture mistakes (NaN equality and confusing pending
with fulfilled lock targets) were corrected before the final run and are not
counted as product regressions.

Current exact outputs are supplied separately in HOTFIX_TEST_RESULTS.json and
PACKAGED_TEST_RESULTS.json. The original PROTOTYPE_TEST_RESULTS.json in this
source tree remains historical P1 evidence, not a receipt for the hotfix.
