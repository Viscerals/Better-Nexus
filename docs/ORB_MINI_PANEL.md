# Optional Orb mini panel

Open **Mini panel** in the Orb window to show a movable 356 × 196 status panel. It starts hidden each session. Drag its title bar to move it; its position lasts until reload. It shares the selected Nexus style and palette. The difficulty / Soul Ash card is unchanged.

The panel shows run status, the reason, Orbs used against the approved maximum, pending operations and **rolled target copies** still missing. Missing data is shown as unavailable; zero rolled copies does not mean the entire build is complete. During local restore it shows loading and unavailable counts; the footer re-enables after local readiness. Lines do not wrap, and every nonempty line is available in full on hover, including short text that a wider client font clips.

Pause and Resume occupy separate fixed buttons. Each click reads status again, then calls the existing runtime action with its final checks. Resume retains the approved maximum and usage. Its outcome is read again after the action, because the runtime may immediately pause or end the run. An ordinary pending spend can resume; restored or selected operations and changed assignments retain their runtime restrictions. Stop prevents another Orb spend; an operation already submitted may still settle. **Open Orbs** opens the full window. Starting a run and approving its maximum remain in that full window.

Close and Escape hide only this panel. An approved run continues; use Pause or Stop to change it. Reopening reuses the panel and clears its old action notice. Visible status refreshes four times per second; hidden status does no work. Showing, moving and closing the panel do not save settings or placement.

`tests/prototype/orb_mini_panel.lua` exercises the real handlers and Orb runtime through synthetic WoW/services, plus fault injection for stale, malformed, missing and failed reads. It tests pending Stop, repeated and nested clicks, tooltips and a geometry model. Native font pixels, client skins, keyboard Escape, actual dragging and server effects require an in-client check; offline tests and the SIMULATED preview do not establish those effects.

Recovery checking/ready/held/refused phase appears first in the compact main strip
and mini state line, before long exposure totals. The phase is an owned scalar;
rendering it adds no active intent/flight/read call. Optional missing uncertain or
outcome totals display unavailable rather than measured zero. A present malformed
historyKnown/count fact disables mini actions; a typed false historyKnown retains
the explicit after-reload unknown-history explanation. Full text remains available
on hover; this is not native font-fit evidence.
