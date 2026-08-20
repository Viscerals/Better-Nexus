-- Nexus: ui/CommunityRenderer.lua
-- Community main/detail frame, virtual-row pool, and binding owner.

Nexus = Nexus or {}
Nexus.CommunityInternals = Nexus.CommunityInternals or {}

local Renderer = {}

local function IsSavedMirror(build)
    local identity = Nexus and Nexus.Identity
    return identity and type(identity.SavedMirrorKind) == "function"
        and identity.SavedMirrorKind(build) == "saved" or false
end

local function InstallPopupDragHandle(parent)
    parent:SetMovable(true)
    local handle = CreateFrame("Frame", nil, parent)
    handle:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -6)
    handle:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -38, -6)
    handle:SetHeight(28)
    handle:EnableMouse(true)
    handle:RegisterForDrag("LeftButton")
    handle:SetScript("OnDragStart", function() parent:StartMoving() end)
    handle:SetScript("OnDragStop", function() parent:StopMovingOrSizing() end)
    return handle
end

local function ConfigureDescriptionEdit(box, scroll, width, minimumHeight)
    box:SetMultiLine(true)
    box:SetWidth(width)
    box:SetHeight(minimumHeight)
    box:SetAutoFocus(false)
    box:SetFontObject(Nexus.LayoutMetrics
        and Nexus.LayoutMetrics.FontObject("normal")
        or "GameFontHighlightSmall")
    box:SetMaxLetters(2000)
    box:EnableMouse(true)
    box:EnableKeyboard(true)
    box._nexusDescriptionScroll = scroll
    box._nexusDescriptionMinHeight = minimumHeight
    box._nexusDescriptionWrap = math.max(1, math.floor(width / 7))
    box:SetScript("OnMouseDown", function(self, button)
        if button == nil or button == "LeftButton" then self:SetFocus() end
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnTextChanged", function(self)
        local measured
        if type(self.GetStringHeight) == "function" then
            local ok, height = pcall(self.GetStringHeight, self)
            if ok and tonumber(height) and tonumber(height) > 0 then
                measured = tonumber(height) + 8
            end
        end
        if not measured then
            local lines, wrap = 0, self._nexusDescriptionWrap
            for line in (tostring(self:GetText() or "") .. "\n"):gmatch("(.-)\n") do
                lines = lines + math.max(1, math.ceil(#line / wrap))
            end
            measured = lines * 14 + 8
        end
        self:SetHeight(math.max(self._nexusDescriptionMinHeight, measured))
    end)
    box:SetScript("OnCursorChanged", function(self, _, y, _, height)
        local owner = self._nexusDescriptionScroll
        if not owner then return end
        local offset = tonumber(owner:GetVerticalScroll()) or 0
        local viewport = tonumber(owner:GetHeight()) or 0
        local cursorTop = math.max(0, -(tonumber(y) or 0))
        local cursorBottom = cursorTop + (tonumber(height) or 0)
        if cursorTop < offset then
            owner:SetVerticalScroll(cursorTop)
        elseif viewport > 0 and cursorBottom > offset + viewport then
            owner:SetVerticalScroll(cursorBottom - viewport)
        end
    end)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local current = tonumber(self:GetVerticalScroll()) or 0
        self:SetVerticalScroll(math.max(0,
            current - (tonumber(delta) or 0) * 24))
    end)
    scroll:SetScrollChild(box)
end

local function Measure(name, callback, ...)
    local performance = Nexus and Nexus.Performance
    if performance and type(performance.Measure) == "function" then
        return performance.Measure(name, callback, ...)
    end
    return callback(...)
end

local function ClockNow()
    if type(GetTime) ~= "function" then return nil end
    local ok, value = pcall(GetTime)
    value = ok and tonumber(value) or nil
    if not value or value ~= value or value >= math.huge
        or value <= -math.huge then return nil end
    return value
end

local function PublicationAge(publishedAt)
    local now = ClockNow()
    if not now or not publishedAt then return -1 end
    local age = math.max(0, math.min(2147483647, now - publishedAt))
    return math.floor(age * 10 + 0.5) / 10
end

function Renderer.New(options)
    options = type(options) == "table" and options or {}
    local M = {}

    local Controller = assert(options.controller,
        "CommunityRenderer requires controller intentions")
    local projectionFactory = assert(options.projection,
        "CommunityRenderer requires Community projection")
    local CandidateEvidence = assert(Nexus.CandidateEvidence,
        "CandidateEvidence must load before CommunityRenderer")

    local function ControllerInstance()
        return Controller
    end

    local function LoadBuild(id)
        return ControllerInstance().Build(id)
    end

    local function Store()
        return ControllerInstance().Builds()
    end

    local function FilterSettings()
        return ControllerInstance().Filters()
    end

    local function ProjectionContext()
        return ControllerInstance().ProjectionContext()
    end

    local function IsOwnBuild(build)
        return ControllerInstance().IsOwnBuild(build)
    end

    local function IsAdmin()
        return ControllerInstance().IsAdmin()
    end

    local function SpellIcon(spellId)
        if not spellId then
            return "Interface\\Icons\\INV_Misc_QuestionMark"
        end
        local ok, _, _, icon = pcall(GetSpellInfo, spellId)
        return (ok and icon and icon ~= "") and icon
            or "Interface\\Icons\\INV_Misc_QuestionMark"
    end

    local function DpsText(value)
        value = tonumber(value) or 0
        if value >= 1000000 then
            return string.format("%.2fM", value / 1000000)
        end
        if value >= 1000 then
            return string.format("%dk", math.floor(value / 1000))
        end
        return tostring(math.floor(value))
    end

    local function RecordBuildId(build)
        return ControllerInstance().RecordBuildId(build)
    end

    local function PublishedBuildId(build)
        local controller = ControllerInstance()
        if type(controller.PublishedBuildId) ~= "function" then return nil end
        local ok, publishedId = pcall(controller.PublishedBuildId, build)
        return ok and publishedId or nil
    end

    local function IsBuildFullyLoaded(build)
        return build and type(build.echoes) == "table"
            and #build.echoes > 0
    end

    local function DeleteBuild(id)
        return ControllerInstance().DeleteBuild(id)
    end

    local function EditBuild(id, title, description, link)
        return ControllerInstance().EditBuild(
            id, title, description, link)
    end

    local function PublishImportedBuild(id)
        return ControllerInstance().PublishImportedBuild(id)
    end

    local function PumpPendingLockIn()
        return ControllerInstance()._PumpPendingLockIn()
    end

    local function PrepareData(force)
        local controller = ControllerInstance()
        if force and type(controller.BeginSavedLoadoutImport) == "function" then
            controller.BeginSavedLoadoutImport(true)
        end
        if type(controller.HasPendingSavedLoadoutImport) == "function"
            and controller.HasPendingSavedLoadoutImport() then
            return controller.PumpSavedLoadoutImport(25)
        end
        return controller.ImportCurrentSavedLoadouts(false)
    end

    local function SelectedId()
        return ControllerInstance().SelectedId()
    end

    local function EnsureCommunityProjection()
        return projectionFactory()
    end

    local function SortedBuilds()
        local projection = EnsureCommunityProjection()
        if not (projection and type(projection.List) == "function") then
            error("Community projection unavailable")
        end
        local rows, summary, err = projection.List(FilterSettings())
        if type(rows) == "table" then return rows, summary end
        return nil, nil, err or "Community projection failed"
    end

    StaticPopupDialogs["NEXUS_LOCKIN_BUILD"] = {
        text = "Lock in '%s'?\nThis overwrites your current active wishlist.",
        button1 = "Lock In", button2 = "Cancel",
        OnAccept = function(_, data)
            ControllerInstance().AcceptLockIn(data)
        end,
        timeout=0, whileDead=true, hideOnEscape=true,
    }

    local function FinishStopSharing(id)
        local build = LoadBuild(id)
        if not build or not IsOwnBuild(build) then
            print("|cffff6060Nexus:|r Stop Sharing refused: this is not your shared build.")
            M.Refresh()
            return
        end
        local ok, result = DeleteBuild(id)
        if not ok then
            print("|cffff6060Nexus:|r " .. tostring(result))
        else
            local outcome = type(result) == "table" and result or {}
            if outcome.queueAdmitted then
                print("|cff4dff80Nexus:|r Build stopped sharing locally; withdrawal queued.")
            elseif outcome.retryPending then
                print("|cffffc040Nexus:|r Build stopped sharing locally; the Sync queue is full. Withdrawal retry is pending.")
            else
                print("|cffffc040Nexus:|r Build stopped sharing locally; withdrawal not queued: "
                    .. tostring(outcome.queueReason or "Sync unavailable") .. ".")
            end
        end
        M.Refresh()
    end

    local function CandidateIdentity(build)
        if type(build) ~= "table" or build.id == nil
            or type(build.fingerprint) ~= "string"
            or build.fingerprint == "" then return nil end
        return type(build.id) .. ":" .. tostring(build.id)
            .. "|" .. build.fingerprint
    end

    local function CandidatePart(value)
        local text = tostring(value == nil and "" or value)
        return type(value) .. ":" .. tostring(#text) .. ":" .. text
    end

    local function CandidateSource(build)
        local identity = CandidateIdentity(build)
        if not identity then return nil, "record identity is unavailable" end
        local authoritative, lockedReason, resolution =
            ControllerInstance().LockedEchoesForBuild(build)
        if lockedReason and lockedReason ~= "" then return nil,lockedReason end
        if type(resolution) ~= "table" then
            resolution = {
                status=type(authoritative)=="table" and "ok" or "none",
                reason="",source=type(authoritative)=="table" and "record" or "none",
                fingerprint=type(authoritative)=="table" and "legacy" or "0",
            }
        end
        if resolution.status ~= "ok" and resolution.status ~= "none" then
            return nil,resolution.reason ~= "" and resolution.reason
                or "locked Echo evidence is unavailable"
        end
        local ordinary, locked = {}, {}
        for _, echo in ipairs(type(build.echoes) == "table"
            and build.echoes or {}) do
            if echo and not echo.locked then ordinary[#ordinary + 1] = echo end
        end
        for _, echo in ipairs(type(authoritative) == "table"
            and authoritative or {}) do
            locked[#locked + 1] = echo
        end
        local parts = {
            CandidatePart(identity),CandidatePart(resolution.fingerprint),
            CandidatePart(resolution.status),CandidatePart(build.ownerKey),
            CandidatePart(build.ownerVerified),CandidatePart(build.isMine),
            CandidatePart(build.relaySender),CandidatePart(build.sourceSavedBuildId),
            CandidatePart(build.publishedBuildId),CandidatePart(build.recordBuildId),
            CandidatePart(build.autoDps),CandidatePart(build.importedSavedBuild),
        }
        return {
            identity=identity,ordinary=ordinary,locked=locked,
            selected=table.concat(parts,"|"),title=build.title,
        }
    end

    local function BuildCandidateEvidence(build)
        local source, sourceReason = CandidateSource(build)
        if not source then return nil,sourceReason end
        local sourceId = build.id
        return CandidateEvidence.Build({
            title=source.title,
            ordinaryEchoes=source.ordinary,
            lockedEchoes=source.locked,
            sourceIdentity=source.identity,
            selectedEvidence=source.selected,
            currentEvidence=function()
                local current = LoadBuild(sourceId)
                local now = current and CandidateSource(current) or nil
                return now and now.selected or nil
            end,
        })
    end

    StaticPopupDialogs["NEXUS_STOP_SHARING_BUILD"] = {
        text = "Stop sharing '%s'?\nThis removes only the shared Nexus record. Server Saved Builds and Wishlists are unchanged.",
        button1 = "Stop Sharing", button2 = "Cancel",
        OnAccept = function(_, data)
            if type(data) == "table" and data.id then
                FinishStopSharing(data.id)
            end
        end,
        timeout=0, whileDead=true, hideOnEscape=true, preferredIndex=3,
    }

    function M.LockInSelected()
        local payload = ControllerInstance().PrepareLockInSelected()
        if not payload then return end
        return StaticPopup_Show(
            "NEXUS_LOCKIN_BUILD", payload.title, nil, payload)
    end

    local CARD_HEIGHT = 88
    local ICON_SIZE = 26
    local MAX_ROW_ICONS = 12
    local ECHO_ICON_SIZE = 22

    local CLASS_COLOR = {
        DEATHKNIGHT={0.77,0.12,0.23},DRUID={1.00,0.49,0.04},
        HUNTER={0.67,0.83,0.45},MAGE={0.25,0.78,0.92},
        PALADIN={0.96,0.55,0.73},PRIEST={1.00,1.00,1.00},
        ROGUE={1.00,0.96,0.41},SHAMAN={0.00,0.44,0.87},
        WARLOCK={0.53,0.53,0.93},WARRIOR={0.78,0.61,0.43},
    }
    local CLASS_LABEL = {
        DEATHKNIGHT="Death Knight",DRUID="Druid",HUNTER="Hunter",
        MAGE="Mage",PALADIN="Paladin",PRIEST="Priest",ROGUE="Rogue",
        SHAMAN="Shaman",WARLOCK="Warlock",WARRIOR="Warrior",
        UNKNOWN="Unknown",
    }
    local CLASS_ICON = {
        DEATHKNIGHT="Interface\\Icons\\Spell_DeathKnight_IceboundFortitude",
        DRUID="Interface\\Icons\\Spell_Nature_NaturesBlessing",
        HUNTER="Interface\\Icons\\Ability_Hunter_BeastCall",
        MAGE="Interface\\Icons\\Spell_Frost_Frostbolt02",
        PALADIN="Interface\\Icons\\Spell_Holy_HolyBolt",
        PRIEST="Interface\\Icons\\Spell_Holy_PowerInfusion",
        ROGUE="Interface\\Icons\\Ability_BackStab",
        SHAMAN="Interface\\Icons\\Spell_Nature_Lightning",
        WARLOCK="Interface\\Icons\\Spell_Shadow_ShadowBolt",
        WARRIOR="Interface\\Icons\\Ability_Warrior_Charge",
    }

    local frame, scrollChild, scrollFrame, scrollBar
    local detailPanel
    local searchBox, clearSearchBtn, classDropBtn, qualifiedBtn, dropPanel
    local sortToggle, sortPanel
    local scopeBtn, myBuildsBtn, syncStatusText, syncBtn, dropdownShield
    local leaderboardBtn, wishlistBtn, resultText
    local prevPageBtn, nextPageBtn, pageText
    local RenderSyncStatus
    local renderBuildWindow, virtualBinding = nil, false
    local lastPublishedPageCount = 1
    local refreshDirty = false
    local viewDiagnostic = {
        publishedAt=nil,publishedPage=0,
        projectionCurrent=false,projectionPending=false,projectionError=false,
        bundledCount=0,overlayCount=0,availableCount=0,
        filterMatchedCount=0,qualifyingCount=0,resultCount=0,
        displayedCount=0,searchActive=false,catalogVersion="unversioned",
    }
    local suppressSearchChange = false
    local virtualStats = {
        created=0,peakActive=0,active=0,results=0,
        dataRefreshes=0,dataFailures=0,
        dataBinds=0,scrollBinds=0,resizeBinds=0,
        dirtyMarks=0,deferredRefreshes=0,periodicSkips=0,
        first=1,last=0,offset=0,maxOffset=0,
    }

    local function PlaceCommunityBox(widget, box)
        if not (widget and box) then return end
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT",frame,"TOPLEFT",box.x,-box.y)
        widget:SetSize(box.w,box.h)
    end

    local function AvailableSize()
        local width, height = 1040, 640
        if UIParent and type(UIParent.GetWidth) == "function" then
            local ok, value = pcall(UIParent.GetWidth,UIParent)
            value = ok and tonumber(value) or nil
            if value and value >= 700 then
                width = math.max(760,math.min(1040,value-40))
            end
        end
        if UIParent and type(UIParent.GetHeight) == "function" then
            local ok, value = pcall(UIParent.GetHeight,UIParent)
            value = ok and tonumber(value) or nil
            if value and value >= 520 then
                height = math.max(520,math.min(640,value-60))
            end
        end
        return width, height
    end

    local function ApplyCommunityLayout(layout)
        frame:SetSize(layout.width,layout.height)

        local boxes = layout.boxes
        PlaceCommunityBox(frame._titleText,boxes.title)
        PlaceCommunityBox(frame._navBar,boxes.nav)
        PlaceCommunityBox(frame._browseLabel,boxes.browseLabel)
        PlaceCommunityBox(searchBox,boxes.search)
        PlaceCommunityBox(scopeBtn,boxes.scope)
        PlaceCommunityBox(myBuildsBtn,boxes.mine)
        PlaceCommunityBox(classDropBtn,boxes.class)
        PlaceCommunityBox(qualifiedBtn,boxes.qualified)
        PlaceCommunityBox(sortToggle,boxes.sort)
        PlaceCommunityBox(frame._actionLabel,boxes.actionLabel)
        PlaceCommunityBox(syncBtn,boxes.sync)
        PlaceCommunityBox(frame._postBtn,boxes.share)
        PlaceCommunityBox(resultText,boxes.result)
        PlaceCommunityBox(prevPageBtn,boxes.prev)
        PlaceCommunityBox(pageText,boxes.page)
        PlaceCommunityBox(nextPageBtn,boxes.next)
        PlaceCommunityBox(syncStatusText,boxes.status)
        PlaceCommunityBox(frame._listClip,boxes.list)
        PlaceCommunityBox(frame._emptyState,boxes.emptyState)
        PlaceCommunityBox(detailPanel,boxes.detail)

        if detailPanel and boxes.detail then
            local inner = math.max(120,boxes.detail.w-20)
            detailPanel.title:SetWidth(math.max(80,inner-46))
            detailPanel.author:SetWidth(math.max(80,inner-46))
            detailPanel.desc:SetWidth(inner)
            detailPanel.linkBox:SetWidth(math.max(80,inner-88))
            detailPanel.missingText:SetWidth(inner)
            detailPanel.dummyRecord:SetWidth(inner)
            detailPanel.lkRecord:SetWidth(inner)
            detailPanel.detailsNote:SetWidth(inner)
            detailPanel.editState:SetWidth(inner)
            for _, row in ipairs(detailPanel.lbDummyRows) do row:SetWidth(inner) end
            for _, row in ipairs(detailPanel.lbLKRows) do row:SetWidth(inner) end
            detailPanel.lbDummyEmpty:SetWidth(inner)
            detailPanel.lbDummyPersonal:SetWidth(inner)
            detailPanel.lbLKEmpty:SetWidth(inner)
            detailPanel.lbLKPersonal:SetWidth(inner)
        end
        if scrollChild then scrollChild:SetWidth(layout.card.width) end
        return true
    end

    function M.ApplyResponsiveLayout(force)
        local owner = Nexus.LayoutMetrics
        if not (frame and owner) then return false end
        local width, height = AvailableSize()
        local keyOk, runtimeKey = pcall(owner.RuntimeKey,
            "community",width,height)
        if not keyOk then return false end
        if not force and frame._nexusRuntimeLayoutKey == runtimeKey then
            return false
        end
        local metricsOk, fontScale, uiScale, revision =
            pcall(owner.RuntimeMetrics)
        if not metricsOk then return false end
        local layoutOk, layout = pcall(owner.Community,{
            width=width,height=height,fontScale=fontScale,uiScale=uiScale,
            revision=revision,empty=virtualStats.results == 0,
            syncActive=Nexus.Sync and Nexus.Sync.IsReceiving
                and Nexus.Sync.IsReceiving() or false,
            results=virtualStats.results,
            labels={
                search="Search title, author, or description",
                scope="All Shared",mine="My Builds",
                class="Current Class Only",qualified="Qualified Only",
                sort="Sort: Highest DPS",sync="Listening...",
                share="Share Build",
            },
        })
        if not layoutOk or type(layout) ~= "table" then return false end
        local previousLayout = frame._responsiveLayout
        local applied = pcall(ApplyCommunityLayout,layout)
        if not applied then
            if type(previousLayout) == "table" then
                pcall(ApplyCommunityLayout,previousLayout)
            end
            return false
        end
        frame._nexusRuntimeLayoutKey = runtimeKey
        frame._nexusLayoutKey = layout.key
        frame._responsiveLayout = layout
        return true
    end

------------------------------------------------------------------------
-- Post popup
------------------------------------------------------------------------

local postPopup, editPopup
local postTitleBox, postDescBox, editTitleBox, editDescBox
local postPreviewIcons = {}
local postWishlistBtn, postClassBtn, postWishlistMenu, postClassMenu
local RefreshPostPopupPreview

local function ClearPostDescriptionFocus()
    if postDescBox and postDescBox.ClearFocus then postDescBox:ClearFocus() end
end

local function ClearEditDescriptionFocus()
    if editDescBox and editDescBox.ClearFocus then editDescBox:ClearFocus() end
end

local CLASS_PICK_ORDER = {
    "DEATHKNIGHT", "DRUID", "HUNTER", "MAGE", "PALADIN",
    "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
}

local function MakeDropdownMenu(parent, width)
    local menu = CreateFrame("Frame", nil, parent)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetWidth(width)
    menu:SetBackdrop({
        bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true,tileSize=16,edgeSize=12,
        insets={left=3,right=3,top=3,bottom=3},
    })
    menu:SetBackdropColor(0.03,0.03,0.03,0.98)
    menu:Hide()
    return menu
end

local function AddMenuButton(menu, text, onClick, index)
    local b = CreateFrame("Button", nil, menu)
    b:SetHeight(22); b:SetPoint("TOPLEFT",6,-6-(index-1)*22); b:SetPoint("TOPRIGHT",-6,0-(index-1)*22)
    b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    local fs = b:CreateFontString(nil,"OVERLAY",Nexus.LayoutMetrics
        and Nexus.LayoutMetrics.FontObject("normal")
        or "GameFontHighlightSmall")
    fs:SetPoint("LEFT",6,0); fs:SetPoint("RIGHT",-6,0); fs:SetJustifyH("LEFT"); fs:SetText(text)
    b:SetScript("OnClick", function() menu:Hide(); onClick() end)
    return b
end

local function HidePostMenus()
    if postWishlistMenu then postWishlistMenu:Hide() end
    if postClassMenu then postClassMenu:Hide() end
end

local function BuildWishlistCandidates()
    return ControllerInstance().PostSourceCandidates()
end

local function WishlistLabel(wl)
    local kind=(wl and wl.sourceKind) or "Wishlist"
    local name=(wl and wl.name and wl.name~="") and wl.name or ("Unnamed "..kind)
    local count=0
    for _,e in ipairs((wl and wl.echoes) or {}) do count=count+(tonumber(e.stacks or e.count) or 1) end
    return string.format("[%s] %s  —  %d / 79", kind, name, count)
end

local function RefreshPostWishlistMenu()
    if not postWishlistMenu then return end
    for _, child in ipairs({postWishlistMenu:GetChildren()}) do child:Hide(); child:SetParent(nil) end
    local candidates = BuildWishlistCandidates()
    local h = math.min(300, 12 + #candidates * 24)
    postWishlistMenu:SetHeight(h)
    for i, c in ipairs(candidates) do
        AddMenuButton(postWishlistMenu, WishlistLabel(c), function()
            ControllerInstance().SetPostWishlist(c)
            postWishlistBtn:SetText("Source: " .. ((c.name and c.name ~= "") and c.name or "Unnamed"))
            RefreshPostPopupPreview()
        end, i)
    end
    if #candidates == 0 then
        AddMenuButton(postWishlistMenu, "No saved builds or wishlists found", function() end, 1)
        postWishlistMenu:SetHeight(40)
    end
end

local function RefreshPostClassMenu()
    if not postClassMenu then return end
    for _, child in ipairs({postClassMenu:GetChildren()}) do child:Hide(); child:SetParent(nil) end
    postClassMenu:SetHeight(12 + #CLASS_PICK_ORDER * 24)
    for i, token in ipairs(CLASS_PICK_ORDER) do
        AddMenuButton(postClassMenu, CLASS_LABEL[token], function()
            ControllerInstance().SetPostClass(token)
            local cc = CLASS_COLOR[token] or {1,1,1}
            postClassBtn:SetText("Class: " .. CLASS_LABEL[token])
            postClassBtn:GetFontString():SetTextColor(cc[1],cc[2],cc[3])
            RefreshPostPopupPreview()
        end, i)
    end
end

local function EnsurePostPopup()
    if postPopup then return postPopup end
    local p = CreateFrame("Frame","NexusPostPopup",UIParent)
    p:SetSize(760, 560)
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:EnableMouse(true)
    p._dragHandle = InstallPopupDragHandle(p)
    p:Hide()
    pcall(function() p:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,edgeSize=32,insets={left=11,right=12,top=12,bottom=11}}) end)

    local titleBar = p:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    titleBar:SetPoint("TOP",0,-14); titleBar:SetText("Share a Nexus Build")
    local close = CreateFrame("Button",nil,p,"UIPanelCloseButton")
    close:SetPoint("TOPRIGHT",-2,-2); close:SetScript("OnClick",function()
        HidePostMenus(); ClearPostDescriptionFocus(); p:Hide()
    end)

    local tl = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); tl:SetPoint("TOPLEFT",16,-38); tl:SetText("Build Title:")
    postTitleBox = CreateFrame("EditBox",nil,p,"InputBoxTemplate"); postTitleBox:SetSize(330,20); postTitleBox:SetPoint("TOPLEFT",16,-54); postTitleBox:SetAutoFocus(false); postTitleBox:SetMaxLetters(80)
    p._postTitleBox = postTitleBox

    local dl = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); dl:SetPoint("TOPLEFT",16,-88); dl:SetText("Description (what makes this build stand out):")
    local descBg = CreateFrame("Frame",nil,p); descBg:SetPoint("TOPLEFT",14,-104); descBg:SetSize(334,180)
    pcall(function() descBg:SetBackdrop({bgFile="Interface\\Tooltips\\UI-Tooltip-Background",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",tile=true,tileSize=16,edgeSize=12,insets={left=3,right=3,top=3,bottom=3}}); descBg:SetBackdropColor(0,0,0,0.5) end)
    local descScroll = CreateFrame("ScrollFrame","NexusPostDescriptionScroll",descBg,
        "UIPanelScrollFrameTemplate")
    descScroll:SetPoint("TOPLEFT",6,-6)
    descScroll:SetPoint("BOTTOMRIGHT",-24,6)
    postDescBox = CreateFrame("EditBox",nil,descScroll)
    ConfigureDescriptionEdit(postDescBox, descScroll, 286, 168)
    p._postDescScroll = descScroll
    p._postDescBox = postDescBox

    local chooseLabel = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); chooseLabel:SetPoint("TOPLEFT",16,-302); chooseLabel:SetText("1. Choose the exact server loadout or wishlist to share:")
    postWishlistBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate"); postWishlistBtn:SetSize(334,26); postWishlistBtn:SetPoint("TOPLEFT",16,-320); postWishlistBtn:SetText("Source: Select a saved build or wishlist")
    p._postWishlistBtn = postWishlistBtn
    postWishlistMenu = MakeDropdownMenu(p,334); postWishlistMenu:SetPoint("TOPLEFT",16,-348)
    postWishlistBtn:SetScript("OnClick",function() HidePostMenus(); RefreshPostWishlistMenu(); postWishlistMenu:Show() end)

    postClassBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate"); postClassBtn:SetSize(334,26); postClassBtn:SetPoint("TOPLEFT",16,-360); postClassBtn:SetText("Class: Select a class")
    p._postClassBtn = postClassBtn
    postClassMenu = MakeDropdownMenu(p,334); postClassMenu:SetPoint("TOPLEFT",16,-388)
    postClassBtn:SetScript("OnClick",function() HidePostMenus(); RefreshPostClassMenu(); postClassMenu:Show() end)

    local previewLabel = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); previewLabel:SetPoint("TOPLEFT",380,-38); previewLabel:SetText("Exact Echo Loadout Preview:")
    local previewWishlist = p:CreateFontString(nil,"OVERLAY","GameFontHighlight"); previewWishlist:SetPoint("TOPLEFT",380,-54); previewWishlist:SetSize(350,16); previewWishlist:SetJustifyH("LEFT"); p._previewWishlist=previewWishlist
    local previewClass = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); previewClass:SetPoint("TOPLEFT",380,-74); previewClass:SetSize(350,14); previewClass:SetJustifyH("LEFT"); p._previewClass=previewClass
    local previewSummary = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall"); previewSummary:SetPoint("TOPLEFT",380,-92); previewSummary:SetSize(350,14); previewSummary:SetJustifyH("LEFT"); p._previewSummary=previewSummary
    local previewClip=CreateFrame("Frame",nil,p); previewClip:SetPoint("TOPLEFT",374,-112); previewClip:SetSize(370,390); pcall(function() previewClip:SetClipsChildren(true) end); p._previewClip=previewClip
    local previewScroll=CreateFrame("ScrollFrame",nil,previewClip); previewScroll:SetAllPoints(previewClip); previewScroll:EnableMouseWheel(true); p._previewScroll=previewScroll
    local previewChild=CreateFrame("Frame",nil,previewScroll); previewChild:SetWidth(360); previewChild:SetHeight(1); previewScroll:SetScrollChild(previewChild); p._previewChild=previewChild
    p._previewRows={}
    for i=1,100 do
        local row=CreateFrame("Frame",nil,previewChild); row:SetSize(355,22)
        local icon=row:CreateTexture(nil,"ARTWORK"); icon:SetSize(20,20); icon:SetPoint("LEFT",0,0); row.icon=icon
        local text=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); text:SetPoint("LEFT",26,0); text:SetSize(325,20); text:SetJustifyH("LEFT"); row.text=text; row:Hide(); p._previewRows[i]=row
    end
    local noWishlistNote=p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall"); noWishlistNote:SetPoint("TOPLEFT",380,-112); noWishlistNote:SetSize(350,80); noWishlistNote:SetJustifyH("LEFT"); noWishlistNote:SetJustifyV("TOP"); p._noWishlistNote=noWishlistNote

    local postGoBtn=CreateFrame("Button",nil,p,"UIPanelButtonTemplate"); postGoBtn:SetSize(150,28); postGoBtn:SetPoint("BOTTOM",0,16); postGoBtn:SetText("Share Build"); p._postGoBtn=postGoBtn
    postGoBtn:SetScript("OnClick",function()
        local wishlist, class = ControllerInstance().PostDraft()
        if not wishlist or not class then print("|cffff6060Nexus:|r Select a source loadout and class before sharing."); return end
        local ok,value,outcome=ControllerInstance().PostCurrentWishlist(postTitleBox:GetText(),postDescBox:GetText(),wishlist,class)
        if not ok then
            print("|cffff6060Nexus:|r "..tostring(value))
            return
        end
        outcome=type(outcome)=="table" and outcome or {}
        if outcome.sendCompleted then
            print("|cff4dff80Nexus:|r Build saved locally and sent. Peer storage confirmation is unavailable.")
        elseif outcome.queueAdmitted then
            print("|cff4dff80Nexus:|r Build saved locally and queued for sharing. Peer storage confirmation is unavailable.")
        elseif outcome.retryPending then
            print("|cffffc040Nexus:|r Build saved locally; the Sync queue is full. One bounded retry is pending.")
        else
            print("|cffffc040Nexus:|r Build saved locally; not queued: "
                ..tostring(outcome.queueReason or "Sync unavailable")..".")
        end
        ClearPostDescriptionFocus(); p:Hide(); M.Refresh()
    end)
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.ApplyFontTree then
        Nexus.LayoutMetrics.ApplyFontTree(p,"normal")
    end
    postPopup=p; return p
end

local function EchoDisplayName(spellId)
    return ControllerInstance().EchoDisplayName(spellId)
end

RefreshPostPopupPreview = function()
    if not postPopup or not postPopup:IsShown() then return end
    local wl, selectedClass = ControllerInstance().PostDraft()
    local echoes = ControllerInstance().WishlistEchoes(wl)
    if not wl or not echoes or #echoes==0 then
        for _,row in ipairs(postPopup._previewRows or {}) do row:Hide() end
        postPopup._noWishlistNote:SetText("|cffff6060No source selected.|r\n\nChoose a server Saved Build or Wishlist to share.")
        postPopup._noWishlistNote:Show(); postPopup._previewWishlist:SetText(""); postPopup._previewSummary:SetText(""); postPopup._previewClass:SetText(""); postPopup._postGoBtn:Disable(); return
    end
    postPopup._noWishlistNote:Hide(); postPopup._postGoBtn:Enable()
    local wishlistName=(wl.name and wl.name~="") and wl.name or "Unnamed Echo Wishlist"
    local classToken=selectedClass or ControllerInstance().InferBuildClass(echoes) or ""
    postPopup._previewWishlist:SetText("|cffffd200"..wishlistName.."|r")
    postPopup._previewSummary:SetText(string.format("|cff888888%d Echo rows in this source|r",#echoes))
    local cc=CLASS_COLOR[(classToken or ""):upper()] or {1,1,1}; postPopup._previewClass:SetTextColor(cc[1],cc[2],cc[3]); postPopup._previewClass:SetText("Posting as: "..(CLASS_LABEL[(classToken or ""):upper()] or classToken or "Select a class"))
    local child=postPopup._previewChild
    for i,row in ipairs(postPopup._previewRows or {}) do
        local e=echoes[i]
        if e then row:ClearAllPoints(); row:SetPoint("TOPLEFT",child,"TOPLEFT",0,-(i-1)*22); row.icon:SetTexture(SpellIcon(e.spellId)); local stacks=tonumber(e.stacks) or 1; local suffix=stacks>1 and ("  x"..stacks) or ""; row.text:SetText(string.format("%02d. %s%s",i,EchoDisplayName(e.spellId),suffix)); row:Show() else row:Hide() end
    end
    child:SetHeight(math.max(1,#echoes*22)); pcall(function() postPopup._previewScroll:SetVerticalScroll(0) end)
end

function M.ShowPostBuild()
    EnsurePostPopup()
    if postPopup:IsShown() then
        HidePostMenus(); ClearPostDescriptionFocus(); postPopup:Hide(); return
    end
    local candidates=BuildWishlistCandidates(); local wl=candidates[1]
    -- Auto-detect class from echo catalog, then fall back to player's own class
    local selectedClass = ControllerInstance().InferBuildClass(
        ControllerInstance().WishlistEchoes(wl) or {}) or ""
    if selectedClass == "" and UnitClass then
        local _, classToken = UnitClass("player")
        selectedClass = (classToken and classToken ~= "UNKNOWN") and tostring(classToken) or ""
    end
    ControllerInstance().BeginPostDraft(wl, selectedClass)
    postTitleBox:SetText((wl and wl.name and wl.name~="") and wl.name or "")
    postDescBox:SetText("")
    postDescBox:SetCursorPosition(0)
    postPopup._postDescScroll:SetVerticalScroll(0)
    postWishlistBtn:SetText("Source: "..((wl and wl.name and wl.name~="") and wl.name or "Select a saved build or wishlist"))
    if selectedClass ~= "" then
        local cc = CLASS_COLOR[selectedClass:upper()] or {1,1,1}
        postClassBtn:SetText("Class: "..(CLASS_LABEL[selectedClass:upper()] or selectedClass))
        pcall(function() postClassBtn:GetFontString():SetTextColor(cc[1],cc[2],cc[3]) end)
    else
        postClassBtn:SetText("Class: Select a class")
    end
    postPopup:ClearAllPoints(); postPopup:SetPoint("CENTER"); postPopup:Show(); RefreshPostPopupPreview()
end

function M.TogglePostPopup(anchor) M.ShowPostBuild() end

------------------------------------------------------------------------
-- Edit popup
------------------------------------------------------------------------

local editEchoBtn, editLockText

local function EnsureEditPopup()
    if editPopup then return editPopup end
    local p = CreateFrame("Frame","NexusEditPopup",UIParent)
    p:SetSize(360,282); p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:EnableMouse(true); p:Hide()
    p._dragHandle = InstallPopupDragHandle(p)

    local title = p:CreateFontString(nil,"OVERLAY","GameFontNormal")
    title:SetPoint("TOP",0,-12); title:SetText("Edit Build")

    local close = CreateFrame("Button",nil,p,"UIPanelCloseButton")
    close:SetPoint("TOPRIGHT",-2,-2); close:SetScript("OnClick",function()
        ClearEditDescriptionFocus()
        p:Hide()
        ControllerInstance().ClearEditDraft()
    end)

    local tl = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    tl:SetPoint("TOPLEFT",16,-36); tl:SetText("Title:")
    editTitleBox = CreateFrame("EditBox",nil,p,"InputBoxTemplate")
    editTitleBox:SetSize(310,20); editTitleBox:SetPoint("TOPLEFT",20,-52); editTitleBox:SetAutoFocus(false); editTitleBox:SetMaxLetters(80)
    p._editTitleBox = editTitleBox

    local dl = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    dl:SetPoint("TOPLEFT",16,-80); dl:SetText("Description:")
    local descBg = CreateFrame("Frame",nil,p)
    descBg:SetPoint("TOPLEFT",18,-96); descBg:SetSize(324,86)
    pcall(function()
        descBg:SetBackdrop({ bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true,tileSize=16,edgeSize=12, insets={left=3,right=3,top=3,bottom=3} })
        descBg:SetBackdropColor(0,0,0,0.5)
    end)
    local descScroll = CreateFrame("ScrollFrame","NexusEditDescriptionScroll",descBg,
        "UIPanelScrollFrameTemplate")
    descScroll:SetPoint("TOPLEFT",6,-6)
    descScroll:SetPoint("BOTTOMRIGHT",-24,6)
    editDescBox = CreateFrame("EditBox",nil,descScroll)
    ConfigureDescriptionEdit(editDescBox, descScroll, 278, 74)
    p._editDescScroll = descScroll
    p._editDescBox = editDescBox

    editLockText = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    editLockText:SetPoint("TOPLEFT",18,-190)
    editLockText:SetSize(324,30)
    editLockText:SetJustifyH("LEFT")
    editLockText:SetJustifyV("TOP")
    p._editLockText = editLockText

    editEchoBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate")
    editEchoBtn:SetSize(210,22)
    editEchoBtn:SetPoint("BOTTOMLEFT",18,16)
    editEchoBtn:SetText("Use Active Wishlist Echoes")
    p._editEchoBtn = editEchoBtn
    editEchoBtn:SetScript("OnClick",function()
        local draft = ControllerInstance().EditDraft()
        if not draft then return end
        local ok, result = ControllerInstance().UpdateFromWishlist(draft.id)
        if ok then
            print(string.format("|cff4dff80Nexus:|r Echo list replaced with the active wishlist (%d Echoes).", result))
            ControllerInstance().ClearEditDraft()
            ClearEditDescriptionFocus(); p:Hide(); M.Refresh()
        else
            print("|cffff6060Nexus:|r " .. tostring(result))
        end
    end)

    local saveBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate")
    saveBtn:SetSize(118,22); saveBtn:SetPoint("BOTTOMRIGHT",-18,16); saveBtn:SetText("Save Details")
    p._saveBtn = saveBtn
    saveBtn:SetScript("OnClick",function()
        if not ControllerInstance().UpdateEditDraft(
            editTitleBox:GetText(), editDescBox:GetText()) then return end
        local ok, err = ControllerInstance().CommitEditDraft()
        if ok then print("|cff4dff80Nexus:|r build updated and re-shared."); ClearEditDescriptionFocus(); p:Hide(); M.Refresh()
        else print("|cffff6060Nexus:|r "..tostring(err)) end
    end)
    pcall(function()
        p:SetBackdrop({ bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
            tile=true,tileSize=32,edgeSize=32, insets={left=11,right=12,top=12,bottom=11} })
    end)
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.ApplyFontTree then
        Nexus.LayoutMetrics.ApplyFontTree(p,"normal")
    end
    editPopup = p; return p
end

function M.ToggleEditPopup(id)
    EnsureEditPopup()
    if editPopup:IsShown() then
        ClearEditDescriptionFocus()
        editPopup:Hide()
        ControllerInstance().ClearEditDraft()
        return
    end
    local prepared = ControllerInstance().PrepareEditDraft(id)
    if not prepared then return end
    -- Retain the established frame projection for compatibility; the
    -- controller draft remains the sole authoritative edit-session state.
    editPopup._editingId = id
    if prepared.locked then
        editEchoBtn:Disable()
        editLockText:SetText("|cffffd200Echo list locked by leaderboard record.|r Post a new build to use a different loadout.")
    else
        editEchoBtn:Enable()
        editLockText:SetText("Change title/description, or replace the Echo list with your current active wishlist.")
    end
    editTitleBox:SetText(prepared.title)
    editTitleBox:HighlightText(0, 0)
    editDescBox:SetText(prepared.description)
    editDescBox:SetCursorPosition(#prepared.description)
    editPopup._editDescScroll:SetVerticalScroll(0)
    editPopup:ClearAllPoints(); editPopup:SetPoint("CENTER")
    editPopup:Show()
end

local function EnsureDetailPanel(parent)
    if detailPanel then return detailPanel end
    local p = CreateFrame("Frame", nil, parent)
    p:SetSize(500, 570)
    p:SetPoint("TOPLEFT", parent, "TOPLEFT", 520, -60)
    p:SetFrameLevel(parent:GetFrameLevel() + 2)
    p:Hide()

    pcall(function()
        p:SetBackdrop({
            bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true, tileSize=16, edgeSize=12,
            insets={left=3,right=3,top=3,bottom=3},
        })
        p:SetBackdropColor(0,0,0,0.9)
    end)

    p.classIcon = p:CreateTexture(nil,"ARTWORK")
    p.classIcon:SetSize(34,34)
    p.classIcon:SetPoint("TOPLEFT",10,-10)
    p.classIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    p.title = p:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    p.title:SetPoint("TOPLEFT",p.classIcon,"TOPRIGHT",8,-1)
    p.title:SetSize(390,20)
    p.title:SetJustifyH("LEFT")

    p.closeBtn = CreateFrame("Button", nil, p, "UIPanelCloseButton")
    p.closeBtn:SetPoint("TOPRIGHT", -2, -2)
    p.closeBtn:SetScript("OnClick", function()
        ControllerInstance().ClearSelection()
        M.Refresh()
    end)

    p.author = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    p.author:SetPoint("TOPLEFT",p.title,"BOTTOMLEFT",0,-2)
    p.author:SetSize(350,12)
    p.author:SetJustifyH("LEFT")

    p.desc = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    p.desc:SetPoint("TOPLEFT",10,-56)
    p.desc:SetSize(350,50)
    p.desc:SetJustifyH("LEFT")
    p.desc:SetJustifyV("TOP")

    -- "Build Link" — a copyable URL field. The admin (or original author)
    -- can paste a URL (EbonBuilds page, video, sim link, etc.) and viewers
    -- get a box they can copy out in one click. Field is hidden when empty.
    local linkLabel = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    linkLabel:SetPoint("TOPLEFT",10,-108)
    linkLabel:SetText("|cff888888DISCORD BUILD LINK|r")
    p.linkLabel = linkLabel

    local linkBox = CreateFrame("EditBox",nil,p,"InputBoxTemplate")
    linkBox:SetSize(382,18)
    linkBox:SetPoint("TOPLEFT",10,-122)
    linkBox:SetAutoFocus(false)
    linkBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    linkBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        if p.linkSaveBtn and p.linkSaveBtn:IsShown() then p.linkSaveBtn:Click() end
    end)
    -- Make the link reliably copyable on 3.3.5: click focuses and selects all.
    linkBox:SetScript("OnMouseUp", function(self)
        self:SetFocus()
        pcall(function() self:HighlightText() end)
    end)
    linkBox:SetScript("OnEditFocusGained", function(self)
        pcall(function() self:HighlightText() end)
    end)
    p.linkBox = linkBox

    -- Owner-only Save button for the link
    local linkSaveBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate")
    linkSaveBtn:SetSize(72,18)
    linkSaveBtn:SetPoint("LEFT",linkBox,"RIGHT",8,0)
    linkSaveBtn:SetText("Save Link")
    linkSaveBtn:SetScript("OnClick", function()
        local link = linkBox:GetText():gsub("^%s+",""):gsub("%s+$","")
        local selected = SelectedId()
        local build = selected and LoadBuild(selected)
        if not build or not IsOwnBuild(build) then return end
        local ok, err = EditBuild(
            selected, build.title, build.description, link)
        if ok then
            print("|cff4dff80Nexus:|r Discord build link saved.")
            M.Refresh()
        else
            print("|cffff6060Nexus:|r " .. tostring(err))
        end
    end)
    linkSaveBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Save this link to the build",0.9,0.9,0.9,true)
        GameTooltip:AddLine("Viewers can click the field and press Ctrl+C to copy it.",0.7,0.7,0.7,true)
        GameTooltip:Show()
    end)
    linkSaveBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    p.linkSaveBtn = linkSaveBtn

    p.echoLabel = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    p.echoLabel:SetPoint("TOPLEFT",10,-148)
    p.echoLabel:SetText("Echoes:")

    -- Locked echo row (permanent baseline, up to 6)
    p.lockedLabel = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    p.lockedLabel:SetPoint("TOPLEFT",10,-150)
    p.lockedLabel:SetText("LOCKED ECHOES")

    p.lockedIcons = {}
    for i = 1, 6 do
        local ic = p:CreateTexture(nil,"ARTWORK")
        ic:SetSize(ECHO_ICON_SIZE+4, ECHO_ICON_SIZE+4)
        ic:SetPoint("TOPLEFT", 10 + (i-1)*(ECHO_ICON_SIZE+6), -164)
        ic:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        ic:Hide()
        p.lockedIcons[i] = ic
    end

    -- echo icon grid: up to 80 icons, 13 per row (shifted down 48px for locked row)
    p.echoIcons = {}
    local COLS = 13
    for i = 1, 80 do
        local col = (i-1) % COLS
        local row = math.floor((i-1) / COLS)
        local ic = p:CreateTexture(nil,"ARTWORK")
        ic:SetSize(ECHO_ICON_SIZE, ECHO_ICON_SIZE)
        ic:SetPoint("TOPLEFT", 10 + col*(ECHO_ICON_SIZE+2), -212 - row*(ECHO_ICON_SIZE+2))
        ic:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        ic:Hide()
        p.echoIcons[i] = ic
    end

    p.missingText = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    p.missingText:SetPoint("TOPLEFT",10,-378)
    p.missingText:SetSize(470,14)
    p.missingText:SetJustifyH("LEFT")

    -- Compact record summary. Full rankings live in the dedicated Leaderboard.
    p.recordsTitle = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    p.recordsTitle:SetPoint("TOPLEFT",10,-402)
    p.recordsTitle:SetText("BEST RECORDS FOR THIS LOADOUT")

    p.dummyRecord = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    p.dummyRecord:SetPoint("TOPLEFT",10,-424)
    p.dummyRecord:SetSize(470,16)
    p.dummyRecord:SetJustifyH("LEFT")

    p.lkRecord = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    p.lkRecord:SetPoint("TOPLEFT",10,-446)
    p.lkRecord:SetSize(470,16)
    p.lkRecord:SetJustifyH("LEFT")

    -- Legacy row widgets are retained but hidden for saved UI compatibility.
    -- DPS section: Training Dummy
    local dummyHeader = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    dummyHeader:SetPoint("TOPLEFT",10,-302)
    dummyHeader:SetText("|cffffd200Training Dummy - Best DPS|r")

    p.lbDummyRows = {}
    for i = 1, 5 do
        local row = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        row:SetPoint("TOPLEFT",10,-318-(i-1)*16)
        row:SetSize(440,14); row:SetJustifyH("LEFT"); row:Hide()
        p.lbDummyRows[i] = row
    end
    p.lbDummyEmpty = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    p.lbDummyEmpty:SetPoint("TOPLEFT",10,-318)
    p.lbDummyEmpty:SetSize(440,14)
    p.lbDummyEmpty:SetText("|cff666666No recorded DPS yet -- hit a training dummy|r")

    p.lbDummyPersonal = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    p.lbDummyPersonal:SetPoint("TOPLEFT",10,-402)
    p.lbDummyPersonal:SetSize(440,14); p.lbDummyPersonal:SetJustifyH("LEFT")
    p.lbDummyPersonal:Hide()

    -- DPS section: Lich King
    local lkHeader = p:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    lkHeader:SetPoint("TOPLEFT",10,-422)
    lkHeader:SetText("|cffffd200Lich King - Best DPS|r")

    p.lbLKRows = {}
    for i = 1, 5 do
        local row = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        row:SetPoint("TOPLEFT",10,-438-(i-1)*16)
        row:SetSize(440,14); row:SetJustifyH("LEFT"); row:Hide()
        p.lbLKRows[i] = row
    end
    p.lbLKEmpty = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    p.lbLKEmpty:SetPoint("TOPLEFT",10,-438)
    p.lbLKEmpty:SetSize(440,14)
    p.lbLKEmpty:SetText("|cff666666No Lich King results yet|r")

    p.lbLKPersonal = p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    p.lbLKPersonal:SetPoint("TOPLEFT",10,-522)
    p.lbLKPersonal:SetSize(440,14); p.lbLKPersonal:SetJustifyH("LEFT")
    p.lbLKPersonal:Hide()

    dummyHeader:Hide()
    lkHeader:Hide()
    p.lbDummyEmpty:Hide()
    p.lbDummyPersonal:Hide()
    p.lbLKEmpty:Hide()
    p.lbLKPersonal:Hide()
    for _, row in ipairs(p.lbDummyRows) do row:Hide() end
    for _, row in ipairs(p.lbLKRows) do row:Hide() end

    -- Details! availability note (shown once at bottom if not installed)
    p.detailsNote = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    p.detailsNote:SetPoint("TOPLEFT",10,-500)
    p.detailsNote:SetSize(470,12)
    p.detailsNote:SetJustifyH("LEFT")
    p.detailsNote:SetText("|cff666666Install Details! damage meter to enable DPS tracking.|r")

    p.editState = p:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    p.editState:SetPoint("TOPLEFT",10,-470)
    p.editState:SetSize(470,26)
    p.editState:SetJustifyH("LEFT")
    p.editState:SetJustifyV("TOP")
    p.editState:Hide()

    -- buttons row
    -- Single consolidated action for the common case: opens the build as a
    -- draft in the Wishlist Editor (name pre-filled from the build's title)
    -- instead of applying immediately -- WishlistEditor.OpenForCandidate ->
    -- LoadPendingEchoes already knows how to split a build's Echoes into
    -- normal picks vs. designed locked slots (using each echo's `locked`
    -- flag). b.echoes' own flags aren't always reliable ground truth though
    -- (see the OnClick handler below), so this resolves against the DPS
    -- record's own lockedEchoes first, same as the display just above it --
    -- carrying locked-Echo intent over whether the source was another
    -- player's build or your own. For a build that's a mirror of your OWN
    -- current server loadout, the same button instead means "publish it"
    -- (see RefreshDetailPanel's label).
    p.lockBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate")
    p.lockBtn:SetSize(130,22)
    p.lockBtn:SetPoint("BOTTOMLEFT",8,8)
    p.lockBtn:SetText("Copy into Editor")
    p.lockBtn:SetScript("OnClick", function()
        local selected = SelectedId()
        local projection = EnsureCommunityProjection()
        local detail = selected and projection
            and projection.Detail(selected, ProjectionContext()) or nil
        local b = detail and detail.build or nil
        if not b then
            print("|cffff6060Nexus:|r Copy unavailable: ordinary Echo evidence is still syncing.")
            return
        end
        if IsSavedMirror(b) then
            local ok, err = PublishImportedBuild(selected)
            if ok then
                print("|cff4dff80Nexus:|r uploaded '" .. tostring(b.title or "Saved Build") .. "' to community builds.")
                M.Refresh()
            else
                print("|cffff6060Nexus:|r " .. tostring(err))
            end
            return
        end
        if type(b.echoes) ~= "table" or #b.echoes == 0 then
            ControllerInstance().RequestLoadout(selected)
            print("|cff7fd5ffNexus:|r this build is still completing its background sync. Try again shortly.")
            return
        end
        if Nexus.WishlistEditor and Nexus.WishlistEditor.OpenForCandidate then
            local candidate, candidateReason = BuildCandidateEvidence(b)
            if not candidate then
                print("|cffff6060Nexus:|r Copy unavailable: "
                    .. tostring(candidateReason) .. ".")
                return
            end
            local validated, validationReason =
                CandidateEvidence.Validate(candidate)
            if not validated then
                print("|cffff6060Nexus:|r Copy unavailable: "
                    .. tostring(validationReason) .. ".")
                return
            end
            local opened = Nexus.WishlistEditor.OpenForCandidate(validated)
            if opened ~= false then parent:Hide() end
        end
    end)
    p.lockBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        local b = ControllerInstance().SelectedBuild()
        if IsSavedMirror(b) then
            GameTooltip:AddLine("Publish this saved loadout",0.9,0.9,0.9,true)
            GameTooltip:AddLine("Uploads it to the community build list so others can see and copy it.",0.7,0.7,0.7,true)
        else
            GameTooltip:AddLine("Review before applying",0.9,0.9,0.9,true)
            GameTooltip:AddLine("Opens this build as a draft in the Wishlist Editor, name pre-filled. Any",0.7,0.7,0.7,true)
            GameTooltip:AddLine("Echoes it had locked show up as designed locked slots you can adjust.",0.7,0.7,0.7,true)
        end
        GameTooltip:Show()
    end)
    p.lockBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    p.editBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate")
    p.editBtn:SetSize(96,22)
    p.editBtn:SetPoint("LEFT",p.lockBtn,"RIGHT",6,0)
    p.editBtn:SetText("Edit Build")
    p.editBtn:SetScript("OnClick", function()
        local selected = SelectedId()
        if selected then M.ToggleEditPopup(selected) end
    end)

    p.retryShareBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate")
    p.retryShareBtn:SetSize(130,22)
    p.retryShareBtn:SetPoint("BOTTOMLEFT",8,8)
    p.retryShareBtn:SetText("Retry Share")
    p.retryShareBtn:Hide()
    p.retryShareBtn:SetScript("OnClick", function(self)
        if self._nexusRetryConsumed then return end
        local selected = SelectedId()
        if not selected then return end
        self._nexusRetryConsumed = true
        self:Disable()
        local controller = ControllerInstance()
        local ok, why, outcome
        if type(controller.RetryShare) == "function" then
            ok, why, outcome = controller.RetryShare(selected)
        else
            ok, why = false, "not retryable"
        end
        outcome = type(outcome) == "table" and outcome or {}
        if ok and outcome.retryPending then
            print("|cffffc040Nexus:|r Share retry is waiting for one bounded Sync queue slot.")
        elseif ok then
            print("|cff4dff80Nexus:|r Share retry queued. Peer storage confirmation is unavailable.")
        else
            print("|cffff6060Nexus:|r Share retry failed: "
                .. tostring(why or "not retryable") .. ".")
            self._nexusRetryConsumed = false
            M.Refresh()
        end
    end)
    p.retryShareBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Retry this failed Share",0.9,0.9,0.9,true)
        GameTooltip:AddLine("Resends the exact saved build only after you click; no automatic terminal retry occurs.",0.7,0.7,0.7,true)
        GameTooltip:Show()
    end)
    p.retryShareBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    p.deleteBtn = CreateFrame("Button",nil,p,"UIPanelButtonTemplate")
    p.deleteBtn:SetSize(104,22)
    p.deleteBtn:SetPoint("BOTTOMRIGHT",-8,8)
    p.deleteBtn:SetText("Delete")
    p.deleteBtn:SetScript("OnClick", function()
        local selected = SelectedId()
        local build = selected and LoadBuild(selected)
        if build and IsOwnBuild(build) then
            StaticPopup_Show("NEXUS_STOP_SHARING_BUILD",
                tostring(build.title or "this build"), nil, {id=selected})
        elseif selected then
            local ok, err = DeleteBuild(selected)
            if not ok then print("|cffff6060Nexus:|r " .. tostring(err)) end
            M.Refresh()
        end
    end)

    parent._detailPanel = p
    detailPanel = p
    return p
end

local function RefreshDetailPanel(buildId)
    if not detailPanel then return end
    if buildId == nil then detailPanel:Hide(); return end
    local projection = EnsureCommunityProjection()
    local detail, build
    if projection then
        local err
        detail, err = projection.Detail(buildId, ProjectionContext())
        if not detail then
            if err then error(err) end
            detailPanel:Hide()
            return
        end
        build = detail.build
    else
        build = LoadBuild(buildId)
    end
    if not build then detailPanel:Hide(); return end

    local c = CLASS_COLOR[(build.class or ""):upper()] or {1,1,1}
    detailPanel.title:SetTextColor(c[1],c[2],c[3])
    detailPanel.title:SetText(build.title or "")
    if detailPanel.classIcon then
        detailPanel.classIcon:SetTexture(CLASS_ICON[(build.class or ""):upper()] or "Interface\\Icons\\INV_Misc_QuestionMark")
    end
    detailPanel.author:SetText("by "..(build.author or "?"))
    detailPanel.desc:SetText((build.description ~= "" and build.description) or "|cff666666(no description)|r")

    -- Link field: always show the box so anyone can copy; only show Save
    -- button for the build's owner. Hide label/box entirely when there's no
    -- link and the viewer isn't the owner (avoids empty-box clutter).
    local hasLink, ownThis
    if detail then
        hasLink, ownThis = detail.hasLink, detail.canSaveLink
    else
        hasLink = type(build.link) == "string" and build.link ~= ""
        ownThis = IsOwnBuild(build) or IsAdmin()
    end
    if detailPanel.linkBox then
        if hasLink or ownThis then
            detailPanel.linkLabel:Show()
            detailPanel.linkBox:Show()
            detailPanel.linkBox:SetText(build.link or "")
            if ownThis then
                detailPanel.linkSaveBtn:Show()
            else
                detailPanel.linkSaveBtn:Hide()
            end
        else
            detailPanel.linkLabel:Hide()
            detailPanel.linkBox:Hide()
            detailPanel.linkSaveBtn:Hide()
        end
    end

    -- Locked echoes come from the same category-aware resolver used by Copy.
    -- That owner already handles an inline build fallback when no DPS record
    -- exists; bypassing it here would hide a conflict or malformed claim.
    local lockedEchoes = detail and detail.lockedEchoes or nil
    if not detail then
        lockedEchoes = ControllerInstance().LockedEchoesForBuild(build)
    end
    if detailPanel.lockedIcons then
        if lockedEchoes and #lockedEchoes > 0 then
            detailPanel.lockedLabel:Show()
            detailPanel.echoLabel:Hide()
            for i, ic in ipairs(detailPanel.lockedIcons) do
                local e = lockedEchoes[i]
                if e then ic:SetTexture(SpellIcon(e.spellId or e.id)); ic:Show()
                else ic:Hide() end
            end
        else
            detailPanel.lockedLabel:Hide()
            detailPanel.echoLabel:Show()
            for _, ic in ipairs(detailPanel.lockedIcons) do ic:Hide() end
        end
    end

    -- echo icons
    local echoes = detail and detail.echoes or build.echoes or {}
    local hasLoadout = detail and detail.hasLoadout or false
    if not detail then
        hasLoadout = type(build.echoes) == "table" and #build.echoes > 0
    end
    local missing = detail and detail.missing or 0
    local totalSlots = detail and detail.totalSlots or 0
    local bySpell = {}
    if not detail then
        bySpell = ProjectionContext().ownedBySpell or {}
    end
    if not hasLoadout then
        ControllerInstance().RequestLoadout(build.id)
    end
    for i, ic in ipairs(detailPanel.echoIcons) do
        local e = echoes[i]
        if e then
            ic:SetTexture(SpellIcon(e.spellId))
            local isMissing
            if detail then
                isMissing = e.missing
            else
                isMissing = (tonumber(bySpell[e.spellId]) or 0)
                    < (tonumber(e.stacks) or 1)
            end
            if isMissing then
                if not detail then missing=missing+1 end
                pcall(function() ic:SetVertexColor(0.4,0.4,0.4) end)
            else
                pcall(function() ic:SetVertexColor(1,1,1) end)
            end
            ic:Show()
        else ic:Hide() end
    end
    if hasLoadout then
        if not detail then
            for _, e in ipairs(echoes) do
                totalSlots = totalSlots
                    + (tonumber(e.stacks or e.count) or 1)
            end
        end
        detailPanel.missingText:SetText(string.format(
            "|cff888888%d echoes|r  --  |cffff9040%d missing|r", totalSlots, missing))
    else
        detailPanel.missingText:SetText("|cffffd200Completing full build sync...|r")
    end

    local mine, admin, loadoutLocked
    if detail then
        mine, admin, loadoutLocked = detail.mine,
            detail.admin, detail.loadoutLocked
    else
        mine, admin, loadoutLocked = IsOwnBuild(build),
            IsAdmin(), HasLeaderboardRecord(build)
    end
    if mine then
        detailPanel.editBtn:Show()
        if IsSavedMirror(build) then
            detailPanel.deleteBtn:Hide()
        else
            detailPanel.deleteBtn:Show()
            detailPanel.deleteBtn:SetText("Stop Sharing")
        end
    elseif admin then
        detailPanel.editBtn:Hide()
        detailPanel.deleteBtn:Show()
        detailPanel.deleteBtn:SetText("Remove")
    else
        detailPanel.editBtn:Hide()
        detailPanel.deleteBtn:Hide()
    end

    if detail then
        if detail.editState then
            detailPanel.editState:SetText(detail.editState)
            detailPanel.editState:Show()
        else
            detailPanel.editState:Hide()
        end
    elseif IsSavedMirror(build) then
        local state = PublishedBuildId(build)
            and "Uploaded. Upload Build again to publish title/description or loadout changes."
            or "Local server loadout. Edit its title/description, then Upload Build when ready."
        detailPanel.editState:SetText(state)
        detailPanel.editState:Show()
    elseif mine and loadoutLocked then
        detailPanel.editState:SetText("|cffffd200Leaderboard loadout locked.|r Title and description may still be edited.")
        detailPanel.editState:Show()
    elseif mine then
        detailPanel.editState:SetText("You own this build. Edit can also replace its Echoes from your active wishlist.")
        detailPanel.editState:Show()
    else
        detailPanel.editState:Hide()
    end

    local controller = ControllerInstance()
    local retryable, _, retryStatus = false, nil, nil
    if mine and type(controller.CanRetryShare) == "function" then
        retryable, _, retryStatus = controller.CanRetryShare(build.id)
    end
    if retryable then
        local generation = retryStatus and retryStatus.generation or 0
        if detailPanel.retryShareBtn._nexusRetryGeneration ~= generation then
            detailPanel.retryShareBtn._nexusRetryGeneration = generation
            detailPanel.retryShareBtn._nexusRetryConsumed = false
        end
        if detailPanel.retryShareBtn._nexusRetryConsumed then
            detailPanel.retryShareBtn:Disable()
        else
            detailPanel.retryShareBtn:Enable()
        end
        detailPanel.lockBtn:Hide()
        detailPanel.retryShareBtn:Show()
    else
        detailPanel.retryShareBtn:Hide()
        detailPanel.lockBtn:Show()
        detailPanel.retryShareBtn._nexusRetryGeneration = nil
        detailPanel.retryShareBtn._nexusRetryConsumed = false
    end
    if detail then
        detailPanel.lockBtn:SetText(detail.actionText)
    elseif IsSavedMirror(build) then
        detailPanel.lockBtn:SetText(
            PublishedBuildId(build) and "Update Upload" or "Upload Build")
    else
        detailPanel.lockBtn:SetText(not hasLoadout and "Request Loadout" or "Copy into Editor")
    end

    -- DPS leaderboards
    local hasDetails = detail and detail.detailsAvailable or false
    if not detail then
        hasDetails = ProjectionContext().detailsAvailable
    end

    local function RecordText(label, rows, personal)
        local top = rows and rows[1]
        local best = top and DpsText(top.dps) or "—"
        local holder = top and tostring(top.player or "Unknown") or "No record yet"
        local yours = personal and DpsText(personal.dps) or "—"
        return string.format("|cffffffff%s|r  |cffffd200%s|r |cff888888%s|r   |cff66ff99Your best %s|r",
            label, best, holder, yours)
    end

    if detail then
        detailPanel.dummyRecord:SetText(detail.dummyRecord)
        detailPanel.lkRecord:SetText(detail.lkRecord)
    else
        local recordId = RecordBuildId(build)
        local dummyLb = ControllerInstance().Leaderboard(
            recordId, "dummy") or {}
        local dummyPB = ControllerInstance().PersonalBest(
            recordId, "dummy")
        local lkLb = ControllerInstance().Leaderboard(
            recordId, "lk") or {}
        local lkPB = ControllerInstance().PersonalBest(recordId, "lk")
        detailPanel.dummyRecord:SetText(RecordText("Training Dummy", dummyLb, dummyPB))
        detailPanel.lkRecord:SetText(RecordText("Lich King", lkLb, lkPB))
    end

    for _, row in ipairs(detailPanel.lbDummyRows) do row:Hide() end
    for _, row in ipairs(detailPanel.lbLKRows) do row:Hide() end
    detailPanel.lbDummyEmpty:Hide(); detailPanel.lbDummyPersonal:Hide()
    detailPanel.lbLKEmpty:Hide(); detailPanel.lbLKPersonal:Hide()

    -- Show/hide the "install Details!" note
    if detailPanel.detailsNote then
        if hasDetails then detailPanel.detailsNote:Hide()
        else detailPanel.detailsNote:Show() end
    end

    detailPanel:Show()
end

------------------------------------------------------------------------
-- Card pool (reuse pre-built frames to avoid GC churn during scroll)
------------------------------------------------------------------------

local cardPool = {}   -- reusable card frames
local activeCards = {}  -- currently visible cards

local function GetCard(parent)
    if #cardPool > 0 then
        local c = table.remove(cardPool)
        c:SetParent(parent)
        c:Show()
        return c
    end

    local card = CreateFrame("Button", nil, parent)
    virtualStats.created = virtualStats.created + 1
    card:SetHeight(CARD_HEIGHT)
    card:EnableMouse(true)

    pcall(function()
        card:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 10,
            insets = { left=3, right=3, top=3, bottom=3 },
        })
        card:SetBackdropColor(0.035, 0.035, 0.045, 0.94)
        card:SetBackdropBorderColor(0.24, 0.24, 0.28, 0.9)
    end)

    card.selectedHighlight = card:CreateTexture(nil, "BACKGROUND")
    card.selectedHighlight:SetAllPoints(card)
    pcall(function() card.selectedHighlight:SetTexture(0.18, 0.38, 0.62, 0.22) end)
    card.selectedHighlight:Hide()

    card.classIcon = card:CreateTexture(nil, "ARTWORK")
    card.classIcon:SetSize(30, 30)
    card.classIcon:SetPoint("TOPLEFT", 10, -9)
    card.classIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.title:SetPoint("TOPLEFT", card.classIcon, "TOPRIGHT", 8, 0)
    card.title:SetSize(250, 16)
    card.title:SetJustifyH("LEFT")

    card.author = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.author:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -2)
    card.author:SetSize(245, 12)
    card.author:SetJustifyH("LEFT")

    card.destination = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.destination:SetPoint("TOPLEFT", card.author, "BOTTOMLEFT", 0, -2)
    card.destination:SetSize(310, 12)
    card.destination:SetJustifyH("LEFT")

    card.echoCount = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    card.echoCount:SetPoint("TOPRIGHT", -12, -9)
    card.echoCount:SetSize(178, 14)
    card.echoCount:SetJustifyH("RIGHT")

    card.dpsBreakdown = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    card.dpsBreakdown:SetPoint("TOPRIGHT", card.echoCount, "BOTTOMRIGHT", 0, -2)
    card.dpsBreakdown:SetSize(220, 12)
    card.dpsBreakdown:SetJustifyH("RIGHT")
    card.dpsBreakdown:SetText("")

    card.icons = {}
    for i = 1, MAX_ROW_ICONS do
        local ic = card:CreateTexture(nil, "ARTWORK")
        ic:SetSize(ICON_SIZE, ICON_SIZE)
        ic:SetPoint("BOTTOMLEFT", 10 + (i-1)*(ICON_SIZE+2), 9)
        ic:Hide()
        card.icons[i] = ic
    end

    card.moreText = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.moreText:SetPoint("LEFT", card.icons[MAX_ROW_ICONS], "RIGHT", 6, 0)
    card.moreText:SetText("")

    card.mineBadge = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    card.mineBadge:SetPoint("BOTTOMRIGHT", -64, 13)
    card.mineBadge:SetSize(70, 12)
    card.mineBadge:SetJustifyH("RIGHT")
    card.mineBadge:Hide()

    card.addBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    card.addBtn:SetSize(52, 22)
    card.addBtn:SetPoint("BOTTOMRIGHT", -8, 7)
    card.addBtn:SetText("View")
    card.addBtn:SetScript("OnClick", function(self)
        local parent = self:GetParent()
        if parent.buildId then
            ControllerInstance().Select(parent.buildId)
            M.Refresh()
        end
    end)
    card.addBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Open build details", 1,1,1)
        GameTooltip:AddLine("Inspect records, exact Echoes, and copy the loadout.", 0.8,0.8,0.8, true)
        GameTooltip:Show()
    end)
    card.addBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Retained for compatibility with older pooled rows; the whole card and
    -- the explicit View button now perform the same clear action.
    card.menuBtn = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
    card.menuBtn:SetSize(1, 1)
    card.menuBtn:SetPoint("BOTTOMRIGHT", -1, 1)
    card.menuBtn:Hide()

    card:SetScript("OnEnter", function(self)
        if not self.buildId then return end
        pcall(function()
            self:SetBackdropColor(0.07, 0.08, 0.11, 0.98)
            self:SetBackdropBorderColor(0.45, 0.55, 0.7, 1)
        end)
        if self._fullTitle and self._displayTitle ~= self._fullTitle then
            GameTooltip:SetOwner(self,"ANCHOR_TOP")
            GameTooltip:AddLine(self._fullTitle,1,0.82,0,true)
            GameTooltip:AddLine(
                "Open build details for the complete title and records.",
                0.8,0.8,0.8,true)
            GameTooltip:Show()
        end
    end)
    card:SetScript("OnLeave", function(self)
        pcall(function()
            self:SetBackdropColor(0.035, 0.035, 0.045, 0.94)
            self:SetBackdropBorderColor(0.24, 0.24, 0.28, 0.9)
        end)
        GameTooltip:Hide()
    end)
    card:SetScript("OnClick", function(self)
        if not self.buildId then return end
        ControllerInstance().Select(self.buildId)
        M.Refresh()
    end)
    if Nexus.Theme and Nexus.Theme.StyleVirtualRow then
        Nexus.Theme.StyleVirtualRow(card, {card.addBtn, card.menuBtn})
    end
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.ApplyFontTree then
        Nexus.LayoutMetrics.ApplyFontTree(card,"normal")
    end
    return card
