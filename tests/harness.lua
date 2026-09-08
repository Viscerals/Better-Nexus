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
            elseif k == "SetMaxLetters" then
                return function(self, value) self.maxLetters = value end
            elseif k == "SetTexture" then
                return function(self, tex) self.texture = tex end
            elseif k == "GetTexture" then
                return function(self) return self.texture end
            elseif k == "SetChecked" then
                return function(self, v) self.checked = v and true or false end
            elseif k == "GetChecked" then
                return function(self) return self.checked end
            elseif k == "SetFocus" then
                return function(self) self.focused = true end
            elseif k == "ClearFocus" then
                return function(self) self.focused = false end
            elseif k == "HasFocus" then
                return function(self) return self.focused and true or false end
            elseif k == "EnableMouse" then
                return function(self, value)
                    self.mouseEnabled = value ~= false
                end
            elseif k == "IsMouseEnabled" then
                return function(self) return self.mouseEnabled and true or false end
            elseif k == "Enable" then
                return function(self) self.enabled = true end
            elseif k == "Disable" then
                return function(self) self.enabled = false end
            elseif k == "IsEnabled" then
                return function(self) return self.enabled ~= false end
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

local function ObserveAuthorityBootstrap()
    local internals = Nexus and Nexus.MainInternals
    local authority = type(internals) == "table" and internals.AuthorityBootstrap
    if type(authority) ~= "table" or type(authority.New) ~= "function"
        or H._observedAuthorityFactory == authority then return end
    local originalNew = authority.New
    authority.New = function(...)
        local coordinator = originalNew(...)
        for _, method in ipairs({"BindAuthorityDatabase", "PumpAuthorityBootstrap"}) do
            local original = coordinator and coordinator[method]
            if type(original) == "function" then
                coordinator[method] = function(self, ...)
                    local result = original(self, ...)
                    H.lastAuthorityBootstrapResult = result
                    return result
                end
            end
        end
        return coordinator
    end
    H._observedAuthorityFactory = authority
end

function H.FireEvent(event, ...)
    if event == "ADDON_LOADED" then ObserveAuthorityBootstrap() end
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

