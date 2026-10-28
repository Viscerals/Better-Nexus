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

-- The shared header (LayoutMetrics.WorkspaceHeader): each workspace places
-- its tabs, Help, Reference and title at the same measured anchors from its
-- own top-left (root: the window, or Explore's scrolled content), so the
-- tabs and title stand still when the workspace changes. Labels, handlers
-- and loading hooks stay with BindTabs and each window. A button's label
-- and the title get their template fonts per widget, after any window-wide
-- font pass; no shared font object is changed.
function M.ApplyHeader(frame, root, parts)
    local LM = Nexus.LayoutMetrics
    if not (frame and type(parts) == "table" and LM
        and type(LM.WorkspaceHeader) == "function") then return nil end
    root = root or frame
    local header = LM.WorkspaceHeader(tonumber(root:GetWidth())
        or tonumber(frame:GetWidth()))
    local function Place(widget, box, fromRight)
        if not (widget and box) then return end
        widget:ClearAllPoints()
        if fromRight then
            widget:SetPoint("TOPRIGHT", root, "TOPRIGHT",
                box.x + box.w - header.width, -box.y)
        else
            widget:SetPoint("TOPLEFT", root, "TOPLEFT", box.x, -box.y)
        end
        widget:SetSize(box.w, box.h)
    end
    local function TemplateFont(button)
        local label = button and type(button.GetFontString) == "function"
            and button:GetFontString() or nil
        if label and type(label.SetFontObject) == "function" then
            pcall(label.SetFontObject, label, "GameFontNormal")
        end
    end
    local tabs = parts.tabs or frame._workspaceTabs or {}
    for _, key in ipairs(header.order) do
        Place(tabs[key], header.boxes[key])
        TemplateFont(tabs[key])
    end
    Place(parts.help, header.boxes.help)
    TemplateFont(parts.help)
    Place(parts.reference, header.boxes.reference, true)
    TemplateFont(parts.reference)
    local title = parts.title
    if title then
        Place(title, header.boxes.title)
        if type(title.SetFontObject) == "function" then
            pcall(title.SetFontObject, title, "GameFontNormalLarge")
        end
        title:SetJustifyH("LEFT")
        if type(title.SetWordWrap) == "function" then
            pcall(title.SetWordWrap, title, false)
        end
    end
    frame._workspaceHeader = header
    return header
end

-- Navigation keeps the place: the destination opens with its top-left
-- corner where the window it replaces had its own (the shared header then
-- puts its tabs where the player's were), in screen units, so a different
-- window scale or a dragged window is followed. The result is kept on
-- screen; a UI size too small to judge is not clamped. Nothing is saved.
function M.CapturePlace(frame)
    if not (frame and frame.IsShown and frame:IsShown()
        and type(frame.GetLeft) == "function" and type(frame.GetTop) == "function") then
        return nil
    end
    local okL, left = pcall(frame.GetLeft, frame)
    local okT, top = pcall(frame.GetTop, frame)
    local okS, scale = pcall(frame.GetEffectiveScale, frame)
    left, top = okL and tonumber(left), okT and tonumber(top)
    scale = okS and tonumber(scale) or 1
    if not (left and top and scale and scale > 0) then return nil end
    return {left=left * scale, top=top * scale}
end

function M.RestorePlace(frame, place)
    if not (frame and type(place) == "table" and tonumber(place.left)
        and tonumber(place.top) and UIParent) then return false end
    local okS, scale = pcall(frame.GetEffectiveScale, frame)
    scale = okS and tonumber(scale) or 1
    if not (scale and scale > 0) then return false end
    local x, y = place.left / scale, place.top / scale
    local okU, uiScale = pcall(UIParent.GetEffectiveScale, UIParent)
    uiScale = okU and tonumber(uiScale) or 1
    local uiW, uiH = tonumber(UIParent:GetWidth()) or 0, tonumber(UIParent:GetHeight()) or 0
    local screenW, screenH = uiW * uiScale / scale, uiH * uiScale / scale
    local w, h = tonumber(frame:GetWidth()) or 0, tonumber(frame:GetHeight()) or 0
    if uiW >= 640 and uiH >= 480 then
        x = math.max(0, math.min(x, screenW - w))
        y = math.min(screenH, math.max(y, h))
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    return true
end

local function Open(owner, frameName, unavailable)
    if not (owner and type(owner.Show) == "function") then return false, unavailable end
    local ok, reason = owner.Show()
    if ok == false then
        -- CommunityBuilds.WaitForStartup opens its own guarded loading window
        -- and closes all other Nexus windows before it returns "pending".
        -- Report that visible transition truthfully to our callers. Its
        -- enabled "Use local Wishlists" control returns to Plan when the
        -- local store is ready; a close button also remains available.
        local loading = _G.NexusSharedStartupFrame
        if reason == "pending" and loading and loading.IsShown and loading:IsShown() then
            return true, "loading"
        end
        return false, reason
    end
    local frame = _G[frameName]
    if frame and frame.IsShown and frame:IsShown() then return true end
    return false, reason or "workspace did not open"
end

function M.ShowPlan()
    return Open(Nexus.WishlistEditor, "NexusEditorFrame", "wishlist editor unavailable")
end

function M.ShowExplore(view)
    local plan = _G.NexusEditorFrame
    if plan and plan.IsShown and plan:IsShown() then
        local editor = Nexus.WishlistEditor
        if not (editor and type(editor.SuspendForWorkspace) == "function") then
            return false, "Plan draft protection is unavailable"
        end
        local allowed, reason = editor.SuspendForWorkspace()
        if not allowed then return false, reason end
    end
    local ok, reason
    if view == "records" then
        ok, reason = Open(Nexus.Leaderboard, "NexusLeaderboardFrame", "leaderboard unavailable")
    elseif view ~= nil and view ~= "builds" then
        ok, reason = false, "unknown Explore view"
    else
        ok, reason = Open(Nexus.CommunityBuilds, "NexusCommunityBuildsFrame", "build library unavailable")
    end
    if not ok and plan and plan:IsShown() and Nexus.WishlistEditor
        and type(Nexus.WishlistEditor.CancelWorkspaceSuspend) == "function" then
        Nexus.WishlistEditor.CancelWorkspaceSuspend()
    end
    return ok, reason
end

function M.Show(kind)
    if kind == "plan" or kind == "wishlists" then return M.ShowPlan() end
    if kind == "explore" or kind == "builds" then return M.ShowExplore() end
    if kind == "records" then return M.ShowExplore("records") end
    return false, "unknown workspace"
end

-- The Plan actions retain the Panel's existing guarded game routes. Opening
-- the Journal is navigation; choosing a Wishlist there remains a separate
-- explicit assignment. A failed native open keeps the editor and draft.
function M.OpenPlanAction(kind)
    local panel = Nexus.Panel
    local route = kind == "assignment" and "OpenAssignment"
        or kind == "mybuilds" and "OpenMyBuilds" or nil
    if not (route and panel and type(panel[route]) == "function") then
        return false, "Plan action unavailable"
    end
    local editor, plan = Nexus.WishlistEditor, _G.NexusEditorFrame
    if plan and plan.IsShown and plan:IsShown() then
        if not (editor and type(editor.SuspendForWorkspace) == "function") then
            return false, "Plan draft protection is unavailable"
        end
        local allowed, reason = editor.SuspendForWorkspace()
        if not allowed then return false, reason end
    end
    local opened, reason = panel[route]()
    if plan and plan.IsShown and plan:IsShown()
        and editor and type(editor.CancelWorkspaceSuspend) == "function" then
        editor.CancelWorkspaceSuspend()
    end
    if opened == false then return false, reason or "Plan action refused" end
    return true
end

-- Ask the destination owner to navigate. A shared-data view can replace this
-- window with its own visible loading surface; that is a valid transition,
-- not proof the shared view opened. If no destination or loading surface opens,
-- the current window remains. Each destination still owns its filters,
-- scroll position and confirmation behavior.
function M.NavigateFrom(source, kind, beforeLeave)
    local names = {
        plan = "NexusEditorFrame",
        builds = "NexusCommunityBuildsFrame",
        records = "NexusLeaderboardFrame",
    }
    if not names[kind] then return false, "unknown workspace" end
    if type(beforeLeave) == "function" then beforeLeave() end
    -- Read before the destination opens: opening closes the other windows.
    local place = M.CapturePlace(source)
    local ok, reason = M.Show(kind)
    if ok == false then
        if type(print) == "function" then
            print("|cffffd200Nexus:|r " .. tostring(reason or "workspace unavailable"))
        end
        return false, reason
    end
    if reason == "loading" then return true, reason end
    local destination = _G[names[kind]]
    if not (destination and destination.IsShown and destination:IsShown()) then
        return false, reason or "workspace did not open"
    end
    if place and source ~= destination then M.RestorePlace(destination, place) end
    if source and source ~= destination and source.IsShown and source:IsShown() then
        source:Hide()
    end
    return true
end
