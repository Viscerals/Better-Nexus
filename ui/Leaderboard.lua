-- Nexus: ui/Leaderboard.lua
-- Clean, focused DPS leaderboard for Training Dummy, Lich King, and builds
-- that have verified records in both categories.

Nexus = Nexus or {}
local Identity = assert(Nexus.Identity,
    "Nexus Identity must load before Leaderboard")
local CandidateEvidence = assert(Nexus.CandidateEvidence,
    "CandidateEvidence must load before Leaderboard")
local M = {}
Nexus.Leaderboard = M

local frame, listChild, listScroll, detail, searchBox, classBtn, classMenu
local dummyBtn, lkBtn, combinedBtn, syncBtn, statusText, countText
local category = "lk"
local selectedKey = nil
local rowPool, activeRows = {}, {}
local Adapter
local currentRows = {}
local currentRowByKey = nil
local renderRowsWindow, applySelection, setScrollValue
local rowBinding = false
local scrollValue, scrollMax = 0, 0
local dataReady = false
local refreshDirty = true
local deferredDirty = false
local interactivePending = false
local lastDataError = nil
local viewDiagnostic = {
    publishedAt=nil,projectionCurrent=false,
    projectionPending=false,projectionError=false,
}
local virtualStats = {
    created=0, active=0, peakActive=0, results=0,
    dataRefreshes=0, statusRefreshes=0, detailRenders=0,
    dataBinds=0, scrollBinds=0, resizeBinds=0, selectionRefreshes=0,
    dataSkips=0, dataFailures=0, dirtyMarks=0, deferredRefreshes=0,
    themeTreeWalks=0, first=1, last=0, offset=0, maxOffset=0,
}

local ROW_H = 38
local LIST_W = 590
local CLASS_COLOR = {
    DEATHKNIGHT={0.77,0.12,0.23}, DRUID={1.00,0.49,0.04}, HUNTER={0.67,0.83,0.45},
    MAGE={0.25,0.78,0.92}, PALADIN={0.96,0.55,0.73}, PRIEST={1,1,1},
    ROGUE={1,0.96,0.41}, SHAMAN={0,0.44,0.87}, WARLOCK={0.53,0.53,0.93}, WARRIOR={0.78,0.61,0.43},
}
local CLASS_LABEL = {
    DEATHKNIGHT="Death Knight", DRUID="Druid", HUNTER="Hunter", MAGE="Mage", PALADIN="Paladin",
    PRIEST="Priest", ROGUE="Rogue", SHAMAN="Shaman", WARLOCK="Warlock", WARRIOR="Warrior",
}
local CLASS_ICON = {
    DEATHKNIGHT="Interface\\Icons\\Spell_DeathKnight_IceboundFortitude",
    DRUID="Interface\\Icons\\Spell_Nature_NaturesBlessing", HUNTER="Interface\\Icons\\Ability_Hunter_BeastCall",
    MAGE="Interface\\Icons\\Spell_Frost_Frostbolt02", PALADIN="Interface\\Icons\\Spell_Holy_HolyBolt",
    PRIEST="Interface\\Icons\\Spell_Holy_PowerInfusion", ROGUE="Interface\\Icons\\Ability_BackStab",
    SHAMAN="Interface\\Icons\\Spell_Nature_Lightning", WARLOCK="Interface\\Icons\\Spell_Shadow_ShadowBolt",
    WARRIOR="Interface\\Icons\\Ability_Warrior_Charge",
}
local NEUTRAL_CLASS_ICON = "Interface\\Icons\\INV_Misc_Note_01"
local CLASS_ORDER = {"ALL","DEATHKNIGHT","DRUID","HUNTER","MAGE","PALADIN","PRIEST","ROGUE","SHAMAN","WARLOCK","WARRIOR"}
local classFilter = "ALL"

-- Category, class, search, and explicit Show requests are user work. They
-- must remain responsive while background Sync coalesces revision-driven
-- refreshes. The flag also lets OnUpdate recreate a projection job if a Sync
-- revision invalidates it between bounded pumps.
local function RefreshInteractive()
    interactivePending = true
    return M.RefreshData()
end

local function DiagnosticClockNow()
    if type(GetTime) ~= "function" then return nil end
    local ok, value = pcall(GetTime)
    value = ok and tonumber(value) or nil
    if not value or value ~= value or value >= math.huge
        or value <= -math.huge then return nil end
    return value
end

local function DiagnosticPublicationAge(publishedAt)
    local now = DiagnosticClockNow()
    if not now or not publishedAt then return -1 end
    local age = math.max(0, math.min(2147483647, now - publishedAt))
    return math.floor(age * 10 + 0.5) / 10
end

local function SetBackdrop(f, alpha, border)
    pcall(function()
        f:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true,tileSize=16,edgeSize=10,insets={left=3,right=3,top=3,bottom=3}})
        f:SetBackdropColor(0.025,0.025,0.04,alpha or 0.94)
        local b = border or 0.22
        f:SetBackdropBorderColor(b,b,b+0.05,0.9)
    end)
end

local function SpellIcon(id)
    local ok, _, _, icon = pcall(GetSpellInfo, tonumber(id))
    return ok and icon or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function DpsText(v)
    v = tonumber(v) or 0
    if v >= 1000000 then return string.format("%.2fM", v / 1000000) end
    if v >= 1000 then return string.format("%.1fk", v / 1000) end
    return tostring(math.floor(v))
end

local function DurationText(v)
    v = tonumber(v) or 0
    if v <= 0 then return "—" end
    return string.format("%d:%02d", math.floor(v / 60), math.floor(v % 60))
end

local function TypedIdentity(value)
    return type(value) .. ":" .. tostring(value or "")
end

local function EvidenceIdentityKey(row)
    if type(row) ~= "table" then return "invalid" end
    local ownerKey = Identity.VerifiedOwnerKey(row)
    if ownerKey then return ownerKey end
    local player = type(row.player) == "string" and row.player:lower() or ""
    local realm = type(row.realm) == "string" and row.realm:lower() or ""
    local owner = type(row.ownerKey) == "string"
        and row.ownerKey:lower() or ""
    local claimed = type(row.claimedOwnerKey) == "string"
        and row.claimedOwnerKey:lower() or ""
    local relay = type(row.relaySender) == "string"
        and row.relaySender:lower() or ""
    if realm == "" and owner == "" and claimed == "" and relay == "" then
        return Identity.PlayerKey(row.player) or "invalid"
    end
    return "evidence:" .. TypedIdentity(player)
        .. ":" .. TypedIdentity(realm)
        .. ":" .. TypedIdentity(owner)
        .. ":" .. TypedIdentity(claimed)
        .. ":" .. TypedIdentity(relay)
end

local function RecordKey(row)
    if type(row) ~= "table" then return "" end
    local identity = row.fingerprint or row.buildId
    return EvidenceIdentityKey(row) .. "|" .. TypedIdentity(identity)
end

local function ExactRecordKey(row)
    if type(row) ~= "table" or type(row.fingerprint) ~= "string"
        or row.fingerprint == "" then return nil end
    local player = Identity.PlayerKey(row.player)
    if not player then return nil end
    return player .. "|string:" .. row.fingerprint
end

local function CombinedRecordKey(row)
    if type(row) ~= "table" or type(row.fingerprint) ~= "string"
        or row.fingerprint == "" then return nil end
    local ownerKey = Identity.VerifiedOwnerKey(row)
    if not ownerKey then return nil end
    return ownerKey .. "|string:" .. row.fingerprint
end

local function DeepCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        out[DeepCopy(key, seen)] = DeepCopy(child, seen)
    end
    return out
end

local function CommonTypedIdentity(left, right)
    return left ~= nil and right ~= nil and type(left) == type(right)
        and tostring(left) == tostring(right) and left or nil
end