local function CloneValue(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[CloneValue(key, seen)] = CloneValue(child, seen)
    end
    return copy
end
function H.CloneValue(value) return CloneValue(value) end

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
H.echoDataChangeNotifications = 0
function EchoJournal.OnDataChanged()
    H.echoDataChangeNotifications = H.echoDataChangeNotifications + 1
end
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
    if H.freshEchoReplies then
        local beforeSlots, beforeGranted, beforeLocked =
            Perks.serverBuildSlots, H.granted, H.locked
        local beforeDiscovered, beforeDisabled = H.discovered, H.disabledEchoes
        Perks.serverBuildSlots = CloneValue(Perks.serverBuildSlots)
        H.granted = CloneValue(H.granted)
        H.locked = CloneValue(H.locked)
        H.discovered = CloneValue(H.discovered)
        H.disabledEchoes = CloneValue(H.disabledEchoes)
        H.freshEchoReplyCount = (H.freshEchoReplyCount or 0) + 1
        if beforeSlots ~= Perks.serverBuildSlots then
            H.freshSlotIdentityChanges = (H.freshSlotIdentityChanges or 0) + 1
        end
        if beforeGranted ~= H.granted then
            H.freshGrantedIdentityChanges =
                (H.freshGrantedIdentityChanges or 0) + 1
        end
        if beforeLocked ~= H.locked then
            H.freshLockedIdentityChanges =
                (H.freshLockedIdentityChanges or 0) + 1
        end
        if beforeDiscovered ~= H.discovered then
            H.freshDiscoveredIdentityChanges =
                (H.freshDiscoveredIdentityChanges or 0) + 1
        end
        if beforeDisabled ~= H.disabledEchoes then
            H.freshDisabledIdentityChanges =
                (H.freshDisabledIdentityChanges or 0) + 1
        end
        if type(H.onFreshEchoReply) == "function" then H.onFreshEchoReply(H) end
        EchoJournal.OnDataChanged()
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

function H.EnableFreshEchoReplies(enabled, callback)
    H.freshEchoReplies = enabled and true or false
    H.onFreshEchoReply = callback
end

function H.SetServerActiveSlot(activeSlot)
    Perks.serverActiveSlot = activeSlot or 0
end

function H.NotifyEchoDataChanged()
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
dofile("core/Identity.lua")
dofile("core/CandidateEvidence.lua")
dofile("core/ViewProjections.lua")
dofile("core/CommunityProjection.lua")
dofile("core/CommunityController.lua")
dofile("ui/VirtualList.lua")
dofile("ui/LayoutMetrics.lua")
dofile("ui/CommunityRenderer.lua")
dofile("core/LoadoutEvidence.lua")
dofile("core/DataCompaction.lua")
dofile("core/BuildCatalog.lua")
dofile("core/DataRetention.lua")
dofile("data/Release.lua")
dofile("logic/Version.lua")
dofile("core/Performance.lua")
dofile("core/StutterAlertIntegration.lua")
dofile("core/EchoCatalogSource.lua")
dofile("core/Errors.lua")
dofile("core/Scheduler.lua")
dofile("core/LegacyDataMigration.lua")
dofile("core/DiagnosticHistory.lua")
dofile("core/DiagnosticLogs.lua")
dofile("core/ViewRefresh.lua")
dofile("core/Updates.lua")

-- Package B catalog authority: complete collections are read only through
-- generation-bound cursors. Test fixtures use these bounded walks instead of
-- the one-call `All`/`Summaries` exports, which refuse over-limit roots.
function H.CatalogAll()
    local catalog = Nexus.BuildCatalog
    local out = {}
    local token = catalog and catalog.BeginRecordCursor and catalog.BeginRecordCursor()
    if not token then return out end
    for _ = 1, 4096 do
        local page, err = catalog.RecordCursorNext(token)
        if err or type(page) ~= "table" or page.done then break end
        if page.id ~= nil and page.record ~= nil then out[page.id] = page.record end
    end
    return out
end

-- The durable authority payload location (MASTER-RC-001, architecture 3b5de54f
-- state machine lines 374/394/4849). After the accepted legacy-to-bundle
-- cutover `authorityDatabase.authorityBundle` is the sole durable payload write
-- and the exact PR #68 locations are read-only preserved input that is never
-- written and never read again once a bundle exists. A fixture that used to
-- inspect `NexusDB.communityBuilds` as storage inspects the bundle's payload
-- map through this seam instead; `NexusDB.communityBuilds` keeps its separate
-- meaning as the preserved legacy input.
function H.DurablePayload(field, database)
    local db = database or NexusDB
    if type(db) ~= "table" then return nil end
    local bundle = rawget(db, "authorityBundle")
    if type(bundle) ~= "table" then return nil end
    return rawget(bundle, field or "communityBuilds")
end

-- Same seam, always a table, for fixtures that only count or iterate.
function H.DurableBuilds(database)
    return H.DurablePayload("communityBuilds", database) or {}
end

function H.DurableTombstones(database)
    return H.DurablePayload("syncTombstones", database) or {}
end

-- Discard the durable authority bundle so the next admission takes the
-- LEGACY_BUNDLE_MIGRATION_REQUIRED bootstrap route (state machine line 374) over
-- the exact PR #68 rows a fixture has just seeded. This models a client whose
-- SavedVariables hold only legacy bytes. It is a fixture-only operation: no
-- production path clears the slot, and after occupancy the legacy locations are
-- never an admission input again (line 394).
function H.ResetDurableAuthority(database)
    local db = database or NexusDB
    if type(db) == "table" then rawset(db, "authorityBundle", nil) end
    return db
end

-- A raw write behind the published root grants no authority. A fixture that
-- seeds SavedVariables directly performs one explicit supported rebind, which
-- re-admits every selected typed slot from cursor zero.
function H.RebindCatalog(database, bundle)
    database = database or NexusDB
    if Nexus.LoadoutEvidence and Nexus.LoadoutEvidence.Init then
        Nexus.LoadoutEvidence.Init(database)
    end
    -- Explicit readmission from cursor zero: `Init` may reuse an exact
    -- unchanged binding, so a fixture that rewrote raw storage asks the
    -- admission owner for a complete new root.
    local catalog = Nexus.BuildCatalog
    catalog.BeginRootAdmission(database, bundle or Nexus.BundledBuilds)
    local result
    for _ = 1, 10000000 do
        result = catalog.PumpRootAdmission()
        if result.state ~= "pending" then break end
    end
    return result
end

-- MASTER-RC-001. Architecture lines 1207-1211 forbid a dependent initializer
-- from driving another domain recovery pump, so Sync.Init no longer admits the
-- catalog root and DpsCapture.Init no longer admits the evidence pool or the
-- catalog root as side effects. Fixtures that seeded SavedVariables and relied
-- on those side effects perform the same admission explicitly here.
--
-- This deliberately calls Init, NOT BeginRootAdmission: Init may reuse an exact
-- unchanged binding, which is precisely what the removed side effect did.
-- H.RebindCatalog forces a complete new admission from cursor zero, which
-- supersedes a serving root a fixture may still be reading, so it is not a
-- drop-in replacement for the removed calls.
--
-- No expected count, tolerance, threshold or oracle in any migrated fixture is
-- altered; only the admission that used to be implicit becomes explicit.
-- MASTER-RC-001. Store.State() is a DURABLE_READ and now returns a bounded
-- defensive copy, so a value captured once no longer aliases writes made after
-- the capture. Several fixtures were written against the older behaviour: they
-- bind `local state = Store.State()` once at file scope and then both observe
-- production writes through it and seed durable state through it, including
-- nested writes like `state.lockDesignTargetsBySlot[key] = {...}`.
--
-- This returns a fixture-side accessor that re-resolves at the point of every
-- access, routing through the architecture's counted private mutation entry
-- StoreAuthorityOwnerV1.UpdateStateV1 (lines 1907-1912) so nested writes land
-- on the live row exactly as they did before. ONLY the timing of the read
-- changes; no expected value, property, or assertion is altered.
--
-- Production does not need this and does not use it: all 14 production
-- Store.State() call sites read and use the value inside a single function
-- before any mutation, which was verified directly rather than assumed.
function H.LiveStoreStateV1()
    local function owner()
        local internals = Nexus and Nexus.MainInternals
        local entry = type(internals) == "table" and internals.StoreAuthorityOwner
        if type(entry) ~= "table" or type(entry.UpdateStateV1) ~= "function" then
            return nil
        end
        return entry
    end
    return setmetatable({}, {
        __index = function(_, key)
            local entry = owner()
            if not entry then return nil end
            -- A READ must not materialize the durable row. UpdateStateV1
            -- creates the row when absent, so routing every read through it
            -- gave fixture reads a side effect they never had, which showed up
            -- as one extra AutoLock postExpiryBlocked event. Consult the pure
            -- defensive read first: if the field is absent there, it is absent,
            -- and nothing is created. Only when it exists is the LIVE value
            -- fetched, so nested writes still land on the real row.
            local snapshot = Nexus.Store and Nexus.Store.State and Nexus.Store.State()
            if type(snapshot) ~= "table" or snapshot[key] == nil then return nil end
            local _, value = entry.UpdateStateV1(function(row) return row[key] end)
            return value
        end,
        __newindex = function(_, key, value)
            local entry = owner()
            if not entry then return end
            entry.UpdateStateV1(function(row) row[key] = value end)
        end,
    })
end

function H.AdmitCatalogV1(database, bundle)
    database = database or NexusDB
    if Nexus.LoadoutEvidence and type(Nexus.LoadoutEvidence.Init) == "function"
        then Nexus.LoadoutEvidence.Init(database)
    end
    local catalog = Nexus.BuildCatalog
    if catalog and type(catalog.Init) == "function" then
        local budget = type(catalog.Budget) == "function" and catalog.Budget() or {}
        local limit = tonumber(budget.maximumPumps) or 0
        local selected = bundle or Nexus.BundledBuilds
        local result = catalog.Init(database, selected)
        local pumps = 1
        while type(result) == "table" and result.state == "pending"
            and pumps < limit do
            pumps = pumps + 1
            result = catalog.Init(database, selected)
        end
        return result
    end
end

function H.CatalogSummaries()
    local catalog = Nexus.BuildCatalog
    local out = {}
    local token = catalog and catalog.BeginSummaryCursor and catalog.BeginSummaryCursor()
    if not token then return out end
    for _ = 1, 4096 do
        local summary, done, err = catalog.SummaryCursorNext(token)
        if err then break end
        if type(summary) == "table" then out[summary.id] = summary end
        if done then break end
    end
    return out
end

-- Authority bootstrap ------------------------------------------------------
-- Architecture 3b5de54f docs/SYNC_TRUST_CATALOG_AUTHORITY_STATE_MACHINE.md:
--   1201-1204  AuthorityBootstrapCoordinatorV1 is the sole startup sequencing
--              owner; its driver dispatches at most ONE PumpAuthorityBootstrap
--              slice per scheduler turn.
--   1206       Store.Init returns the explicit detached {state="pending"}
--              result until the coordinator reaches STORE_READY. A successful
--              call is never readiness.
--   1715       Init processes no more than one V1 slice and may be called only
--              inside the startup coordinator or an explicit supported rebind.
--
-- Offline fixtures that need a bound, ready authority root act as that
-- scheduler. Each call is ONE process start -- a fresh coordinator that
-- reclassifies from the exact durable source, exactly as a reload does --
-- followed by one slice per turn under a closed bound. Bound exhaustion is
-- never reported as readiness: the honest pending or terminal result is
-- returned, so a fixture that fails to reach STORE_READY fails visibly
-- instead of silently proceeding against an unbound root.
H.BOOTSTRAP_TURN_BOUND = 32

function H.BootstrapStore()
    local Store = Nexus and Nexus.Store
    assert(type(Store) == "table" and type(Store.Init) == "function",
        "BootstrapStore requires Nexus.Store to be loaded")
    local internals = Nexus and Nexus.MainInternals
    local owner = type(internals) == "table" and internals.AuthorityBootstrap
    local factory = type(owner) == "table" and owner.owner == Store
        and owner.New or nil
    if type(factory) ~= "function" then
        -- A Store stub without the coordinator factory keeps its own contract;
        -- readiness is still whatever its explicit result says.
        return Store.Init()
    end
    local coordinator = factory()
    local result = Store.Init(coordinator)
    local turns, catalogSlices = 0, 0
    local catalog = Nexus and Nexus.BuildCatalog
    local budget = catalog and type(catalog.Budget) == "function"
        and catalog.Budget() or {}
    local catalogLimit = tonumber(budget.maximumPumps) or 0
    while type(result) == "table" and result.state == "pending"
        and ((result.workDomain == "catalog" and catalogSlices < catalogLimit)
            or (result.workDomain ~= "catalog"
                and turns < H.BOOTSTRAP_TURN_BOUND)) do
        if result.workDomain == "catalog" then
            catalogSlices = catalogSlices + 1
        else
            turns = turns + 1
        end
        result = coordinator:PumpAuthorityBootstrap()
    end
    return result
end

-- Same drive, but asserts the run actually reached STORE_READY.
function H.BootstrapStoreReady()
    local result = H.BootstrapStore()
    assert(type(result) == "table" and result.state == "ready",
        "authority bootstrap did not reach STORE_READY: "
            .. tostring(type(result) == "table"
                and (result.reason or result.state) or result))
    return result
end

-- Bounded startup driver -----------------------------------------------------
-- Architecture 3b5de54f lines 1203-1204: MainLifecycle dispatches at most ONE
-- PumpAuthorityBootstrap slice per scheduler turn, so a full startup
-- legitimately spans several turns, and world entry completes on the turn the
-- coordinator reaches STORE_READY (line 1519). A fixture that fires
-- ADDON_LOADED and PLAYER_ENTERING_WORLD back to back must therefore drive
-- ordinary scheduler turns until startup completes before it may assert
-- anything about an initialized addon.
--
-- The completion signal is deliberately INDEPENDENT of anything a caller
-- asserts. Nexus.Scheduler.IsInitialized() becomes true only inside
-- MainLifecycle's Initialize (core/MainLifecycle.lua, the Scheduler.Init
-- owner), which runs only once the coordinator has reached STORE_READY and
-- released its dependents (line 1519). None of the fixtures that use this
-- helper reference the Scheduler at all, so waiting on it cannot make any of
-- their assertions vacuous -- unlike waiting on a caller's own subject, which
-- is deliberately NOT done.
--
-- BuildCatalog's ROOT_ADMITTED status is explicitly NOT the signal: the
-- coordinator releases BuildCatalog.Init at STORE_AUTHORITY_PENDING, several
-- slices before STORE_READY, so it reports startup complete too early.
--
-- The bound is closed and exhaustion is reported honestly as false. Callers
-- assert that startup completed; they never assume it, and no expected count,
-- tolerance, threshold or oracle is altered to accommodate the extra turns.
function H.AuthorityBootstrapComplete()
    local scheduler = Nexus and Nexus.Scheduler
    if not (scheduler and type(scheduler.IsInitialized) == "function") then
        return false
    end
    local ok, initialized = pcall(scheduler.IsInitialized)
    return ok and initialized == true
