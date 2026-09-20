-- Nexus: ui/CommunityBuilds.lua
-- Nexus Builds community browser -- modeled on the in-game Echo Journal
-- Community Loadouts screen (see screenshots 2026-07-24): scrollable
-- list of build cards grouped under class headers, each showing echo
-- icons inline, author, and a +/... menu. Click any card to expand a
-- detail panel (all echoes, full description, Copy / owner Edit / Stop Sharing). Sync: posts broadcast automatically; receiving is opt-in via
-- "Sync Now".

Nexus = Nexus or {}
local M = {}
Nexus.CommunityBuilds = M

------------------------------------------------------------------------
-- Internal owner assembly
------------------------------------------------------------------------

local communityProjection
local communityController
local communityRenderer
local startupFrame, startupTitle, startupText, startupResume, startupView
local startupBar, startupProgress, startupLocal

local function StartupStatus()
    if type(Nexus.StartupStatus)=="function" then return Nexus.StartupStatus() end
    return {state="ready"} -- standalone consumers/tests retain the old contract
end

local function StartupMessage(status)
    if Nexus.LoadingStatus then return Nexus.LoadingStatus.Detail(status) end
    if not status.coreReady then
        return status.state=="failed" and "Saved-data validation stopped. No readiness checks were bypassed. Use /nexus status for the reason."
            or "Validating local saved data... Controls become available after validation completes."
    end
    if status.state=="failed" then
        return "Shared data preparation failed. Local Wishlist and Echo controls remain available. Use /nexus log errors for details."
    end
    return "Preparing shared build data in the background...\nLocal Wishlist and Echo controls are available. This view will open when ready."
end

-- Opening a shared-data view before its data is ready is a read-only UI action.
-- Do not start imports, projections or publications just to render a spinner.
function M.WaitForStartup(view, resume)
    local status=StartupStatus()
    if status.state=="ready" then return false end
    if not startupFrame then
        startupFrame=CreateFrame("Frame","NexusSharedStartupFrame",UIParent)
        startupFrame:Hide()
        startupFrame:SetSize(510,232)
        startupFrame:SetPoint("CENTER")
        startupFrame:SetFrameStrata("DIALOG")
        startupFrame:SetFrameLevel(110)
        startupFrame:SetClampedToScreen(true)
        startupFrame:EnableMouse(true)
        pcall(function()
            startupFrame:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",tile=true,tileSize=32,
                edgeSize=24,insets={left=6,right=6,top=6,bottom=6}})
        end)
        startupTitle=startupFrame:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
        startupTitle:SetPoint("TOP",0,-22)
        startupText=startupFrame:CreateFontString(nil,"OVERLAY","GameFontHighlight")
        startupText:SetPoint("TOPLEFT",24,-55)
        startupText:SetSize(462,78)
        startupText:SetJustifyH("LEFT")
        startupFrame:SetBackdropColor(0.035,0.035,0.04,1)
        startupBar=CreateFrame("StatusBar",nil,startupFrame)
        startupBar:SetFrameStrata("DIALOG");startupBar:SetFrameLevel(111)
        startupBar:SetPoint("TOPLEFT",24,-142);startupBar:SetSize(462,12)
        startupBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
        startupBar:SetStatusBarColor(.45,.45,.48,1);startupBar:SetMinMaxValues(0,100)
        local back=startupBar:CreateTexture(nil,"BACKGROUND");back:SetAllPoints(startupBar)
        back:SetTexture("Interface\\Buttons\\WHITE8X8");back:SetVertexColor(.12,.12,.14,1)
        startupProgress=startupFrame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        startupProgress:SetPoint("TOPLEFT",24,-162);startupProgress:SetSize(280,42);startupProgress:SetJustifyH("LEFT")
        startupLocal=CreateFrame("Button","NexusSharedLoadingWishlists",startupFrame,"UIPanelButtonTemplate")
        startupLocal:SetFrameStrata("DIALOG");startupLocal:SetFrameLevel(112)
        startupLocal:SetPoint("BOTTOMRIGHT",-24,18);startupLocal:SetSize(154,25);startupLocal:SetText("Use local Wishlists")
        startupLocal:SetScript("OnClick",function()
            if StartupStatus().coreReady and Nexus.WishlistEditor then
                startupFrame:Hide();Nexus.WishlistEditor.Show()
            end
        end)
        local close=CreateFrame("Button",nil,startupFrame,"UIPanelCloseButton")
        close:SetFrameStrata("DIALOG");close:SetFrameLevel(112)
        close:SetPoint("TOPRIGHT",-4,-4)
        close:SetScript("OnClick",function() startupFrame:Hide() end)
        if type(UISpecialFrames)=="table" then
            table.insert(UISpecialFrames,"NexusSharedStartupFrame")
        end
        startupFrame:SetScript("OnHide",function()
            startupResume,startupView=nil,nil
        end)
        startupFrame:SetScript("OnUpdate",function(self,elapsed)
            self._tick=(self._tick or 0)+elapsed
            if self._tick<0.25 then return end
            self._tick=0
            local current=StartupStatus()
            if current.state=="ready" then
                local nextView=startupResume
                self:Hide()
                if nextView then nextView() end
            else
                startupText:SetText(StartupMessage(current))
                if Nexus.LoadingStatus then
                    local percent,text=Nexus.LoadingStatus.Progress(current)
                    startupBar:SetValue(percent or 0);startupProgress:SetText(text)
                end
                if current.coreReady then startupLocal:Enable() else startupLocal:Disable() end
            end
        end)
    end
    startupView,startupResume=view,resume
    startupTitle:SetText("Nexus - "..tostring(view).." |cff999999Loading|r")
    startupText:SetText(StartupMessage(status))
    if Nexus.LoadingStatus then
        local percent,text=Nexus.LoadingStatus.Progress(status)
        startupBar:SetValue(percent or 0);startupProgress:SetText(text)
    end
    if status.coreReady then startupLocal:Enable() else startupLocal:Disable() end
    if Nexus.Panel and Nexus.Panel.AttachMenuFrame then
        Nexus.Panel.AttachMenuFrame(startupFrame)
    end
    if Nexus.Panel and Nexus.Panel.CloseOtherWindows then
        Nexus.Panel.CloseOtherWindows("NexusSharedStartupFrame")
    end
    startupFrame:Show()
    return true
