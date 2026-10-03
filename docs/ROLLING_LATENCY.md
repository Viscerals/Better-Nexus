# Client-side delay between Echo actions (early poll)

Status: private experimental change. Offline evidence only (simulated clock, mocked server).
No native measurement, no server measurement, no promise of live speed.

## Where the time goes between two automatic actions

One automatic action needs these steps. Only the addon's own steps are changed here.

| Step | Kind | Time |
|---|---|---|
| Server round trip, client reply handling | server and client | not controlled by Nexus |
| Reply seen by the loop | polling | up to 0.2 s (the loop ran only on a 0.2 s tick) |
| Decision, panel and overlay render | CPU | about 1 ms per step offline, including the simulated services |
| Intent beat: the action is shown, then sent | configured cadence | 0.4 s (`ACTION_INTENT_BEAT`), unchanged |
| Scheduled deadline (beat over) seen by the loop | polling | up to 0.2 s after the deadline |
| Adapter send | synchronous | no spacing for Take, Banish, Freeze, Reroll |
| Confirmation | server | a board change, a cleared client latch, a grant: never time |

Before this change one cycle (send to next send) at 60 fps was 0.65 s whenever the round
trip was under 0.2 s. That is the 0.4 s beat plus 0.2 s of waiting for the next poll tick plus
about 0.03 s of frame rounding.

## Hypothesis and change

The loop (`AutomationRuntime.RunUpdate`) polls the adapter every 0.2 s. A server reply and
a due deadline both wait for the next tick. The early poll runs the same poll sooner:
while Auto is ON, at most once per 0.05 s, when a scheduled step is due or the client has
reported a board or Echo-data notification (`GameAdapter.NotificationPending`, read only).
A notification is set by the client's board and Echo-data hooks (Show, UpdateSinglePerk, the
Echo data hook). They are meant for server replies; a hook can also fire for another caller,
and that is harmless because the same poll only reads and reconciles.

Scope: the early poll wakes the whole loop, so other time-paced work whose deadline is due also
runs at its deadline instead of at the next tick: Tome-lever sends (0.5 s spacing) and auto-lock
retries. Their own spacing checks are unchanged; the effective lever spacing can move from about
0.6 s to about 0.5 s plus a frame (estimated from the code, not measured).

Not changed: the poll itself, the confirmation rules (latch, board transition, grant), the
in-flight and awaiting-grant holds, the unconfirmed/uncertain/expired states, the 0.4 s beat,
authorization, the one-intent-one-action rule, the policy, resource and permission checks,
Orb recovery, same-ID handling, zone and reload handling. No server action is sent earlier
than before relative to its own intent beat, and no action is pipelined: a second action still
needs the first one confirmed.

Bounds and guards:
- Auto OFF: no early poll, no extra read.
- Auto ON: after 0.05 s without a poll, each frame reads the disable knob, the two guards and
  `nextStepAt`, may read the clock, and asks the adapter whether a notification is pending: a
  fixed handful of scalar reads, no catalog or HUD work.
- At most one early poll per 0.05 s. Notifications arrive per server reply, not per frame.
- If a full step keeps failing while notifications keep arriving, early polls resume after each
  retry is used up. Offline, a failing step under a notification on every frame for 2 s made
  about 1.7 times the old number of polls and failures (bounded by the 0.05 s spacing).
- A failing poll, or a pending step retry, blocks early polls until the next normal tick.
- `Nexus.EarlyPollDisabled = true` restores the old timing (test and rollback knob).
- `RecomputeStats().earlyPolls` counts them.

## Measured (offline: `latency-012/latency_probe.lua`, `rolling_latency` test)

A mocked server answers each accepted action after a fixed round trip with the next scripted
board. Times are simulated seconds; "cycle" is send to next send; "client delay" is cycle minus
round trip.

| Frames/s | Round trip | Cycle before | Cycle after | Saved |
|---|---|---|---|---|
| 30 | 0.05 | 0.700 | 0.533 | 0.167 |
| 30 | 0.15 | 0.700 | 0.633 | 0.067 |
| 30 | 0.30 | 0.933 | 0.800 | 0.133 |
| 60 | 0.05 | 0.650 | 0.483 | 0.167 |
| 60 | 0.15 | 0.650 | 0.600 | 0.050 |
| 60 | 0.30 | 0.867 | 0.750 | 0.117 |
| 144 | 0.05 | 0.604 | 0.465 | 0.139 |
| 144 | 0.15 | 0.604 | 0.562 | 0.042 |
| 144 | 0.30 | 0.806 | 0.715 | 0.091 |

The saving depends on where the round trip falls against the 0.2 s grid: 0 to 0.2 s per
action. With a jittered round trip (uniform in 0.5x to 1.5x of 0.1 s and of 0.2 s, 60 fps)
the client delay fell from 0.550 and 0.562 s to 0.442 and 0.445 s (probe parameters:
`PROBE_JITTER=0.5`, `PROBE_FPS=60`, `PROBE_PLAN=mixed`, `PROBE_RTT=0.10,0.20`; an independent
run with other parameters gave 0.550 to 0.445 and 0.561 to 0.450): about 0.11 s per action. The remaining client delay is the 0.4 s beat plus frame rounding. The same actions
are chosen in the same order with and without the early poll.

Overhead (`latency-012/overhead_bench.lua`, interleaved rounds, one machine, not a WoW client):
idle Auto ON, 120 simulated seconds at 60 fps, two runs: 127 against 128 ms and 131 against 125 ms
of CPU (-0.14 and +0.83 us per frame, noise-limited with another heavy program running on the
machine; the harness frame itself costs about 17 us), the same 679 polls, 2 early polls. Active 30-action chain: 59 early polls
for 30 actions (about 2 per action), CPU -8% and 0% in two runs (less simulated time passes),
allocation -0.7 MiB.

## What this does not claim

- Live latency. The mocked server has a fixed or jittered round trip and no client frame
  hitches. Real values need a native measurement.
- That 0.1 s per action is the best possible. The 0.4 s intent beat is the largest remaining
  client delay. It is a deliberate safety and display contract (the intent is shown one beat
  before it is sent) and is not changed here. Lowering it needs an owner decision and its own
  evidence.
- Anything about the server's own pacing.

## Minimal native measurement procedure (for a later, authorized test)

Not run under this change. Observe only rolling the owner already intends and has authorized,
with the same character, level, Wishlist, policy, permissions and recording setting. Do not spend
extra resources to reach a sample; stop with a smaller sample when normal play ends. At a safe
boundary with no unresolved action, compare `Nexus.EarlyPollDisabled = true` (set in a macro)
with the default in short alternating blocks of the same session; never toggle it during an
outstanding action. Read `/nexus perf` rows `gameadapter.poll` and `automation.step` (cost and
call deltas) with the frame-rate context.

From the local roll record (`/nexus trace`) the `t` column gives a **decision-to-decision
interval**. It is NOT the send-to-send cycle that the offline probe measures: a decision can be
prepared, superseded, refused or held before it is sent, the lifecycle times (`io`) are rounded
to 0.1 s, and the record has no exact send time. Use only records with exactly one accepted
submission (`sa` set, no `am` flag) and a complete outcome; report the sample count, range,
median and action mix; report holds, uncertain, expired, rejected and superseded actions and
incomplete records separately. Do not combine these intervals with the offline send-to-send
cycles and do not call them server round trips. Exact send timing needs separately admitted
native observation.
