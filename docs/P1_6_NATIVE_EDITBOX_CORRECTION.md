# P1.6 native EditBox correction

The coordinator demonstrated a native Orb-panel refresh failure on the exact
`test.9008-83a1936` package. `ui/OrbPanel.lua:17` called `Enable` on the maximum
EditBox. Native inspection confirmed that EditBox has no `Enable`, `Disable`,
`IsEnabled`, or `SetEnabled`. The failure stopped rendering before the maximum,
usage and status were populated. Advanced controls remained visible below the
closed-size panel. The prior offline PASS did not establish native acceptance.

The field now uses the confirmed legacy `EnableMouse`, `EnableKeyboard`,
`ClearFocus`, `HasFocus`, and focus-event API. Running, pending, paused and
maximum-reached states lock input, release focus and reject the field's Enter
handler before it can change configuration. Idle refresh preserves typing.
Enter, Escape and Close release focus. The actual runtime remains the authority
for maximum changes and every spend; its algorithms and adapter are unchanged.

The panel starts hidden until construction completes. Advanced starts hidden.
Local loading disables all mutation controls and the maximum field. A failed
refresh applies the same inactive state, hides Advanced, shows an explanation,
and rethrows the original error. It does not turn a partial render into usable
mutation controls or conceal the failure. Help and Close remain available.

The general synthetic harness incorrectly supplied Button methods to every
widget and fabricated unknown capitalized methods. The three new regressions
use a bounded legacy EditBox fixture without those methods. Before correction,
they demonstrated the idle `Enable` error, busy `Disable` error, and unlocked
input during loading. They exercise real UI handlers and runtime states with
fake services only. Retained tests continue to cover the spending, confirmation,
read-only Recheck, assignment and Help behavior.

The first post-fix test run exposed two test-authoring errors: the zero-balance
assertion abbreviated the actual existing explanation, and the SetLimit counter
included a later legitimate explicit Start. The assertions now require the
actual explanation and zero additional calls from a locked Enter event. Those
receipts remain preserved. No product assertion was removed to admit a defect.

Native screenshots, capability observations, the original source/package,
earlier passing and failing results, and the immutable offline handoff remain
preserved. The new package requires separate native UI confirmation by the
coordinator. No installation, native interaction, live saved-data access or
resource spending was performed by the writer. Orb spending and native result
confirmation remain unverified and unauthorized.
