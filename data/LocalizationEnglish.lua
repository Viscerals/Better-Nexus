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

Nexus = Nexus or {}
Nexus.LocalizationEnglish = {
    ["reason.save_in_progress"] = "Saving is still in progress; wait for its final result",
    ["reason.list_preparing"] = "This list is still being prepared",
    ["reason.saved_data_reading"] = "Reading your saved data",
    ["reason.wait_three_choices"] = "Waiting for the next three Echo choices",
    ["reason.wait_pending_pick_count"] = "waiting for pending-pick count",
    ["readout.charge_counts"] = "B:{banish} R:{reroll} F:{freeze}",
}
