# Install & update

Keep your plans and history. Replace the addon code, while preserving the saved data separately.

!!! warning "Before you change anything"
    **Close WoW completely.** Back up the existing `Nexus` and `NexusSupport` addon folders, if present, and the client’s entire **WTF** folder to a location outside the game directory. Do not delete or reset SavedVariables as part of an update.

## 1. Get the public package

Use the [test.9094 download page](../releases/index.md). The release package is a ZIP with the player addons. The repository’s green **Code** button downloads source, which is not the player release package.

This is an experimental beta. Check the complete build label rather than relying on the shared `1.20.0-beta.1` addon version alone.

## 2. Replace both addon folders

Extract the ZIP into a temporary location. Find your actual WoW client folder and open `Interface\AddOns`.

With the game closed, replace the installed **Nexus** and **NexusSupport** folders with the folders from the same release package. Do not merge an old package with a new one. Keep your backup outside `AddOns` so the game does not load a second copy.

The installed layout should include:

```text
Your WoW client/
├── Interface/
│   └── AddOns/
│       ├── Nexus/
│       │   └── Nexus.toc
│       └── NexusSupport/
│           └── NexusSupport.toc
└── WTF/                  ← preserve your existing saved data
```

The runtime folder stays **Nexus**, even though the project is called Better Nexus. Avoid `Nexus\Nexus\Nexus.toc` and do not rename the addon folder to `Better-Nexus`.

## 3. Preserve saved data

`NexusDB` and `WishlistRealizerDB` are the existing SavedVariables used by Nexus. Back up their containing WTF data before testing. Keep your NexusSupport saved report data too; backing up the entire WTF folder covers it.

Do not clear old Wishlists, recovery markers, or unresolved entries to make a beta load. If data appears missing, preserve it and [capture a report](troubleshooting.md#prepare-a-useful-report).

## 4. Check your first login

1. Enable **Nexus** and **NexusSupport** in the client’s AddOns list.
2. Keep **Automation OFF** while checking navigation, Wishlists, and saved builds.
3. Open `/nexus help` for the in-game guide. Confirm the loaded build is **test.9094** in the startup/build information or report.
4. Review your active loadout and Wishlist assignment before enabling any automatic actions.
5. Disable competing Echo pickers before using Nexus automation. A separate LoadoutPilot is not required to run Nexus.

## Updating an existing installation

Use the same backup-and-replace process for every update. Replace both addon folders from one package, preserve WTF, and verify the complete loaded label. Avoid combining files from public and private diagnostic builds.

## Rolling back

Close the game and restore the **matching old addon code and old saved data together** from your backup.

A local restore cannot undo currency or Orbs already spent, changed owned Echoes, or builds already sent to other players. Do not roll back while a server-side Orb offer remains unresolved. Record that state for support first.

---

Next: [Create or import your first Wishlist →](first-wishlist.md)

Source: [public repository installation guide](https://github.com/Viscerals/Better-Nexus/blob/v1.20.0-beta.1-test.9094/README.md) and [published test.9094 notes](https://github.com/Viscerals/Better-Nexus/releases/tag/v1.20.0-beta.1-test.9094).
