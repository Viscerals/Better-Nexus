# Boundaries to preserve

**Preparation only; source pin and status are in [README](README.md).** The
working terms below distinguish evidence and intentions. They do not define a
new stored type or replace the current contract.

Read the issue's [later units correction](https://github.com/Viscerals/Better-Nexus/issues/47#issuecomment-6080819599)
with its original requirements; the older 6/85 wording is not a universal
held-evidence or server rule.

## Current units and authority

| Concept | Established source boundary | Consequence for #47 |
| --- | --- | --- |
| Exact authored Wishlist | At most 79 ordinary copies and six locked target copies; the two roles remain separate. This is a design envelope. | Do not turn extra acceptable alternatives into exact requested copies or increase existing limits. |
| Flexible planning pool | Requested in #47, with entity and resolution still undecided; not implemented in the inspected paths. | Membership would express acceptability, not current ownership, a complete exact build, or action authority. |
| Held locked evidence | Occupied native records, stacks within each record, per-spell copies and reported capacity are separate facts. | Do not count records as copies, merge the roles, or discard held copies merely because they exceed six. |
| Received/durable locked evidence | Bounded by resource ceilings rather than a guessed native capacity. | A representable held set is not necessarily an authored design or a server-legal loadout. |
| Resolved exact target | A future output whose semantics must first be agreed; no resolver exists in this slice. | Before any action-facing use it must meet the existing applicable exact-target validation and readiness gates. A pool is never a substitute for that result. |

The authoritative details are
[`CONTRACTS.md:96–156`](https://github.com/Viscerals/Better-Nexus/blob/18dc5b0313033dbc522bec1ab89c304078aa5645/CONTRACTS.md#L96-L156):

- The live locked projection counts recognized occupied records and keeps exact
  stacks. Its live capacity may be unavailable; retained positive capacity has
  unobservable freshness. Server enforcement and one-record-per-spell are not
  established.
- Durable evidence has resource ceilings of 256 locked rows, 120 copies in one
  row and 10,000 copies in all, beside at most 79 ordinary copies. These are
  parser/resource limits, not a server budget.
- The separate DPS wire remains narrower: each received ordinary or locked
  Echo list has at most 120 entries and 120 copies in all.
- Wishlist design, Share plan limits and EBH1 use the authored 79 ordinary /
  six locked-target-copy / 85-total envelope. Unknown native/server legality
  does not justify changing those established compatibility rules.

[`LoadoutEvidence.SemanticLimits` and `PlanLimits`](https://github.com/Viscerals/Better-Nexus/blob/18dc5b0313033dbc522bec1ab89c304078aa5645/core/LoadoutEvidence.lua#L1160-L1185)
make the distinction explicit. A future pool needs its own agreed storage and
projection bounds; none of the numbers above is automatically its capacity.

## Exactness must survive the boundary

The current draft has explicit design-copy and occupancy checks
([`WishlistModel`](https://github.com/Viscerals/Better-Nexus/blob/18dc5b0313033dbc522bec1ab89c304078aa5645/core/WishlistModel.lua#L367-L440)).
`Strategy.Compile` separately counts all requested copies and locked requested
copies, preserving explicit source roles
([source](https://github.com/Viscerals/Better-Nexus/blob/18dc5b0313033dbc522bec1ab89c304078aa5645/logic/Strategy.lua#L106-L137)).
Ordinary quality progress also has exact-tier accounting; lower-tier surplus
does not satisfy a higher exact quota
([`Model.TargetProgress`](https://github.com/Viscerals/Better-Nexus/blob/18dc5b0313033dbc522bec1ab89c304078aa5645/logic/Model.lua#L402-L435)).
A proposed alternative/substitution rule must state how it differs without
silently redefining these existing meanings.

Keep exact ordinary fingerprints/build identity unchanged. Do not infer
completeness from array length or a claimed count: current
[`OrdinaryCompleteness`](https://github.com/Viscerals/Better-Nexus/blob/18dc5b0313033dbc522bec1ab89c304078aa5645/core/LoadoutEvidence.lua#L710-L805)
checks evidence, roles and fingerprint agreement. Pool membership cannot be
relabeled as observed ownership or complete received loadout evidence.

## Action, persistence and sharing boundaries

Any future resolved target still passes the current action gates. Pool design
must not weaken unknown/pending-state waits, role trust, unresolved action
tracking, or spending permissions. The authoritative
[rolling and Orb contract](https://github.com/Viscerals/Better-Nexus/blob/18dc5b0313033dbc522bec1ab89c304078aa5645/CONTRACTS.md#L16-L95)
also forbids inferred future-roll guarantees; acceptable alternatives predict
no future offer.

Do not reuse an existing exact encoding as a new pool encoding. For example,
[`Codec.EncodeEBH1`](https://github.com/Viscerals/Better-Nexus/blob/18dc5b0313033dbc522bec1ab89c304078aa5645/core/Codec.lua#L451-L504)
has bounded exact rows and a scoped Nexus locked-role extension; its source
explicitly does not claim native importer support for that extension. Pool
sharing, format negotiation and older-peer handling remain pending decisions.

No migration is specified or run here. Any future additive saved-format design
must preserve existing data, unknown/future fields, exact identities and rollback
behavior under repository policy. Current assignment and locked-design
ambiguity protections also remain intact
([`CONTRACTS.md:157–181`](https://github.com/Viscerals/Better-Nexus/blob/18dc5b0313033dbc522bec1ab89c304078aa5645/CONTRACTS.md#L157-L181)).
An attractive pool name or matching ordinary contents cannot prove assignment
or authorize borrowing a different retained locked design.