end

local function ReleaseCard(card)
    card:Hide()
    card:ClearAllPoints()
    card:SetParent(nil)
    cardPool[#cardPool+1] = card
end

local function ReleaseAllCards()
    for _, c in ipairs(activeCards) do ReleaseCard(c) end
    activeCards = {}
end

------------------------------------------------------------------------
-- Class header frames
------------------------------------------------------------------------

local headerPool = {}
local activeHeaders = {}

local function GetHeader(parent)
    if #headerPool > 0 then
        local h = table.remove(headerPool)
        h:SetParent(parent); h:Show(); return h
    end
    local h = CreateFrame("Frame", nil, parent)
    h:SetHeight(22)
    h.label = h:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    h.label:SetPoint("BOTTOMLEFT",2,-2)
    h.sep = h:CreateTexture(nil,"ARTWORK")
    h.sep:SetHeight(1)
    h.sep:SetPoint("BOTTOMLEFT",h,"BOTTOMLEFT",0,0)
    h.sep:SetPoint("BOTTOMRIGHT",h,"BOTTOMRIGHT",0,0)
    pcall(function() h.sep:SetTexture(0.4,0.4,0.4,0.6) end)
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.ApplyFontTree then
        Nexus.LayoutMetrics.ApplyFontTree(h,"normal")
    end
    return h
end
local function ReleaseHeader(h)
    h:Hide(); h:ClearAllPoints(); h:SetParent(nil)
    headerPool[#headerPool+1] = h
end
local function ReleaseAllHeaders()
    for _, h in ipairs(activeHeaders) do ReleaseHeader(h) end
    activeHeaders = {}
end

------------------------------------------------------------------------
-- Main frame construction
------------------------------------------------------------------------

local function EnsureFrame()
    if frame then return frame end

    -- Main browser window: list and detail panel live together in one surface.
    frame = CreateFrame("Frame","NexusCommunityBuildsFrame",UIParent)
    frame:SetClampedToScreen(true)
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "NexusCommunityBuildsFrame")
    end
    frame:SetSize(1040,640)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetFrameLevel(50)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart",function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local retryTicker, statusTicker, dataTicker = 0, 0, 0
    local lastReceiving = false
    frame:SetScript("OnUpdate",function(self,elapsed)
        if not self:IsShown() then return end
        local controller = ControllerInstance()
        local receivingNow = Nexus.Sync and Nexus.Sync.IsReceiving
            and Nexus.Sync.IsReceiving() or false
        retryTicker = retryTicker + elapsed
        if retryTicker >= 0.5 then
            retryTicker = 0
            PumpPendingLockIn()
        end

        -- Keep the live sync label responsive without rebuilding and sorting
        -- the entire build library every half second. The old full refresh was
        -- especially expensive with 100+ builds because it also resolved DPS
        -- records, recreated every card and recursively restyled the frame.
        local receiveEnded = false
        statusTicker = statusTicker + elapsed
        if statusTicker >= 0.25 then
            statusTicker = 0
            local receiveCount = Nexus.Sync and Nexus.Sync.LastSyncNewCount and Nexus.Sync.LastSyncNewCount() or 0
            if receivingNow and syncStatusText and Nexus.Sync
                and RenderSyncStatus then
                RenderSyncStatus(receiveCount)
            end

            -- Build/DPS revisions mark the view dirty while Sync is active.
            -- Publish once when that burst ends; changing the live count alone
            -- is status work and must not rebuild the catalog.
            receiveEnded = lastReceiving and not receivingNow
            lastReceiving = receivingNow
        end

        if type(controller.HasPendingSavedLoadoutImport) == "function"
            and controller.HasPendingSavedLoadoutImport() then
            local _, pending = PrepareData(false)
            if not pending then M.Refresh() end
        end
        if receiveEnded and refreshDirty then
            virtualStats.deferredRefreshes =
                virtualStats.deferredRefreshes + 1
            M.Refresh()
            return
        end
        local projections = Nexus and Nexus.ViewProjections
        local coldStart = virtualStats.dataBinds == 0
        if projections and (not receivingNow or coldStart)
            and type(projections.PumpBuilds) == "function" then
            -- A receive window may already be active when the browser first
            -- opens. Keep that cold persisted projection moving, but retain an
            -- existing last-good publication until the burst becomes quiet.
            if receivingNow and coldStart then M.Refresh() end
            local ok, published, pumpError = pcall(projections.PumpBuilds)
            if ok and published then M.Refresh() end
            if ok and pumpError then M.Refresh() end
        end

        -- Cheap safety probe for missed invalidations. An unchanged tick does
        -- not request/copy the cached projection or sort/rebind any rows.
        dataTicker = dataTicker + elapsed
        if dataTicker >= 8.0 then
            dataTicker = 0
            local projection = EnsureCommunityProjection()
            local current = nil
            if projection and type(projection.ListCurrent) == "function" then
                local ok, result = pcall(projection.ListCurrent,
                    FilterSettings())
                if ok then current = result end
            else
                local projections = Nexus and Nexus.ViewProjections
                if projections and type(projections.BuildsCurrent) == "function" then
                    local ok, result = pcall(projections.BuildsCurrent,
                        FilterSettings())
                    if ok then current = result end
                end
            end
            local receiving = Nexus.Sync and Nexus.Sync.IsReceiving
                and Nexus.Sync.IsReceiving() or false
            -- Preserve the result of work the safety probe already performed.
            -- This keeps diagnostics truthful during a receive window even if
            -- the normal revision notification was missed, without adding a
            -- second currentness read to DiagnosticSnapshot.
            if current ~= true then
                viewDiagnostic.projectionCurrent = false
            end
            -- A missing/failing dirty probe must retain the old safe behavior:
            -- attempt the refresh instead of treating an unknown state as
            -- current forever.
            if not receiving and (refreshDirty or current ~= true) then
                M.Refresh()
            else
                virtualStats.periodicSkips = virtualStats.periodicSkips + 1
            end
        end
    end)
    frame:Hide()
    frame:HookScript("OnHide",function()
        if dropPanel then dropPanel:Hide() end
        if sortPanel then sortPanel:Hide() end
        if dropdownShield then dropdownShield:Hide() end
    end)

    pcall(function()
        frame:SetBackdrop({
            bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",
            tile=true, tileSize=32, edgeSize=32,
            insets={left=11,right=12,top=12,bottom=11},
        })
    end)
    pcall(function() frame:SetBackdropColor(0.16,0.165,0.175,0.90) end)

    -- Title bar ---------------------------------------------------------
    local titleText = frame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    titleText:SetPoint("TOP",0,-12)
    titleText:SetJustifyH("CENTER")
    frame._titleText = titleText
    titleText:SetText("Nexus  —  Builds")

    local closeBtn = CreateFrame("Button",nil,frame,"UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT",-6,-6)

    -- A single click-away layer and one-open-menu rule make every selector
    -- behave like the same control instead of three unrelated popup frames.
    dropdownShield = CreateFrame("Button","NexusBuildDropdownShield",UIParent)
    dropdownShield:SetAllPoints(UIParent)
    dropdownShield:SetFrameStrata("DIALOG")
    dropdownShield:SetFrameLevel(frame:GetFrameLevel() - 1)
    dropdownShield:EnableMouse(true)
    dropdownShield:Hide()

    local function CloseDropdowns()
        if dropPanel then dropPanel:Hide() end
        if sortPanel then sortPanel:Hide() end
        if dropdownShield then dropdownShield:Hide() end
    end
    dropdownShield:SetScript("OnClick", CloseDropdowns)

    local function OpenDropdown(panel, anchor)
        local wasShown = panel and panel:IsShown()
        CloseDropdowns()
        if wasShown or not panel then return end
        panel:ClearAllPoints()
        panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -3)
        panel:SetFrameStrata("TOOLTIP")
        panel:SetFrameLevel(dropdownShield:GetFrameLevel() + 2)
        dropdownShield:Show()
        panel:Show()
    end

    local function StyleDropdownPanel(panel)
        panel:EnableMouse(true)
        panel:Hide()
        pcall(function()
            panel:SetBackdrop({
                bgFile="Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
                tile=true, tileSize=16, edgeSize=12,
                insets={left=4,right=4,top=4,bottom=4},
            })
            panel:SetBackdropColor(0.02,0.02,0.025,0.99)
            panel:SetBackdropBorderColor(0.55,0.45,0.22,1)
        end)
    end

    local function AddDropdownRow(panel, entry, index, width, selectedFn, onSelect, color)
        local item = entry
        local row = CreateFrame("Button",nil,panel)
        row:SetSize(width - 10,24)
        row:SetPoint("TOPLEFT",5,-(5+(index-1)*24))
        row:EnableMouse(true)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        local check = row:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        check:SetPoint("LEFT",7,0)
        check:SetText(">")
        local label = row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        label:SetPoint("LEFT",check,"RIGHT",7,0)
        label:SetPoint("RIGHT",row,"RIGHT",-8,0)
        label:SetJustifyH("LEFT")
        label:SetText(item.label)
        if color then label:SetTextColor(color[1],color[2],color[3]) end
        row._entry, row._check, row._label = item, check, label
        row:SetScript("OnClick",function()
            onSelect(item)
            CloseDropdowns()
            M.Refresh()
        end)
        panel._rows = panel._rows or {}
        panel._rows[#panel._rows+1] = row
        row._selectedFn = selectedFn
        return row
    end

    local function RefreshDropdown(panel)
        if not panel or not panel._rows then return end
        for _, row in ipairs(panel._rows) do
            local selected = row._selectedFn and row._selectedFn(row._entry)
            if selected then
                row._check:Show()
                row._label:SetTextColor(1,0.82,0.2)
            else
                row._check:Hide()
                local key = row._entry and row._entry.key
                local c = key and CLASS_COLOR[key]
                if c then row._label:SetTextColor(c[1],c[2],c[3])
                else row._label:SetTextColor(0.92,0.92,0.92) end
            end
        end
    end
    frame._CloseDropdowns = CloseDropdowns
    frame._RefreshDropdown = RefreshDropdown

    local function StyleSelectorButton(button)
        button:SetNormalFontObject("GameFontHighlightSmall")
        button:SetHighlightFontObject("GameFontNormalSmall")
        button:SetPushedTextOffset(0, -1)
        if not button._arrow then
            local arrow = button:CreateTexture(nil, "OVERLAY")
            arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
            arrow:SetSize(12, 12)
            arrow:SetPoint("RIGHT", button, "RIGHT", -7, 0)
            arrow:SetTexCoord(0, 1, 0, 1)
            button._arrow = arrow
        end
        local fs = button:GetFontString()
        if fs then
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", button, "LEFT", 9, 0)
            fs:SetPoint("RIGHT", button, "RIGHT", -22, 0)
            fs:SetJustifyH("CENTER")
        end
        pcall(function()
            button:SetBackdrop({
                bgFile="Interface\\Buttons\\WHITE8X8",
                edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
                tile=false, edgeSize=10,
                insets={left=2,right=2,top=2,bottom=2},
            })
            button:SetBackdropColor(0.025,0.03,0.04,0.96)
            button:SetBackdropBorderColor(0.38,0.38,0.42,0.95)
        end)
        button:SetScript("OnEnter", function(self)
            pcall(function() self:SetBackdropBorderColor(0.9,0.72,0.25,1) end)
        end)
        button:SetScript("OnLeave", function(self)
            pcall(function() self:SetBackdropBorderColor(0.38,0.38,0.42,0.95) end)
            GameTooltip:Hide()
        end)
    end

    -- Primary navigation is centered and visually separate from filtering.
    local navBar = CreateFrame("Frame",nil,frame)
    navBar:SetSize(314,24)
    navBar:SetPoint("TOPLEFT",18,-12)
    frame._navBar = navBar

    local buildsTab = CreateFrame("Button",nil,navBar,"UIPanelButtonTemplate")
    buildsTab:SetSize(92,22)
    buildsTab:SetPoint("LEFT",0,0)
    buildsTab:SetText("|cffffd200Builds|r")
    buildsTab:Disable()

    leaderboardBtn = CreateFrame("Button",nil,navBar,"UIPanelButtonTemplate")
    leaderboardBtn:SetSize(112,22)
    leaderboardBtn:SetPoint("LEFT",buildsTab,"RIGHT",4,0)
    leaderboardBtn:SetText("Leaderboard")
    leaderboardBtn:SetScript("OnClick",function()
        CloseDropdowns()
        frame:Hide()
        if Nexus.Leaderboard then Nexus.Leaderboard.Show() end
    end)

    wishlistBtn = CreateFrame("Button",nil,navBar,"UIPanelButtonTemplate")
    wishlistBtn:SetSize(98,22)
    wishlistBtn:SetPoint("LEFT",leaderboardBtn,"RIGHT",4,0)
    wishlistBtn:SetText("Wishlists")
    wishlistBtn:SetScript("OnClick",function()
        CloseDropdowns()
        frame:Hide()
        if Nexus.WishlistEditor then Nexus.WishlistEditor.Show() end
    end)

    -- Browse toolbar ----------------------------------------------------
    local browseLabel = frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    browseLabel:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -64)
    frame._browseLabel = browseLabel
    browseLabel:SetText("BROWSE BUILDS")

    local actionLabel = frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    actionLabel:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -64)
    frame._actionLabel = actionLabel
    actionLabel:SetText("ACTIONS")

    searchBox = CreateFrame("EditBox","NexusBuildsSearch",frame,"InputBoxTemplate")
    frame._searchBox = searchBox
    searchBox:SetSize(165,22)
    searchBox:SetPoint("TOPLEFT",20,-78)
    searchBox:SetAutoFocus(false)
    searchBox:SetText(FilterSettings().search or "")
    searchBox:SetScript("OnTextChanged",function(self)
        if clearSearchBtn then
            if (self:GetText() or "") ~= "" then clearSearchBtn:Show()
            else clearSearchBtn:Hide() end
        end
        if suppressSearchChange then return end
        ControllerInstance().SetFilter("search", self:GetText() or "")
        M.Refresh()
    end)
    local searchLabel = frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    searchLabel:SetPoint("LEFT",searchBox,"LEFT",6,0)
    searchLabel:SetText("Search title, author, or description...")
    searchBox:SetScript("OnEditFocusGained",function() searchLabel:Hide(); CloseDropdowns() end)
    searchBox:SetScript("OnEditFocusLost",function(self)
        if self:GetText() == "" then searchLabel:Show() end
    end)
    if (FilterSettings().search or "") ~= "" then searchLabel:Hide() end

    clearSearchBtn = CreateFrame("Button",nil,searchBox,"UIPanelButtonTemplate")
    frame._clearSearchBtn = clearSearchBtn
    clearSearchBtn:SetSize(82,18)
    clearSearchBtn:SetPoint("RIGHT",searchBox,"RIGHT",-2,0)
    clearSearchBtn:SetText("Clear Search")
    pcall(function() searchBox:SetTextInsets(6,86,0,0) end)
    if (FilterSettings().search or "") == "" then clearSearchBtn:Hide() end
    clearSearchBtn:SetScript("OnClick",function()
        local filters = FilterSettings()
        local requestedPage = math.max(1,math.floor(tonumber(filters.page) or 1))
        ControllerInstance().SetFilter("search", "")
        suppressSearchChange = true
        searchBox:SetText("")
        suppressSearchChange = false
        ControllerInstance().SetFilter("page", requestedPage)
        searchLabel:Show()
        clearSearchBtn:Hide()
        M.Refresh()
    end)

    -- Library scope is a direct two-button selector instead of a hidden dropdown.
    scopeBtn = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    frame._scopeBtn = scopeBtn
    scopeBtn:SetSize(84,22)
    scopeBtn:SetPoint("LEFT",searchBox,"RIGHT",8,0)
    scopeBtn:SetText("All Shared")
    scopeBtn:SetScript("OnClick",function()
        ControllerInstance().SetFilter("scope", "all")
        ControllerInstance().ClearSelection()
        CloseDropdowns()
        M.Refresh()
    end)
    scopeBtn:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("All Shared",1,0.82,0.2)
        GameTooltip:AddLine("Browse shared community builds.",0.8,0.8,0.8,true)
        GameTooltip:Show()
    end)
    scopeBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)

    myBuildsBtn = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    frame._myBuildsBtn = myBuildsBtn
    myBuildsBtn:SetSize(84,22)
    myBuildsBtn:SetPoint("LEFT",scopeBtn,"RIGHT",4,0)
    myBuildsBtn:SetText("My Builds")
    myBuildsBtn:SetScript("OnClick",function()
        ControllerInstance().SetFilter("scope", "mine")
        ControllerInstance().ClearSelection()
        CloseDropdowns()
        M.Refresh()
    end)
    myBuildsBtn:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("My Builds",1,0.82,0.2)
        GameTooltip:AddLine("Open your saved loadouts and uploaded builds.",0.8,0.8,0.8,true)
        GameTooltip:Show()
    end)
    myBuildsBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)

    classDropBtn = CreateFrame("Button",nil,frame)
    classDropBtn:SetSize(128,22)
    classDropBtn:SetPoint("LEFT",myBuildsBtn,"RIGHT",6,0)
    frame._classDropBtn = classDropBtn
    StyleSelectorButton(classDropBtn)
    classDropBtn:SetScript("OnClick",function()
        local filters = FilterSettings()
        ControllerInstance().SetFilter("currentClassOnly",
            filters.currentClassOnly == false)
        ControllerInstance().ClearSelection()
        CloseDropdowns()
        M.Refresh()
    end)
    classDropBtn:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Current Class Only",1,0.82,0.2)
        GameTooltip:AddLine("Turn off to include every class; missing class data is shown as Unknown.",0.8,0.8,0.8,true)
        GameTooltip:Show()
    end)
    classDropBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)
    -- Preserve the established named frame for compatibility. The class
    -- choice is now a direct two-state control, so the shell stays hidden.
    dropPanel = CreateFrame("Frame","NexusClassDropPanel",UIParent)
    dropPanel:SetSize(138,10)
    StyleDropdownPanel(dropPanel)
    dropPanel:Hide()

    qualifiedBtn = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    qualifiedBtn:SetSize(112,22)
    qualifiedBtn:SetPoint("LEFT",classDropBtn,"RIGHT",6,0)
    frame._qualifiedBtn = qualifiedBtn
    qualifiedBtn:SetScript("OnClick",function()
        local filters = FilterSettings()
        ControllerInstance().SetFilter("qualifiedOnly",
            filters.qualifiedOnly == false)
        ControllerInstance().ClearSelection()
        CloseDropdowns()
        M.Refresh()
    end)
    qualifiedBtn:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Qualified Only",1,0.82,0.2)
        GameTooltip:AddLine("Turn off to include shared builds missing one or both ranked records.",0.8,0.8,0.8,true)
        GameTooltip:Show()
    end)
    qualifiedBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)

    local sorts={{key="dps",label="Highest DPS"},{key="recent",label="Newest"},{key="title",label="Name"}}
    sortToggle = CreateFrame("Button",nil,frame)
    sortToggle:SetSize(126,22)
    sortToggle:SetPoint("LEFT",qualifiedBtn,"RIGHT",6,0)
    frame._sortToggle = sortToggle
    StyleSelectorButton(sortToggle)
    sortPanel = CreateFrame("Frame","NexusBuildSortPanel",UIParent)
    sortPanel:SetSize(134,#sorts*24+10)
    StyleDropdownPanel(sortPanel)
    for i,entry in ipairs(sorts) do
        AddDropdownRow(sortPanel,entry,i,134,
            function(item) return (FilterSettings().sortMode or "dps") == item.key end,
            function(item)
                ControllerInstance().SetFilter("sortMode", item.key)
            end)
    end
    sortToggle:SetScript("OnClick",function(self) OpenDropdown(sortPanel,self) end)
    sortToggle:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Sort builds",1,1,1)
        GameTooltip:AddLine("Eligible builds use only the selected order.",0.8,0.8,0.8,true)
        GameTooltip:Show()
    end)
    sortToggle:SetScript("OnLeave",function() GameTooltip:Hide() end)

    syncBtn = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    syncBtn:SetSize(88,22)
    syncBtn:SetPoint("TOPRIGHT",-132,-78)
    frame._syncBtn = syncBtn
    syncBtn:SetText("Sync Now")
    syncBtn:SetScript("OnClick",function()
        CloseDropdowns()
        local ok, err, available = ControllerInstance().RequestSync()
        if not available then return end
        if ok then print("|cff7fd5ffNexus:|r asking other players for their builds...")
        else print("|cffff6060Nexus:|r "..tostring(err)) end
    end)
    syncBtn:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Refresh community data",1,1,1)
        GameTooltip:AddLine("Ask nearby Nexus users for builds and DPS records.",0.8,0.8,0.8,true)
        GameTooltip:Show()
    end)
    syncBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)

    local postBtn = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    postBtn:SetSize(110,22)
    postBtn:SetPoint("TOPRIGHT",-15,-78)
    frame._postBtn = postBtn
    postBtn:SetText("Share Build")
    postBtn:SetScript("OnClick",function() CloseDropdowns(); M.ShowPostBuild() end)
    postBtn:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:AddLine("Share a build",1,1,1)
        GameTooltip:AddLine("Choose a saved loadout or wishlist, then add its title and description.",0.8,0.8,0.8,true)
        GameTooltip:Show()
    end)
    postBtn:SetScript("OnLeave",function() GameTooltip:Hide() end)

    resultText = frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    resultText:SetPoint("TOPLEFT",20,-108)
    resultText:SetSize(180,16)
    resultText:SetJustifyH("LEFT")
    frame._resultText = resultText

    prevPageBtn = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    prevPageBtn:SetSize(48,20)
    prevPageBtn:SetPoint("TOPLEFT",202,-104)
    prevPageBtn:SetText("Prev")
    frame._prevPageBtn = prevPageBtn
    prevPageBtn:SetScript("OnClick",function()
        local filters = FilterSettings()
        if (filters.page or 1) <= 1 then return end
        ControllerInstance().SetFilter("page", (filters.page or 1) - 1)
        if scrollBar then scrollBar.value = 0 end
        M.Refresh()
    end)

    pageText = frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    pageText:SetPoint("TOPLEFT",254,-108)
    pageText:SetSize(62,16)
    pageText:SetJustifyH("CENTER")
    frame._pageText = pageText

    nextPageBtn = CreateFrame("Button",nil,frame,"UIPanelButtonTemplate")
    nextPageBtn:SetSize(48,20)
    nextPageBtn:SetPoint("TOPLEFT",320,-104)
    nextPageBtn:SetText("Next")
    frame._nextPageBtn = nextPageBtn
    nextPageBtn:SetScript("OnClick",function()
        local filters = FilterSettings()
        ControllerInstance().SetFilter("page", (filters.page or 1) + 1)
        if scrollBar then scrollBar.value = 0 end
        M.Refresh()
    end)

    syncStatusText = frame:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    frame._syncStatusText = syncStatusText
    syncStatusText:SetPoint("TOPLEFT",378,-108)
    syncStatusText:SetSize(632,14)
    syncStatusText:SetJustifyH("LEFT")

    -- Left: scrollable card list -----------------------------------------
    -- Clip region (SetClipsChildren is retail-only on 3.3.5 -- same class
    -- of API as SetColorTexture; wrap defensively so everything below still
    -- gets created even if this call throws)
    local listClip = CreateFrame("Frame",nil,frame)
    listClip:SetPoint("TOPLEFT",20,-130)
    listClip:SetPoint("BOTTOMLEFT",20,20)
    listClip:SetWidth(480)
    frame._listClip = listClip
    pcall(function() listClip:SetClipsChildren(true) end)

    scrollFrame = CreateFrame("ScrollFrame",nil,listClip)
    scrollFrame:SetAllPoints(listClip)
    scrollFrame:EnableMouseWheel(true)

    scrollChild = CreateFrame("Frame",nil,scrollFrame)
    scrollChild:SetWidth(460)
    scrollChild:SetHeight(1)     -- set dynamically in Refresh
    scrollFrame:SetScrollChild(scrollChild)

    -- Simple scroll offset tracking -- no template, no SetVerticalScroll,
    -- just keep an offset and SetVerticalScroll via pcall (different API
    -- names across WoW versions).
    scrollBar = { value = 0, min = 0, max = 0 }  -- plain table, no template
    local function SetScroll(val)
        val = math.max(scrollBar.min, math.min(scrollBar.max, val))
        scrollBar.value = val
        pcall(function() scrollFrame:SetVerticalScroll(val) end)
        if renderBuildWindow and frame and frame:IsShown()
            and not virtualBinding then
            Measure("community.render", renderBuildWindow, "scroll")
        end
    end
    scrollBar.SetValue = function(_, val) SetScroll(val) end
    scrollBar.GetValue = function(_) return scrollBar.value end
    scrollBar.SetMinMaxValues = function(_, mn, mx) scrollBar.min = mn; scrollBar.max = mx end
    scrollBar.GetMinMaxValues = function(_) return scrollBar.min, scrollBar.max end

    scrollFrame:SetScript("OnMouseWheel",function(_,delta)
        SetScroll(scrollBar.value - delta * CARD_HEIGHT * 3)
    end)
    scrollFrame:SetScript("OnSizeChanged", function()
        if renderBuildWindow and frame and frame:IsShown()
            and not virtualBinding then
            Measure("community.render", renderBuildWindow, "resize")
        end
    end)
    frame._virtualListScrollFrame = scrollFrame

    local emptyState = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyState:SetPoint("TOPLEFT", listClip, "TOPLEFT", 20, 34)
    emptyState:SetSize(400, 80)
    emptyState:SetJustifyH("CENTER")
    emptyState:SetJustifyV("TOP")
    emptyState:Hide()
    frame._emptyState = emptyState

    -- Right: detail panel ------------------------------------------------
    EnsureDetailPanel(frame)
    frame._detailPanel = detailPanel
    detailPanel:ClearAllPoints()
    detailPanel:SetPoint("TOPLEFT", frame, "TOPLEFT", 520, -130)
    detailPanel:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -20, 20)
    detailPanel:SetFrameLevel(frame:GetFrameLevel() + 10)

    -- Style the static browser controls once. Dynamic cards are created from
    -- an already dark template and do not need a full recursive restyle on
    -- every refresh.
    if Nexus.Theme then Nexus.Theme.StyleTree(frame) end
    M.ApplyResponsiveLayout(true)
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.ApplyFontTree then
        Nexus.LayoutMetrics.ApplyFontTree(frame,"normal")
        Nexus.LayoutMetrics.ApplyFontTree(dropPanel,"normal")
        Nexus.LayoutMetrics.ApplyFontTree(sortPanel,"normal")
        frame._nexusOwnedFonts = true
    end
    return frame
