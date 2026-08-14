-- Nexus: ui/Leaderboard.lua
-- Clean, focused DPS leaderboard for Training Dummy, Lich King, and builds
-- that have verified records in both categories.

Nexus = Nexus or {}
local M = {}
Nexus.Leaderboard = M

local frame, listChild, listScroll, detail, searchBox, classBtn, classMenu
local dummyBtn, lkBtn, combinedBtn, syncBtn, statusText, countText
local category = "lk"
local selectedKey = nil
local rowPool, activeRows = {}, {}
local Adapter
local currentRows = {}
local renderRowsWindow, applySelection, setScrollValue
local rowBinding = false
local scrollValue, scrollMax = 0, 0
local searchPending, searchElapsed = false, 0
local virtualStats = {
    created=0, active=0, peakActive=0, results=0,
    dataRefreshes=0, statusRefreshes=0, detailRenders=0,
    dataBinds=0, scrollBinds=0, resizeBinds=0, selectionRefreshes=0,
    themeTreeWalks=0, first=1, last=0, offset=0, maxOffset=0,
}

local ROW_H = 38
local LIST_W = 590
local SEARCH_DEBOUNCE = 0.18
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
local CLASS_ORDER = {"ALL","DEATHKNIGHT","DRUID","HUNTER","MAGE","PALADIN","PRIEST","ROGUE","SHAMAN","WARLOCK","WARRIOR"}
local classFilter = "ALL"

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

local function PlayerKey(v)
    return tostring(v or "?"):lower():gsub("%s+", "")
end

local function CharacterKey(row)
    row = type(row) == "table" and row or {}
    if type(row.ownerKey) == "string" then
        local name, realm = row.ownerKey:match("^([^@]+)@([^@]+)$")
        name = PlayerKey(name)
        realm = tostring(realm or ""):lower():gsub("%s+", "")
        if name ~= "?" and realm ~= "" and realm ~= "unknown" then
            return name .. "@" .. realm
        end
    end
    local realm = tostring(row.realm or ""):lower():gsub("%s+", "")
    if realm ~= "" and realm ~= "unknown" then
        local name = PlayerKey(row.player):match("^([^-]+)")
            or PlayerKey(row.player)
        return name .. "@" .. realm
    end
    return PlayerKey(row.player)
end

local function RecordKey(row)
    if not row then return "" end
    local identity = row.fingerprint or row.buildId
    return CharacterKey(row) .. "|" .. type(identity) .. ":"
        .. tostring(identity or "")
end

local function Board(cat)
    local D = Nexus.DpsCapture
    if not (D and D.GetDpsBoard) then return {} end
    local ok, rows = pcall(D.GetDpsBoard, cat)
    return ok and type(rows) == "table" and rows or {}
end

local function Rows()
    local projections = Nexus and Nexus.ViewProjections
    if projections and type(projections.Leaderboard) == "function" then
        local rows = projections.Leaderboard(category, {
            search=searchBox and searchBox:GetText() or "",
            classFilter=classFilter,
        })
        if type(rows) == "table" then return rows end
    end
    local rows = Board(category)
    local query = searchBox and tostring(searchBox:GetText() or ""):lower() or ""
    local out = {}
    for _, row in ipairs(rows) do
        local build = row.build or {}
        local class = tostring(build.class or row.class or "UNKNOWN"):upper()
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

