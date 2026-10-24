# Future acceptance matrix

**Prospective scenarios only. No feature, fixture, test or native result is
implemented or claimed by this document.** The [pending choices](RESOLUTION_OPTIONS.md)
must be accepted before expected resolver behavior can be made executable.
Scenario labels are document references, not a new runtime contract.

The first eight rows trace the eight regression requirements in
[#47](https://github.com/Viscerals/Better-Nexus/issues/47). Apply its
[later units correction](https://github.com/Viscerals/Better-Nexus/issues/47#issuecomment-6080819599)
to rows A05/A06 and the older issue wording: the authored locked-target limit is
not a universal held-evidence or server limit.

| ID / issue requirement | Future discriminating setup | Required invariant or decision-dependent outcome |
| --- | --- | --- |
| A01 / exact Wishlist unchanged | An existing valid exact 79-ordinary Wishlist, including role/quality and identity controls, before and after a future pool feature. | Existing exact validation, compilation, fingerprint, assignment and action permission results stay unchanged. Compare against the same source baseline; a matching displayed count alone is insufficient. |
| A02 / more than 79 alternatives | A pool with more than 79 distinct acceptable alternatives, plus an ordinary exact Wishlist control. | The agreed pool representation may retain its allowed alternatives but cannot be classified as an exact complete loadout or fed directly to action/Sync admission. Future pool bounds still apply. |
| A03 / valid exact resolution | An agreed resolvable pool and its explicit context, with a deliberately over-budget output control. | Any proposed actionable result has at most 79 ordinary copies and meets all applicable existing role/design, completeness and readiness rules. A shorter unresolved target must not be labeled complete. Exact selection depends on the accepted resolver contract. |
| A04 / impossible or ambiguous | Unsatisfiable requested quotas, conflicting alternatives and indistinguishable preference outcomes under the selected contract. | Do not fabricate completeness, ownership or an action target. Define an explicit unresolved/refused result before implementing assertions; no incidental iteration-order winner. |
| A05 / separate locked targets | Same spell represented in ordinary and locked roles; authored locked-target copies at six and above six; independent held-lock record/copy observations. | Existing authored design limits still refuse invalid target designs. Held evidence above six is not discarded merely for exceeding that design budget; occupied records and live capacity remain distinct. |
| A06 / sharing boundary | Pool-shaped input presented to existing exact import/Community/Sync paths, alongside valid exact and valid received held-evidence controls. | No pool is admitted as an exact complete build by count, name or reused identity. Preserve current evidence/resource and peer-compatibility rules. A distinct pool exchange is unavailable unless separately designed and accepted. |
| A07 / reload determinism | Agreed pool and result lifecycle across serialization/reload, plus unknown/future fields, local edits and catalog/context changes. | Preserve current saved data and exact identities. Assert deterministic retention/resolution only against the accepted input/lifecycle contract; make context invalidation explicit rather than silently recomputing a different target. No migration format is assumed here. |
| A08 / bounded UI work | Maximum supported pool/collection sizes and malformed/oversized inputs at the later agreed limits. | Demonstrate bounded parsing, storage, projections and visible work; unknown size must not become unbounded per-frame traversal. Specific budgets and any refusal/truncation behavior require design decisions and measured evidence. |

## Cross-cutting negative controls

| ID | Future control and boundary |
| --- | --- |
| C01: units | Keep valid held locked evidence above six copies, repeated occupied records and unknown capacity distinct from an invalid authored seven-copy locked target. Resource ceilings and the narrower DPS wire are separate controls; none proves server legality. |
| C02: evidence authority | Missing, conflicting, cross-role or fingerprint-mismatched exact evidence remains unavailable under existing rules. Neither pool membership nor `#echoes == echoCount` supplies missing completeness authority. |
| C03: quality and provenance | Lower-quality surplus, same-family variants, equal ordinary contents with different locked designs, and local/shared edits must not borrow fulfillment or a design without the accepted exact/provenance rules. |
| C04: actions | Unknown/pending native state, an unresolved action and insufficient permission still stop the existing action path. Adding alternatives does not submit an action, grant ownership, predict an offer or remove a safety wait. |
| C05: scope | Existing exact encodings, current fingerprints, older-peer behavior and unknown/future fields survive unchanged unless a separately approved migration/protocol change explicitly covers them. |

The current anchors for these controls are the authoritative
[`CONTRACTS.md:16–181`](https://github.com/Viscerals/Better-Nexus/blob/18dc5b0313033dbc522bec1ab89c304078aa5645/CONTRACTS.md#L16-L181),
[`LoadoutEvidence.OrdinaryCompleteness`](https://github.com/Viscerals/Better-Nexus/blob/18dc5b0313033dbc522bec1ab89c304078aa5645/core/LoadoutEvidence.lua#L710-L805),
and the exact-target source references in [Boundaries](BOUNDARIES.md).

## Evidence required later

Future authors must retain meaningful baseline failures for new behavior,
passing controls for existing exact behavior, final-source focused/full checks,
and independent Spec/Standards review. These scenarios do not prescribe a test
file, runner edit, implementation order or release. A synthetic pass cannot
prove native UI, server budgets, response hydration, resource-spending safety or
wire compatibility with a real peer. Those boundaries need their own authorized
evidence when relevant. Until the design is accepted and implemented, #47 stays
open and this feature remains outside the current beta.
