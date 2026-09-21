# NATIVE-02: Help over the Orb window

On exact installed `test.9009-e013e51`, the coordinator confirmed that the
previous native EditBox correction works. Assignment, zero balance, maximum,
usage and status render. Idle typing survives timer refresh. Escape restores
the saved maximum; Enter releases focus. Advanced and read-only Recheck work.

The actual Orb Help button then opened Help page 5 over the still-shown Orb
window. Text and buttons interleaved. Read-only native output was:

`P16LAYERS 30 30 31 32 DIALOG`

Orb and Help both had parent level 30. Help scroll/content used 31/32. Orb
buttons used 32; Advanced and its controls used 31/33. The two windows shared
the same DIALOG layer band. The observation does not establish a global native
API clamp. Earlier Help-alone native successes remain valid for their cases.

Help now uses parent/scroll/content-and-navigation levels 40/41/42. Its opaque
background is above the entire known Orb subtree. Each Help child stays above
its own background. The levels also remain below the earlier observed
high-level Help layout failure. No dynamic window manager or new UI flow is
introduced. Both windows retain their shown state. Help Close reveals Orb;
Orb Close still only hides an approved run. No spending or confirmation logic
changes.

The new fail-capable regression invokes the actual Orb Help button with
Advanced shown. It checks the complete visible subtree, content and navigation,
both reopening orders, Help navigation, running Close, and a paused ready offer
through timer refresh and Recheck. It asserts unchanged actions, Sync traffic,
approved limit, spent count and unresolved exposure for passive paths. It fails
on the old Help level 30 against Orb control level 33. It uses synthetic data
and does not claim native pixel, click or keyboard confirmation.

The prior source, package, sealed handoffs, native successes and new failure
screenshots remain preserved. All prior 75 scripts are retained. A unique
replacement must pass source/package tests and fresh focused review before the
coordinator's separate non-spending native recheck. No native action or live
saved-data access is performed by the writer. Orb spending remains untested
and unauthorized.