end

-- Drives scheduler turns with the smallest useful step, so the simulated clock
-- moves as little as possible and time-based cadences are perturbed as little
-- as possible while still granting one bootstrap slice per turn.
function H.AdvanceUntilStarted(step)
    step = step or 0.01
    local turns, catalogSlices = 0, 0
    local catalog = Nexus and Nexus.BuildCatalog
    local budget = catalog and type(catalog.Budget) == "function"
        and catalog.Budget() or {}
    local catalogLimit = tonumber(budget.maximumPumps) or 0
    while not H.AuthorityBootstrapComplete() do
        local result = H.lastAuthorityBootstrapResult
        local catalogTurn = type(result) == "table"
            and result.workDomain == "catalog"
        if catalogTurn then
            if catalogSlices >= catalogLimit then break end
            catalogSlices = catalogSlices + 1
        else
            if turns >= H.BOOTSTRAP_TURN_BOUND then break end
            turns = turns + 1
        end
        H.Advance(step, step)
    end
    return H.AuthorityBootstrapComplete(), turns, catalogSlices
end

-- Asserting form, for fixtures that require a started addon.
function H.RequireStarted(step)
    local started, turns, catalogSlices = H.AdvanceUntilStarted(step)
    assert(started, string.format(
        "authority bootstrap did not complete within %d non-catalog turns and %d catalog slices",
        H.BOOTSTRAP_TURN_BOUND, catalogSlices))
    return turns