local function EvidenceRecord(row)
    row=type(row)=="table" and row or {}
    return {
        player=row.player,fingerprint=row.fingerprint,
        buildId=row.buildId,resolvedBuildId=row.resolvedBuildId,
        ownerKey=row.ownerKey,ownerVerified=row.ownerVerified==true,
        claimedOwnerKey=row.claimedOwnerKey,relaySender=row.relaySender,
        buildIdentityMismatch=row.buildIdentityMismatch,
        recordIdentityMismatch=row.recordIdentityMismatch,
        resolvedIdentityMismatch=row.resolvedIdentityMismatch,
    }
end

local function Board(cat)
    local D = Nexus.DpsCapture
    if not (D and D.GetDpsBoard) then return {} end
    local ok, rows = pcall(D.GetDpsBoard, cat)
    return ok and type(rows) == "table" and rows or {}
end

local function CombinedRows()
    local dummy, lk = Board("dummy"), Board("lk")
    local dummyByKey = {}
    for _, row in ipairs(dummy) do
        local key = CombinedRecordKey(row)
        if key then dummyByKey[key] = row end
    end
    local out = {}
    for _, lrow in ipairs(lk) do
        local key = CombinedRecordKey(lrow)
        local drow = key and dummyByKey[key]
        if drow then
            local avg = ((tonumber(drow.dps) or 0) + (tonumber(lrow.dps) or 0)) / 2
            local ordinary = lrow.echoes or drow.echoes
            local locked = CandidateEvidence.ResolveLocked({
                ordinaryEchoes=ordinary,
                allowOrdinaryOverflow=true,
                buildId=CommonTypedIdentity(drow.resolvedBuildId,
                    lrow.resolvedBuildId)
                    or CommonTypedIdentity(drow.buildId,lrow.buildId),
                fingerprint=lrow.fingerprint or drow.fingerprint,
                dummyRecord=drow,lkRecord=lrow,
            })
            local ownerKey = Identity.VerifiedOwnerKey(lrow)
            out[#out+1] = {
                player=lrow.player, dps=avg, average=avg, dummyDps=drow.dps, lkDps=lrow.dps,
                dummyDuration=drow.duration, lkDuration=lrow.duration,
                level=math.max(tonumber(drow.level) or 0, tonumber(lrow.level) or 0),
                ts=math.min(tonumber(drow.ts) or 0, tonumber(lrow.ts) or 0),
                category="combined", fingerprint=lrow.fingerprint or drow.fingerprint,
                ownerKey=ownerKey,ownerVerified=true,
                dummyEvidence=EvidenceRecord(drow),
                lkEvidence=EvidenceRecord(lrow),
                echoes=ordinary,
                lockedEchoes=locked.status=="ok" and locked.lockedEchoes or nil,
                lockedEvidenceStatus=locked.status,
                lockedEvidenceReason=locked.reason,
                lockedEvidenceSource=locked.source,
                lockedFingerprint=locked.fingerprint,
                buildId=lrow.buildId or drow.buildId, build=lrow.build or drow.build,
                protocolVersion=lrow.protocolVersion or drow.protocolVersion,
                resolvedBuildId=lrow.resolvedBuildId==drow.resolvedBuildId
                    and lrow.resolvedBuildId or nil,
                resolvedFingerprintEpoch=
                    lrow.resolvedFingerprintEpoch==drow.resolvedFingerprintEpoch
                    and lrow.resolvedFingerprintEpoch or nil,
                resolvedFingerprintRevision=
                    lrow.resolvedFingerprintRevision==drow.resolvedFingerprintRevision
                    and lrow.resolvedFingerprintRevision or nil,
                resolvedIdentityMismatch=lrow.resolvedBuildId~=drow.resolvedBuildId
                    and (lrow.resolvedBuildId~=nil or drow.resolvedBuildId~=nil)
                    or lrow.resolvedFingerprintEpoch~=drow.resolvedFingerprintEpoch
                    or lrow.resolvedFingerprintRevision~=
                        drow.resolvedFingerprintRevision or nil,
                buildIdentityMismatch=lrow.buildIdentityMismatch
                    or drow.buildIdentityMismatch or nil,
                recordIdentityMismatch=lrow.recordIdentityMismatch
                    or drow.recordIdentityMismatch or nil,
                lockedEvidenceMismatch=locked.status=="conflict" or nil,
            }
        end
    end
    table.sort(out,function(a,b)
        if a.average ~= b.average then return a.average > b.average end
        return tostring(a.player):lower() < tostring(b.player):lower()
    end)
    return out
end

local function ProjectionFilters()
    return {
        search=searchBox and searchBox:GetText() or "",
        classFilter=classFilter,
    }
end

local function ProjectionCurrent()
    local projections = Nexus and Nexus.ViewProjections
    return projections and type(projections.LeaderboardCurrent) == "function"
        and projections.LeaderboardCurrent(category, ProjectionFilters())
        or false
end

