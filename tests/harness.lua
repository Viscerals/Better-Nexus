-- Nexus offline harness: stubs the WoW 3.3.5 API + ProjectEbonhold
-- with the AUDITED client semantics (latches with no timeout, silent banish
-- refusal on guaranteed cards, latch-less ToggleTomeEcho with 530-delayed
-- mirror, in-place SS-103 board mutation via UpdateSinglePerk, live tables
-- returned by reference, nil-until-540 slots, run-data table identity
-- replacement) and boots the REAL addon files under LuaJIT.
-- Loaded by run_integration.lua.

local H = {}

-- Simulated clock ---------------------------------------------------------
H.now = 1000
function GetTime() return H.now end
function H.Advance(seconds, step)
    step = step or 0.1
    local t = 0
    while t < seconds - 1e-9 do
        H.now = H.now + step
        t = t + step
        for _, f in ipairs(H.updateHandlers) do f(nil, step) end
    end
end

-- Chat capture ------------------------------------------------------------
H.chat = {}
DEFAULT_CHAT_FRAME = {
    AddMessage = function(_, msg) H.chat[#H.chat + 1] = msg end,
}
function H.ChatContains(pattern)
    for _, line in ipairs(H.chat) do
        if line:find(pattern, 1, true) then return line end
    end
    return nil
end

-- Frame stub (forked from EchoOptimizer's harness) -------------------------
H.updateHandlers = {}
H.eventHandlers = {}
H.frames = {}

local function NewRegion()
    local r = { shown = false, text = "", scripts = {}, events = {}, points = {} }
    local meta
    meta = {
        __index = function(t, k)
            if k == "SetText" then
                return function(self, txt) self.text = txt or "" end
            elseif k == "GetText" then
                return function(self) return self.text end
            elseif k == "SetTexture" then
                return function(self, tex) self.texture = tex end
            elseif k == "GetTexture" then
                return function(self) return self.texture end
            elseif k == "SetChecked" then
                return function(self, v) self.checked = v and true or false end
            elseif k == "GetChecked" then
                return function(self) return self.checked end
            elseif k == "SetFrameStrata" then
                return function(self, s) self.strata = s end
            elseif k == "GetFrameStrata" then
                return function(self) return self.strata end
            elseif k == "SetFrameLevel" then
                return function(self, l) self.level = l end
            elseif k == "GetFrameLevel" then
                return function(self) return rawget(self, "level") or 0 end
            elseif k == "SetValue" then
                return function(self, v) self.sliderValue = v end
            elseif k == "GetValue" then
                return function(self) return rawget(self, "sliderValue") or 0 end
            elseif k == "SetMinMaxValues" then
                return function(self, min, max) self.sliderMin, self.sliderMax = min, max end
            elseif k == "GetMinMaxValues" then
                return function(self)
                    return rawget(self, "sliderMin") or 0,
                        rawget(self, "sliderMax") or 1
                end
            elseif k == "SetValueStep" then
                return function(self, s) self.sliderStep = s end
            elseif k == "SetSize" then
                return function(self, w2, h2) self.w, self.h = w2, h2 end
            elseif k == "SetWidth" then
                return function(self, w2) self.w = w2 end
            elseif k == "SetHeight" then
                return function(self, h2) self.h = h2 end
            elseif k == "GetWidth" then
                return function(self) return rawget(self, "w") or 100 end
            elseif k == "GetHeight" then
                return function(self) return rawget(self, "h") or 20 end
            elseif k == "SetPoint" then
                return function(self, point, relTo, relPoint, x, y)
                    self.points[#self.points + 1] =
                        { point = point, relTo = relTo, relPoint = relPoint, x = x, y = y }
                end
            elseif k == "GetPoint" then
                return function(self, i)
                    local p = self.points[i or 1]
                    if not p then return nil end
                    return p.point, p.relTo, p.relPoint, p.x, p.y
                end
            elseif k == "ClearAllPoints" then
                return function(self) self.points = {} end
            elseif k == "GetScript" then
                return function(self, which) return self.scripts[which] end
            elseif k == "Show" then
                return function(self) self.shown = true end
            elseif k == "Hide" then
                return function(self) self.shown = false end
            elseif k == "IsShown" then
                return function(self) return self.shown end
            elseif k == "GetEffectiveScale" then
                return function() return 1 end
            elseif k == "CreateFontString" then
                return function() return NewRegion() end
            elseif k == "CreateTexture" then
                return function() return NewRegion() end
            elseif k == "SetScript" then
                return function(self, which, fn)
                    self.scripts[which] = fn
                    if which == "OnUpdate" and fn then
                        H.updateHandlers[#H.updateHandlers + 1] = fn
                    elseif which == "OnEvent" and fn then
                        H.eventHandlers[#H.eventHandlers + 1] = fn
                    end
                end
            elseif k == "RegisterEvent" then
                return function(self, ev) self.events[ev] = true end
            end
            if type(k) == "string" and k:match("^[A-Z]") then
                return function() end
            end
            return nil
        end,
    }
    return setmetatable(r, meta)
end
H.NewRegion = NewRegion

function CreateFrame(_, name)
    local f = NewRegion()
    if name then H.frames[name] = f; _G[name] = f end
    return f
end

function H.FireEvent(event, ...)
    for _, fn in ipairs(H.eventHandlers) do fn(nil, event, ...) end
end

-- Misc WoW API ------------------------------------------------------------
UIParent = NewRegion()
Minimap = NewRegion()
GetCursorPosition = function() return 0, 0 end
H.bags = {}
H.bagSizes = {}
function H.SetBagItem(bag, slot, name)
    H.bags[bag] = H.bags[bag] or {}
    H.bagSizes[bag] = math.max(H.bagSizes[bag] or 0, slot)
    H.bags[bag][slot] = name and
        ("|cffa335ee|Hitem:900001:0:0:0:0:0:0:0|h[" .. name .. "]|h|r")
        or nil
end
function GetContainerNumSlots(bag)
    return H.bagSizes[bag] or 0
end
function GetContainerItemLink(bag, slot)
    return H.bags[bag] and H.bags[bag][slot] or nil
end
function GetItemInfo(link)
    return type(link) == "string" and link:match("%[(.-)%]") or nil
end
NUM_CHAT_WINDOWS = 1
_G.ChatFrame1 = NewRegion()
H.joinedChannels = {}
function JoinTemporaryChannel(name) H.joinedChannels[name:lower()] = (H.nextChannelIndex or 1) end
function JoinChannelByName(name) H.joinedChannels[name:lower()] = (H.nextChannelIndex or 1) end
function GetChannelList()
    local out = {}
    for name, idx in pairs(H.joinedChannels) do
        out[#out + 1] = idx
        out[#out + 1] = name
    end
    return unpack(out)
end
H.sentChatMessages = {}
function SendChatMessage(text, kind, lang, target)
    H.sentChatMessages[#H.sentChatMessages + 1] = { text = text, kind = kind, target = target }
    return true
end
function ChatFrame_RemoveChannel() end
ChatFontNormal = {}
StaticPopupDialogs = {}
H.lastStaticPopup = nil
function StaticPopup_Show(which, arg1, arg2, data)
    H.lastStaticPopup = { which = which, arg1 = arg1, arg2 = arg2, data = data }
    return { which = which }
end
function H.AcceptLastStaticPopup()
    local p = H.lastStaticPopup
    if not p then return false end
    local def = StaticPopupDialogs[p.which]
    if def and def.OnAccept then def.OnAccept(nil, p.data) end
    return true
end
SlashCmdList = {}
UIErrorsFrame = { AddMessage = function() end }
bit = bit or require("bit")

function hooksecurefunc(tbl, name, hook)
    if type(tbl) == "string" then tbl, name, hook = _G, tbl, name end
    local orig = tbl[name]
    tbl[name] = function(...)
        local r = orig and orig(...)
        hook(...)
        return r
    end
end

H.playerLevel = 1
function UnitLevel() return H.playerLevel end
function UnitClass() return "Boganic", "MAGE" end
function UnitName() return "Boganic" end
function GetNormalizedRealmName() return "Ebonhold" end
H.projectVersion = nil
function GetAddOnMetadata(addon, field)
    if addon == "ProjectEbonhold" and field == "Version" then
        return H.projectVersion
    end
    return nil
end

-- Catalog fixture ----------------------------------------------------------
-- comment carries "Name - Rarity"; GetSpellInfo serves echo + tome names.
H.db = {}
H.tomeNames = {}
local RARITY = { [0] = "Common", [1] = "Uncommon", [2] = "Rare", [3] = "Epic" }
function H.AddEcho(id, name, opts)
    opts = opts or {}
    H.db[id] = {
        comment = name .. " - " .. (RARITY[opts.quality or 3]),
        classMask = opts.classMask or 1535,
        quality = opts.quality or 3,
        maxStack = opts.maxStack or 1,
        minLevel = opts.minLevel or 1,
        groupId = opts.groupId or 0,
        families = {},
        requiredSpell = opts.requiredSpell or 0,
    }
    H.names = H.names or {}
    H.names[id] = name
    if opts.requiredSpell and opts.requiredSpell ~= 0 and not opts.garbageTome then
        H.tomeNames[opts.requiredSpell] = "Tome of " .. name
    end
end

function GetSpellInfo(id)
    if H.tomeNames[id] then return H.tomeNames[id] end
    if H.names and H.names[id] then return H.names[id] end
    return nil
end

-- Wishlist families
H.AddEcho(200100, "Alpha Strike", { quality = 3, requiredSpell = 300100 })
H.AddEcho(200102, "Beta Guard", { quality = 2 })
H.AddEcho(200104, "Double Strike", { quality = 2, maxStack = 5, requiredSpell = 300104 })
-- multi-quality family (groupId 50 shared)
H.AddEcho(200110, "Gamma Bolt", { quality = 0, groupId = 50, requiredSpell = 300110 })
H.AddEcho(200112, "Gamma Bolt", { quality = 2, groupId = 50, requiredSpell = 300112 })
-- filler
H.AddEcho(200200, "Junk Aura", { quality = 1, requiredSpell = 300200 })
H.AddEcho(200202, "Junk Wall", { quality = 1 })
-- garbage shared lever 9 (non-conformant: GetSpellInfo(9) = nil)
H.AddEcho(200300, "Ward A", { quality = 0, requiredSpell = 9, garbageTome = true })
H.AddEcho(200302, "Ward B", { quality = 0, requiredSpell = 9, garbageTome = true })
-- shared CONFORMANT lever (two members, same name, distinct groups)
H.AddEcho(200400, "Temporal Echo", { quality = 3, groupId = 60, requiredSpell = 300400 })
H.AddEcho(200402, "Temporal Echo", { quality = 3, groupId = 61, requiredSpell = 300400 })
-- off-class echo (warrior-only mask)
H.AddEcho(200500, "Blade Ward", { quality = 1, classMask = 1 })
-- an off-wishlist CONFORMANT tome echo that the char has NOT discovered:
-- its lever must be SKIPPED (nothing to disable), not toggled
H.AddEcho(200700, "Lone Tome", { quality = 1, requiredSpell = 300700 })
-- the anchor: Adaptive Power (scales with distinct echoes)
H.AddEcho(200960, "Adaptive Power", { quality = 3 })

-- ProjectEbonhold stub ------------------------------------------------------
local Perks = {
    currentChoice = nil,
    pendingSelectSpellId = nil, pendingBanishIndex = nil,
    pendingFreezeIndex = nil, pendingReroll = nil,
    serverBuildSlots = nil, serverActiveSlot = 0,
    discoveredEchoes = nil,
}
H.Perks = Perks

H.wire = {}            -- ToggleTomeEcho sends: "lever|flag"
H.selectCalls = {}
H.banishCalls = {}
H.freezeCalls = {}
H.rerollCalls = 0
H.activateCalls = {}
H.saveCalls = {}
H.pollutedCalls = 0
H.pendingRollsCallsAtLowLevel = 0
H.disabledEchoes = {}
H.buildBusyUntil = -1
H.banishBlackhole = false

H.runDataTable = nil   -- nil/{} until first push; replace identity via PushRunData
function H.PushRunData(t) H.runDataTable = t end

H.granted = nil        -- name-keyed, one entry per stack (client shape)
H.locked = nil
H.wishlist = nil       -- raw client shape

local PerkUI = {}
H.shownBoards = {}
function PerkUI.Show(choices)
    H.shownBoards[#H.shownBoards + 1] = choices
end
function PerkUI.UpdateSinglePerk(idx, ...)
    H.updateSingleCalls = (H.updateSingleCalls or 0) + 1
end

local EchoJournal = {}
function EchoJournal.OnDataChanged() end
function EchoJournal.NotifyNewEcho() end

local Service = {}

function Service.GetCurrentChoice() return Perks.currentChoice end -- BY REFERENCE

function Service.GetGrantedPerks() return H.granted end
function Service.GetLockedPerks() return H.locked end
function Service.RequestGrantedPerks()
    H.grantedRequests = (H.grantedRequests or 0) + 1
    -- A completed server response replaces the client's granted table even
    -- when the authoritative result is empty. This is the generation-aware
    -- signal GameAdapter uses instead of trusting an elapsed timeout.
    if type(H.granted) == "table" then
        local fresh = {}
        for key, value in pairs(H.granted) do fresh[key] = value end
        H.granted = fresh
    end
end
function Service.GetActiveEchoLoadout() return H.wishlist end       -- BY REFERENCE
function Service.IsSpellInActiveEchoLoadout(id)
    H.pollutedCalls = H.pollutedCalls + 1
    return true -- deliberately poisoned: any use misclassifies
end
function Service.IsTomeEchoDisabled(id) return H.disabledEchoes[id] == true end
function Service.GetDiscoveredEchoes() return H.discovered or {} end

function Service.ToggleTomeEcho(spellId)
    -- client semantics: requiredSpell row check, LEVEL 1 ONLY self-reject,
    -- read-before-write from the (530-delayed) mirror, NO latch
    local row = H.db[spellId]
    if not row or not row.requiredSpell or row.requiredSpell == 0 then return false end
    if H.playerLevel ~= 1 then return false end
    local enable = Service.IsTomeEchoDisabled(spellId) and "1" or "0"
    H.wire[#H.wire + 1] = tostring(row.requiredSpell) .. "|" .. enable
    return true
end

-- Deliver the SS-530 reply: server-authoritative disabled set
function H.DeliverDiscovery(disabledEchoIds)
    Perks.discoveredEchoes = Perks.discoveredEchoes or {}
    H.disabledEchoes = {}
    for _, id in ipairs(disabledEchoIds or {}) do H.disabledEchoes[id] = true end
    EchoJournal.OnDataChanged()
end

function Service.SelectPerk(spellId)
    if Perks.pendingSelectSpellId then return false end
    if not spellId or spellId == 0 then return false end
    if not Perks.currentChoice then return false end
    local found = false
    for _, c in ipairs(Perks.currentChoice) do
        if c.spellId == spellId then found = true break end
    end
    if not found then return false end
    Perks.pendingSelectSpellId = spellId
    H.selectCalls[#H.selectCalls + 1] = spellId
    return true
end
function H.ResolveSelect(ok)
    Perks.pendingSelectSpellId = nil
    if ok then Perks.currentChoice = nil end
end

function Service.BanishPerk(idx)
    H.banishAttempts = (H.banishAttempts or 0) + 1
    if H.refuseNextBanish then
        H.refuseNextBanish = nil
        return false
    end
    if Perks.pendingBanishIndex then return false end
    if not idx or idx < 0 or idx > 2 then return false end
    local c = Perks.currentChoice and Perks.currentChoice[idx + 1]
    if c and c.isGuaranteed then return false end     -- silent refusal
    local rd = H.runDataTable or {}
    if (rd.remainingBanishes or 0) <= 0 then return false end
    Perks.pendingBanishIndex = idx
    H.banishCalls[#H.banishCalls + 1] = idx
    return true
end
function H.ResolveBanish(newId, newQ)
    -- SS-103: in-place mutation + UpdateSinglePerk (NOT Show)
    if H.banishBlackhole then return end
    local idx = Perks.pendingBanishIndex
    if idx == nil then return end
    local c = Perks.currentChoice and Perks.currentChoice[idx + 1]
    if c then c.spellId = newId; c.quality = newQ or 0 end
    Perks.pendingBanishIndex = nil
    ProjectEbonhold.PerkUI.UpdateSinglePerk(idx)
end

function Service.FreezePerk(idx)
    if Perks.pendingFreezeIndex then return false end
    local c = Perks.currentChoice and Perks.currentChoice[idx + 1]
    if c and c.isGuaranteed then return false end
    Perks.pendingFreezeIndex = idx
    H.freezeCalls[#H.freezeCalls + 1] = idx
    return true
end

function Service.RequestReroll()
    H.rerollAttempts = (H.rerollAttempts or 0) + 1
    if H.refuseNextReroll then
        H.refuseNextReroll = nil
        return false
    end
    if Perks.pendingReroll then return false end
    Perks.pendingReroll = true
    H.rerollCalls = H.rerollCalls + 1
    return true
end

function Service.GetPendingRollsCount()
    if H.playerLevel <= 1 then
        H.pendingRollsCallsAtLowLevel = H.pendingRollsCallsAtLowLevel + 1
    end
    return H.pendingRolls or 40
end

-- Build slots: nil until DeliverSlots; 3s single-flight busy
local function BuildBusy() return GetTime() < H.buildBusyUntil end
function Service.GetServerBuildSlots() return Perks.serverBuildSlots end
function Service.GetServerActiveSlot() return Perks.serverActiveSlot or 0 end
function Service.GetServerMaxSlots() return 5 end
function Service.GetServerUnlockedSlots() return H.unlockedSlots or 5 end
function Service.AreServerBuildSlotsEnabled() return true end
function Service.CanActivateServerBuildSlot()
    return H.playerLevel == 1 or H.playerLevel == 80
end
function Service.RequestServerBuildSlots()
    H.slotRequests = (H.slotRequests or 0) + 1
    -- model the fresh SS-540: a pending save/seed becomes visible now
    -- (unless H.saveBlackhole simulates an invisible SS-541 FAIL)
    if H.pendingSnapshot and not H.saveBlackhole then
        local ps = H.pendingSnapshot
        Perks.serverBuildSlots = Perks.serverBuildSlots or {}
        Perks.serverBuildSlots[ps.slot] =
            { slot = ps.slot, name = ps.name, verified = true, echoes = ps.echoes }
        H.pendingSnapshot = nil
    end
end
function Service.ActivateServerBuildSlot(slot)
    if not slot or slot < 0 then return false end
    if BuildBusy() then return false end
    H.buildBusyUntil = GetTime() + 3
    H.activateCalls[#H.activateCalls + 1] = slot
    return true
end
function Service.SaveServerBuildSlot(slot, name)
    if BuildBusy() then return false end
    H.buildBusyUntil = GetTime() + 3
    H.saveCalls[#H.saveCalls + 1] = { slot = slot, name = name }
    -- the server snapshots the whole granted+locked build into the slot;
    -- it surfaces on the NEXT RequestServerBuildSlots (fresh SS-540)
    local bySpell = {}
    if type(H.granted) == "table" then
        for _, entries in pairs(H.granted) do
            if type(entries) == "table" then
                for i = 1, #entries do
                    local id = entries[i].spellId
                    if id then bySpell[id] = (bySpell[id] or 0) + 1 end
                end
            end
        end
    end
    if type(H.locked) == "table" then
        for i = 1, #H.locked do
            local e = H.locked[i]
            if e.spellId then bySpell[e.spellId] = (bySpell[e.spellId] or 0) + (e.stack or 1) end
        end
    end
    local echoes = {}
    for id, st in pairs(bySpell) do
        echoes[#echoes + 1] = { spellId = id, stacks = st, locked = false }
    end
    H.pendingSnapshot = { slot = slot, name = name, echoes = echoes }
    H.lastSavedSlot = slot
    return true
end

function H.DeliverSlots(bySlot, activeSlot)
    Perks.serverBuildSlots = bySlot
    Perks.serverActiveSlot = activeSlot or 0
    EchoJournal.OnDataChanged()
end

-- Board delivery: sets the INTERNAL table (returned by reference), clears
-- pendingReroll (the one self-healing latch), fires PerkUI.Show like the
-- SS-16 handler does.
function H.DeliverBoard(cards)
    local choices = {}
    for i, c in ipairs(cards) do
        choices[i] = {
            spellId = c.spellId, quality = c.quality or 0,
            isFrozen = c.isFrozen or false, isCarried = c.isCarried or false,
            isGuaranteed = c.isGuaranteed or false,
        }
        if c.justFrozen then choices[i].justFrozen = true end
    end
    Perks.currentChoice = choices
    Perks.pendingReroll = nil
    ProjectEbonhold.PerkUI.Show(choices)
end

local PlayerRunService = {
    GetCurrentData = function() return H.runDataTable or {} end,
}

ProjectEbonhold = {
    PerkDatabase = H.db,
    PerkService = Service,
    Perks = Perks,
    PerkUI = PerkUI,
    EchoJournal = EchoJournal,
    PlayerRunService = PlayerRunService,
    Constants = { ENABLE_BANISH_SYSTEM = true },
}
H.service = Service

-- Options service (separate global, colon methods, persistent settings)
local optSettings = { autoAcceptLoadoutEchoes = true }
ProjectEbonholdOptionsService = {
    GetSetting = function(self, k) return optSettings[k] end,
    SetSetting = function(self, k, v) optSettings[k] = v end,
}
H.optSettings = optSettings

-- Runtime modules now consume the merged build catalog. Most focused suites do
-- not need to parse the multi-megabyte release baseline, so give them the same
-- schema with an empty test baseline; export/runtime-catalog suites load or
-- replace the real bundle explicitly. Each module Init call rebinds the facade
-- after a fixture replaces NexusDB.
Nexus = Nexus or {}
Nexus.BundledBuilds = {
    schemaVersion=1, catalogVersion="test-empty", sourceVersion="test",
    generatedAt=0, builds={},
}
dofile("core/Revisions.lua")
dofile("core/ViewProjections.lua")
dofile("ui/VirtualList.lua")
dofile("core/LoadoutEvidence.lua")
dofile("core/DataCompaction.lua")
dofile("core/BuildCatalog.lua")
dofile("core/DataRetention.lua")
dofile("data/Release.lua")
dofile("logic/Version.lua")
dofile("core/Performance.lua")
dofile("core/EchoCatalogSource.lua")
dofile("core/Errors.lua")
dofile("core/Scheduler.lua")
dofile("core/DiagnosticHistory.lua")
dofile("core/DiagnosticLogs.lua")
dofile("core/ViewRefresh.lua")
dofile("core/Updates.lua")

return H
