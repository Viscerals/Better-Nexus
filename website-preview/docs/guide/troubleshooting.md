# Troubleshooting

Check the simple things first. Preserve the state that explains the problem before changing or deleting it.

## The addon does not appear

- Check that `Interface\AddOns\Nexus\Nexus.toc` exists in the client you actually launch.
- Remove accidental folder nesting; the path should not be `Nexus\Nexus\Nexus.toc`.
- Keep the folder named **Nexus**, not Better-Nexus.
- Confirm both **Nexus** and **NexusSupport** are enabled in the AddOns list.
- Confirm you extracted the player release package instead of GitHub’s source ZIP.

See the [complete install guide](install.md) before reinstalling.

## Saved plans look missing

Keep your WTF data and backups. Verify the character, realm, active loadout, and exact installed build. Do not reset SavedVariables or delete unresolved Wishlists as a generic fix.

Capture a report and describe when the data last appeared. A server-list omission alone does not prove a Wishlist was deleted.

## Automation is on but nothing happens

Check the Wishlist assignment, individual permissions, and the reason shown by Nexus. A loading condition, unavailable capability, pending action, or active/unknown Orb offer can block ordinary rolling.

Disable competing Echo pickers. Do not repeatedly reload or force recovery state to hide a missing response.

## Sharing is incomplete

Confirm both players are on the same realm, then record their exact build labels and the displayed Sync states. Distinguish “sent” from confirmed completion. Include the small sequence that reproduces the problem, not an assumption about the peer’s state.

## Stutters or Lua errors

Record what you were doing, when the stall happened, and whether it repeats. Use `/nexus report` for diagnostics, `/nexus log errors` for recorded errors, and `/nexus perf` for runtime observations. Performance observations are different from combat DPS.

Public test.9092 reduces work in some offline-measured paths. That is **not a verified claim that in-game hitching is fixed**.

## Prepare a useful report

1. Run **`/nexus report`**. Follow the report tool’s copy/export instructions. If the output is paged, include the pages in order.
2. Include the **exact addon version and test/build label**. For example: `1.20.0-beta.1 / test.9092`. Include the startup build information or package name if helpful.
3. Describe the action and the smallest repeatable sequence.
4. State **what you observed** and **what you expected** separately.
5. Include relevant errors or a small screenshot. Send report files and full diagnostics **privately** to the maintainer through your existing private support conversation.

This website does not receive, store, or upload reports. There is no web report form. Do not paste report files, player backups, or account/character data into a public GitHub issue.

!!! info "If the reporting tool fails"
    Say that `/nexus report` failed. Provide your exact version, what you were doing, and any error messages or screenshots you can capture. Preserve the saved data for a possible follow-up.

## Before asking for help

Search the [existing issues](https://github.com/Viscerals/Better-Nexus/issues) for a matching symptom. A sanitized public summary may use the appropriate [bug](https://github.com/Viscerals/Better-Nexus/issues/new?template=01-bug-report.yml), [performance](https://github.com/Viscerals/Better-Nexus/issues/new?template=02-performance-stutter-report.yml), or [Sync](https://github.com/Viscerals/Better-Nexus/issues/new?template=03-sync-multiplayer-report.yml) form. Keep full reports private.

Requests without the version, diagnostics, and observed/expected behavior will not be investigated. Even a complete report does not guarantee an investigation or a fix. Read the [limited-support note](../support.md).

For a security issue, use [GitHub’s private vulnerability route](https://github.com/Viscerals/Better-Nexus/security/advisories/new).

---

Sources: [published reporting and support note](https://github.com/Viscerals/Better-Nexus/releases/tag/v1.20.0-beta.1-test.9092) and [public support routes](https://github.com/Viscerals/Better-Nexus/blob/v1.20.0-beta.1-test.9092/SUPPORT.md).
