-- Nexus integration suite: boots the REAL addon files under the
-- harness and asserts the safety-critical flows headlessly.
-- Run from the addon root:  luajit tests/run_integration.lua
-- Exits non-zero on any failure. A red suite blocks deploy.

local H = dofile("tests/harness.lua")

local failures, checks = 0, 0
local function check(cond, msg)
    checks = checks + 1
    if not cond then
        failures = failures + 1
        print("FAIL: " .. msg)
    end
end

dofile("tests/run_secure_globals.lua")

-- Boot in .toc order.
dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Relay.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("ui/Readout.lua")
dofile("ui/Panel.lua")
dofile("ui/JournalTab.lua")
dofile("core/AutomationRuntime.lua")
dofile("core/MainLifecycle.lua")
dofile("core/MainCommands.lua")
dofile("core/MainViewModel.lua")
dofile("core/MainDiagnostics.lua")
dofile("core/Main.lua")

NexusDB = {}

-- Wishlist fixture (client shape; families: Alpha, Beta, DoubleStrike x3, g50)
H.wishlist = { name = "MyBuild", class = "MAGE", echoes = {
    { spellId = 200100, quality = 3, stacks = 1 },
    { spellId = 200102, quality = 2, stacks = 1 },
    { spellId = 200104, quality = 2, stacks = 3 },
    { spellId = 200110, quality = 0, stacks = 1 },
} }

local function DesignedWishlistEchoes()
    return {
        { spellId = 200100, quality = 3, stacks = 1, locked = false },
        { spellId = 200102, quality = 2, stacks = 1, locked = false },
        { spellId = 200104, quality = 2, stacks = 3, locked = false },
        { spellId = 200110, quality = 0, stacks = 1, locked = false },
    }
end

local function PadGrantedTo79(granted, currentTotal)
    granted["Capacity Filler"] = granted["Capacity Filler"] or {}
    for _ = currentTotal + 1, 79 do
        granted["Capacity Filler"][#granted["Capacity Filler"] + 1] = {
            spellId=200200, stack=1, maxStack=1, quality=1,
        }
    end
    return granted
end

------------------------------------------------------------------------
-- S1: boot at level 1; SPELLS_CHANGED-before-PEW guard; solo picker
------------------------------------------------------------------------
H.playerLevel = 1
H.FireEvent("ADDON_LOADED", "Nexus")
H.FireEvent("SPELLS_CHANGED")
H.FireEvent("PLAYER_ENTERING_WORLD")
-- 1.19.3 intentionally starts in manual mode; the integration run opts in to
-- automation before exercising automatic board and tome behavior.
SlashCmdList.NEXUS("auto")
check(H.ChatContains("nexus for commands") or H.ChatContains("Nexus"),
    "S1 addon initialized after PLAYER_ENTERING_WORLD")
check(H.optSettings.autoAcceptLoadoutEchoes == false,
    "S1 client auto-accept disabled (sole picker)")
check((H.slotRequests or 0) >= 1, "S1 RequestServerBuildSlots fired on load")

local A = Nexus.GameAdapter

local function AssociateSnapshot(snapshotSlot, wishlistSlot)
    local ok, err = A.SetLoadoutWishlist(snapshotSlot, wishlistSlot)
    check(ok, "test fixture associated Snapshot " .. tostring(snapshotSlot)
        .. " with wishlist " .. tostring(wishlistSlot) .. ": " .. tostring(err))
end

------------------------------------------------------------------------
-- S2: catalog -- lever conformance, families, corrected class mask
------------------------------------------------------------------------
local cat = A.Catalog()
check(cat ~= nil, "S2 catalog built")
check(cat.levers[9] and cat.levers[9].conformant == false,
    "S2 garbage lever 9 marked non-conformant")
check(cat.levers[300400] and cat.levers[300400].conformant == true
    and #cat.levers[300400].members == 2,
    "S2 shared conformant lever 300400 has 2 members")
check(cat.familyOf[200110] == "g50" and cat.familyOf[200112] == "g50",
    "S2 multi-quality family shares key g50")
check(cat.playerMask == 128, "S2 corrected MAGE class mask")

