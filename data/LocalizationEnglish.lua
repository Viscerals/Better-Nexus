-- Nexus: data/LocalizationEnglish.lua
-- Reviewed English base text for core/Localization.lua (issue #123). Data
-- only: one plain table from stable semantic key to player-facing text, with
-- no function, metatable or generated key. The text/data
-- contract is stated in core/Localization.lua, which loads just after this
-- file (Nexus.toc) and copies the valid entries once.
-- First slice: the three status reasons UserText maps from
-- ROOT_MUTATION_PENDING, CURSOR_REQUIRED and STORE_PENDING. These are the
-- exact English bytes shown before the seam existed; keep them identical.
-- Issue #142 first cohort: the two planner wait reasons UserText maps from
-- "waiting for three-card board" and "waiting for pending-pick count" (the
-- second keeps the producer's lower-case bytes), and the compact charge row.
-- "readout.charge_counts" is a template: its placeholders and their types are
-- owned by the code schema in core/Localization.lua, never by this data.
-- Issues #143/#148: a 21-meaning ui/Panel.lua cohort of static texts, the
-- exact English bytes of the current Panel literals: My Builds navigation,
-- first-run Assign/Create Wishlist navigation, the progress, still-needed,
-- extra-copies and locked-target headings and the complete locked-target
-- hover. The base is now 27 entries: 26 static texts and the one template.
-- This data alone does not prove that any consumer shows these keys.

Nexus = Nexus or {}
Nexus.LocalizationEnglish = {
    ["reason.save_in_progress"] = "Saving is still in progress; wait for its final result",
    ["reason.list_preparing"] = "This list is still being prepared",
    ["reason.saved_data_reading"] = "Reading your saved data",
    ["reason.wait_three_choices"] = "Waiting for the next three Echo choices",
    ["reason.wait_pending_pick_count"] = "waiting for pending-pick count",
    ["readout.charge_counts"] = "B:{banish} R:{reroll} F:{freeze}",
    ["panel.button.my_builds"] = "My Builds",
    ["panel.tooltip.open_my_builds"] = "Open My Builds",
    ["panel.tooltip.my_builds_destination"] = "Open the server My Builds page. Choosing a different Saved Build there changes the active loadout.",
    ["panel.button.assign_wishlist"] = "Assign Wishlist",
    ["panel.tooltip.assignment_heading"] = "Assign Wishlist",
    ["panel.tooltip.assignment_chooser"] = "Opens the Echo Journal with its Wishlist chooser for this loadout. Nothing is assigned until you choose a Wishlist there.",
    ["panel.button.create_wishlist"] = "Create Wishlist",
    ["panel.tooltip.create_wishlist_heading"] = "Import or create a wishlist",
    ["panel.tooltip.create_wishlist_source"] = "Paste a wishlist string or build one directly in Nexus.",
    ["panel.tooltip.create_wishlist_draft"] = "This opens the Wishlist editor with a draft. Nothing is saved or assigned until you press Create & assign or Create unassigned there.",
    ["panel.heading.locked_targets"] = "LOCKED TARGETS",
    ["panel.tooltip.locked_remaining"] = "Locked targets remaining",
    ["panel.tooltip.locked_plan"] = "These targets are planned for your locked Echo slots (a plan designs at most six target copies).",
    ["panel.tooltip.locked_acquire"] = "Acquire the exact requested Echo and quality first.",
    ["panel.tooltip.locked_placement"] = "Owned copies still need to be placed in locked Echo slots.",
    ["panel.tooltip.locked_not_freeze"] = "Current locked Echo slots and card Freeze are separate.",
    ["panel.tooltip.locked_acquire_list"] = "Still need to acquire:",
    ["panel.tooltip.open_wishlist_editor"] = "Click to open Wishlist Editor",
    ["panel.heading.progress"] = "PROGRESS",
    ["panel.heading.still_needed"] = "STILL NEEDED",
    ["panel.heading.extra_copies"] = "EXTRA COPIES",
}