end


function M.GetSelectedBuildForPanel()
    if not frame or not frame:IsShown() then return nil end
    return ControllerInstance().SelectedBuild()
end

function M.GetSelectedBuildForPanelKey()
    if not frame or not frame:IsShown() then return nil, 0, 0 end
    return ControllerInstance().SelectedBuildKey()
end

function M.VirtualStats()
    local out = {}
    for key, value in pairs(virtualStats) do out[key] = value end
    out.selectedId = SelectedId()
    out.refreshDirty = refreshDirty
    out.savedImport = ControllerInstance().SavedImportStats()
    return out
end

local function ReadViewStatus()
    local controller = ControllerInstance()
    if not (controller and type(controller.ViewDiagnosticState) == "function") then
        return {}
    end
    local ok, value = pcall(controller.ViewDiagnosticState)
    return ok and type(value) == "table" and value or {}
end

RenderSyncStatus = function(receiveCount)
    if not (syncStatusText and Nexus and Nexus.Sync) then return end
    local sync = Nexus.Sync
    local published = viewDiagnostic.publishedPage > 0
    local base = published and {} or ReadViewStatus()
    local bundled = published and viewDiagnostic.bundledCount
        or (base.bundledCount or 0)
    local overlay = published and viewDiagnostic.overlayCount
        or (base.overlayCount or 0)
    local available = published and viewDiagnostic.availableCount
        or (base.availableCount or 0)
    local shown = viewDiagnostic.displayedCount or 0
    local results = viewDiagnostic.resultCount or 0
    local version = published and viewDiagnostic.catalogVersion
        or (base.catalogVersion or "unversioned")
    local receiving = type(sync.IsReceiving) == "function"
        and sync.IsReceiving() == true
    if receiving then
        receiveCount = tonumber(receiveCount)
            or (type(sync.LastSyncNewCount) == "function"
                and tonumber(sync.LastSyncNewCount())) or 0
        local remaining = type(sync.ReceiveTimeLeft) == "function"
            and tonumber(sync.ReceiveTimeLeft()) or 0
        syncStatusText:SetText(string.format(
            "|cff4dff80Listening %ds (%d new); %d bundled + %d overlay; %d available; %d shown of %d results|r",
            math.ceil(math.max(0,remaining)),receiveCount,bundled,overlay,
            available,shown,results))
    else
        local stats = type(sync.Stats) == "function" and sync.Stats() or {}
        local received = type(stats) == "table"
            and (tonumber(stats.received) or 0) or 0
        local added = type(sync.LastSyncNewCount) == "function"
            and (tonumber(sync.LastSyncNewCount()) or 0) or 0
        if received > 0 then
            syncStatusText:SetText(string.format(
                "|cff888888%d bundled + %d overlay; %d available; %d shown of %d results. Last sync added %d; catalog %s.|r",
                bundled,overlay,available,shown,results,added,version))
        else
            syncStatusText:SetText(string.format(
                "|cff888888%d bundled + %d overlay; %d available; %d shown of %d results; catalog %s. Sync Now checks the nearby mesh.|r",
                bundled,overlay,available,shown,results,version))
        end
    end
    if syncBtn then syncBtn:SetText(receiving and "Listening..." or "Sync Now") end