local function SelectRow(row)
    selectedKey = RecordKey(row)
    if applySelection then applySelection(row) end
    if row and row.buildId and (not row.echoes or #row.echoes == 0) and Nexus.Sync and Nexus.Sync.RequestLoadout then
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
    r:SetScript("OnEnter",function(self) pcall(function() self:SetBackdropColor(0.08,0.09,0.14,0.96) end) end)
    r:SetScript("OnLeave",function(self) pcall(function() self:SetBackdropColor(0.025,0.025,0.04,0.80) end) end)
    r:SetScript("OnClick",function(self) SelectRow(self.data) end)
    if Nexus.Theme and Nexus.Theme.StyleVirtualRow then Nexus.Theme.StyleVirtualRow(r) end
    return r
end

local function NormalizeLockedEchoes(value)
    if type(value) ~= "table" then return nil end
    local out = {}
    for _, e in pairs(value) do
        local id, stacks
        if type(e)=="table" then id=tonumber(e.spellId or e.spellID or e.id or e.perkId or e.perkID); stacks=tonumber(e.stacks or e.stack or e.count or e.amount) or 1
        else id=tonumber(e); stacks=1 end
        if id and id>0 then out[#out+1]={spellId=id,stacks=math.max(1,stacks)} end
    end
    if #out==0 then return nil end
    table.sort(out,function(a,b) return a.spellId<b.spellId end)
    return out
end

local function ResolveLockedEchoes(row)
    if type(row)~="table" then return nil end
    local locked=NormalizeLockedEchoes(row.lockedEchoes) or NormalizeLockedEchoes(row.build and row.build.lockedEchoes)
    if locked then return locked end
    if row.buildId and Nexus and Nexus.BuildCatalog
        and Nexus.BuildCatalog.Get then
        local build=Nexus.BuildCatalog.Get(row.buildId)
        locked=NormalizeLockedEchoes(build and build.lockedEchoes)
    end
    return locked
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
    -- Previously wrote straight to the server via CommunityBuilds.LockInSelected()
    -- -- the same direct-write path the Community Builds panel's own detail
    -- view used before it was replaced with "Copy into Editor" (Dev Test 37).
    -- That fix never reached this screen, so copying from the Leaderboard
    -- still silently overwrote the active wishlist with no editor preview
    -- and no locked-Echo handling at all.
    --
    -- Dev Test 44 routed this through CommunityBuilds.EnsureDpsBuildForEchoes,
    -- expecting it to merge the row's locked Echoes in -- but that function
    -- ALWAYS finds an existing Store() entry first for anything already on
    -- the leaderboard (that's what's rendering right here) and returns it
    -- as-is, never reaching the merge code at all. Its stored .echoes never
    -- had locked Echoes folded in to begin with (only the DPS record/row
    -- carries those, separately, in .lockedEchoes -- see ResolveLockedEchoes
    -- and DpsCapture.lua's personalRow.lockedEchoes). Net effect: the 79
    -- copied correctly, but the locked Echoes silently never did.
    --
    -- Build the candidate directly instead of going through the build store
    -- at all -- merge row.echoes (the 79) with ResolveLockedEchoes(row) (the
    -- up to 6 locked, tagged .locked=true) the same way
    -- CommunityBuilds.EnsureDpsBuildForEchoes does for a FRESH build, then
    -- open it as a draft. Nothing is written -- to the server OR to Nexus's
    -- own locked-slot design tracking -- until the player actually saves.
    detail.copy:SetScript("OnClick",function()
        local row=detail.row
        if not row or type(row.echoes)~="table" or #row.echoes==0 then return end
        if not (Nexus.WishlistEditor and Nexus.WishlistEditor.OpenForCandidate) then return end
        local echoes, seen = {}, {}
        for _, e in ipairs(row.echoes) do
            local id = tonumber(e and (e.spellId or e.id))
            if id then
                echoes[#echoes+1] = { spellId=id, quality=e.quality, stacks=e.stacks or e.count or 1 }
                seen[id] = true
            end
        end
        for _, e in ipairs(ResolveLockedEchoes(row) or {}) do
            local id = tonumber(e and e.spellId)
            if id and not seen[id] then
                echoes[#echoes+1] = { spellId=id, stacks=e.stacks or e.count or 1, locked=true }
                seen[id] = true
            end
        end
        local b = row.build or {}
        M.Hide()
        Nexus.WishlistEditor.OpenForCandidate({
            title = b.title or (row.player and (tostring(row.player) .. "'s Loadout")) or "Leaderboard Build",
            echoes = echoes,
        })
    end)
    detail.open=CreateFrame("Button",nil,detail,"UIPanelButtonTemplate"); detail.open:SetSize(138,24); detail.open:SetPoint("LEFT",detail.copy,"RIGHT",8,0); detail.open:SetText("Open Build")
    detail.open:SetScript("OnClick",function() if detail.row and detail.row.buildId and Nexus.CommunityBuilds then M.Hide(); Nexus.CommunityBuilds.ShowBuild(detail.row.buildId) end end)
    detail.empty=detail:CreateFontString(nil,"OVERLAY","GameFontHighlight"); detail.empty:SetPoint("CENTER",0,15); detail.empty:SetSize(280,70); detail.empty:SetJustifyH("CENTER")
    parent._leaderboardDetail=detail
end

local function RenderDetail(row)
    if not detail then return end
    virtualStats.detailRenders = virtualStats.detailRenders + 1
    detail.row=row
    if not row then
        for _,x in ipairs({detail.title,detail.owner,detail.record,detail.desc,detail.echoTitle,detail.more,detail.copy,detail.open,detail.lockedTitle}) do x:Hide() end
        for _,b in ipairs(detail.lockedIcons) do b:Hide() end; for _,b in ipairs(detail.icons) do b:Hide() end
        detail.empty:Show(); return
    end
    detail.empty:Hide()
    for _,x in ipairs({detail.title,detail.owner,detail.record,detail.desc,detail.echoTitle,detail.more,detail.copy,detail.open}) do x:Show() end
    local b=row.build or {}; local c=CLASS_COLOR[tostring(b.class or ""):upper()] or {1,1,1}
    detail.title:SetText(b.title or "Record Loadout"); detail.title:SetTextColor(c[1],c[2],c[3]); detail.owner:SetText("by "..tostring(b.author or row.player or "?"))
    if row.category=="combined" then
        detail.record:SetText("|cff4dff80Average "..DpsText(row.average).." DPS|r\nDummy "..DpsText(row.dummyDps).."  •  Lich King "..DpsText(row.lkDps))
    else
        local label=row.category=="lk" and "Lich King" or "Training Dummy"
        detail.record:SetText("|cff4dff80"..DpsText(row.dps).." DPS|r  •  "..label.."\n"..DurationText(row.duration).."  •  Level "..tostring(tonumber(row.level) or 0))
    end
    detail.desc:SetText((b.description and b.description~="") and b.description or "No build description provided.")
    local locked=ResolveLockedEchoes(row)
    if locked and #locked>0 then detail.lockedTitle:Show() else detail.lockedTitle:Hide() end
    for i,btn in ipairs(detail.lockedIcons) do local e=locked and locked[i]; if e then btn.icon:SetTexture(SpellIcon(e.spellId)); btn.tip=e.spellId; btn:Show() else btn:Hide() end end
    local echoes=row.echoes or b.echoes or {}; local shown=math.min(#echoes,#detail.icons); local total=0
    for _,e in ipairs(echoes) do total=total+(tonumber(e.stacks or e.count) or 1) end
    for i,btn in ipairs(detail.icons) do local e=echoes[i]; if i<=shown and e then local id=e.spellId or e.id; btn.icon:SetTexture(SpellIcon(id)); btn.tip=id; local n=tonumber(e.stacks or e.count) or 1; btn.count:SetText(n>1 and n or ""); btn:Show() else btn:Hide() end end
    detail.more:SetText(#echoes==0 and "Exact loadout is still syncing." or (tostring(total).." Echo slots"))
    if #echoes>0 then detail.copy:Enable() else detail.copy:Disable() end
end

local function FindSelectedRow()
    if not selectedKey then return nil end
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
            local class=tostring((row.build or {}).class or row.class or "UNKNOWN"):upper()
            local c=CLASS_COLOR[class] or {0.8,0.8,0.8}
            r.rank:SetText(index<=3 and "|cffffd200"..index.."|r" or tostring(index))
            r.icon:SetTexture(CLASS_ICON[class] or "Interface\\Icons\\INV_Misc_QuestionMark")
            r.player:SetText(tostring(row.player or "?"))
            r.player:SetTextColor(c[1],c[2],c[3])
            r.build:SetText(tostring((row.build or {}).title or "Record Loadout"))
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

    searchBox=CreateFrame("EditBox","NexusLeaderboardSearch",frame,"InputBoxTemplate"); searchBox:SetSize(265,22); searchBox:SetPoint("TOPLEFT",18,-50); searchBox:SetAutoFocus(false); searchBox:SetScript("OnTextChanged",function() searchPending=true; searchElapsed=0 end)
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
        rb:SetScript("OnClick",function() classFilter=k; classMenu:Hide(); selectedKey=nil; M.RefreshData() end)
    end
    classBtn:SetScript("OnClick",function(self) if classMenu:IsShown() then classMenu:Hide() else classMenu:ClearAllPoints(); classMenu:SetPoint("TOPLEFT",self,"BOTTOMLEFT",0,-2); classMenu:Show() end end)

    syncBtn=MakeNavButton(frame,"Sync Now",90); syncBtn:SetPoint("TOPRIGHT",-18,-50); frame._syncBtn=syncBtn; syncBtn:SetScript("OnClick",function()
        classMenu:Hide()
        local S=Nexus.Sync
        if not (S and S.RequestSync) then return end
        local ok,err=S.RequestSync()
        if ok then print("|cff7fd5ffNexus:|r asking other players for builds and DPS records...")
        else print("|cffff6060Nexus:|r "..tostring(err)) end
        M.RefreshStatus()
    end)
    dummyBtn=MakeTab(frame,"Training Dummy",118); dummyBtn:SetPoint("TOPLEFT",18,-82); dummyBtn:SetScript("OnClick",function() category="dummy"; selectedKey=nil; classMenu:Hide(); M.RefreshData() end)
    lkBtn=MakeTab(frame,"Lich King",100); lkBtn:SetPoint("LEFT",dummyBtn,"RIGHT",5,0); lkBtn:SetScript("OnClick",function() category="lk"; selectedKey=nil; classMenu:Hide(); M.RefreshData() end)
    combinedBtn=MakeTab(frame,"Average",112); combinedBtn:SetPoint("LEFT",lkBtn,"RIGHT",5,0); combinedBtn:SetScript("OnClick",function() category="combined"; selectedKey=nil; classMenu:Hide(); M.RefreshData() end); frame._averageTab=combinedBtn
    statusText=frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall"); statusText:SetPoint("LEFT",combinedBtn,"RIGHT",12,0); statusText:SetSize(250,14); statusText:SetJustifyH("LEFT"); frame._syncStatusText=statusText
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
        if searchPending then
            searchElapsed=searchElapsed+elapsed
            if searchElapsed>=SEARCH_DEBOUNCE then
                searchPending,searchElapsed=false,0
                M.RefreshData()
            end
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
        elseif state=="off" then statusText:SetText("|cffff6060Sync Off — change mode in Builds|r")
        elseif state=="suspended" then
            local effective=S.GetEffectiveState and S.GetEffectiveState() or nil
            statusText:SetText("|cffffcc55Sync waiting"..(effective and effective.reason and (" — "..tostring(effective.reason)) or "").."|r")
        elseif state=="manual-idle" then statusText:SetText("|cff888888Manual — press Sync Now while resting|r")
        else statusText:SetText("|cff888888Best exact loadout per character|r") end
        if syncBtn then
            syncBtn:SetText(state=="off" and "Sync Off"
                or state=="suspended" and "Waiting..."
                or state=="syncing" and "Syncing..."
                or "Sync Now")
        end
    else statusText:SetText("|cff888888Best exact loadout per character|r") end
    virtualStats.statusRefreshes=virtualStats.statusRefreshes+1
    return true
end

function M.RefreshData()
    if not frame or not frame:IsShown() then return end
    searchPending,searchElapsed=false,0
    local tabs={{dummyBtn,"dummy"},{lkBtn,"lk"},{combinedBtn,"combined"}}
    for _,v in ipairs(tabs) do if category==v[2] then v[1].active:Show() else v[1].active:Hide() end; v[1].text:SetTextColor(category==v[2] and 1 or 0.82, category==v[2] and 0.82 or 0.82, category==v[2] and 0 or 0.82) end
    classBtn.text:SetText(classFilter=="ALL" and "All Classes" or CLASS_LABEL[classFilter] or classFilter)
    currentRows=Rows()
    local selected=FindSelectedRow()
    if not selected and selectedKey then selectedKey=nil end
    local label=category=="lk" and "Lich King" or (category=="dummy" and "Training Dummy" or "Best Average")
    countText:SetText(tostring(#currentRows).." ranked "..label..(category=="combined" and " • requires both records • ranked by average DPS" or " records"))
    renderRowsWindow=BindRows
    BindRows("data")
    if #currentRows==0 then
        RenderDetail(nil)
        detail.empty:SetText(category=="combined" and "No builds have both Training Dummy and Lich King records yet.\n\nBest Average ranks verified dual-record loadouts by their average Training Dummy and Lich King DPS." or ("No "..label.." records are known yet.\n\nLeaderboard data syncs on login; Sync Now checks again."))
    else
        RenderDetail(selected)
    end
    virtualStats.dataRefreshes=virtualStats.dataRefreshes+1
    M.RefreshStatus()
    return true
end

function M.Refresh()
    return M.RefreshData()
end

function M.Init(adapter) Adapter=adapter end
function M.Show(mode) EnsureFrame(); if Nexus.Panel and Nexus.Panel.AttachMenuFrame then Nexus.Panel.AttachMenuFrame(frame) end; if Nexus.Theme and Nexus.Theme.StyleWindow then Nexus.Theme.StyleWindow(frame, 0.96) end; if Nexus.Theme and Nexus.Theme.StyleTree and not frame._nexusLeaderboardTreeStyled then Nexus.Theme.StyleTree(frame); frame._nexusLeaderboardTreeStyled=true; virtualStats.themeTreeWalks=virtualStats.themeTreeWalks+1 end; if Nexus.Panel and Nexus.Panel.CloseOtherWindows then Nexus.Panel.CloseOtherWindows("NexusLeaderboardFrame") end; if mode=="lk" or mode=="dummy" or mode=="combined" then category=mode end; frame:Show(); M.RefreshData() end
function M.Hide() if frame then frame:Hide(); classMenu:Hide() end end
function M.Toggle(mode) EnsureFrame(); if frame:IsShown() then M.Hide() else M.Show(mode) end end
function M.SetCategory(mode) category=(mode=="dummy" or mode=="combined") and mode or "lk"; selectedKey=nil; M.RefreshData() end
function M.SetClassFilter(value) classFilter=CLASS_LABEL[value] and value or "ALL"; selectedKey=nil; M.RefreshData() end
function M.ScrollTo(offset) if not setScrollValue then return false end; setScrollValue(offset,"scroll"); return true end
function M.SelectKey(key)
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
    return out
end
function M.IsShown() return frame and frame:IsShown() or false end
