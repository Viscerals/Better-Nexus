-- Nexus: data/LocalizationEnglish.lua
-- Reviewed English base text for core/Localization.lua (issue #123). Data
-- only: one plain table from stable semantic key to player-facing text, with
-- no function, metatable, placeholder or generated key. The text/data
-- contract is stated in core/Localization.lua, which loads just after this
-- file (Nexus.toc) and copies the valid entries once.
-- First slice: the three status reasons UserText maps from
-- ROOT_MUTATION_PENDING, CURSOR_REQUIRED and STORE_PENDING. These are the
-- exact English bytes shown before the seam existed; keep them identical.

Nexus = Nexus or {}
Nexus.LocalizationEnglish = {
    ["reason.save_in_progress"] = "Saving is still in progress; wait for its final result",
    ["reason.list_preparing"] = "This list is still being prepared",
    ["reason.saved_data_reading"] = "Reading your saved data",
}