end

function M.DiagnosticSnapshot()
    local base = ReadViewStatus()
    local current = viewDiagnostic.projectionCurrent == true
    local receiving = false
    local sync = Nexus and Nexus.Sync
    if sync and type(sync.IsReceiving) == "function" then
        local ok, value = pcall(sync.IsReceiving)
        receiving = ok and value == true
    end
    local shown = frame and frame:IsShown() or false
    local dirty = refreshDirty or not current
    local reason
    if not shown then reason = "hidden"
    elseif base.filterScope == "mine" and base.savedImportPending then
        reason = "saved-import"
    elseif viewDiagnostic.projectionPending then reason = "projection-pending"
    elseif viewDiagnostic.projectionError then reason = "projection-error"
    elseif dirty and receiving and viewDiagnostic.publishedPage > 0 then
        reason = "sync-receiving"
    elseif dirty then reason = "dirty"
    elseif viewDiagnostic.publishedPage == 0 then reason = "not-published"
    else reason = "none" end
    return {
        schema=1,view="community",
        catalogCount=base.catalogCount or 0,
        bundledCount=viewDiagnostic.publishedPage > 0
            and viewDiagnostic.bundledCount or (base.bundledCount or 0),
        overlayCount=viewDiagnostic.publishedPage > 0
            and viewDiagnostic.overlayCount or (base.overlayCount or 0),
        availableCount=viewDiagnostic.publishedPage > 0
            and viewDiagnostic.availableCount or (base.availableCount or 0),
        filterMatchedCount=viewDiagnostic.filterMatchedCount,
        qualifyingCount=viewDiagnostic.qualifyingCount,
        resultCount=viewDiagnostic.resultCount,
        displayedCount=viewDiagnostic.displayedCount,
        searchActive=viewDiagnostic.publishedPage > 0
            and viewDiagnostic.searchActive or base.filterSearchActive == true,
        catalogVersion=viewDiagnostic.publishedPage > 0
            and viewDiagnostic.catalogVersion
            or (base.catalogVersion or "unversioned"),
        requestedPage=base.requestedPage or 1,
        publishedPage=viewDiagnostic.publishedPage,
        pageCount=viewDiagnostic.publishedPage > 0
            and lastPublishedPageCount or 0,
        publishedRows=viewDiagnostic.publishedPage > 0
            and virtualStats.results or 0,
        filterScope=base.filterScope or "all",
        filterClass=base.filterClass or "UNAVAILABLE",
        filterCurrentClassOnly=base.filterCurrentClassOnly ~= false,
        filterQualifiedOnly=base.filterQualifiedOnly ~= false,
        filterSearchActive=base.filterSearchActive == true,
        filterSort=base.filterSort or "dps",filterCategory="builds",
        projectionCurrent=current,projectionPending=
            viewDiagnostic.projectionPending == true,
        projectionDirty=dirty,savedImportPending=
            base.savedImportPending == true,
        savedImportPhase=base.savedImportPhase or "unknown",
        syncReceiving=receiving,
        lastPublicationAge=PublicationAge(viewDiagnostic.publishedAt),
        blockedReason=reason,
    }