end

-- MASTER-RC-009. The local-owner proof is an admission input. A READ never
-- binds, admits, or re-admits; on owner drift the read gate records one
-- explicit OWNER_REBIND_REQUIRED request and returns a fixed read-only
-- refusal. In the product, MainLifecycle's scheduler turn dispatches the
-- rebind. Offline fixtures that load Store/BuildCatalog directly have no
-- lifecycle, so they stand in for that scheduler here -- exactly as
-- H.BootstrapStore stands in for the bootstrap pump. This is the authorized
-- coordinator route, never a consumer driving admission.
function H.RebindAuthorityV1(reason)
    local catalog = Nexus and Nexus.BuildCatalog
    assert(type(catalog) == "table"
        and type(catalog.PumpAuthorityRebindV1) == "function",
        "RebindAuthorityV1 requires Nexus.BuildCatalog")
    local budget = type(catalog.Budget) == "function" and catalog.Budget() or {}
    local limit = tonumber(budget.maximumPumps) or 0
    local result = catalog.PumpAuthorityRebindV1(
        nil, nil, reason or "OWNER_REBIND_REQUIRED")
    local pumps = 1
    while type(result) == "table" and type(result.summary) == "table"
        and result.summary.state == "pending"
        and pumps < limit do
        pumps = pumps + 1
        result = catalog.PumpAuthorityRebindV1(
            nil, nil, reason or "OWNER_REBIND_REQUIRED")
    end
    return result