end

local function Measure(name, callback, ...)
    local performance = Nexus and Nexus.Performance
    if performance and type(performance.Measure) == "function" then
        return performance.Measure(name, callback, ...)
    end
    return callback(...)
end

local function EnsureCommunityController()
    if communityController then return communityController end
    local internals = Nexus and Nexus.CommunityInternals
    local factory = internals and internals.Controller
    if not (factory and type(factory.New) == "function") then return nil end
    communityController = factory.New({
        refresh=function()
            if type(M.Refresh) == "function" then M.Refresh() end
        end,
    })
    return communityController
end

local function ControllerInstance()
    return assert(EnsureCommunityController(),
        "Community controller unavailable")
end

local function ProjectSavedBuild(build)
    return ControllerInstance().ProjectBuild(build)
end

local function BindSavedProjectionRelation(projections)
    projections = projections or (Nexus and Nexus.ViewProjections)
    if not (projections
        and type(projections.BindSavedRelationResolver) == "function") then
        return false
    end
    projections.BindSavedRelationResolver(ProjectSavedBuild)
    return true
end

local function EnsureCommunityProjection()
    if communityProjection then return communityProjection end
    local internals = Nexus and Nexus.CommunityInternals
    local factory = internals and internals.Projection
    local projections = Nexus and Nexus.ViewProjections
    if not (factory and type(factory.New) == "function"
        and projections and type(projections.Builds) == "function"
        and type(projections.BuildsCurrent) == "function"
        and type(projections.BindSavedRelationResolver) == "function") then
        return nil
    end
    BindSavedProjectionRelation(projections)
    communityProjection = factory.New({
        builds=function(filters)
            local reader = projections.RequestBuilds or projections.Builds
            return reader(filters)
        end,
        buildsCurrent=function(filters)
            return projections.BuildsCurrent(filters)
        end,
        loadBuild=function(id) return ControllerInstance().Build(id) end,
        recordBuildId=function(build)
            return ControllerInstance().RecordBuildId(build)
        end,
        publishedBuildId=function(build)
            return ControllerInstance().PublishedBuildId(build)
        end,
        savedProjection=function(build)
            return ControllerInstance().ProjectBuild(build)
        end,
        revisionSnapshot=function()
            return ControllerInstance().RevisionSnapshot()
        end,
        dpsBoard=function(category)
            return ControllerInstance().DpsBoard(category)
        end,
        dpsRecord=function(build, category)
            return ControllerInstance().DpsRecord(build, category)
        end,
        leaderboard=function(buildId, category)
            return ControllerInstance().Leaderboard(buildId, category)
        end,
        personalBest=function(buildId, category)
            return ControllerInstance().PersonalBest(buildId, category)
        end,
    })
    return communityProjection
end

local function EnsureCommunityRenderer()
    if communityRenderer then return communityRenderer end
    local internals = Nexus and Nexus.CommunityInternals
    local factory = internals and internals.Renderer
    if not (factory and type(factory.New) == "function") then return nil end
    communityRenderer = factory.New({
        controller=ControllerInstance(),
        projection=EnsureCommunityProjection,
    })
    return communityRenderer
end

local function RendererInstance()
    return assert(EnsureCommunityRenderer(),
        "Community renderer unavailable")
end
-- The public facade stays stable while one frame-free controller owns every
-- Community catalog mutation, selection/filter transition, Sync/loadout
-- intention, popup draft, and bounded lock-in retry.
function M.IsOwnBuild(idOrBuild)
    return ControllerInstance().IsOwnBuild(idOrBuild)
end

