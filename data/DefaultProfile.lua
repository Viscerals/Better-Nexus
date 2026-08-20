-- Nexus: data/DefaultProfile.lua
-- PURE data: no WoW API, no SavedVariables, no ProjectEbonhold.
-- Loads under bare LuaJIT via dofile.

Nexus = Nexus or {}
local DefaultProfile = {}
Nexus.DefaultProfile = DefaultProfile

-- Ordinal value scale for Model.Delta. Units are arbitrary; only the
-- ordering and rough ratios carry meaning (calibration-free by design).
DefaultProfile.params = {
    coverage = 100,           -- uncovered wished family
    qualityBonus = 2,         -- per quality rank, on coverage picks
    anchorUnlock = 150,       -- the anchor spellId itself, uncovered
    diversity = 5,            -- unique new family while anchor owned
    duplicate = -5,           -- duplicate of an owned maxStack==1 family
    filler = -15,             -- off-wishlist non-duplicate
    qualityMiss = -20,        -- below-wished-quality copy of a single-stack
                              -- multi-quality family: locks the family at
                              -- the wrong quality, worse than plain filler
    deferFactor = 0.35,       -- discount on a free-slot wished card whose
                              -- guarantee is still pending (it comes back;
                              -- a one-shot pick shouldn't lose to it)
    rerollCost = 8,           -- charge price inside the reroll EV test
    rerollHoldThreshold = 25, -- guaranteed delta below this frees a reroll
    rerollPacingBase = 6,     -- cost scales up once remaining rerolls drop
                              -- below this (the last few are precious)
    deferRerollFloor = 4,     -- min remaining rerolls before one may be
                              -- spent dodging a merely-deferred pick
}

DefaultProfile.defaultSettings = {
    autoPick = true,
    autoActivate = true,
    autoDisable = true,
    autoSave = true,
    autoBanish = true,
    -- Separate opt-IN from the other auto-* switches, defaulting OFF: a
    -- fresh capability (LockPerk/UnlockPerk, confirmed live 2026-08-01)
    -- that permanently changes a real character choice deserves its own
    -- explicit consent even when the player already has board automation
    -- fully on. Existing saves simply lack this key (nil), which is
    -- exactly as falsy as `false` -- no SETTINGS_VERSION bump needed.
    autoLockEchoes = false,
    updateNotifications = true, -- chat + persistent panel notice; manual install only
    -- Community persistence is a local cache over the immutable bundled
    -- catalog. Ranked pruning is opt-in; when disabled, build and DPS content
    -- is retained without count limits. The values below remain the saved
    -- policy used if ranked retention is enabled later.
    communityRetentionEnabled = false,
    communityRetentionTopPerCategory = 100,
    communityRetentionMinPerClassPerCategory = 15,
    communityRetentionTopAverage = 50,
    communityRetentionMinAveragePerClass = 10,
    communityRetentionOtherRemoteBuilds = 75,
    communityRetentionMaxPerAuthor = 12,
    communityRetentionPersonalFingerprints = 128,
    communityRetentionBuildFingerprints = 128,
    anchorSpellId = nil, -- explicit override; honored only when on the wishlist
    -- Diversity-anchor auto-detection: if no explicit anchorSpellId, the
    -- anchor is the wishlist echo whose name matches one of these. Adaptive
    -- Power scales with DISTINCT echoes, so owning it makes new distinct
    -- echoes valuable. Data-driven (not hardcoded logic); extend as needed.
    anchorNames = { "Adaptive Power" },
    leverOptOut = {},    -- [leverId (requiredSpell)] = true
}

DefaultProfile.defaultFlags = {
    -- true: user-confirmed from live play 2026-07-23. Runtime-demotable:
    -- a disabled-lever member observed with isGuaranteed demotes it for
    -- the session (recorded in Store state.flagDemotions).
    DISABLE_SUPPRESSES_GUARANTEE = true,
    -- nil = conservative (reroll-to-hold suppressed) until M3 measures.
    REROLL_HOLDS_GUARANTEED = nil,
}