------------------------------------------------------------------------
-- S3: ARM at L1 -- activate best verified slot; lever discipline
------------------------------------------------------------------------
-- only these off-wishlist tome echoes have been discovered (learned); their
-- levers are disable-able. 200700 (Lone Tome) is NOT discovered -> skip it.
H.discovered = { [200200] = 1, [200400] = 1, [200402] = 1 }
H.DeliverDiscovery({})     -- discovery synced, nothing disabled
local activatesBeforeArm = #H.activateCalls
H.DeliverSlots({
    [2] = { slot = 2, name = "Main", verified = true, echoes = {
        { spellId = 200100, quality = 3, stacks = 1, locked = false },
        { spellId = 200200, quality = 1, stacks = 1, locked = false },
        { spellId = 200104, quality = 2, stacks = 2, locked = false },
        { spellId = 200202, quality = 1, stacks = 1, locked = false },
    } },
    [3] = { slot = 3, name = "Design", verified = false,
        echoes = DesignedWishlistEchoes() },
}, 2)
AssociateSnapshot(2, 3)
-- Rare Tome of Echo items show this stock bind confirmation. The guard must
-- engage while the tome is still in the bag, before the first click, and must
-- leave the stock popup's acceptance path untouched so the item is learned.
H.SetBagItem(0, 1, "Tome of Echo: Demon's Bane")
StaticPopupDialogs["USE_BIND"] = {
    text = "Using this item will bind it to you.",
    OnAccept = function()
        H.SetBagItem(0, 1, nil)
        H.discovered[200569] = 1
    end,
}
H.Advance(2)
check(#H.wire == 0,
    "S3 carried Tome of Echo pauses mutations before the first item click")
StaticPopup_Show("USE_BIND")
check(H.AcceptLastStaticPopup()
        and H.discovered[200569] == 1
        and GetContainerItemLink(0, 1) == nil,
    "S3 stock bind acceptance consumes and learns Demon's Bane")
H.Advance(8)
check(#H.wire == 0,
    "S3 learned tome keeps automatic mutations paused while settling")
H.Advance(13)              -- clears the 20s bind-settle guard
check(#H.activateCalls == activatesBeforeArm
        and A.Slots().activeSlot == 2,
    "S3 preserves the user-selected active Snapshot instead of switching builds")

