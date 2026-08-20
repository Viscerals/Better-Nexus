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
    return RendererInstance().GetSelectedBuildForPanel()
end

function M.GetSelectedBuildForPanelKey()
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
    return RendererInstance().Refresh()
end

function M.ShowPostBuild()
    return RendererInstance().ShowPostBuild()
end

function M.TogglePostPopup(anchor)
    return RendererInstance().TogglePostPopup(anchor)
end

function M.ToggleEditPopup(id)
    return RendererInstance().ToggleEditPopup(id)
end

------------------------------------------------------------------------
-- Public API
------------------------------------------------------------------------

-- Community data is intentionally empty on first install.
-- The admin can publish real builds from the Post Build flow.

function M.Init(adapter, model)
    ControllerInstance().Initialize(adapter, Nexus.BundledBuilds)
    -- Bind before the first render so direct startup consumers such as Peer
    -- Debug and ExplainBuild use the same Saved relationship authority.
    BindSavedProjectionRelation()
    RendererInstance()
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
    ControllerInstance().Select(id)
    M.Show()
    local build = id and ControllerInstance().Build(id)
    if build and (not build.echoes or #build.echoes == 0) then
        ControllerInstance().RequestLoadout(id)
    end
    M.Refresh()
end

function M.Hide()
    return RendererInstance().Hide()
end

function M.IsShown()
    return RendererInstance().IsShown()
end

function M.Toggle()
    if M.IsShown() then M.Hide()
    else M.Show() end
end