end

function H.RebindAuthorityOwner()
    return H.RebindAuthorityV1("OWNER_REBIND_REQUIRED")
end


-- ---------------------------------------------------------------------------
-- MASTER-RC-015: shared mixed-client fixture mechanics.
--
-- Architecture fixture rules 1-4 (lines 4700-4706) require every mixed-client
-- case to materialize the verified PR #68 tree, load each side's exact
-- `Nexus.toc` order into its own isolated global table, capture the ACTUAL wire
-- bytes a sender produces, and feed those exact bytes through the other side's
-- real decoder, receiver and durable catalog path.
--
-- These four primitives exist so those mechanics are written once instead of
-- per case. The reuse boundary is deliberate and narrow:
--
--   * ONE verified immutable source tree may serve MANY fresh isolated
--     runtimes. Materialization is the expensive part and is cached per commit.
--   * Captured wire vectors are immutable bytes and may be replayed.
--   * SHARED SETUP IS NEVER SHARED MUTABLE ADDON STATE. Every side handed out
--     by H.IsolatedSideV1 is a fresh environment with its own global table and
--     its own database. Nothing is reset and reused, because a reset would have
--     to be proven complete and is not.
--
-- What is deliberately NOT provided, because a helper that offers a shortcut
-- gets used: nothing here injects a decoded table, seeds correlation or request
-- state, or reports success before a durable terminal. Feeding a receiver goes
-- through its real public incoming entry point and pumps to terminal, and the
-- caller asserts the durable result itself.

