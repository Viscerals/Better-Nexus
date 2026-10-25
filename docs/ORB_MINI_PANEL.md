# Optional Orb mini panel

Open **Mini panel** in the Orb window to show a movable 356 × 196 status panel. It starts hidden each session. Drag its title bar to move it; its position lasts until reload. It shares the selected Nexus style and palette. The difficulty / Soul Ash card is unchanged.

The panel shows run status, the run's reason, Orbs used against the approved maximum, pending operations and **rolled target copies** still missing. Missing data is shown as unavailable; zero rolled copies does not mean the entire build is complete. During local restore it shows loading and unavailable counts; the footer re-enables after local readiness. Lines do not wrap. A long value is shortened on a character boundary, and every nonempty line shows its complete text on hover, including short text that a wider client font clips. The line limits follow an offline character model, not a native measurement. They do not show that long text fits native pixels or the line height of a doubled font.

The Orb window, the main Nexus panel strip and this panel share one run-control model. It covers fixed Pause and Resume, the Resume target, target review in the full window, usage and pending wording, and the unrecorded maximum. It is described in [User interface and local readiness](ORB_MEMORY_MODE.md#user-interface-and-local-readiness); this page describes the mini panel's compact form.

Pause and Resume occupy separate fixed buttons. Each click reads status again and acts only if that read offers the action. It then calls the existing runtime action with its final checks; a click grants nothing beyond those checks. Resume retains the approved maximum and usage. Its outcome is read again after the action, because the runtime may immediately pause or end the run. An ordinary pending spend can resume; restored or selected operations and changed assignments retain their runtime restrictions. The mini panel never offers Resume for a changed target, new or back, even after it was reviewed in the full window. Stop prevents another Orb spend; an operation already submitted may still settle. **Open Orbs** opens the full window. Starting a run and approving its maximum remain in that full window.

While a run is paused, the reason line keeps the run's own reason, shortened to the line and complete on hover. What Resume would act on (the runtime's `resumeTarget`) is named on the rolled-copies line, after the count: "Rolled missing: N; 'name'". An unavailable count shows "?", never 0. The count keeps its meaning, the rolled target copies still missing at the latest check; it is not relabelled as the named target's progress. For a pending run the name is that of the original operation Resume continues. For a settled run it is the ready Wishlist Resume would use: unchanged, new, or changed and back. "(unnamed)" stands for a Wishlist without a name. "target ?" stands for a target the runtime reports as unknown because the assigned Wishlist is not ready. A long name is shortened on a character boundary inside its quotes. The length is a character count from the offline doubled-font model rather than a native measurement, and no native fit of a full name or of the line's height is promised. The hover keeps the complete count, the complete target with its kind ("Resume uses: …", "New target: …", "Target back to …" or "Resume target unknown") and what the line means. The visible name carries no kind; the state line says when a target needs review. When Resume is blocked or not offered, no target is guessed. For example, an operation that must settle first, a record restored after a reload or a run that can no longer resume shows only the count.

While paused, the state line says what holds Resume:

- "Paused - review the new target in Open Orbs", or "Paused - review the target in Open Orbs" for a target that came back.
- "Paused - the assigned Wishlist is not ready".
- "Paused - this run can no longer resume" for a run that no longer owns its approval or action. The way on is Stop and a new approval. A loading screen does not necessarily end approval.
- "Paused - a pending result must settle first" for another paused state without an offered Resume, such as an operation that must settle or a restored or already selected one.

Not every such state offers Continue; **Open Orbs** shows the explanation and any eligible Continue. A refused Resume click is worded the same way ("Not resumed: …"). For a changed target, **Review target**, **Cancel review** and the reviewed Resume happen only in the full window, on the exact target shown there; Review target and Cancel review write, send and spend nothing. Usage keeps the mini form "Orbs used: N of M approved". A restored receipt without a recorded approved maximum shows "Orbs used: N (maximum not recorded)" instead of a number. The configured fallback still gates it, and it is not a new approval.

The pending line counts Orbs requested whose spend is not confirmed yet: "Pending: N Orbs requested, not confirmed yet". With none pending, an unsettled last action reads "Last Orb result is not settled" instead; that is not a pending count. The line changes form when unknown spend exposure or unconfirmed outcomes are present, or earlier totals are unavailable after a reload. It then keeps the three apart ("Unknown spend: X; Reserved: N; Outcomes: U", with "?" for an unavailable count). Reserved is the same requested, not-confirmed count. The hover gives the complete explanation, including an awaited Orb result. These counts stay apart from Orbs used. None is taken as a confirmed spend, a refund or a settled result.

Close and Escape hide only this panel. An approved run continues; use Pause or Stop to change it. Reopening reuses the panel and clears its old action notice. Visible status refreshes four times per second; hidden status does no work. Showing, moving and closing the panel do not save settings or placement.

`tests/prototype/orb_mini_panel.lua` exercises the real handlers and Orb runtime through synthetic WoW/services, plus fault injection for stale, malformed, missing and failed reads. It tests pending Stop, repeated and nested clicks, tooltips and a geometry model. `tests/prototype/orb_target_review.lua`, `orb_fixed_pause_resume.lua` and `orb_recovery_layers.lua` exercise target naming and review, the fixed controls, and recovery and usage wording through the same real handlers. Native font pixels, client skins, keyboard Escape, actual dragging, double-clicks and server effects require an in-client check; offline tests and the SIMULATED preview do not establish those effects.

Recovery checking/ready/held/refused phase appears first in the compact main strip
and mini state line, before long exposure totals. The phase is an owned scalar;
rendering it adds no active intent/flight/read call. Optional missing uncertain or
outcome totals display unavailable rather than measured zero. A present malformed
historyKnown/count fact disables mini actions; a typed false historyKnown retains
the explicit after-reload unknown-history explanation. Full text remains available
on hover; this is not native font-fit evidence.

Owed-offer Resume eligibility in compact views uses the last complete pump
observation plus the current native latch scalar. Rendering does not refresh
active intent, flight, ownership or catalog facades. That display observation is
not server freshness or permission: explicit Resume reads all current guards
again before choosing the already-approved offer.