end

function M.MarkDataDirty()
    if not refreshDirty then
        refreshDirty = true
        virtualStats.dirtyMarks = virtualStats.dirtyMarks + 1
    end
    viewDiagnostic.projectionPending = false
    viewDiagnostic.projectionError = false
    viewDiagnostic.projectionCurrent = false
    return true
end

function M.ScrollTo(offset)
    if not scrollBar then return false end
    scrollBar:SetValue(tonumber(offset) or 0)
    return true
end

------------------------------------------------------------------------
-- Refresh  (called every tick while open, and whenever data changes)
------------------------------------------------------------------------

function M.Refresh()
    if not frame or not frame:IsShown() then return end
    M.ApplyResponsiveLayout(false)

    -- Update control labels
    local fs = FilterSettings()
    if classDropBtn then
        if fs.currentClassOnly == false then
            classDropBtn:SetText("All Classes")
        elseif fs.classFilter then
            classDropBtn:SetText("Current Class Only")
        else
            classDropBtn:SetText("Class Loading...")
        end
    end
    if qualifiedBtn then
        qualifiedBtn:SetText(fs.qualifiedOnly == false
            and "All Shared" or "Qualified Only")
    end
    if scopeBtn and myBuildsBtn then
        if fs.scope == "mine" then
            scopeBtn:Enable()
            myBuildsBtn:Disable()
        else
            scopeBtn:Disable()
            myBuildsBtn:Enable()
        end
    end
    if sortToggle then
        if fs.sortMode == "class" or not fs.sortMode then fs.sortMode = "dps" end
        local labels={dps="Highest DPS",recent="Newest",title="Name"}
        sortToggle:SetText("Sort: "..(labels[fs.sortMode] or "Highest DPS"))
        sortToggle:Show()
    end
    if frame._RefreshDropdown then
        frame._RefreshDropdown(dropPanel)
        frame._RefreshDropdown(sortPanel)
    end

    -- A page click is cheap state too. Show the requested page immediately
    -- while retaining both the last-good rows and their last published bound
    -- until the deferred projection can clamp and publish the new result.
    local requestedPage = math.max(1, math.floor(tonumber(fs.page) or 1))
    local visiblePageCount = math.max(requestedPage, lastPublishedPageCount)
    if pageText then
        pageText:SetText(string.format("%d / %d", requestedPage,
            visiblePageCount))
    end
    if prevPageBtn and nextPageBtn then
        if requestedPage > 1 then prevPageBtn:Enable()
        else prevPageBtn:Disable() end
        if requestedPage < visiblePageCount then nextPageBtn:Enable()
        else nextPageBtn:Disable() end
    end

    -- Import/projection work may be deferred for many frames. Keep the cheap
    -- filter, scope, sort, and page controls truthful before that gate so the
    -- visible browser never looks frozen while its last-good rows stay bound.
    local controller = ControllerInstance()
    local importPending = fs.scope == "mine"
        and type(controller.HasPendingSavedLoadoutImport) == "function"
        and controller.HasPendingSavedLoadoutImport()
    if importPending then
        refreshDirty = true
        viewDiagnostic.projectionPending = false
        viewDiagnostic.projectionError = false
        viewDiagnostic.projectionCurrent = false
        RenderSyncStatus()
        return false, "pending"
    end

    -- Build browser contains builds only. DPS rankings are rendered in the
    -- dedicated Leaderboard window.
    local boardRows = nil
    local builds, projectionSummary, projectionError =
        Measure("community.projection", SortedBuilds)
    if type(builds) ~= "table" then
        if projectionError == "pending" then
            refreshDirty = true
            viewDiagnostic.projectionPending = true
            viewDiagnostic.projectionError = false
            viewDiagnostic.projectionCurrent = false
            RenderSyncStatus()
            return false, "pending"
        end
        refreshDirty = true
        viewDiagnostic.projectionPending = false
        viewDiagnostic.projectionError = true
        viewDiagnostic.projectionCurrent = false
        virtualStats.dataFailures = virtualStats.dataFailures + 1
        RenderSyncStatus()
        return false, projectionError
    end
    if projectionSummary and fs.page ~= projectionSummary.page then
        ControllerInstance().SetFilter("page", projectionSummary.page)
        fs.page = projectionSummary.page
    end
    if projectionSummary then
        viewDiagnostic.bundledCount = math.max(0,math.floor(tonumber(
            projectionSummary.bundledCount) or 0))
        viewDiagnostic.overlayCount = math.max(0,math.floor(tonumber(
            projectionSummary.overlayCount) or 0))
        viewDiagnostic.availableCount = math.max(0,math.floor(tonumber(
            projectionSummary.availableCount) or 0))
        viewDiagnostic.filterMatchedCount = math.max(0,math.floor(tonumber(
            projectionSummary.filterMatchedCount) or 0))
        viewDiagnostic.qualifyingCount = math.max(0,math.floor(tonumber(
            projectionSummary.qualifyingCount) or 0))
        viewDiagnostic.resultCount = math.max(0,math.floor(tonumber(
            projectionSummary.resultCount) or 0))
        viewDiagnostic.displayedCount = math.max(0,math.floor(tonumber(
            projectionSummary.displayedCount) or #builds))
        viewDiagnostic.searchActive = projectionSummary.searchActive == true
        viewDiagnostic.catalogVersion = tostring(
            projectionSummary.catalogVersion or "unversioned"):sub(1,64)
    end
    RenderSyncStatus()
    lastPublishedPageCount = math.max(1,
        tonumber(projectionSummary and projectionSummary.pageCount) or 1)
    if pageText and projectionSummary then
        pageText:SetText(string.format("%d / %d",
            projectionSummary.page or 1, projectionSummary.pageCount or 1))
    end
    if prevPageBtn and nextPageBtn then
        local page = projectionSummary and projectionSummary.page or 1
        local pageCount = projectionSummary and projectionSummary.pageCount or 1
        if page > 1 then prevPageBtn:Enable() else prevPageBtn:Disable() end
        if page < pageCount then nextPageBtn:Enable() else nextPageBtn:Disable() end
    end
    if resultText then
        local first = projectionSummary and projectionSummary.first or 0
        local last = projectionSummary and projectionSummary.last or #builds
        local total = projectionSummary and projectionSummary.filteredTotal or #builds
        resultText:SetText(string.format("|cffd8c7a0Showing %d-%d of %d|r",
            first, last, total))
    end
    renderBuildWindow = function(reason)
        if virtualBinding then return end
        virtualBinding = true
        local ok, err = pcall(function()
    ReleaseAllCards()
    ReleaseAllHeaders()
    local cardLayout = frame and frame._responsiveLayout
        and frame._responsiveLayout.card or {
            width=460,titleWidth=250,dpsWidth=178,contentWidth=428,
            gap=6,iconCapacity=12,
        }

    local rowHeight = CARD_HEIGHT + 4
    local visibleH = math.max(100,
        (scrollFrame and scrollFrame:GetHeight()) or 458)
    local virtual = Nexus.VirtualList.Window(
        #builds, rowHeight, visibleH,
        scrollBar and scrollBar.value or 0, 2)
    local yOffset = (virtual.first - 1) * rowHeight
    local lastClass = "__none__"
    local showHeaders = false

    for index = virtual.first, virtual.last do
        local projected = builds[index]
        local b = LoadBuild(projected.id) or projected
        b._nexusDps = projected._nexusDps
        b._nexusBestDps = projected._nexusBestDps
        b._nexusQualified = projected._nexusQualified
        b._nexusQualification = projected._nexusQualification
        local bClass = (b.class or "UNKNOWN"):upper()
        if bClass == "" then bClass = "UNKNOWN" end

        -- Class header when sorted by class and not filtered
        if showHeaders and bClass ~= lastClass then
            lastClass = bClass
            local h = GetHeader(scrollChild)
            h:SetWidth(cardLayout.width)
            h:ClearAllPoints()
            h:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
            local c = CLASS_COLOR[bClass] or {0.8,0.8,0.8}
            h.label:SetTextColor(c[1],c[2],c[3])
            h.label:SetText(CLASS_LABEL[bClass] or bClass)
            activeHeaders[#activeHeaders+1] = h
            yOffset = yOffset + 26
        end

        -- Build card
        local card = GetCard(scrollChild)
        -- Check cards into the active set before binding data so the failure
        -- path can always reclaim a partially bound card.
        activeCards[#activeCards+1] = card
        card:SetWidth(cardLayout.width)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -yOffset)
        card.buildId = b.id

        -- Selection highlight
        if b.id == SelectedId() then
            card.selectedHighlight:Show()
        else
            card.selectedHighlight:Hide()
        end

        -- Use a stable class-themed icon instead of a question mark.
        pcall(function() card.classIcon:SetTexture(CLASS_ICON[bClass] or "Interface\\Icons\\INV_Misc_QuestionMark") end)

        -- Title (class colored)
        local c = CLASS_COLOR[bClass] or {1,1,1}
        card.title:SetTextColor(c[1],c[2],c[3])
        card.title:SetWidth(cardLayout.titleWidth)
        card.author:SetWidth(cardLayout.titleWidth)
        card.destination:SetWidth(math.max(80,cardLayout.width-80))
        card.echoCount:SetWidth(cardLayout.dpsWidth)
        card.dpsBreakdown:SetWidth(cardLayout.dpsWidth)
        local fullTitle = tostring(b.title or "")
        local titleChars = math.max(12,math.floor(cardLayout.titleWidth
            / (6 * ((frame._responsiveLayout and frame._responsiveLayout.scale)
                or 1))))
        local displayTitle = Nexus.LayoutMetrics
            and Nexus.LayoutMetrics.Truncate(fullTitle,titleChars) or fullTitle
        card._fullTitle,card._displayTitle = fullTitle,displayTitle
        card.title:SetText(displayTitle)
        do
            local ownerTag = ""
            if IsSavedMirror(b) then ownerTag = "  |cff66ccffSaved loadout|r"
            elseif IsOwnBuild(b) then ownerTag = "  |cffffd200Your build|r" end
            local qualityTag = ""
            if b._nexusQualified == false then
                qualityTag = qualityTag .. "  |cffffa040Unqualified|r"
            end
            if bClass == "UNKNOWN" then
                qualityTag = qualityTag .. "  |cffaaaaaaUnknown class|r"
            end
            card.author:SetText("by "..(b.author or "?")..ownerTag..qualityTag)
        end
        if IsSavedMirror(b) then
            if b.destinationWishlistName then
                card.destination:SetText(string.format("|cffffd200Destination:|r %s  |cff66ff99%d/%d in progress|r", b.destinationWishlistName, tonumber(b.destinationProgress) or 0, tonumber(b.destinationTotal) or 79))
            else
                card.destination:SetText("|cff999999No destination wishlist associated|r")
            end
            card.destination:Show()
        else
            card.destination:SetText("")
            card.destination:Hide()
        end

        -- Echo icons
        local echoes = b.echoes or {}
        local shown = math.min(#echoes,MAX_ROW_ICONS,
            cardLayout.iconCapacity or MAX_ROW_ICONS)
        for i, ic in ipairs(card.icons) do
            if i <= shown then
                ic:SetTexture(SpellIcon(echoes[i].spellId))
                pcall(function() ic:SetVertexColor(1,1,1) end)
                ic:Show()
            else
                ic:Hide()
            end
        end
        local extra = #echoes - shown
        card.moreText:ClearAllPoints()
        card.moreText:SetPoint("LEFT",card.icons[math.max(1,shown)],"RIGHT",6,0)
        card.moreText:SetText(extra > 0 and ("|cffff9040+"..extra.."|r") or "")
        if #echoes > 0 then
            do
                -- Public Community rows already carry the revision-scoped
                -- dual-record summary. Never fall back to per-build DPS reads
                -- from the renderer if that projection invariant is broken.
                local dps = b._nexusDps or {
                    dummy=0,lk=0,best=0,average=0,count=0,
                }
                if dps.count == 2 then
                    card.echoCount:SetText(string.format("|cff4dff80%s avg|r", DpsText(dps.average)))
                    card.dpsBreakdown:SetText(string.format("Dummy %s  |cff777777•|r  LK %s", DpsText(dps.dummy), DpsText(dps.lk)))
                elseif dps.dummy > 0 then
                    card.echoCount:SetText(string.format("|cff4dff80%s DPS|r", DpsText(dps.dummy)))
                    card.dpsBreakdown:SetText("Training Dummy")
                elseif dps.lk > 0 then
                    card.echoCount:SetText(string.format("|cff4dff80%s DPS|r", DpsText(dps.lk)))
                    card.dpsBreakdown:SetText("Lich King")
                else
                    card.echoCount:SetText("|cff777777No DPS record|r")
                    card.dpsBreakdown:SetText("")
                end
            end
        else
            card.echoCount:SetText("|cffffd200Syncing full loadout...|r")
            card.dpsBreakdown:SetText("")
            card.title:SetTextColor(0.65,0.65,0.65)
            card.author:SetText("by "..(b.author or "?").."  |cff777777- waiting for Echoes|r")
        end

        card.mineBadge:Hide()
        card.addBtn:SetText("View")
        card.addBtn:SetSize(52,22)
        card.addBtn:Show()
        card.menuBtn:Hide()
        card.record = nil

        yOffset = yOffset + rowHeight
    end

    -- Empty state
    if #builds == 0 then
        local total = projectionSummary and projectionSummary.total or 0
        if not projectionSummary then
            for _ in pairs(Store()) do total=total+1 end
        end
        local msg
        msg = total == 0
            and "No builds yet.\n\nPost a build from your active Echo Wishlist, or press Sync Now to find builds from other players."
            or  "No builds match the current scope, class, qualification, or search filters."
        if frame._emptyState then
            frame._emptyState:SetText(msg)
            frame._emptyState:Show()
        end
        scrollChild:SetHeight(80)
        scrollBar:SetMinMaxValues(0,0)
        scrollBar.value = 0
        pcall(function() scrollFrame:SetVerticalScroll(0) end)
        RefreshDetailPanel(nil)
    else
        if frame._emptyState then frame._emptyState:Hide() end
        scrollChild:SetHeight(math.max(virtual.contentHeight, 10))
        scrollBar:SetMinMaxValues(0, virtual.maxOffset)
        scrollBar.value = virtual.offset
        pcall(function() scrollFrame:SetVerticalScroll(virtual.offset) end)
    end
    virtualStats.results = #builds
    virtualStats.active = #activeCards
    virtualStats.peakActive = math.max(virtualStats.peakActive, #activeCards)
    virtualStats.first, virtualStats.last = virtual.first, virtual.last
    virtualStats.offset, virtualStats.maxOffset = virtual.offset, virtual.maxOffset
    virtualStats.selectedVisible = false
    for index = virtual.first, virtual.last do
        if builds[index] and builds[index].id == SelectedId() then
            virtualStats.selectedVisible = true
            break
        end
    end
    if reason == "scroll" then
        virtualStats.scrollBinds = virtualStats.scrollBinds + 1
    elseif reason == "resize" then
        virtualStats.resizeBinds = virtualStats.resizeBinds + 1
    else
        virtualStats.dataBinds = virtualStats.dataBinds + 1
    end
        end)
        virtualBinding = false
        if not ok then
            pcall(ReleaseAllCards)
            pcall(ReleaseAllHeaders)
            virtualStats.active = 0
            virtualStats.first, virtualStats.last = 1, 0
            virtualStats.selectedVisible = false
            error(err)
        end
    end
    Measure("community.render", renderBuildWindow, "data")
    virtualStats.dataRefreshes = virtualStats.dataRefreshes + 1
    local projections = Nexus and Nexus.ViewProjections
    if projections and type(projections.RecordBind) == "function" then
        projections.RecordBind("builds")
    end
    local peerDebug = Nexus and Nexus.PeerDebug
    if peerDebug and type(peerDebug.IsEnabled) == "function"
        and peerDebug.IsEnabled() and type(peerDebug.Record) == "function" then
        pcall(peerDebug.Record, "community_publication", {
            outcome="published",rows=#builds,
            page=projectionSummary and projectionSummary.page or 1,
        })
        local selected = type(peerDebug.SelectedBuild) == "function"
            and peerDebug.SelectedBuild() or nil
        if selected then
            local included = false
            for index = 1, math.min(#builds, 200) do
                if builds[index] and builds[index].id == selected then
                    included = true
                    break
                end
            end
            local reason
            if not included and type(projections.ExplainBuild) == "function" then
                local ok, explained = pcall(projections.ExplainBuild,
                    selected, FilterSettings())
                if ok then reason = explained end
            end
            pcall(peerDebug.Record, "community_result", {
                id=selected,outcome=included and "included" or "outside_page",
                rows=#builds,page=projectionSummary and projectionSummary.page or 1,
                reason=reason,
            })
        end
    end

    -- Detail panel
    RefreshDetailPanel(SelectedId())

    -- Search placeholder visibility
    if searchBox then
        local lbl = searchBox:GetParent() and searchBox:GetParent().searchLabel
        -- just handle via the text directly: show placeholder if empty
    end
    viewDiagnostic.publishedAt = ClockNow()
    viewDiagnostic.publishedPage = math.max(1, math.floor(tonumber(
        projectionSummary and projectionSummary.page) or requestedPage))
    viewDiagnostic.projectionPending = false
    viewDiagnostic.projectionError = false
    viewDiagnostic.projectionCurrent = true
    refreshDirty = false
    return true
end


    function M.SetViewMode(mode)
        if mode == "dummy" or mode == "lk" then
            if frame then frame:Hide() end
            if Nexus.Leaderboard then Nexus.Leaderboard.Show(mode) end
            return
        end
        M.Refresh()
    end

    function M.Show()
        Measure("community.frame.ensure", EnsureFrame)
        M.ApplyResponsiveLayout(false)
        if Nexus.Panel and Nexus.Panel.AttachMenuFrame then
            Nexus.Panel.AttachMenuFrame(frame)
        end
        if Nexus.Theme and Nexus.Theme.StyleWindow then
            Nexus.Theme.StyleWindow(frame, 0.96)
        end
        if Nexus.Panel and Nexus.Panel.CloseOtherWindows then
            Nexus.Panel.CloseOtherWindows("NexusCommunityBuildsFrame")
        end
        frame:Show()
        M.Refresh()
    end

    function M.Hide()
        if frame then frame:Hide() end
    end

    function M.IsShown()
        return frame and frame:IsShown() or false
    end

    return M
end

Nexus.CommunityInternals.Renderer = Renderer