local MIX_TREES = {}

local function MixReadFile(path)
    local handle = io.open(path, "rb")
    if not handle then return nil end
    local text = handle:read("*a")
    handle:close()
    return text
end

-- Fixture rule 1. Materializes the exact commit once per process and returns
-- the root plus the tree hash for verification. The caller must verify the
-- hash: this returns it rather than asserting, so a fixture cannot silently
-- accept an unverified tree.
function H.MaterializeBaseTreeV1(commit)
    assert(type(commit) == "string" and #commit >= 7,
        "MaterializeBaseTreeV1 requires an exact commit")
    local cached = MIX_TREES[commit]
    if cached then return cached.root, cached.tree end
    local temp = (os.getenv("TEMP") or os.getenv("TMPDIR") or ".")
    local dir = (temp:gsub("\\", "/")) .. "/bn-mix-" .. commit:sub(1, 12)
    local windows = dir:gsub("/", "\\")
    os.execute('rmdir /s /q "' .. windows .. '" 2>nul')
    os.execute('mkdir "' .. windows .. '" 2>nul')
    os.execute('git archive ' .. commit .. ' | tar -x -C "' .. dir .. '"')
    -- `git rev-parse <sha>^{tree}` cannot be used: `^` is the cmd.exe escape
    -- character and is consumed before git sees it.
    local hashPath = dir .. "/.mix-tree"
    os.execute('git log -1 --format=%T ' .. commit .. ' > "' .. hashPath .. '"')
    local tree = MixReadFile(hashPath)
    tree = tree and (tree:gsub("%s+$", "")) or nil
    MIX_TREES[commit] = {root=dir, tree=tree}
    return dir, tree
end

H.MIX_STDLIB = {
    "print", "type", "pairs", "ipairs", "string", "table", "math", "assert",
    "tostring", "tonumber", "setmetatable", "getmetatable", "rawget", "rawset",
    "rawequal", "next", "select", "error", "pcall", "xpcall", "os", "io",
    "load", "unpack", "collectgarbage", "coroutine", "debug", "require",
}

-- Fixture rules 2 and 3: one isolated global table per side, resolving every
-- module against that side's own source root so a module can never reach the
-- other tree.
function H.NewIsolatedEnvV1(root)
    local env = {}
    for _, name in ipairs(H.MIX_STDLIB) do env[name] = _G[name] end
    env.unpack = env.unpack or table.unpack
    env._G = env
    env.__root = root
    env.dofile = function(relative)
        local source = MixReadFile(env.__root .. "/" .. relative)
        if not source then error("missing " .. tostring(relative)) end
        local chunk, err = load(source, "@" .. relative, "t", env)
        if not chunk then error(err) end
        return chunk()
    end
    return env
end

