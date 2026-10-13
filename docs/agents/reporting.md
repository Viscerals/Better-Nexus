# Shared Claude and Codex reporting

These are portable instruction adaptations of Savvy Progress, You Should Know, Cache Tax, Blast Radius and Reflect. They do not install those mods or reproduce their native UI, hooks or side agents.

## Progress

For work with several steps, state the current stage, what is completed and what remains. Update the plan when scope changes. Count only completed, verified steps against an explicit plan; otherwise use stage names. Never invent a completion percentage, elapsed estimate, worker status or test result. Keep routine updates brief and link detailed evidence when useful.

## You should know

Surface important information the user could miss in a long work log: a blocker, changed scope, unresolved risk, decision requiring their input, or a limit on the result. Use a short “You should know:” paragraph when there is something material to report; omit it otherwise. Say what it means for the task and the next action. Distinguish verified facts from inference. Deliver the outcome and material limits in the final response even if earlier updates already mentioned them.

## Context and usage

Keep updates concise and retain source pins, decisions and validation in a scoped handoff when needed. Report usage or cache figures only from actual provider evidence, with its timestamp and limitations. Do not infer subscription savings from an API-equivalent price estimate. Background cache warming, additional model calls or telemetry changes need explicit informed authorization; this guidance enables none.

## Impact before action

For an action that could discard work, change shared state or publish content, inspect the affected paths, refs or recipients with read-only checks first and describe the concrete effect. Follow the existing task scope, permission system and repository gates. A preview or instruction is advisory and cannot approve a tool call or replace those gates. Do not run project scripts merely to generate an impact preview without checking what they execute.

## Deliberate lessons

Apply user corrections to the current task. For a reusable lesson, propose its exact wording and repository or user scope before saving it. Save only after the user approves the wording and destination; read the target again and update the existing rule rather than duplicating it. Do not turn a one-off direction into a global policy or silently write learned rules.

## Loading and scope

Keep the shared policy in root `AGENTS.md` and these referenced documents. Confirm that each Claude worker actually loads `AGENTS.md`; when its launcher does not, include a read-`AGENTS.md` instruction in that worker's brief. Do not copy the policy into a second `CLAUDE.md` body. User configuration, plugin installation, telemetry, permissions, cache timers and automatic memory capture are outside this repository change.
