-- #163: Plan and Explore are a tabbed collection of the real Nexus windows.
-- The existing Wishlist, Build Library and Leaderboard controllers continue to
-- own their state and explicit Save, Sync, assignment and sharing actions.
local Nexus = Nexus
local M = {}
Nexus.FullUIWorkspaces = M

local descriptions = {
    plan = { label = "Plan", detail = "Wishlist Editor: choose Echoes and edit a plan. Nothing is saved or assigned by opening this tab." },
    builds = { label = "Explore", detail = "Build Library: browse builds. Sharing, importing and Sync require their own controls." },
    records = { label = "Records", detail = "Explore DPS records in the Leaderboard. Sync requires its own button." },
}

-- Keep the existing buttons and their handlers. This preserves the local
-- close/dropdown cleanup and LoadingStatus hooks installed by each window.
function M.BindTabs(frame, active, buttons, beforeLeave)
    if not (frame and type(buttons) == "table") then return false end
    if not descriptions[active] then return false end
    for _, key in ipairs({"plan", "builds", "records"}) do
        local button = buttons[key]
        if not button then return false end
        local item = descriptions[key]
        button:SetText(key == active and "|cffffd200" .. item.label .. "|r" or item.label)
        if key ~= active then
            button:SetScript("OnClick", function()
                M.NavigateFrom(frame, key, beforeLeave)
            end)
        end
        if button.HookScript and not button._nexusWorkspaceTip then
            button._nexusWorkspaceTip = true
            button:HookScript("OnEnter", function(self)
                -- LoadingStatus owns the pending-data explanation here.
                if not GameTooltip or self._nexusDataLoading then return end
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:AddLine(item.label, 1, .82, .2)
                GameTooltip:AddLine(item.detail, .8, .8, .8, true)
                GameTooltip:Show()
            end)
            button:HookScript("OnLeave", function()
                if GameTooltip then GameTooltip:Hide() end
            end)
        end
    end
    frame._workspaceTabs = buttons
    frame._workspaceGroup = active == "plan" and "Plan" or "Explore"
    return true
end

local function Open(owner, frameName, unavailable)
    if not (owner and type(owner.Show) == "function") then return false, unavailable end
    local ok, reason = owner.Show()
    if ok == false then return false, reason end
    local frame = _G[frameName]
    if frame and frame.IsShown and frame:IsShown() then return true end
    return false, reason or "workspace did not open"
end

function M.ShowPlan()
    return Open(Nexus.WishlistEditor, "NexusEditorFrame", "wishlist editor unavailable")
end

function M.ShowExplore(view)
    if view == "records" then
        return Open(Nexus.Leaderboard, "NexusLeaderboardFrame", "leaderboard unavailable")
    end
    if view ~= nil and view ~= "builds" then return false, "unknown Explore view" end
    return Open(Nexus.CommunityBuilds, "NexusCommunityBuildsFrame", "build library unavailable")
end

function M.Show(kind)
    if kind == "plan" or kind == "wishlists" then return M.ShowPlan() end
    if kind == "explore" or kind == "builds" then return M.ShowExplore() end
    if kind == "records" then return M.ShowExplore("records") end
    return false, "unknown workspace"
end

-- Request the destination before dismissing the current surface. An inbound
-- Community/Leaderboard view can be pending while shared data starts; that
-- must not strand the player with every window closed. Each destination still
-- owns its filters, scroll position and confirmation behavior.
function M.NavigateFrom(source, kind, beforeLeave)
    local names = {
        plan = "NexusEditorFrame",
        builds = "NexusCommunityBuildsFrame",
        records = "NexusLeaderboardFrame",
    }
    if not names[kind] then return false, "unknown workspace" end
    if type(beforeLeave) == "function" then beforeLeave() end
    local ok, reason = M.Show(kind)
    if ok == false then return false, reason end
    local destination = _G[names[kind]]
    if not (destination and destination.IsShown and destination:IsShown()) then
        return false, reason or "workspace did not open"
    end
    if source and source ~= destination and source.IsShown and source:IsShown() then
        source:Hide()
    end
    return true
end