function H.TocOrderV1(root)
    local text = MixReadFile(root .. "/Nexus.toc")
    if not text then return {} end
    local order = {}
    for line in text:gmatch("[^\r\n]+") do
        local entry = line:match("^%s*(.-)%s*$")
        if entry ~= "" and not entry:find("^#") and entry:find("%.lua$") then
            order[#order + 1] = (entry:gsub("\\", "/"))
        end
    end
    return order
end

-- A COMPLETELY FRESH side: new environment, new global table, exact TOC order,
-- new database. Never a reset of a previous one. `database` may be supplied so
-- a scenario starts from exact SavedVariables bytes; otherwise a clean one is
-- created. Returns a table so callers cannot accidentally share state through
-- positional returns.
-- `identity` gives this side its own character. It matters: a peer exchange
-- driven between two sides that share a character name is treated as a SELF
-- request and silently dropped -- core/SyncReconciler.lua ScheduleLoadout
-- returns true without scheduling when isSelfRequest(requester) holds. Measured:
-- a responder holding a build answers a WLLQ from "Requestor" with a decodable
-- 1/1 sequence and answers the identical request from its own name with
-- nothing. Identity is applied AFTER the harness stubs load and BEFORE the TOC
-- loads, because modules capture the character name at load time.
function H.IsolatedSideV1(root, database, identity)
    local env = H.NewIsolatedEnvV1(".")
    local harness = env.dofile("tests/harness.lua")
    env.__root = root
    if type(identity) == "table" and identity.playerName then
        local realm = identity.realm or "Ebonhold"
        env.UnitName = function(unit)
            if unit == nil or unit == "player" then
                return identity.playerName, nil
            end
            return identity.playerName, nil
        end
        env.GetNormalizedRealmName = function() return realm end
        env.GetRealmName = env.GetNormalizedRealmName
    end
    local loaded, failed = 0, {}
    for _, relative in ipairs(H.TocOrderV1(root)) do
        local ok, err = pcall(env.dofile, relative)
        if ok then loaded = loaded + 1
        else failed[#failed + 1] = relative .. ": " .. tostring(err) end
    end
    env.NexusDB = database or {communityBuilds={}, syncTombstones={},
        dpsCapture={}}
    local nexus = env.Nexus
    if type(harness.BootstrapStore) == "function" then
        pcall(harness.BootstrapStore)
    end
    if nexus then
        pcall(nexus.LoadoutEvidence and nexus.LoadoutEvidence.Init, env.NexusDB)
        if nexus.BuildCatalog and nexus.BuildCatalog.Init then
            pcall(nexus.BuildCatalog.Init, env.NexusDB, nexus.BundledBuilds)
        end
        if nexus.Sync and nexus.Sync.Init then
            pcall(nexus.Sync.Init, nexus.Codec, {})
        end
    end
    return {env=env, harness=harness, nexus=nexus, root=root,
        loaded=loaded, failed=failed}
end

-- Fixture rule 4, capture half. Runs `operation` on this side -- the real
-- production send path, whatever it is -- and returns every wire message the
-- side actually emitted, in order, as immutable strings.
--
-- This is deliberately generic rather than a BroadcastBuild helper, because the
-- five-step totals trace also has to capture the bytes a RECEIVER emits when it
-- creates its own request. One primitive, no special case.
function H.CaptureWireV1(side, operation, pumps)
    assert(type(side) == "table" and side.nexus, "CaptureWireV1 needs a side")
    side.harness.sentChatMessages = {}
    local results = {pcall(operation, side)}
    for _ = 1, (pumps or 40) do
        pcall(side.nexus.Sync.OnUpdate, 0.2)
    end
    local wire = {}
    for _, message in ipairs(side.harness.sentChatMessages) do
        wire[#wire + 1] = message.text or ""
    end
    return wire, table.unpack(results)
end

-- Only the messages carrying `code`, so a caller never attributes ambient
-- scheduled traffic to the operation under test. Measured: a reconciliation
-- request appears in the pump window even when the operation was refused.
function H.WireOfCodeV1(wire, code)
    local matched = {}
    for _, text in ipairs(wire or {}) do
        if text:find("^" .. code) then matched[#matched + 1] = text end
    end
    return matched
end

function H.WireCodesV1(wire)
    local codes = {}
    for _, text in ipairs(wire or {}) do
        codes[#codes + 1] = text:match("^(%u%u%u%u)") or "????"
    end
    return table.concat(codes, ",")
end

-- Fixture rule 4, replay half, and rule 5's verdict rule. Feeds exact captured
-- bytes through the receiving side's REAL public incoming entry point and pumps
-- to terminal. It returns the durable JSON either side of the exchange so the
-- caller asserts durable convergence or the fail-closed terminal itself.
--
-- It does not decode, does not inject, and does not judge: there is no
-- "accepted" verdict here beyond what the real entry point returned, precisely
-- so a caller cannot substitute a helper return for a durable assertion.
function H.ReplayIntoReceiverV1(side, wire, sender, pumps)
    assert(type(side) == "table" and side.nexus, "ReplayIntoReceiverV1 needs a side")
    local codec = side.nexus.Codec
    local before = codec and codec.JSONEncode(side.env.NexusDB) or nil
    local accepted = {}
    for index, text in ipairs(type(wire) == "table" and wire or {wire}) do
        local ok, result = pcall(side.nexus.Sync.HandleIncoming, text,
            sender or "Boganic")
        accepted[index] = ok and result or false
    end
    for _ = 1, (pumps or 20) do
        pcall(side.nexus.Sync.OnUpdate, 0.2)
    end
    local after = codec and codec.JSONEncode(side.env.NexusDB) or nil
    return {
        side=side, before=before, after=after, accepted=accepted,
        mutated=(before ~= after),
        Durable=function(id)
            local ok, record = pcall(side.nexus.BuildCatalog.Get, id)
            return ok and type(record) == "table" and record or nil
        end,
    }
end

return H