function M.EnsureDpsBuildForEchoes(echoes, category, record)
    return ControllerInstance().EnsureDpsBuildForEchoes(
        echoes, category, record)
end

function M.PostCurrentWishlist(title, description, wishlist, class)
    return ControllerInstance().PostCurrentWishlist(
        title, description, wishlist, class)
end

function M.ShareStatus(id)
    return ControllerInstance().ShareStatus(id)
end

function M.PumpPendingShare()
    if not communityController then return false, false end
    return communityController.PumpPendingShare()
end

function M.CanRetryShare(id)
    return ControllerInstance().CanRetryShare(id)
end

function M.RetryShare(id)
    return ControllerInstance().RetryShare(id)
end

function M.PublishImportedBuild(id)
    return ControllerInstance().PublishImportedBuild(id)
end

function M.EditBuild(id, title, description, link)
    return ControllerInstance().EditBuild(id, title, description, link)
end

function M.UpdateFromWishlist(id)
    return ControllerInstance().UpdateFromWishlist(id)
end

function M.DeleteBuild(id)
    return ControllerInstance().DeleteBuild(id)
end

function M._PumpPendingLockIn()
    return ControllerInstance()._PumpPendingLockIn()
end

function M.IsLockInPending()
    return ControllerInstance().IsLockInPending()
end

function M.LockInSelected()
    return RendererInstance().LockInSelected()
end

function M.GetSelectedBuildForPanel()
    if StartupStatus().state~="ready" then return nil end
    return RendererInstance().GetSelectedBuildForPanel()
end

function M.GetSelectedBuildForPanelKey()
    if StartupStatus().state~="ready" then return nil end
    return RendererInstance().GetSelectedBuildForPanelKey()
end

function M.VirtualStats()
    return RendererInstance().VirtualStats()
end

function M.DiagnosticSnapshot()
    return RendererInstance().DiagnosticSnapshot()
end

function M.MarkDataDirty()
    return RendererInstance().MarkDataDirty()
end

function M.ScrollTo(offset)
    return RendererInstance().ScrollTo(offset)
end

function M.Refresh()
    if StartupStatus().state~="ready" then return false,"pending" end
    return RendererInstance().Refresh()
end

function M.ShowPostBuild()
    if M.WaitForStartup("Community",M.ShowPostBuild) then return false,"pending" end
    return RendererInstance().ShowPostBuild()
end

function M.TogglePostPopup(anchor)
    if M.WaitForStartup("Community",function() M.ShowPostBuild() end) then
        return false,"pending"
    end
    return RendererInstance().TogglePostPopup(anchor)
end

function M.ToggleEditPopup(id)
    if M.WaitForStartup("Community",function() M.ToggleEditPopup(id) end) then
        return false,"pending"
    end
    return RendererInstance().ToggleEditPopup(id)
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

-- Community data is intentionally empty on first install.
-- The admin can publish real builds from the Post Build flow.

function M.Init(adapter, model, updateStarted,maxUnits)
    local result=ControllerInstance().Initialize(adapter, Nexus.BundledBuilds,updateStarted,maxUnits)
    -- Bind before the first render so direct startup consumers such as Peer
    -- Debug and ExplainBuild use the same Saved relationship authority.
    BindSavedProjectionRelation()
    RendererInstance()
    return result
end

function M.Select(id)
    ControllerInstance().Select(id)
    M.Refresh()
end

function M.SetViewMode(mode)
    return RendererInstance().SetViewMode(mode)
end

function M.GetViewMode() return "builds" end

function M.Show()
    if M.WaitForStartup("Community",M.Show) then return false,"pending" end
    return Measure("community.show", function()
        local controller = ControllerInstance()
        Measure("community.saved-import",
            controller.BeginSavedLoadoutImport, true)
        -- Preserve the bounded first import unit on open, but keep it outside
        -- Renderer.Refresh so public filters and cached page clicks never
        -- become personal-reconciliation work.
        if type(controller.HasPendingSavedLoadoutImport) == "function"
            and controller.HasPendingSavedLoadoutImport()
            and type(controller.PumpSavedLoadoutImport) == "function" then
            controller.PumpSavedLoadoutImport(25)
        end
        return RendererInstance().Show()
    end)
end

function M.ShowBuild(id)
    if M.WaitForStartup("Community",function() M.ShowBuild(id) end) then
        return false,"pending"
    end
    ControllerInstance().Select(id)
    M.Show()
    local build = id and ControllerInstance().Build(id)
    if build and (not build.echoes or #build.echoes == 0) then
        ControllerInstance().RequestLoadout(id)
    end
    M.Refresh()
end

function M.Hide()
    if startupFrame and startupView=="Community" then startupFrame:Hide() end
    return RendererInstance().Hide()
end

function M.IsShown()
    if startupFrame and startupView=="Community" and startupFrame:IsShown() then return true end
    return RendererInstance().IsShown()
end

function M.Toggle()
    if M.IsShown() then M.Hide()
    else M.Show() end
end
