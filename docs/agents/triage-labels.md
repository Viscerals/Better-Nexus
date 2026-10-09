# Triage labels

Reuse the existing GitHub vocabulary for `Viscerals/Better-Nexus`.

| Canonical role | GitHub label | Meaning |
| --- | --- | --- |
| `needs-triage` | `needs-triage` | Maintainer evaluation is required. |
| `needs-info` | `needs-diagnostics` | More reporter, diagnostic or native evidence is required. |
| `ready-for-agent` | `ready-for-agent` | Specified and ready for approved agent work planning. |
| `ready-for-human` | `ready-for-human` | Requires human implementation or interaction. |
| `wontfix` | `wontfix` | Will not be actioned. |

Category roles map to `bug` and `enhancement`. Every issue processed by triage should have one category role and one state role. Surface conflicting state roles to the maintainer before changing them.

Keep `confirmed`, `documentation`, `duplicate`, `good first issue`, `help wanted`, `invalid`, `migration`, `performance`, `prerelease`, `question` and `sync` as supporting labels; they do not replace triage state. Use `needs-diagnostics` for the canonical `needs-info` role rather than creating a second label.

Read prior triage notes and retain resolved decisions. Existing unlabeled issues are not an instruction to bulk-classify or close them. `ready-for-agent` is advisory under `docs/agents/issue-tracker.md`.