local function Rows()
    local projections = Nexus and Nexus.ViewProjections
    if projections and type(projections.Leaderboard) == "function" then
        local reader = projections.RequestLeaderboard or projections.Leaderboard
        local rows, summary, err = reader(
            category, ProjectionFilters())
        if type(rows) == "table" then return rows, summary end
        return nil, nil, err or "Leaderboard projection failed"
    end
    local rows = category == "combined" and CombinedRows() or Board(category)
    local query = searchBox and tostring(searchBox:GetText() or ""):lower() or ""
    local out = {}
    for _, row in ipairs(rows) do
        local build = row.build or {}
        local class = type(row.resolvedClass) == "string"
            and row.resolvedClass:upper() or nil
        local classOk = classFilter == "ALL" or class == classFilter
        local searchOk = query == ""
            or tostring(row.player or ""):lower():find(query,1,true)
            or tostring(build.title or ""):lower():find(query,1,true)
            or tostring(build.author or ""):lower():find(query,1,true)
        if classOk and searchOk then out[#out+1] = row end
    end
    return out
end

local function ReleaseRows()
    for _, r in ipairs(activeRows) do r:Hide(); r:ClearAllPoints(); rowPool[#rowPool+1] = r end
    activeRows = {}
end

local function OrdinaryComplete(row)
    if type(row) ~= "table" then return false end
    if row.ordinaryComplete == false then return false end
    local evidence = Nexus and Nexus.LoadoutEvidence
    if not (evidence and type(evidence.OrdinaryCompleteness) == "function") then
        return false
    end
    local ok, verdict = pcall(evidence.OrdinaryCompleteness, row)
    return ok and type(verdict) == "table" and verdict.complete == true
end

local function SelectRow(row)
    selectedKey = RecordKey(row)
    if applySelection then applySelection(row) end
    if row and row.buildId and not OrdinaryComplete(row)
        and Nexus.Sync and Nexus.Sync.RequestLoadout then
        Nexus.Sync.RequestLoadout(row.buildId)
    end
end

local function GetRow(parent)
    local r = table.remove(rowPool)
    if r then r:SetParent(parent); r:Show(); return r end
    r = CreateFrame("Button",nil,parent); virtualStats.created=virtualStats.created+1; r:SetHeight(ROW_H); r:EnableMouse(true); SetBackdrop(r,0.80)
    r.rank=r:CreateFontString(nil,"OVERLAY","GameFontNormal"); r.rank:SetPoint("LEFT",8,0); r.rank:SetSize(30,14); r.rank:SetJustifyH("CENTER")
    r.icon=r:CreateTexture(nil,"ARTWORK"); r.icon:SetSize(26,26); r.icon:SetPoint("LEFT",44,0)
    r.player=r:CreateFontString(nil,"OVERLAY","GameFontHighlight"); r.player:SetPoint("LEFT",80,7); r.player:SetSize(190,14); r.player:SetJustifyH("LEFT")
    r.build=r:CreateFontString(nil,"OVERLAY","GameFontDisableSmall"); r.build:SetPoint("LEFT",80,-9); r.build:SetSize(275,13); r.build:SetJustifyH("LEFT")
    r.extra=r:CreateFontString(nil,"OVERLAY","GameFontDisableSmall"); r.extra:SetPoint("RIGHT",-12,-9); r.extra:SetSize(205,13); r.extra:SetJustifyH("RIGHT")
    r.dps=r:CreateFontString(nil,"OVERLAY","GameFontNormal"); r.dps:SetPoint("RIGHT",-12,7); r.dps:SetSize(150,14); r.dps:SetJustifyH("RIGHT")
    r.sel=r:CreateTexture(nil,"BACKGROUND"); r.sel:SetAllPoints(r); r.sel:SetTexture(0.15,0.55,0.9,0.16); r.sel:Hide()
    r:SetScript("OnEnter",function(self)
        pcall(function() self:SetBackdropColor(0.08,0.09,0.14,0.96) end)
        if self.classUnavailable and GameTooltip then
            pcall(function()
                GameTooltip:SetOwner(self,"ANCHOR_LEFT")
                GameTooltip:SetText("Class unavailable")
                GameTooltip:Show()
            end)
        end
    end)
    r:SetScript("OnLeave",function(self)
        pcall(function() self:SetBackdropColor(0.025,0.025,0.04,0.80) end)
        if self.classUnavailable and GameTooltip then
            pcall(function() GameTooltip:Hide() end)
        end
    end)
    r:SetScript("OnClick",function(self) SelectRow(self.data) end)
    if Nexus.Theme and Nexus.Theme.StyleVirtualRow then Nexus.Theme.StyleVirtualRow(r) end
    return r
end

local function ScalarPart(value)
    local text = tostring(value == nil and "" or value)
    return type(value) .. ":" .. tostring(#text) .. ":" .. text
end

local function ResolveRowLocked(row)
    if type(row) ~= "table" then
        return {status="unavailable",reason="record is unavailable",
            source="none",fingerprint="0",lockedEchoes={}}
    end
    if row.lockedEvidenceStatus then
        return {
            status=row.lockedEvidenceStatus,
            reason=tostring(row.lockedEvidenceReason or ""),
            source=tostring(row.lockedEvidenceSource or "none"),
            fingerprint=tostring(row.lockedFingerprint or "0"),
            lockedEchoes=DeepCopy(row.lockedEchoes or {}),
        }
    end
    local options = {
        ordinaryEchoes=row.echoes,
        ordinaryComplete=OrdinaryComplete(row),
        allowOrdinaryOverflow=true,
        buildId=row.resolvedBuildId or row.buildId,
        fingerprint=row.fingerprint,
        inlineLockedEchoes=row.lockedEchoes,
        inlineLockedFingerprint=row.lockedFingerprint,
    }
    if row.category == "dummy" then options.dummyRecord = row
    elseif row.category == "lk" then options.lkRecord = row end
    return CandidateEvidence.ResolveLocked(options)
end

local function RecordEvidenceParts(parts, label, row)
    row = type(row) == "table" and row or {}
    parts[#parts+1] = ScalarPart(label)
    parts[#parts+1] = ScalarPart(row.player)
    parts[#parts+1] = ScalarPart(row.fingerprint)
    parts[#parts+1] = ScalarPart(row.buildId)
    parts[#parts+1] = ScalarPart(row.resolvedBuildId)
    parts[#parts+1] = ScalarPart(row.ownerKey)
    parts[#parts+1] = ScalarPart(row.ownerVerified)
    parts[#parts+1] = ScalarPart(row.relaySender)
    parts[#parts+1] = ScalarPart(row.buildIdentityMismatch)
    parts[#parts+1] = ScalarPart(row.recordIdentityMismatch)
    parts[#parts+1] = ScalarPart(row.resolvedIdentityMismatch)
end

local function PreparedEvidenceRecord(seed, row)
    if type(row) ~= "table" then return nil end
    local copied = DeepCopy(row)
    copied.ownerVerified = row.ownerVerified == true
    if seed.resolvedBuildId ~= nil
        and CommonTypedIdentity(row.buildId, seed.buildId) ~= nil
        and tostring(row.fingerprint or "")
            == tostring(seed.fingerprint or "") then
        copied.resolvedBuildId = seed.resolvedBuildId
        copied.buildIdentityMismatch = seed.buildIdentityMismatch
        copied.resolvedIdentityMismatch = seed.resolvedIdentityMismatch
    end
    return copied
end

local function CurrentEvidenceRows(seed, selected)
    if selected then
        if seed.category == "combined" then
            return PreparedEvidenceRecord(seed,
                    seed.dummyEvidence or seed),
                PreparedEvidenceRecord(seed,seed.lkEvidence or seed)
        end
        local row = PreparedEvidenceRecord(seed, seed)
        return seed.category == "dummy" and row or nil,
            seed.category == "lk" and row or nil
    end
    local dps = Nexus and Nexus.DpsCapture
    if not (dps and type(dps.GetCharacterBest) == "function") then
        return CurrentEvidenceRows(seed, true)
    end
    local function Read(which)
        local expected = seed
        if seed.category == "combined" then
            if which == "dummy" then
                expected = seed.dummyEvidence or seed
            else
                expected = seed.lkEvidence or seed
            end
        end
        local expectedOwner = Identity.VerifiedOwnerKey(expected)
        if seed.category == "combined" and not expectedOwner then return nil end
        local expectedEvidence
        if not expectedOwner then
            if type(dps.EvidenceIdentityKey) ~= "function" then return nil end
            expectedEvidence = dps.EvidenceIdentityKey(expected)
            if not expectedEvidence then return nil end
        end
        local ok, value = pcall(
            dps.GetCharacterBest, which, seed.player, expectedOwner,
            expectedEvidence)
        return ok and PreparedEvidenceRecord(expected, value) or nil
    end
    if seed.category == "combined" then return Read("dummy"),Read("lk") end
    return seed.category == "dummy" and Read("dummy") or nil,
        seed.category == "lk" and Read("lk") or nil
end

local function CurrentEvidenceScalar(seed, selected)
    local dps = Nexus and Nexus.DpsCapture
    if not selected and not (dps
        and type(dps.GetCharacterBest) == "function") then
        return CurrentEvidenceScalar(seed, true)
    end
    local dummy, lk = CurrentEvidenceRows(seed, selected)
    local primary = seed.category == "dummy" and dummy
        or seed.category == "lk" and lk or (lk or dummy)
    if not primary then return nil,"record unavailable" end
    local fingerprint = primary.fingerprint
    if seed.category == "combined" and (not dummy or not lk
        or tostring(dummy.fingerprint or "") ~= tostring(lk.fingerprint or "")) then
        return nil,"record categories disagree"
    end
    local ordinary = primary.echoes
    local catalog = Nexus and Nexus.BuildCatalog
    local resolvedId = seed.resolvedBuildId
    local epoch, revision, recordEpoch, recordRevision
    local recoveredAssociation = resolvedId ~= nil
        and CommonTypedIdentity(seed.buildId, resolvedId) == nil
    if recoveredAssociation and catalog
        and type(catalog.ExactFingerprintRevision) == "function" then
        epoch,revision = catalog.ExactFingerprintRevision(fingerprint)
    end
    local targetId = resolvedId or CommonTypedIdentity(
        dummy and dummy.buildId,lk and lk.buildId) or primary.buildId
    if catalog and type(catalog.RecordRevision) == "function"
        and targetId ~= nil then
        recordEpoch,recordRevision = catalog.RecordRevision(targetId)
    end
    local locked
    if selected then
        locked = ResolveRowLocked(seed)
    else
        locked = CandidateEvidence.ResolveLocked({
            ordinaryEchoes=ordinary,buildId=targetId,
            fingerprint=fingerprint,dummyRecord=dummy,lkRecord=lk,
        })
    end
    if locked.status ~= "ok" and locked.status ~= "none" then
        return nil,locked.reason ~= "" and locked.reason
            or "locked Echo evidence is unavailable"
    end
    local parts = {
        ScalarPart(ExactRecordKey(primary)),ScalarPart(seed.category),
        ScalarPart(locked.status),ScalarPart(locked.fingerprint),
        ScalarPart(resolvedId),ScalarPart(epoch),ScalarPart(revision),
        ScalarPart(recordEpoch),ScalarPart(recordRevision),
    }
    RecordEvidenceParts(parts,"dummy",dummy)
    RecordEvidenceParts(parts,"lk",lk)
    if resolvedId ~= nil and catalog and type(catalog.GetSummary)=="function" then
        local summary = catalog.GetSummary(resolvedId)
        if type(summary)=="table" then
            parts[#parts+1]=ScalarPart(summary.id)
            parts[#parts+1]=ScalarPart(summary.fingerprint)
            parts[#parts+1]=ScalarPart(summary.ownerKey)
            parts[#parts+1]=ScalarPart(summary.ownerVerified)
            parts[#parts+1]=ScalarPart(summary.author)
            parts[#parts+1]=ScalarPart(summary.sourceSavedBuildId)
            parts[#parts+1]=ScalarPart(summary.publishedBuildId)
            parts[#parts+1]=ScalarPart(summary.recordBuildId)
        end
    end
    return table.concat(parts,"|")
end

local function CopyEvidence(row)
    if type(row)~="table" then return nil,"record is unavailable" end
    if not OrdinaryComplete(row) then
        return nil,"ordinary Echo evidence is still syncing"
    end
    local identity=ExactRecordKey(row)
    if not identity then return nil,"record fingerprint is unavailable" end
    if row.recordIdentityMismatch then
        return nil,"record fingerprint does not match its Echo evidence"
    end
    if row.resolvedIdentityMismatch then
        return nil,"record categories disagree on resolved build identity"
    end
    if row.buildIdentityMismatch and row.resolvedBuildId == nil then
        return nil,"record and catalog identities do not match"
    end
    local build=type(row.build)=="table" and row.build or nil
    if build and type(build.fingerprint)=="string" and build.fingerprint~=""
        and build.fingerprint~=row.fingerprint then
        return nil,"record and catalog identities do not match"
    end
    if build and build.id~=nil and row.buildId~=nil
        and (type(build.id)~=type(row.buildId)
            or tostring(build.id)~=tostring(row.buildId)) then
        return nil,"record and catalog build IDs do not match"
    end
    if type(row.echoes)~="table" or #row.echoes==0 then
        return nil,"ordinary Echo evidence is still syncing"
    end

    local locked=ResolveRowLocked(row)
    if locked.status ~= "ok" and locked.status ~= "none" then
        return nil,locked.reason ~= "" and locked.reason
            or "locked Echo evidence is unavailable"
    end
    local selected,selectedReason=CurrentEvidenceScalar(row, true)
    if not selected then
        return nil,selectedReason or "record evidence is unavailable"
    end
    local current,currentReason=CurrentEvidenceScalar(row, false)
    if not current then
        return nil,currentReason or "record evidence is unavailable"
    end
    if current ~= selected then return nil,"record evidence changed" end
    local title=build and build.title
        or (row.player and (tostring(row.player).."'s Loadout"))
        or "Leaderboard Build"
    return CandidateEvidence.Build({
        title=title,
        ordinaryEchoes=row.echoes,
        lockedEchoes=locked.lockedEchoes,
        sourceIdentity=identity,
        selectedEvidence=selected,
        currentEvidence=function() return CurrentEvidenceScalar(row, false) end,
    })
end

local function ResolveOpenBuildId(row)
    if type(row) ~= "table" or row.resolvedIdentityMismatch then
        return nil,"exact build identity is unavailable"
    end
    if not OrdinaryComplete(row) then
        return nil,"ordinary Echo evidence is still syncing"
    end
    if row.resolvedBuildId ~= nil then
        local catalog=Nexus and Nexus.BuildCatalog
        if not (catalog and type(catalog.ExactFingerprintRevision)=="function"
            and row.resolvedFingerprintEpoch~=nil
            and row.resolvedFingerprintRevision~=nil) then
            return nil,"exact build identity revision is unavailable"
        end
        local epoch,revision=catalog.ExactFingerprintRevision(row.fingerprint)
        if epoch~=row.resolvedFingerprintEpoch
            or revision~=row.resolvedFingerprintRevision then
            return nil,"exact build identity changed; refresh the record"
        end
        return row.resolvedBuildId
    end
    local protocolVersion = tonumber(row.protocolVersion)
    local recovered = protocolVersion and protocolVersion == math.floor(protocolVersion)
        and protocolVersion > 0 and protocolVersion < 7
    if not recovered and not row.buildIdentityMismatch and row.buildId ~= nil then
        return row.buildId
    end
    return nil,"exact build identity is unavailable"
end

local function EnsureDetail(parent)
    if detail then return end
    detail=CreateFrame("Frame",nil,parent); detail:SetWidth(335); detail:SetPoint("TOPRIGHT",-18,-102); detail:SetPoint("BOTTOMRIGHT",-18,18); SetBackdrop(detail,0.90)
    detail.title=detail:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); detail.title:SetPoint("TOPLEFT",14,-14); detail.title:SetSize(305,22); detail.title:SetJustifyH("LEFT")
    detail.owner=detail:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); detail.owner:SetPoint("TOPLEFT",14,-39); detail.owner:SetSize(305,16); detail.owner:SetJustifyH("LEFT")
    detail.record=detail:CreateFontString(nil,"OVERLAY","GameFontNormal"); detail.record:SetPoint("TOPLEFT",14,-62); detail.record:SetSize(305,42); detail.record:SetJustifyH("LEFT"); detail.record:SetJustifyV("TOP")
    detail.desc=detail:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); detail.desc:SetPoint("TOPLEFT",14,-109); detail.desc:SetSize(305,48); detail.desc:SetJustifyH("LEFT"); detail.desc:SetJustifyV("TOP")
    detail.lockedTitle=detail:CreateFontString(nil,"OVERLAY","GameFontDisableSmall"); detail.lockedTitle:SetPoint("TOPLEFT",14,-166); detail.lockedTitle:SetText("LOCKED ECHOES")
    detail.lockedIcons={}
    for i=1,6 do
        local b=CreateFrame("Button",nil,detail); b:SetSize(32,32); b:SetPoint("TOPLEFT",14+(i-1)*37,-180); b.icon=b:CreateTexture(nil,"OVERLAY"); b.icon:SetAllPoints(b)
        b:SetScript("OnEnter",function(self) if self.tip then GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:SetHyperlink("spell:"..tostring(self.tip)); GameTooltip:Show() end end)
        b:SetScript("OnLeave",function() GameTooltip:Hide() end); b:Hide(); detail.lockedIcons[i]=b
    end
    detail.echoTitle=detail:CreateFontString(nil,"OVERLAY","GameFontDisableSmall"); detail.echoTitle:SetPoint("TOPLEFT",14,-228); detail.echoTitle:SetText("EXACT LOADOUT")
    detail.icons={}
    for i=1,80 do
        local b=CreateFrame("Button",nil,detail); b:SetSize(22,22); local col=(i-1)%10; local row=math.floor((i-1)/10); b:SetPoint("TOPLEFT",14+col*29,-245-row*26)
        b.icon=b:CreateTexture(nil,"ARTWORK"); b.icon:SetAllPoints(b); b.count=b:CreateFontString(nil,"OVERLAY","NumberFontNormalSmall"); b.count:SetPoint("BOTTOMRIGHT",1,-1)
        b:SetScript("OnEnter",function(self) if self.tip then GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:SetHyperlink("spell:"..tostring(self.tip)); GameTooltip:Show() end end)
        b:SetScript("OnLeave",function() GameTooltip:Hide() end); b:Hide(); detail.icons[i]=b
    end
    detail.more=detail:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); detail.more:SetPoint("TOPLEFT",14,-458); detail.more:SetSize(305,18); detail.more:SetJustifyH("LEFT")
    detail.copy=CreateFrame("Button",nil,detail,"UIPanelButtonTemplate"); detail.copy:SetSize(138,24); detail.copy:SetPoint("BOTTOMLEFT",14,14); detail.copy:SetText("Copy into Editor")
    -- Keep ordinary and permanently locked evidence in separate immutable
    -- pools.  Neither ordering nor a shared spell ID may redefine its role.
    detail.copy:SetScript("OnClick",function()
        local candidate=detail.copyCandidate
        if not candidate then return end
        if not (Nexus.WishlistEditor and Nexus.WishlistEditor.OpenForCandidate) then return end
        local validated,reason=CandidateEvidence.Validate(candidate)
        if not validated then
            detail.copyCandidate=nil
            detail.copyReason=tostring(reason or "record validation failed")
            detail.copy:Disable()
            detail.more:SetText("Copy unavailable: "..detail.copyReason)
            return
        end
        local opened=Nexus.WishlistEditor.OpenForCandidate(validated)
        if opened~=false then M.Hide() end
    end)
    detail.open=CreateFrame("Button",nil,detail,"UIPanelButtonTemplate"); detail.open:SetSize(138,24); detail.open:SetPoint("LEFT",detail.copy,"RIGHT",8,0); detail.open:SetText("Open Build")
    detail.open:SetScript("OnClick",function()
        local id,reason=ResolveOpenBuildId(detail.row)
        if not id or not (Nexus.CommunityBuilds
            and Nexus.CommunityBuilds.ShowBuild) then
            detail.openReason=tostring(reason or "Community Builds is unavailable")
            detail.more:SetText("Open unavailable: "..detail.openReason)
            detail.open:Disable()
            return
        end
        local opened=Nexus.CommunityBuilds.ShowBuild(id)
        if opened~=false then M.Hide() end
    end)
    detail.empty=detail:CreateFontString(nil,"OVERLAY","GameFontHighlight"); detail.empty:SetPoint("CENTER",0,15); detail.empty:SetSize(280,70); detail.empty:SetJustifyH("CENTER")
    parent._leaderboardDetail=detail
end

local function RenderDetail(row)
    if not detail then return end
    virtualStats.detailRenders = virtualStats.detailRenders + 1
    detail.row=row
    detail.copyCandidate=nil
    detail.copyReason=nil
    detail.openBuildId=nil
    detail.openReason=nil
    if not row then
        for _,x in ipairs({detail.title,detail.owner,detail.record,detail.desc,detail.echoTitle,detail.more,detail.copy,detail.open,detail.lockedTitle}) do x:Hide() end
        for _,b in ipairs(detail.lockedIcons) do b:Hide() end; for _,b in ipairs(detail.icons) do b:Hide() end
        detail.empty:Show(); return
    end
    detail.empty:Hide()
    for _,x in ipairs({detail.title,detail.owner,detail.record,detail.desc,detail.echoTitle,detail.more,detail.copy,detail.open}) do x:Show() end
    local b=row.build or {}; local class=type(row.resolvedClass)=="string" and row.resolvedClass:upper() or nil; local c=CLASS_COLOR[class] or {0.8,0.8,0.8}
    detail.title:SetText(b.title or "Record Loadout"); detail.title:SetTextColor(c[1],c[2],c[3]); detail.owner:SetText("by "..tostring(b.author or row.player or "?")..(class and "" or " - Class unavailable"))
    if row.category=="combined" then
        detail.record:SetText("|cff4dff80Average "..DpsText(row.average).." DPS|r\nDummy "..DpsText(row.dummyDps).."  •  Lich King "..DpsText(row.lkDps))
    else
        local label=row.category=="lk" and "Lich King" or "Training Dummy"
        detail.record:SetText("|cff4dff80"..DpsText(row.dps).." DPS|r  •  "..label.."\n"..DurationText(row.duration).."  •  Level "..tostring(tonumber(row.level) or 0))
    end
    detail.desc:SetText((b.description and b.description~="") and b.description or "No build description provided.")
    local lockedResolution=ResolveRowLocked(row)
    local locked=lockedResolution.status=="ok"
        and lockedResolution.lockedEchoes or nil
    if locked and #locked>0 then detail.lockedTitle:Show() else detail.lockedTitle:Hide() end
    for i,btn in ipairs(detail.lockedIcons) do local e=locked and locked[i]; if e then btn.icon:SetTexture(SpellIcon(e.spellId)); btn.tip=e.spellId; btn:Show() else btn.tip=nil; btn:Hide() end end
    local echoes=row.echoes or b.echoes or {}; local shown=math.min(#echoes,#detail.icons); local total=0
    for _,e in ipairs(echoes) do total=total+(tonumber(e.stacks or e.count) or 1) end
    for i,btn in ipairs(detail.icons) do local e=echoes[i]; if i<=shown and e then local id=e.spellId or e.id; btn.icon:SetTexture(SpellIcon(id)); btn.tip=id; local n=tonumber(e.stacks or e.count) or 1; btn.count:SetText(n>1 and n or ""); btn:Show() else btn:Hide() end end
    local candidate,copyReason=CopyEvidence(row)
    detail.copyCandidate,detail.copyReason=candidate,copyReason
    local openBuildId,openReason=ResolveOpenBuildId(row)
    detail.openBuildId,detail.openReason=openBuildId,openReason
    detail.more:SetText(copyReason and openReason
            and ("Copy unavailable: "..tostring(copyReason)
                .."; Open unavailable: "..tostring(openReason))
        or copyReason and ("Copy unavailable: "..tostring(copyReason))
        or openReason and ("Open unavailable: "..tostring(openReason))
        or (#echoes==0 and "Exact loadout is still syncing."
            or (tostring(total).." Echo slots")))
    if candidate then detail.copy:Enable() else detail.copy:Disable() end
    if openBuildId then detail.open:Enable() else detail.open:Disable() end
end

local function FindSelectedRow()
    if not selectedKey then return nil end
    if currentRowByKey then return currentRowByKey[selectedKey] end
    for _, row in ipairs(currentRows) do
        if RecordKey(row) == selectedKey then return row end
    end
    return nil
end

local function BindRows(reason)
    if rowBinding then return end
    rowBinding = true
    local ok, err = pcall(function()
        ReleaseRows()
        local rowHeight = ROW_H + 2
        local visibleH = math.max(100,
            (listScroll and listScroll:GetHeight()) or 458)
        local virtual = Nexus.VirtualList.Window(
            #currentRows, rowHeight, visibleH, scrollValue, 2)
        for index = virtual.first, virtual.last do
            local row = currentRows[index]
            local r = GetRow(listChild)
            -- Own the checked-out row before binding so failure cleanup can
            -- reclaim partially populated widgets.
            activeRows[#activeRows+1] = r
            r:SetWidth(LIST_W)
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT",0,-(index-1)*rowHeight)
            r.data=row
            local class=type(row.resolvedClass)=="string"
                and row.resolvedClass:upper() or nil
            local c=CLASS_COLOR[class] or {0.8,0.8,0.8}
            r.rank:SetText(index<=3 and "|cffffd200"..index.."|r" or tostring(index))
            r.icon:SetTexture(CLASS_ICON[class] or NEUTRAL_CLASS_ICON)
            r.classUnavailable=class==nil
            r.classLabel=class and (CLASS_LABEL[class] or class)
                or "Class unavailable"
            r.player:SetText(tostring(row.player or "?"))
            r.player:SetTextColor(c[1],c[2],c[3])
            r.build:SetText(tostring((row.build or {}).title or "Record Loadout")
                ..(class and "" or " - Class unavailable"))
            if category=="combined" then
                r.dps:SetText("|cff4dff80"..DpsText(row.average).." avg|r")
                r.extra:SetText("Dummy "..DpsText(row.dummyDps).."  •  LK "..DpsText(row.lkDps))
            else
                r.dps:SetText("|cff4dff80"..DpsText(row.dps).." DPS|r")
                r.extra:SetText(DurationText(row.duration))
            end
            if RecordKey(row)==selectedKey then r.sel:Show() else r.sel:Hide() end
        end
        listChild:SetHeight(math.max(1,virtual.contentHeight))
        scrollMax, scrollValue = virtual.maxOffset, virtual.offset
        pcall(function() listScroll:SetVerticalScroll(scrollValue) end)
        virtualStats.results=#currentRows
        virtualStats.active=#activeRows
        virtualStats.peakActive=math.max(virtualStats.peakActive,#activeRows)
        virtualStats.first,virtualStats.last=virtual.first,virtual.last
        virtualStats.offset,virtualStats.maxOffset=virtual.offset,virtual.maxOffset
        virtualStats.selectedVisible=false
        for index=virtual.first,virtual.last do
            if RecordKey(currentRows[index])==selectedKey then
                virtualStats.selectedVisible=true
                break
            end
        end
        if reason=="scroll" then virtualStats.scrollBinds=virtualStats.scrollBinds+1
        elseif reason=="resize" then virtualStats.resizeBinds=virtualStats.resizeBinds+1
        else virtualStats.dataBinds=virtualStats.dataBinds+1 end
    end)
    rowBinding = false
    if not ok then
        pcall(ReleaseRows)
        virtualStats.active=0
        virtualStats.first,virtualStats.last=1,0
        virtualStats.selectedVisible=false
        error(err)
    end
end

applySelection = function(row)
    for _, r in ipairs(activeRows) do
        if RecordKey(r.data)==selectedKey then r.sel:Show() else r.sel:Hide() end
    end
    virtualStats.selectedVisible=false
    for _, r in ipairs(activeRows) do
        if RecordKey(r.data)==selectedKey then
            virtualStats.selectedVisible=true
            break
        end
    end
    virtualStats.selectionRefreshes=virtualStats.selectionRefreshes+1
    RenderDetail(row)
end

local function MakeNavButton(parent,text,w)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate"); b:SetSize(w,22); b:SetText(text); return b
end

local function MakeTab(parent,text,w)
    local b=CreateFrame("Button",nil,parent); b:SetSize(w,24); SetBackdrop(b,0.88)
    b.text=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); b.text:SetPoint("CENTER"); b.text:SetText(text)
    b.active=b:CreateTexture(nil,"BACKGROUND"); b.active:SetPoint("BOTTOMLEFT",4,3); b.active:SetPoint("BOTTOMRIGHT",-4,3); b.active:SetHeight(2); b.active:SetTexture(1,0.82,0,0.9); b.active:Hide()
    return b
end

local function EnsureFrame()
    if frame then return frame end
    frame=CreateFrame("Frame","NexusLeaderboardFrame",UIParent); frame:SetClampedToScreen(true); if type(UISpecialFrames)=="table" then table.insert(UISpecialFrames,"NexusLeaderboardFrame") end
    frame:SetSize(980,640); frame:SetPoint("CENTER"); frame:SetFrameStrata("DIALOG"); frame:SetFrameLevel(55); frame:EnableMouse(true); frame:SetMovable(true); frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart",function(self) self:StartMoving() end); frame:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end); frame:Hide()
    pcall(function() frame:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,edgeSize=32,insets={left=11,right=12,top=12,bottom=11}}) end)
    pcall(function() frame:SetBackdropColor(0.16,0.165,0.175,0.90) end)
    local title=frame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); title:SetPoint("TOP",0,-14); title:SetText("Nexus — Leaderboard")
    local close=CreateFrame("Button",nil,frame,"UIPanelCloseButton"); close:SetPoint("TOPRIGHT",-6,-6)
    local builds=MakeNavButton(frame,"Builds",88); builds:SetPoint("TOPLEFT",18,-12); builds:SetScript("OnClick",function() M.Hide(); if Nexus.CommunityBuilds then Nexus.CommunityBuilds.Show() end end)
    local board=MakeNavButton(frame,"Leaderboard",102); board:SetPoint("LEFT",builds,"RIGHT",4,0); board:SetText("|cffffd200Leaderboard|r"); board:Disable()
    local wish=MakeNavButton(frame,"Wishlists",92); wish:SetPoint("LEFT",board,"RIGHT",4,0); wish:SetScript("OnClick",function() M.Hide(); if Nexus.WishlistEditor then Nexus.WishlistEditor.Show() end end)

    searchBox=CreateFrame("EditBox","NexusLeaderboardSearch",frame,"InputBoxTemplate"); searchBox:SetSize(265,22); searchBox:SetPoint("TOPLEFT",18,-50); searchBox:SetAutoFocus(false); searchBox:SetScript("OnTextChanged",RefreshInteractive)
    local ph=frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall"); ph:SetPoint("LEFT",searchBox,"LEFT",6,0); ph:SetText("Search player or build...")
    searchBox:SetScript("OnEditFocusGained",function() ph:Hide() end); searchBox:SetScript("OnEditFocusLost",function(self) if self:GetText()=="" then ph:Show() end end)

    classBtn=CreateFrame("Button",nil,frame); classBtn:SetSize(150,22); classBtn:SetPoint("LEFT",searchBox,"RIGHT",10,0); SetBackdrop(classBtn,0.94)
    classBtn.text=classBtn:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); classBtn.text:SetPoint("LEFT",10,0); classBtn.text:SetSize(118,14); classBtn.text:SetJustifyH("LEFT")
    classBtn.arrow=classBtn:CreateTexture(nil,"ARTWORK"); classBtn.arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow"); classBtn.arrow:SetSize(12,12); classBtn.arrow:SetPoint("RIGHT",-8,0)
    classMenu=CreateFrame("Frame",nil,UIParent); classMenu:SetFrameStrata("TOOLTIP"); classMenu:SetSize(170,#CLASS_ORDER*22+8); classMenu:EnableMouse(true); classMenu:Hide(); SetBackdrop(classMenu,0.99,0.32)
    for i,k in ipairs(CLASS_ORDER) do
        local rb=CreateFrame("Button",nil,classMenu); rb:SetSize(160,22); rb:SetPoint("TOPLEFT",5,-4-(i-1)*22)
        rb.bg=rb:CreateTexture(nil,"BACKGROUND"); rb.bg:SetAllPoints(rb); rb.bg:SetTexture(0.12,0.12,0.17,0); local t=rb:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); t:SetPoint("LEFT",9,0)
        local c=CLASS_COLOR[k] or {1,0.82,0}; t:SetText(k=="ALL" and "All Classes" or CLASS_LABEL[k]); t:SetTextColor(c[1],c[2],c[3])
        rb:SetScript("OnEnter",function(self) self.bg:SetTexture(0.14,0.18,0.25,0.9) end); rb:SetScript("OnLeave",function(self) self.bg:SetTexture(0.12,0.12,0.17,0) end)
        rb:SetScript("OnClick",function() classFilter=k; classMenu:Hide(); selectedKey=nil; RefreshInteractive() end)
    end
    classBtn:SetScript("OnClick",function(self) if classMenu:IsShown() then classMenu:Hide() else classMenu:ClearAllPoints(); classMenu:SetPoint("TOPLEFT",self,"BOTTOMLEFT",0,-2); classMenu:Show() end end)

    syncBtn=MakeNavButton(frame,"Sync Now",90); syncBtn:SetPoint("TOPRIGHT",-18,-50); syncBtn:SetScript("OnClick",function() classMenu:Hide(); if Nexus.Sync then Nexus.Sync.RequestSync() end end)
    dummyBtn=MakeTab(frame,"Training Dummy",118); dummyBtn:SetPoint("TOPLEFT",18,-82); dummyBtn:SetScript("OnClick",function() category="dummy"; selectedKey=nil; classMenu:Hide(); RefreshInteractive() end)
    lkBtn=MakeTab(frame,"Lich King",100); lkBtn:SetPoint("LEFT",dummyBtn,"RIGHT",5,0); lkBtn:SetScript("OnClick",function() category="lk"; selectedKey=nil; classMenu:Hide(); RefreshInteractive() end)
    combinedBtn=MakeTab(frame,"Best Average",112); combinedBtn:SetPoint("LEFT",lkBtn,"RIGHT",5,0); combinedBtn:SetScript("OnClick",function() category="combined"; selectedKey=nil; classMenu:Hide(); RefreshInteractive() end)
    statusText=frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall"); statusText:SetPoint("LEFT",combinedBtn,"RIGHT",12,0); statusText:SetSize(250,14); statusText:SetJustifyH("LEFT")
    countText=frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall"); countText:SetPoint("TOPLEFT",18,-113); countText:SetSize(LIST_W,14); countText:SetJustifyH("LEFT")

    local head=CreateFrame("Frame",nil,frame); head:SetSize(LIST_W,22); head:SetPoint("TOPLEFT",18,-133); SetBackdrop(head,0.74)
    local labels={{"#",8,30,"CENTER"},{"CHARACTER / LOADOUT",80,300,"LEFT"},{"RESULT",430,145,"RIGHT"}}
    for _,x in ipairs(labels) do local t=head:CreateFontString(nil,"OVERLAY","GameFontDisableSmall"); t:SetPoint("LEFT",x[2],0); t:SetSize(x[3],14); t:SetJustifyH(x[4]); t:SetText(x[1]) end
    local clip=CreateFrame("Frame",nil,frame); clip:SetPoint("TOPLEFT",18,-158); clip:SetPoint("BOTTOMLEFT",18,18); clip:SetWidth(LIST_W); pcall(function() clip:SetClipsChildren(true) end)
    listScroll=CreateFrame("ScrollFrame",nil,clip); listScroll:SetAllPoints(clip); listScroll:EnableMouseWheel(true); listChild=CreateFrame("Frame",nil,listScroll); listChild:SetWidth(LIST_W); listChild:SetHeight(1); listScroll:SetScrollChild(listChild)
    setScrollValue=function(value,reason)
        value=tonumber(value)
        if value==math.huge then value=scrollMax end
        if not value or value~=value or value==-math.huge then value=0 end
        scrollValue=math.max(0,math.min(scrollMax,value))
        pcall(function() listScroll:SetVerticalScroll(scrollValue) end)
        if renderRowsWindow and frame and frame:IsShown() and not rowBinding then
            renderRowsWindow(reason or "scroll")
        end
    end
    listScroll:SetScript("OnMouseWheel",function(_,d) setScrollValue(scrollValue-d*(ROW_H+2)*4,"scroll") end)
    listScroll:SetScript("OnSizeChanged",function()
        if renderRowsWindow and frame and frame:IsShown() and not rowBinding then
            renderRowsWindow("resize")
        end
    end)
    frame._virtualListScrollFrame=listScroll
    listScroll:SetScript("OnMouseDown",function() classMenu:Hide() end)
    EnsureDetail(frame)
    frame:SetScript("OnMouseDown",function(self) if classMenu:IsShown() then classMenu:Hide() end end)
    frame:SetScript("OnUpdate",function(self,elapsed)
        if not self:IsShown() then return end
        local receiving = Nexus.Sync and Nexus.Sync.IsReceiving
            and Nexus.Sync.IsReceiving() or false
        local projections = Nexus and Nexus.ViewProjections
        local coldStart = not dataReady
        if interactivePending or viewDiagnostic.projectionPending then
            -- Requesting again is O(1) while the job is current and recreates
            -- it after a represented-data revision canceled the prior cursor.
            M.RefreshData()
        end
        if projections and (not receiving or coldStart or interactivePending)
            and type(projections.PumpLeaderboard) == "function" then
            -- Populate persisted rankings even when login Sync is already
            -- receiving. Once a last-good board exists, receive bursts remain
            -- coalesced and publish through the established quiet path.
            if receiving and coldStart then M.RefreshData() end
            local ok, published, pumpError = pcall(projections.PumpLeaderboard)
            if ok and published then M.RefreshData() end
            if ok and pumpError then M.RefreshData() end
        end
        self._tick=(self._tick or 0)+elapsed
        if self._tick>1 then self._tick=0; M.RefreshStatus() end
    end)
    return frame
end

function M.RefreshStatus()
    if not frame or not frame:IsShown() then return end
    local S=Nexus.Sync
    if S and S.GetLeaderboardSyncStatus then
        local state,waitSeconds,pending,work=S.GetLeaderboardSyncStatus(); work=type(work)=="table" and work or {}; local receiving=tonumber(work.receiving) or 0
        if state=="throttled" then statusText:SetText("|cffffcc55Sync resumes in "..tostring(waitSeconds).."s|r")
        elseif state=="syncing" then statusText:SetText("|cff4dff80Syncing"..(receiving>0 and (" • "..receiving.." receiving") or "...").."|r")
        elseif state=="cleaning" then statusText:SetText("|cffffcc55Cleaning expired Sync work...|r")
        elseif state=="sending" then statusText:SetText("|cff4dff80Sending queued Nexus work...|r")
        else statusText:SetText("|cff888888Best exact loadout per character|r") end
    else statusText:SetText("|cff888888Best exact loadout per character|r") end
    virtualStats.statusRefreshes=virtualStats.statusRefreshes+1
    return true
end

function M.RefreshData()
    if not frame or not frame:IsShown() then return end
    if dataReady and not refreshDirty and ProjectionCurrent() then
        interactivePending = false
        virtualStats.dataSkips = virtualStats.dataSkips + 1
        M.RefreshStatus()
        return true
    end
    local tabs={{dummyBtn,"dummy"},{lkBtn,"lk"},{combinedBtn,"combined"}}
    for _,v in ipairs(tabs) do if category==v[2] then v[1].active:Show() else v[1].active:Hide() end; v[1].text:SetTextColor(category==v[2] and 1 or 0.82, category==v[2] and 0.82 or 0.82, category==v[2] and 0 or 0.82) end
    classBtn.text:SetText(classFilter=="ALL" and "All Classes" or CLASS_LABEL[classFilter] or classFilter)
    local nextRows, nextSummary, rowsError = Rows()
    if type(nextRows) ~= "table" then
        refreshDirty = true
        if rowsError == "pending" then
            viewDiagnostic.projectionPending = true
            viewDiagnostic.projectionError = false
            viewDiagnostic.projectionCurrent = false
            if interactivePending and countText then
                local label=category=="lk" and "Lich King"
                    or (category=="dummy" and "Training Dummy" or "Best Average")
                countText:SetText("Loading "..label.." records...")
            end
            M.RefreshStatus()
            return false, "pending"
        end
        interactivePending = false
        viewDiagnostic.projectionPending = false
        viewDiagnostic.projectionError = true
        viewDiagnostic.projectionCurrent = false
        lastDataError = tostring(rowsError or "Leaderboard projection failed")
        virtualStats.dataFailures = virtualStats.dataFailures + 1
        M.RefreshStatus()
        return false, lastDataError
    end
    local previousRows, previousIndex, previousSelected =
        currentRows, currentRowByKey, selectedKey
    currentRows=nextRows
    currentRowByKey=type(nextSummary) == "table"
        and type(nextSummary.rowByKey) == "table"
        and nextSummary.rowByKey or nil
    local selected=FindSelectedRow()
    if not selected and selectedKey then selectedKey=nil end
    local label=category=="lk" and "Lich King" or (category=="dummy" and "Training Dummy" or "Best Average")
    countText:SetText(tostring(#currentRows).." ranked "..label..(category=="combined" and " • requires both records • ranked by average DPS" or " records"))
    renderRowsWindow=BindRows
    local bound, bindError = pcall(BindRows, "data")
    if not bound then
        currentRows, currentRowByKey, selectedKey =
            previousRows, previousIndex, previousSelected
        pcall(BindRows, "restore")
        RenderDetail(FindSelectedRow())
        refreshDirty = true
        viewDiagnostic.projectionPending = false
        viewDiagnostic.projectionError = true
        viewDiagnostic.projectionCurrent = false
        lastDataError = tostring(bindError or "Leaderboard row binding failed")
        virtualStats.dataFailures = virtualStats.dataFailures + 1
        M.RefreshStatus()
        return false, lastDataError
    end
    if #currentRows==0 then
        RenderDetail(nil)
        detail.empty:SetText(category=="combined" and "No builds have both Training Dummy and Lich King records yet.\n\nBest Average ranks verified dual-record loadouts by their average Training Dummy and Lich King DPS." or ("No "..label.." records are known yet.\n\nLeaderboard data syncs on login; Sync Now checks again."))
    else
        RenderDetail(selected)
    end
    virtualStats.dataRefreshes=virtualStats.dataRefreshes+1
    local projections = Nexus and Nexus.ViewProjections
    if projections and type(projections.RecordBind) == "function" then
        projections.RecordBind("leaderboard")
    end
    local peerDebug = Nexus and Nexus.PeerDebug
    if peerDebug and type(peerDebug.IsEnabled) == "function"
        and peerDebug.IsEnabled() and type(peerDebug.Record) == "function" then
        pcall(peerDebug.Record, "leaderboard_publication", {
            outcome="published",rows=#currentRows,category=category,
        })
    end
    dataReady = true
    interactivePending = false
    viewDiagnostic.publishedAt = DiagnosticClockNow()
    viewDiagnostic.projectionPending = false
    viewDiagnostic.projectionError = false
    viewDiagnostic.projectionCurrent = true
    refreshDirty = false
    lastDataError = nil
    if deferredDirty then
        virtualStats.deferredRefreshes = virtualStats.deferredRefreshes + 1
        deferredDirty = false
    end
    M.RefreshStatus()
    return true
end

function M.Refresh()
    return M.RefreshData()
end

function M.MarkDataDirty()
    if not refreshDirty then
        refreshDirty = true
        virtualStats.dirtyMarks = virtualStats.dirtyMarks + 1
    end
    viewDiagnostic.projectionPending = false
    viewDiagnostic.projectionError = false
    viewDiagnostic.projectionCurrent = false
    deferredDirty = true
    return true
end

function M.Init(adapter) Adapter=adapter end
function M.Show(mode) EnsureFrame(); if Nexus.Panel and Nexus.Panel.AttachMenuFrame then Nexus.Panel.AttachMenuFrame(frame) end; if Nexus.Theme and Nexus.Theme.StyleWindow then Nexus.Theme.StyleWindow(frame, 0.96) end; if Nexus.Theme and Nexus.Theme.StyleTree and not frame._nexusLeaderboardTreeStyled then Nexus.Theme.StyleTree(frame); frame._nexusLeaderboardTreeStyled=true; virtualStats.themeTreeWalks=virtualStats.themeTreeWalks+1 end; if Nexus.Panel and Nexus.Panel.CloseOtherWindows then Nexus.Panel.CloseOtherWindows("NexusLeaderboardFrame") end; if mode=="lk" or mode=="dummy" or mode=="combined" then category=mode end; frame:Show(); RefreshInteractive() end
function M.Hide() if frame then frame:Hide(); classMenu:Hide() end end
function M.Toggle(mode) EnsureFrame(); if frame:IsShown() then M.Hide() else M.Show(mode) end end
function M.SetCategory(mode) category=(mode=="dummy" or mode=="combined") and mode or "lk"; selectedKey=nil; RefreshInteractive() end
function M.SetClassFilter(value) classFilter=CLASS_LABEL[value] and value or "ALL"; selectedKey=nil; RefreshInteractive() end
function M.ScrollTo(offset) if not setScrollValue then return false end; setScrollValue(offset,"scroll"); return true end
function M.SelectKey(key)
    if currentRowByKey and currentRowByKey[key] then
        SelectRow(currentRowByKey[key])
        return true
    end
    for _,row in ipairs(currentRows) do
        if RecordKey(row)==key then SelectRow(row); return true end
    end
    return false
end
function M.VirtualStats()
    local out={}
    for key,value in pairs(virtualStats) do out[key]=value end
    out.selectedKey=selectedKey
    out.category=category
    out.classFilter=classFilter
    out.refreshDirty=refreshDirty
    out.interactivePending=interactivePending
    out.dataReady=dataReady
    out.lastDataError=lastDataError
    out.publishedRows=#currentRows
    out.displayedRows=#activeRows
    return out
end
function M.ResolveOpenBuildId(row)
    return ResolveOpenBuildId(row)
end
function M.DiagnosticSnapshot()
    local current = viewDiagnostic.projectionCurrent == true
    local receiving = false
    local sync = Nexus and Nexus.Sync
    if sync and type(sync.IsReceiving) == "function" then
        local ok, result = pcall(sync.IsReceiving)
        receiving = ok and result == true
    end
    local catalogCount = 0
    local catalog = Nexus and Nexus.BuildCatalog
    if catalog and type(catalog.Count) == "function" then
        local ok, result = pcall(catalog.Count)
        if ok then catalogCount = math.floor(tonumber(result) or 0) end
    end
    catalogCount = math.max(0, math.min(2147483647, catalogCount))
    local filterClass = classFilter == "ALL" and "ALL"
        or (CLASS_LABEL[classFilter] and classFilter or "UNAVAILABLE")
    local searchActive = false
    if searchBox and type(searchBox.GetText) == "function" then
        local ok, text = pcall(searchBox.GetText, searchBox)
        searchActive = ok and type(text) == "string" and text ~= "" or false
    end
    local shown = frame and frame:IsShown() or false
    local dirty = refreshDirty or not current
    local reason
    if not shown then reason = "hidden"
    elseif viewDiagnostic.projectionPending then reason = "projection-pending"
    elseif viewDiagnostic.projectionError then reason = "projection-error"
    elseif dirty and receiving and dataReady then reason = "sync-receiving"
    elseif dirty then reason = "dirty"
    elseif not dataReady then reason = "not-published"
    else reason = "none" end
    return {
        schema=1,view="leaderboard",catalogCount=catalogCount,
        requestedPage=1,publishedPage=dataReady and 1 or 0,
        pageCount=dataReady and 1 or 0,publishedRows=#currentRows,
        filterScope="all",filterClass=filterClass,
        filterCurrentClassOnly=false,filterQualifiedOnly=false,
        filterSearchActive=searchActive,filterSort="dps",
        filterCategory=(category == "dummy" or category == "combined")
            and category or "lk",
        projectionCurrent=current,
        projectionPending=viewDiagnostic.projectionPending == true,
        projectionDirty=dirty,savedImportPending=false,
        savedImportPhase="idle",syncReceiving=receiving,
        lastPublicationAge=DiagnosticPublicationAge(viewDiagnostic.publishedAt),
        blockedReason=reason,
    }
end
function M.IsShown() return frame and frame:IsShown() or false end
