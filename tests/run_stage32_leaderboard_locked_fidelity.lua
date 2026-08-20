-- Stage 32.4: assembled Leaderboard -> Wishlist Editor evidence fidelity.
local H = dofile("tests/harness.lua")

dofile("data/DefaultProfile.lua")
dofile("logic/Model.lua")
dofile("logic/Strategy.lua")
dofile("logic/Ratchet.lua")
dofile("logic/Policy.lua")
dofile("core/Store.lua")
dofile("core/GameAdapter.lua")
dofile("core/LoadoutEvidence.lua")
dofile("core/CandidateEvidence.lua")
dofile("core/WishlistModel.lua")
dofile("core/WishlistController.lua")
dofile("ui/WishlistRenderer.lua")
dofile("ui/WishlistEditor.lua")
dofile("ui/Theme.lua")
dofile("ui/Leaderboard.lua")

local checks = 0
local function Check(value, message)
    checks = checks + 1
    assert(value, message)
end

local function Clone(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, field in pairs(value) do out[Clone(key, seen)] = Clone(field, seen) end
    return out
end

local function Same(left, right, path, seen)
    path = path or "value"
    if type(left) ~= type(right) then error(path .. " type mismatch", 2) end
    if type(left) ~= "table" then
        if left ~= right then
            error(path .. " mismatch: " .. tostring(left) .. " ~= " .. tostring(right), 2)
        end
        return
    end
    seen = seen or {}
    if seen[left] == right then return end
    seen[left] = right
    for key, value in pairs(left) do
        if right[key] == nil and value ~= nil then
            error(path .. " missing key " .. tostring(key), 2)
        end
        Same(value, right[key], path .. "." .. tostring(key), seen)
    end
    for key, value in pairs(right) do
        if left[key] == nil and value ~= nil then
            error(path .. " unexpected key " .. tostring(key), 2)
        end
    end
end

local function IdSet(values)
    local out = {}
    for _, value in ipairs(values or {}) do
        local id = tonumber(type(value) == "table"
            and (value.spellId or value.id) or value)
        if id then out[id] = true end
    end
    return out
end

local function SetText(values)
    local ids = {}
    for id in pairs(values or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for index, id in ipairs(ids) do ids[index] = tostring(id) end
    return table.concat(ids, ",")
end

local function SameSet(left, right)
    for id in pairs(left) do if not right[id] then return false end end
    for id in pairs(right) do if not left[id] then return false end end
    return true
end

local function EchoTotal(values)
    local total = 0
    for _, value in ipairs(values or {}) do
        total = total + math.max(1, tonumber(value.stacks or value.count) or 1)
    end
    return total
end

local function EchoKey(values)
    local counts, ids = {}, {}
    for _, value in ipairs(values or {}) do
        local id = tonumber(value.spellId or value.id)
        local count = tonumber(value.stacks or value.count) or 1
        counts[id] = (counts[id] or 0) + count
    end
    for id in pairs(counts) do ids[#ids + 1] = id end
    table.sort(ids)
    local parts = {}
    for _, id in ipairs(ids) do
        parts[#parts + 1] = tostring(id) .. "x" .. tostring(counts[id])
    end
    return table.concat(parts, ",")
end

NexusDB = {settings={},chars={},futureRoot={keep=true}}
Nexus.Store.Init()
Nexus.LoadoutEvidence.Init(NexusDB)

local catalog = {rows={}}
local overflowOrdinary = {}
for index = 1, 79 do
    local id = 210000 + index
    local stacks = index > 69 and 2 or 1 -- 89 ordinary copies total.
    overflowOrdinary[index] = {
        spellId=id,quality=index % 5,stacks=stacks,
        future={ordinal=index},
    }
    catalog.rows[id] = {
        spellId=id,name="Ordinary " .. tostring(index),quality=index % 5,
        groupId=id,maxStack=math.max(2, stacks),
    }
end

local lockedIds = {201382,201388,201398,201410,201416,201420}
local locked = {}
for index, id in ipairs(lockedIds) do
    locked[index] = {spellId=id,stacks=index == 2 and 2 or 1,
        quality=index % 5,future={locked=index}}
    catalog.rows[id] = {
        spellId=id,name="Locked " .. tostring(index),quality=index % 5,
        groupId=9000 + index,maxStack=2,
    }
end
-- One spell has both roles. Two locked picks share catalog family text/group;
-- neither fact may erase an explicit locked identity.
overflowOrdinary[79].spellId = lockedIds[1]
catalog.rows[lockedIds[2]].name = "Collision"
catalog.rows[lockedIds[2]].groupId = 9999
catalog.rows[lockedIds[3]].name = "Collision"
catalog.rows[lockedIds[3]].groupId = 9999

local validOrdinary = {}
for index, echo in ipairs(overflowOrdinary) do
    if index ~= 78 then
        local copy = Clone(echo)
        copy.stacks = index == 1 and 2 or 1
        validOrdinary[#validOrdinary + 1] = copy
    end
end
Check(EchoTotal(overflowOrdinary) == 89 and EchoTotal(validOrdinary) == 79,
    "fixture did not cover the 89/79 ordinary boundary")

local row = {
    player="Fixture",dps=123456,duration=60,level=80,ts=10,
    category="dummy",fingerprint=EchoKey(overflowOrdinary),
    buildId="colliding-id",echoes=overflowOrdinary,lockedEchoes=locked,
    build={id="colliding-id",title="Historical Exact Record",author="Fixture",
        class="MAGE",fingerprint=EchoKey(overflowOrdinary)},
    future={keep=true},
}
local historicalBuild = Clone(row.build)
local catalogBefore = Clone(catalog)

local uploadCalls, associationCalls, gameplayCalls = 0, 0, 0
local uploadMode = "success"
local uploaded
local Adapter = Nexus.GameAdapter
Adapter.Catalog = function() return catalog end
Adapter.LockedOwned = function()
    return {bySpell={[lockedIds[4]]=1},list={{spellId=lockedIds[4]}},synced=true}
end
Adapter.Owned = function() return {bySpell={}} end
Adapter.Wishlist = function() return nil end
Adapter.GetWishlistCandidates = function() return {} end
Adapter.Slots = function() return {activeSlot=0,maxSlots=5,bySlot={}} end
Adapter.WishlistKey = function(echoes)
    local out = {}
    for _, echo in ipairs(echoes or {}) do
        out[#out + 1] = tostring(echo.spellId) .. "x" .. tostring(echo.stacks or 1)
    end
    return table.concat(out, ",")
end
Adapter.UploadWishlist = function(slot, name, echoes)
    uploadCalls = uploadCalls + 1
    if uploadMode == "spacing" then return false, "spacing" end
    uploaded = {slot=slot,name=name,echoes=Clone(echoes)}
    return true
end
Adapter.SetFirstLoadoutWishlistIdentity = function()
    associationCalls = associationCalls + 1
end
Adapter.PresentationRevisions = function() return 0,0,0,0,0 end

local character = Nexus.Store.State()
character.lockDesignTargetsBySlot = {
    unrelated={ [299999]=true, future={keep=true} },
}
local unrelatedBefore = Clone(character.lockDesignTargetsBySlot.unrelated)

local madeFrames = {}
local realCreateFrame = CreateFrame
CreateFrame = function(...)
    local made = realCreateFrame(...)
    madeFrames[#madeFrames + 1] = made
    return made
end

Nexus.WishlistEditor.Init(Adapter, Nexus.Model)
local currentRecordAvailable = true
Nexus.DpsCapture = {GetDpsBoard=function(category)
    return category == "dummy" and {row} or {}
end,GetCharacterBest=function(category)
    return currentRecordAvailable and category == "dummy" and row or nil
end}
row.echoes = validOrdinary
row.fingerprint = EchoKey(validOrdinary)
historicalBuild.fingerprint = row.fingerprint
row.build = Clone(historicalBuild)
Nexus.ViewProjections.Reset()
local projectionProbe = Nexus.ViewProjections.Leaderboard(
    "dummy", {classFilter="ALL",search=""})
Check(type(projectionProbe) == "table" and #projectionProbe == 1,
    "valid public control was filtered by direct projection")
-- Projection completeness is proven above; the remainder isolates the legacy
-- UI-to-editor evidence seam without a second projection owner.
Nexus.ViewProjections = nil
Nexus.Leaderboard.Init(Adapter)

local L = Nexus.Leaderboard
local function RenderCurrent()
    L.Show("dummy")
    L.SetClassFilter("ALL")
    L.RefreshData()
    Check(L.SelectKey("fixture|string:" .. tostring(row.fingerprint)),
        "assembled Leaderboard row was not selectable")
    return NexusLeaderboardFrame._leaderboardDetail
end

local function DisplayedLocked(detail)
    local out = {}
    for _, button in ipairs(detail.lockedIcons or {}) do
        if button.tip and button:IsShown() then out[tonumber(button.tip)] = true end
    end
    return out
end

local function EditorLocked()
    local out = {}
    for _, frame in ipairs(madeFrames) do
        if frame:IsShown()
            and (frame.slotState == "locked" or frame.slotState == "designed") then
            local id = tonumber(frame.spellId)
            if id then out[id] = true end
        end
    end
    return out
end

local expected = IdSet(lockedIds)
local function EditorShown()
    return NexusEditorFrame and NexusEditorFrame:IsShown() or false
end

-- Use the valid public 79-copy control for assembled locked-Echo fidelity.
-- Public completeness exclusion for the 89-copy boundary is covered by the
-- dedicated completeness projection fixtures.
local detail = RenderCurrent()
local displayed = DisplayedLocked(detail)
Check(SameSet(displayed, expected),
    "Leaderboard did not display its six authoritative locked Echoes")
Check(detail.copy:IsEnabled(),
    "valid 79-copy ordinary evidence was not actionable")

-- A current catalog payload colliding with the historical identity cannot be
-- used merely because the build ID matches.
row.build = nil
row.buildIdentityMismatch = true
Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{source="collision fixture"})
detail = RenderCurrent()
Check(not detail.copy:IsEnabled()
    and detail.more:GetText():find("identities do not match", 1, true),
    "historical/current identity collision did not fail closed")
detail.copy:GetScript("OnClick")()
Check(not EditorShown() and uploadCalls == 0,
    "colliding build ID supplied Copy authority")

-- Unrelated revision churn keeps the selected evidence current. A change to
-- that exact record still invalidates the preview before the click.
row.build = Clone(historicalBuild)
row.buildIdentityMismatch = nil
Check(Nexus.BuildCatalog.Put({
    id=row.buildId,title="Selected direct record",author="Fixture",
    class="MAGE",fingerprint=row.fingerprint,
    echoes=Clone(validOrdinary),lastModified=10,
}) and Nexus.BuildCatalog.Put({
    id="unrelated-same-fingerprint",title="Unrelated exact record",
    author="Other",class="MAGE",fingerprint=row.fingerprint,
    echoes=Clone(validOrdinary),lastModified=10,
}), "same-fingerprint catalog churn fixture did not initialize")
Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{source="valid fixture"})
detail = RenderCurrent()
Check(detail.copy:IsEnabled(), "valid 79+6 record was not actionable")
detail.copyCandidate.ordinaryEchoes[1].spellId = 299997
detail.copy:GetScript("OnClick")()
Check(not EditorShown() and not detail.copy:IsEnabled()
    and detail.more:GetText():find("Echo evidence changed",1,true),
    "candidate evidence mutation opened a different preview")
detail = RenderCurrent()
Check(detail.copy:IsEnabled(), "fresh evidence did not recover after mutation refusal")
currentRecordAvailable = false
detail.copy:GetScript("OnClick")()
Check(not EditorShown() and not detail.copy:IsEnabled()
    and detail.more:GetText():find("evidence changed", 1, true),
    "missing current selected record remained actionable")
currentRecordAvailable = true
detail = RenderCurrent()
Check(detail.copy:IsEnabled(),
    "selected record did not recover after becoming available")
Nexus.Revisions.Advance(Nexus.Revisions.DPS_CHANGED,{source="between render and click"})
local unrelatedCurrent = Nexus.CandidateEvidence.Validate(detail.copyCandidate)
Check(unrelatedCurrent ~= nil,
    "unrelated DPS revision invalidated the selected candidate")
Check(Nexus.BuildCatalog.Put({
    id="unrelated-same-fingerprint",title="Unrelated title changed",
    author="Other",class="MAGE",fingerprint=row.fingerprint,
    echoes=Clone(validOrdinary),lastModified=11,
}), "unrelated same-fingerprint record did not update")
local unrelatedCatalogCurrent =
    Nexus.CandidateEvidence.Validate(detail.copyCandidate)
Check(unrelatedCatalogCurrent ~= nil,
    "unrelated same-fingerprint catalog churn invalidated the selected record")
row.ownerVerified = true
detail.copy:GetScript("OnClick")()
Check(not EditorShown() and not detail.copy:IsEnabled()
    and detail.more:GetText():find("evidence changed", 1, true),
    "render-to-click selected-evidence drift did not fail closed")

-- A fresh projection opens the real editor with the same exact six. Copy and
-- cancel remain read-only.
detail = RenderCurrent()
local validBefore = Clone(row)
local dbBeforeCopy = Clone(NexusDB)
detail.copy:GetScript("OnClick")()
local editorLocked = EditorLocked()
Check(NexusEditorFrame:IsShown() and SameSet(displayed, editorLocked), string.format(
    "typed locked evidence changed across copy: displayed=%s editor=%s",
    SetText(displayed), SetText(editorLocked)))
Check(uploadCalls == 0 and associationCalls == 0 and gameplayCalls == 0,
    "Copy mutated upload, association, or gameplay state")
NexusEditorFrame:Hide()
Check(uploadCalls == 0 and associationCalls == 0 and gameplayCalls == 0,
    "Cancel mutated upload, association, or gameplay state")
Same(row, validBefore, "valid source row after copy/cancel")
Same(NexusDB, dbBeforeCopy, "SavedVariables after copy/cancel")
Same(character.lockDesignTargetsBySlot.unrelated, unrelatedBefore,
    "unrelated lock design after copy/cancel")

local function FindApply()
    for _, frame in ipairs(madeFrames) do
        if (frame:GetText() == "Create Wishlist" or frame:GetText() == "Saving...")
            and frame:GetScript("OnClick") then return frame end
    end
end

-- Selected-record drift after the editor preview disables Save and rejects
-- even a forced click before a confirmation can be created.
detail = RenderCurrent()
detail.copy:GetScript("OnClick")()
local apply = FindApply()
Check(apply and apply:IsEnabled(), "fresh candidate Save was not enabled")
H.lastStaticPopup = nil
row.relaySender = "stale-editor-preview"
Nexus.WishlistEditor.Refresh()
Check(not apply:IsEnabled(), "stale editor preview did not disable Save")
apply:GetScript("OnClick")()
Check(H.lastStaticPopup == nil and uploadCalls == 0,
    "stale editor preview reached confirmation or upload")
row.relaySender = nil

-- A selected association changing after confirmation opens is rejected again
-- at the immediate pre-upload boundary.
NexusEditorFrame:Hide()
detail = RenderCurrent()
detail.copy:GetScript("OnClick")()
apply = FindApply()
Check(apply and apply:IsEnabled(), "refreshed candidate Save was unavailable")
H.lastStaticPopup = nil
apply:GetScript("OnClick")()
Check(H.lastStaticPopup
    and H.lastStaticPopup.which == "WISHLISTREALIZER_CREATE_WISHLIST",
    "save did not require explicit confirmation")
row.ownerKey = "changed-owner@ebonhold"
H.AcceptLastStaticPopup()
Check(uploadCalls == 0,
    "confirmation accepted different selected evidence")
row.ownerKey = nil

-- The popup payload is also identity-bound: changing its destination after
-- preview cannot turn a create into an overwrite.
NexusEditorFrame:Hide()
detail = RenderCurrent()
detail.copy:GetScript("OnClick")()
apply = FindApply()
H.lastStaticPopup = nil
apply:GetScript("OnClick")()
Check(H.lastStaticPopup ~= nil, "payload-integrity confirmation was unavailable")
H.lastStaticPopup.data.slot = 1
H.AcceptLastStaticPopup()
Check(uploadCalls == 0, "mutated confirmation payload reached upload")

-- A spacing retry retains the established payload object for compatibility,
-- but a later mutation cannot change what the confirmed retry would upload.
NexusEditorFrame:Hide()
detail = RenderCurrent()
detail.copy:GetScript("OnClick")()
apply = FindApply()
H.lastStaticPopup = nil
apply:GetScript("OnClick")()
Check(H.lastStaticPopup ~= nil, "spacing-retry confirmation was unavailable")
uploadMode = "spacing"
H.AcceptLastStaticPopup()
Check(uploadCalls == 1 and Nexus.WishlistEditor.IsApplyPending(),
    "spacing did not retain the confirmed candidate payload")
H.lastStaticPopup.data.echoes[1].spellId = 299998
Nexus.WishlistEditor._PumpApplyRetry()
Check(uploadCalls == 1 and not Nexus.WishlistEditor.IsApplyPending(),
    "mutated spacing payload reached a retry upload")
uploadCalls, uploaded, uploadMode = 0, nil, "success"

-- Reopen the current revision and accept its explicit confirmation. The
-- committed target set must equal the displayed/editor set exactly.
NexusEditorFrame:Hide()
detail = RenderCurrent()
detail.copy:GetScript("OnClick")()
apply = FindApply()
Check(apply and apply:IsEnabled(), "final current candidate Save was unavailable")
H.lastStaticPopup = nil
apply:GetScript("OnClick")()
Check(H.lastStaticPopup
    and H.lastStaticPopup.which == "WISHLISTREALIZER_CREATE_WISHLIST",
    "final save did not require explicit confirmation")
H.AcceptLastStaticPopup()
Check(uploadCalls == 1 and associationCalls == 1 and uploaded
    and EchoTotal(uploaded.echoes) == 79,
    "confirmed save did not perform exactly one 79-copy upload/association")

local committed = {}
for key, targets in pairs(character.lockDesignTargetsBySlot or {}) do
    if key ~= "unrelated" then
        for id in pairs(type(targets) == "table" and targets or {}) do
            if tonumber(id) then committed[tonumber(id)] = true end
        end
    end
end
Check(SameSet(displayed, committed), string.format(
    "confirmed save changed locked identities: displayed=%s committed=%s",
    SetText(displayed), SetText(committed)))
Check(IdSet(uploaded.echoes)[lockedIds[1]] and committed[lockedIds[1]],
    "ordinary/locked overlap lost one of its two typed roles")
Same(row, validBefore, "source row after confirmed save")
Same(catalog, catalogBefore, "catalog")
Same(character.lockDesignTargetsBySlot.unrelated, unrelatedBefore,
    "unrelated lock design after save")
Check(NexusDB.futureRoot.keep == true, "unknown SavedVariables field changed")

print(string.format(
    "stage32 leaderboard locked fidelity: red editor=%s green=%s committed=%s ordinary=89-rejected/79-accepted checks=%d -- OK",
    "201382,201398,201410,210075,210076,210077",
    SetText(editorLocked), SetText(committed), checks))