local function CountWire(prefix)
    local n = 0
    for _, w in ipairs(H.wire) do
        if w:sub(1, #prefix) == prefix then n = n + 1 end
    end
    return n
end
H.Advance(3)               -- more ticks BEFORE the 530 reply: dedupe must hold
check(CountWire("300200|0") == 1, "S3 off-wishlist lever 300200 disabled EXACTLY once")
check(CountWire("300400|0") == 1, "S3 shared lever 300400 disabled EXACTLY once")
check(CountWire("9|") == 0, "S3 garbage lever 9 NEVER toggled")
check(CountWire("300700|") == 0,
    "S3 undiscovered tome lever (Lone Tome) is SKIPPED, not toggled (no spam)")
check(CountWire("300100|") == 0 and CountWire("300110|") == 0
    and CountWire("300112|") == 0,
    "S3 wishlist-family levers never disabled (incl. other quality rank)")
H.DeliverDiscovery({ 200200, 200400, 200402 })   -- server confirms
H.Advance(1)
check(CountWire("300200|0") == 1, "S3 no re-send after 530 confirmation")

------------------------------------------------------------------------
-- S4: RUN -- guaranteed identified by FLAG at arbitrary index
------------------------------------------------------------------------
H.playerLevel = 5
H.granted = { ["Alpha Strike"] = { { spellId = 200100, stack = 1, maxStack = 1, quality = 3 } } }
H.locked = nil
H.DeliverBoard({
    { spellId = 200104, quality = 2, isGuaranteed = true },   -- index 1, not "rightmost"
    { spellId = 200202, quality = 1 },
    { spellId = 200500, quality = 1 },
})
H.Advance(1.2)
check(H.selectCalls[#H.selectCalls] == 200104,
    "S4 took the guaranteed wanted card found by flag at index 1")
H.ResolveSelect(true)
H.Advance(0.5)
local owned = A.Owned()
check((owned.bySpell[200104] or 0) >= 1,
    "S4 recorded pick unions into owned before granted refresh")

------------------------------------------------------------------------
-- S5: wanted FREE card beats guaranteed filler; disable self-check demotes
------------------------------------------------------------------------
H.DeliverBoard({
    { spellId = 200200, quality = 1, isGuaranteed = true },   -- disabled-lever filler, flag-3!
    { spellId = 200102, quality = 2 },                        -- uncovered wishlist family
    { spellId = 200202, quality = 1 },
})
H.Advance(1.2)
check(H.selectCalls[#H.selectCalls] == 200102,
    "S5 took the wanted free card over guaranteed filler")
check(Nexus.Store.State().flagDemotions.DISABLE_SUPPRESSES_GUARANTEE ~= nil,
    "S5 disabled-lever guarantee demoted DISABLE_SUPPRESSES_GUARANTEE")
H.ResolveSelect(true)
H.Advance(0.5)

------------------------------------------------------------------------
-- S6: zero-guaranteed board (4-card trim case) falls through gracefully
------------------------------------------------------------------------
local selectsBefore = #H.selectCalls
H.DeliverBoard({
    { spellId = 200202, quality = 1 },
    { spellId = 200500, quality = 1 },
})
H.Advance(1.2)
check(#H.selectCalls == selectsBefore + 1,
    "S6 zero-flag-3 board still resolved to a least-harmful take")
H.ResolveSelect(true)
H.Advance(0.5)

------------------------------------------------------------------------
-- S7: stall regression -- blocked cards refuse locally, sender untouched
------------------------------------------------------------------------
H.DeliverBoard({
    { spellId = 200400, quality = 3, isGuaranteed = true },
    { spellId = 200202, quality = 1, justFrozen = true },
    { spellId = 200500, quality = 1 },
})
local banishesBefore = #H.banishCalls
local ok1 = A.Banish(0)
check(ok1 == false and #H.banishCalls == banishesBefore,
    "S7 banish on guaranteed card dropped BEFORE the client sender")
local ok2 = A.Banish(1)
check(ok2 == false and #H.banishCalls == banishesBefore,
    "S7 banish on justFrozen card dropped (post-SS-104 window covered)")

------------------------------------------------------------------------
-- S8: charge ledger -- {} run data, synthesized formats, one-per-push
------------------------------------------------------------------------
H.runDataTable = nil
local ch = A.Charges()
check(ch.arrived == false and ch.banish == 0 and ch.reroll == 0,
    "S8 empty run data reads as not-arrived, zero charges, no error")
H.PushRunData({ remainingBanishes = 1, totalFreezes = 0, usedFreezes = 0,
    totalRerolls = 0, usedRerolls = 0 })
ch = A.Charges()
check(ch.trustworthy == false, "S8 synthesized 14-field shape flagged untrustworthy")
H.PushRunData({ remainingBanishes = 2, totalFreezes = 2, usedFreezes = 0,
    totalRerolls = 5, usedRerolls = 0 })
H.DeliverBoard({
    { spellId = 200202, quality = 1 },
    { spellId = 200500, quality = 1 },
})
local okB = A.Banish(0)
check(okB == true, "S8 banish on junk card allowed with charges")
local okB2 = A.Banish(1)
check(okB2 == false, "S8 second banish same push refused (ledger gate)")
H.ResolveBanish(200102, 2)
H.Advance(0.5)
check((H.updateSingleCalls or 0) >= 1, "S8 banish result arrived via UpdateSinglePerk")
H.PushRunData({ remainingBanishes = 1, totalFreezes = 2, usedFreezes = 0,
    totalRerolls = 5, usedRerolls = 0 })
ch = A.Charges()
check(ch.banishSpentThisPush == false, "S8 fresh push resets the per-push banish gate")

------------------------------------------------------------------------
-- S9: deep-copy isolation (board + wishlist are copies, never references)
------------------------------------------------------------------------
H.DeliverBoard({ { spellId = 200202, quality = 1 } })
local b = A.Board()
b.cards[1].spellId = 999999
check(H.Perks.currentChoice[1].spellId == 200202,
    "S9 board copy isolated from the client's internal table")
local wl = A.Wishlist()
wl.entries[1].spellId = 999999
check(H.wishlist.echoes[1].spellId == 200100,
    "S9 wishlist copy isolated from the SavedVariables store")
H.ResolveSelect(false)

------------------------------------------------------------------------
-- S10: the polluted predicate is NEVER consulted
------------------------------------------------------------------------
check(H.pollutedCalls == 0, "S10 IsSpellInActiveEchoLoadout never called")

------------------------------------------------------------------------
-- S11: verified-field-absent payload never arms
------------------------------------------------------------------------
H.playerLevel = 1
H.Advance(0.3)             -- let Main observe the level change (resets arm state)
local activatesBefore = #H.activateCalls
H.DeliverSlots({
    [2] = { slot = 2, name = "Main", verified = true, echoes = {
        { spellId = 200100, quality = 3, stacks = 1, locked = false } } },
    [7] = { slot = 7, name = "Design", verified = true, echoes = {} },  -- designed slot "verified"
}, 0)
H.Advance(6)
check(#H.activateCalls == activatesBefore,
    "S11 verified-defaults-true payload (designed slot verified) never armed")

------------------------------------------------------------------------
-- S12: explicit level gates on build ops
------------------------------------------------------------------------
H.playerLevel = 5
local okAct = A.Activate(2)
check(okAct == false, "S12 activate refused at level 5 (client would send it)")
local okSave = A.Save(2, "x")
check(okSave == false, "S12 save refused below level 80")

------------------------------------------------------------------------
-- S13: SAVE at 80 -- domination-guarded save fires once
------------------------------------------------------------------------
H.DeliverSlots({
    [2] = { slot = 2, name = "Main", verified = true, echoes = {
        { spellId = 200100, quality = 3, stacks = 1, locked = false },
        { spellId = 200200, quality = 1, stacks = 1, locked = false },
        { spellId = 200104, quality = 2, stacks = 2, locked = false },
        { spellId = 200202, quality = 1, stacks = 1, locked = false },
    } },
    [3] = { slot = 3, name = "Design", verified = false,
        echoes = DesignedWishlistEchoes() },
}, 2)
AssociateSnapshot(2, 3)
H.granted = {
    ["Alpha Strike"] = { { spellId = 200100, stack = 1, maxStack = 1, quality = 3 } },
    ["Beta Guard"] = { { spellId = 200102, stack = 1, maxStack = 1, quality = 2 } },
    ["Gamma Bolt"] = { { spellId = 200110, stack = 1, maxStack = 1, quality = 0 } },
    ["Double Strike"] = {
        { spellId = 200104, stack = 1, maxStack = 5, quality = 2 },
        { spellId = 200104, stack = 1, maxStack = 5, quality = 2 },
        { spellId = 200104, stack = 1, maxStack = 5, quality = 2 },
    },
}
PadGrantedTo79(H.granted, 6)
H.DeliverBoard({
    { spellId=200102, quality=2 },
    { spellId=200202, quality=1 },
})
H.Advance(0.3)
H.Perks.currentChoice = nil
H.playerLevel = 80
H.Perks.currentChoice = nil      -- final board already consumed
H.Advance(8)
check(#H.saveCalls >= 1 and H.saveCalls[#H.saveCalls].slot == 2,
    "S13 dominating run saved only into the confirmed active loadout")
local savesAfter = #H.saveCalls
H.Advance(4)
check(#H.saveCalls == savesAfter, "S13 save fires only once per visit")

------------------------------------------------------------------------
-- S14: bad run does NOT save (anti-brick)
------------------------------------------------------------------------
H.playerLevel = 5
H.Advance(0.3)
H.granted = {
    ["Junk Aura"] = { { spellId = 200200, stack = 1, maxStack = 1, quality = 1 } },
    ["Double Strike"] = { { spellId = 200104, stack = 1, maxStack = 5, quality = 2 } },
}
H.playerLevel = 80
H.Perks.currentChoice = nil
local savesBefore = #H.saveCalls
H.Advance(8)
check(#H.saveCalls == savesBefore,
    "S14 non-dominating run (lost coverage, owns filler) never saved")

------------------------------------------------------------------------
-- S15: advisor mode -- no wishlist, no auto actions
------------------------------------------------------------------------
H.playerLevel = 5
H.Advance(0.3)
H.wishlist = nil
A.ClearLoadoutWishlist(2)
H.DeliverSlots({
    [2] = { slot = 2, name = "Main", verified = true, echoes = {
        { spellId = 200100, quality = 3, stacks = 1, locked = false },
    } },
    [3] = { slot = 3, name = "MyBuild", verified = false, echoes = {
        { spellId = 200100, quality = 3, stacks = 1, locked = false },
        { spellId = 200102, quality = 2, stacks = 1, locked = false },
    } },
}, 2)
local selBefore = #H.selectCalls
H.DeliverBoard({
    { spellId = 200102, quality = 2 },
    { spellId = 200202, quality = 1 },
})
H.Advance(1.5)
check(#H.selectCalls == selBefore, "S15 advisor mode never auto-picks")
H.wishlist = { name = "MyBuild", class = "MAGE", echoes = {
    { spellId = 200100, quality = 3, stacks = 1 },
    { spellId = 200102, quality = 2, stacks = 1 },
} }
local restoredAssociation, restoredErr = A.SetLoadoutWishlistIdentity(
    2, H.wishlist.name, H.wishlist.echoes)
check(restoredAssociation,
    "S15 fixture restored the explicit loadout association: "
        .. tostring(restoredErr))

------------------------------------------------------------------------
-- S16: rival addon suspends auto
------------------------------------------------------------------------
_G.EchoOptimizer = {}
selBefore = #H.selectCalls
H.DeliverBoard({
    { spellId = 200102, quality = 2 },
    { spellId = 200202, quality = 1 },
})
H.Advance(3.5)
check(#H.selectCalls == selBefore, "S16 auto suspended while EchoOptimizer is loaded")
_G.EchoOptimizer = nil

------------------------------------------------------------------------
-- S17: user re-enabling client auto-accept suspends auto
------------------------------------------------------------------------
H.optSettings.autoAcceptLoadoutEchoes = true
selBefore = #H.selectCalls
local rrBefore = H.rerollCalls
local banishBeforeResume = #H.banishCalls
local freezeBeforeResume = #H.freezeCalls
H.DeliverBoard({
    { spellId = 200102, quality = 2 },
    { spellId = 200202, quality = 1 },
})
H.Advance(1.5)
check(#H.selectCalls == selBefore and H.rerollCalls == rrBefore,
    "S17 auto suspended when client picker re-enabled")
H.optSettings.autoAcceptLoadoutEchoes = false
H.Advance(3.5)
-- Deferred-reroll economics (v1.3.1): a board whose best option is a
-- deferred loadout echo is RE-ROLLED when charges and EV allow, else
-- selected. Either way, auto must have acted after the picker went off.
check(#H.selectCalls == selBefore + 1 or H.rerollCalls == rrBefore + 1
    or #H.banishCalls == banishBeforeResume + 1
    or #H.freezeCalls == freezeBeforeResume + 1,
    "S17 auto resumes once the client picker is off")
if H.Perks.pendingSelectSpellId then
    H.ResolveSelect(true)
elseif H.Perks.pendingReroll then
    -- resolve the reroll: latch clears, board goes away before any
    -- further action can fire (no state leaks into later scenarios)
    H.Perks.pendingReroll = nil
    H.Perks.currentChoice = nil
    H.Advance(0.3)
elseif H.Perks.pendingBanishIndex then
    H.Perks.pendingBanishIndex = nil
elseif H.Perks.pendingFreezeIndex then
    H.Perks.pendingFreezeIndex = nil
end
H.Perks.currentChoice = nil
H.Advance(0.3)

------------------------------------------------------------------------
-- S19: an unusable filler guarantee does not suppress search. Nexus safely
-- Banishes an off-wishlist side while preserving wished families.
------------------------------------------------------------------------
H.PushRunData({ remainingBanishes = 2, totalFreezes = 2, usedFreezes = 0,
    totalRerolls = 0, usedRerolls = 0 })
-- S17 now rerolls its board (deferred-reroll economics) instead of
-- selecting Alpha, so Alpha ownership must be granted explicitly for
-- this scenario's "owned duplicate" premise to hold.
H.granted = { ["Alpha Strike"] = { { spellId = 200100, stack = 1, maxStack = 1, quality = 3 } } }
local banishesB4 = #H.banishCalls
local selectsB4 = #H.selectCalls
H.DeliverBoard({
    { spellId = 200302, quality = 0 },                       -- filler (worst)
    { spellId = 200100, quality = 3 },                       -- owned duplicate
    { spellId = 200300, quality = 0, isGuaranteed = true },  -- filler, flag-3
})
H.Advance(1.5)
check(#H.banishCalls == banishesB4 + 1,
    "S19 unusable guaranteed filler permits a safe search Banish")
check(#H.selectCalls == selectsB4,
    "S19 did not drain the unusable guarantee before search")
H.ResolveBanish(200102, 2)
H.Perks.currentChoice = nil
H.Advance(0.3)

------------------------------------------------------------------------
-- S20: advisor mode (no wishlist) never auto-ACTIVATES a snapshot
-- (the save gate existed; the activate gate was missing)
------------------------------------------------------------------------
H.granted, H.locked = nil, nil       -- fresh run owns nothing
H.wishlist = nil                     -- advisor mode
H.playerLevel = 80
H.Advance(0.3)                       -- authoritative prior-run completion
H.playerLevel = 1
H.Advance(0.3)                       -- run-boundary reset (owned sig "")
H.buildBusyUntil = -1
local actB4 = #H.activateCalls
H.DeliverSlots({
    [2] = { slot = 2, name = "Main", verified = true, echoes = {
        { spellId = 200100, quality = 3, stacks = 1, locked = false } } },
    [3] = { slot = 3, name = "MyBuild", verified = false, echoes = {
        { spellId = 200100, quality = 3, stacks = 1, locked = false },
        { spellId = 200102, quality = 2, stacks = 1, locked = false },
    } },
}, 0)
H.Advance(8)
check(#H.activateCalls == actB4, "S20 advisor mode never auto-activates a snapshot")
H.wishlist = { name = "MyBuild", class = "MAGE", echoes = {
    { spellId = 200100, quality = 3, stacks = 1 },
    { spellId = 200102, quality = 2, stacks = 1 },
} }
local starterOk = A.SetFirstRunWishlistIdentity(
    H.wishlist.name, H.wishlist.echoes)
check(starterOk, "S20 fixture restored the explicit first-run wishlist")
H.granted = {}
A.RequestGranted()

------------------------------------------------------------------------
-- S21: untrustworthy charges (fabricated legacy remainingBanishes=1)
-- must NOT fire a banish into a dead latch; board still resolves
------------------------------------------------------------------------
H.playerLevel = 5
H.Advance(0.3)
H.PushRunData({ remainingBanishes = 1, totalFreezes = 0, usedFreezes = 0,
    totalRerolls = 0, usedRerolls = 0 })     -- tf==0,uf==0,rb==1 -> trustworthy=false
local banB4, selB4 = #H.banishCalls, #H.selectCalls
H.DeliverBoard({
    { spellId = 200302, quality = 0 },       -- filler
    { spellId = 200202, quality = 1 },       -- filler
})
H.Advance(1.5)
check(#H.banishCalls == banB4, "S21 untrustworthy charges -> no auto-banish")
check(#H.selectCalls == selB4 + 1, "S21 junk board still resolved with a take")
H.ResolveSelect(true)
H.Advance(0.3)

------------------------------------------------------------------------
-- S22: save is CONFIRMED against a fresh SS-540, not latched on send.
-- An invisible SS-541 FAIL (saveBlackhole) must clear savedThisVisit and
-- retry, never leave a false "saved" behind.
------------------------------------------------------------------------
H.saveBlackhole = true
H.granted = nil
H.playerLevel = 1
H.Advance(0.5)
H.granted = {
    ["Alpha Strike"] = { { spellId = 200100, stack = 1, maxStack = 1, quality = 3 } },
    ["Beta Guard"] = { { spellId = 200102, stack = 1, maxStack = 1, quality = 2 } },
}
PadGrantedTo79(H.granted, 2)
A.RequestGranted()
H.DeliverSlots({
    [2] = { slot = 2, name = "Main", verified = true, echoes = {
        { spellId = 200100, quality = 3, stacks = 1, locked = false } } },
    [3] = { slot = 3, name = "D", verified = false,
        echoes = DesignedWishlistEchoes() },
}, 2)
AssociateSnapshot(2, 3)
H.buildBusyUntil = -1
H.playerLevel = 2
H.DeliverBoard({{spellId=200102,quality=2},{spellId=200202,quality=1}})
H.Advance(0.3)
H.playerLevel = 80
H.Perks.currentChoice = nil
local saveB4 = #H.saveCalls
H.Advance(45)                        -- one save; bounded readback remains unconfirmed
check(#H.saveCalls == saveB4 + 1
    and NexusDB.lastSaveStatus and NexusDB.lastSaveStatus.state == "saved_unverified",
    "S22 unconfirmed save stayed single-write and was not falsely confirmed"
        .. " calls=" .. tostring(#H.saveCalls-saveB4)
        .. " state=" .. tostring(NexusDB.lastSaveStatus
            and NexusDB.lastSaveStatus.state))
H.saveBlackhole = false
H.Advance(6)
local saveAfterConfirm = #H.saveCalls
H.Advance(8)
check(#H.saveCalls == saveAfterConfirm,
    "S22 unconfirmed save never retries an overwrite automatically")

------------------------------------------------------------------------
-- S23: Phi-monotone ratchet -- a coverage-gaining run still saves even
-- though it picks up one extra filler family (subset test would refuse)
------------------------------------------------------------------------
H.granted = nil
H.playerLevel = 1
H.Advance(0.5)
H.granted = {
    ["Alpha Strike"] = { { spellId = 200100, stack = 1, maxStack = 1, quality = 3 } },
    ["Beta Guard"] = { { spellId = 200102, stack = 1, maxStack = 1, quality = 2 } },
    ["Junk Aura"] = { { spellId = 200200, stack = 1, maxStack = 1, quality = 1 } },
}
PadGrantedTo79(H.granted, 3)
A.RequestGranted()
H.DeliverSlots({
    [2] = { slot = 2, name = "Main", verified = true, echoes = {
        { spellId = 200100, quality = 3, stacks = 1, locked = false } } },  -- covers {Alpha}
    [3] = { slot = 3, name = "D", verified = false,
        echoes = DesignedWishlistEchoes() },
}, 2)
AssociateSnapshot(2, 3)
H.buildBusyUntil = -1
H.playerLevel = 2
H.DeliverBoard({{spellId=200102,quality=2},{spellId=200202,quality=1}})
H.Advance(0.3)
H.playerLevel = 80
H.Perks.currentChoice = nil
saveB4 = #H.saveCalls
H.Advance(8)
check(#H.saveCalls == saveB4 + 1,
    "S23 coverage +1 with filler +1 still saves (Phi-monotone, not filler-subset)")

------------------------------------------------------------------------
-- S24: Ready() gate -- per-char getters must not run before the player
-- is known (else the client's session char-key is poisoned)
------------------------------------------------------------------------
local realUnitName = UnitName
UnitName = function() return "Unknown" end
check(Nexus.GameAdapter.Ready() == false,
    "S24 Adapter.Ready() false while UnitName is Unknown")
UnitName = realUnitName
check(Nexus.GameAdapter.Ready() == true,
    "S24 Adapter.Ready() true once UnitName resolves")

------------------------------------------------------------------------
-- S25: /wr wishlist reports the detected wishlist NAME (and "none" when
-- there is no active loadout)
------------------------------------------------------------------------
H.wishlist = { name = "Frostbite Tank", class = "MAGE", echoes = {
    { spellId = 200100, quality = 3, stacks = 1 },
    { spellId = 200104, quality = 2, stacks = 3 },
} }
H.DeliverSlots({
    [2] = { slot = 2, name = "Snap", verified = true, echoes = {
        { spellId = 200100, quality = 3, stacks = 1, locked = false } } },
    [3] = { slot = 3, name = "Frostbite Tank", verified = false, echoes = {
        { spellId = 200100, quality = 3, stacks = 1, locked = false },
        { spellId = 200104, quality = 2, stacks = 3, locked = false },
    } },
}, 2)
AssociateSnapshot(2, 3)
local chatB4 = #H.chat
SlashCmdList["NEXUS"]("wishlist")
check(H.ChatContains("Frostbite Tank") ~= nil,
    "S25 /wr wishlist prints the detected wishlist name")
H.wishlist = nil
-- clear any designed builds so this reads as genuinely no-wishlist
H.DeliverSlots({
    [2] = { slot = 2, name = "Snap", verified = true, echoes = {
        { spellId = 200100, quality = 3, stacks = 1, locked = false } } },
}, 2)
A.ClearLoadoutWishlist(2)
SlashCmdList["NEXUS"]("wishlist")
check(H.ChatContains("no wishlist association") ~= nil,
    "S25 /wr wishlist explains the missing active-Snapshot association")

------------------------------------------------------------------------
-- S26: 1.19.3 never guesses a target from an arbitrary designed slot. The
-- active Saved Build needs an explicit association selected by the player.
------------------------------------------------------------------------
H.wishlist = nil                     -- no active loadout
H.DeliverSlots({
    [2] = { slot = 2, name = "Snap", verified = true, echoes = {   -- a snapshot
        { spellId = 200100, quality = 3, stacks = 1, locked = false } } },
    [6] = { slot = 6, name = "My Goal", verified = false, echoes = {  -- designed wishlist
        { spellId = 200100, quality = 3, stacks = 1, locked = false },
        { spellId = 200102, quality = 2, stacks = 1, locked = false },
        { spellId = 200104, quality = 2, stacks = 3, locked = false } } },
}, 2)
local wlD = Nexus.GameAdapter.Wishlist()
check(wlD == nil,
    "S26 unassociated designed slot is not guessed as the active target")
local chatD = #H.chat
SlashCmdList["NEXUS"]("wishlist")
check(H.ChatContains("no wishlist association") ~= nil,
    "S26 /wr wishlist explains that an explicit association is required")

------------------------------------------------------------------------
-- S27: /wr status reports BOTH the target source and whether the loadout
-- snapshots are readable (answers "is it reading wishlist or loadout")
------------------------------------------------------------------------
H.chat = {}
SlashCmdList["NEXUS"]("status")
check(H.ChatContains("TARGET:") ~= nil and H.ChatContains("no wishlist") ~= nil,
    "S27 /wr status reports the missing explicit target")
check(H.ChatContains("loadout snapshot") ~= nil and H.ChatContains("ACTIVE slot 2") ~= nil,
    "S27 /wr status reports readable loadout snapshots and the active build")

------------------------------------------------------------------------
-- S28: never-duplicate -- a board of one owned duplicate + one new echo
-- takes the NEW echo (feeds Adaptive Power's distinct count), never the
-- duplicate, even though the duplicate has the higher raw Delta
------------------------------------------------------------------------
local dupPlan = Nexus.Strategy.Compile(
    Nexus.GameAdapter.Catalog(),
    { name = "w", entries = { { spellId = 200100, quality = 3, stacks = 1, family = "s200100" } },
      byFamily = { s200100 = { targetStacks = 1, wishedQuality = 3, spellId = 200100 } } },
    Nexus.Store.Settings())
local dupOwned = { bySpell = { [200100] = 1 }, byFamily = { s200100 = 1 },
    synced = true, distinct = 1 }
local dupState = {
    board = { cards = {
        { spellId = 200100, quality = 3, family = "s200100" },   -- owned duplicate
        { spellId = 200202, quality = 1, family = "s200202" },   -- new (filler) echo
    }, guaranteedIndex = nil, signature = "dup" },
    owned = dupOwned, charges = { banish = 0, reroll = 0, trustworthy = true },
    plan = dupPlan, catalog = Nexus.GameAdapter.Catalog(),
    level = 40, params = Nexus.DefaultProfile.params,
}
local dupAct = Nexus.Policy.Decide(dupState)
check(dupAct.type == "take" and dupAct.spellId == 200202,
    "S28 takes the NEW distinct echo, never the owned duplicate")

------------------------------------------------------------------------
-- S29: anchor auto-detection -- a wishlist containing "Adaptive Power"
-- (200960) sets it as the diversity anchor with no manual /wr anchor
------------------------------------------------------------------------
local apPlan = Nexus.Strategy.Compile(
    Nexus.GameAdapter.Catalog(),
    { name = "ap", entries = {
        { spellId = 200960, quality = 3, stacks = 1, family = "s200960" },
        { spellId = 200100, quality = 3, stacks = 1, family = "s200100" } },
      byFamily = {
        s200960 = { targetStacks = 1, wishedQuality = 3, spellId = 200960 },
        s200100 = { targetStacks = 1, wishedQuality = 3, spellId = 200100 } } },
    Nexus.Store.Settings())
check(apPlan.anchorSpellId == 200960,
    "S29 Adaptive Power auto-detected as the anchor from the wishlist")

------------------------------------------------------------------------
-- S18: journal tab soft-fail (no journal frames in harness)
------------------------------------------------------------------------
local okInstall = pcall(function()
    return Nexus.JournalTab.TryInstall(function()
        return { sections = {}, version = "t" }
    end)
end)
check(okInstall, "S18 JournalTab.TryInstall soft-fails without journal frames")

------------------------------------------------------------------------
print(string.format("checks=%d failures=%d", checks, failures))
os.exit(failures == 0 and 0 or 1)
