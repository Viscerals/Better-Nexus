-- Nexus: ui/ServerStatus.lua
-- Two-mode integration for Project Ebonhold's difficulty / Soul Ash HUD.
-- Default: hide the server HUD and mirror its values on the Nexus panel.

Nexus = Nexus or {}
local M = {}
Nexus.ServerStatus = M

local rootFrame
local scanner
local elapsed = 0
local hideHooked = false
-- The exact widget THIS module hid, or nil. Holding the frame rather than a
-- flag answers both questions at once: whether we are the reason something is
-- hidden, and WHICH something. It is deliberately not cleared when the world
-- changes -- a widget we took away and have not given back is still ours to
-- give back, and client frames survive a zone change -- but a different frame
-- object is not the one we hid and is never given back on its behalf.
local suppressedFrame = nil
local cachedSummary = { mode = nil, tier = nil, ash = nil, gain = nil, intensity = nil, intensityLevel = nil, raw = "" }
local cachedSignature = ""

local function Strip(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function SafeText(obj)
    if not obj or type(obj.GetText) ~= "function" then return nil end
    local ok, value = pcall(obj.GetText, obj)
    if not ok or value == nil then return nil end
    value = Strip(value)
    return value ~= "" and value or nil
end

local function CollectTexts(frame, out, seen, depth)
    out = out or {}
    seen = seen or {}
    depth = depth or 0
    if not frame or seen[frame] or depth > 8 then return out end
    seen[frame] = true

    local own = SafeText(frame)
    if own then out[#out + 1] = own end

    if type(frame.GetRegions) == "function" then
        local ok, regions = pcall(function() return { frame:GetRegions() } end)
        if ok then
            for i = 1, #regions do
                local text = SafeText(regions[i])
                if text then out[#out + 1] = text end
            end
        end
    end

    if type(frame.GetChildren) == "function" then
        local ok, children = pcall(function() return { frame:GetChildren() } end)
        if ok then
            for i = 1, #children do
                CollectTexts(children[i], out, seen, depth + 1)
            end
        end
    end
    return out
end

local function FindFrames()
    rootFrame = _G.ProjectEbonholdPlayerRunFrame
    return rootFrame ~= nil
end

local function GetAllSourceTexts()
    local out, seen = {}, {}
    -- Only traverse the confirmed Project Ebonhold HUD root. Any nested
    -- difficulty/Soul Ash controls are discovered as children of that frame.
    if rootFrame then CollectTexts(rootFrame, out, seen, 0) end
    return out
end

local function ParseSummary(texts)
    local clean = Strip(table.concat(texts or {}, "  "))

    local tier = clean:match("[Hh][Cc]%s*([1-5])")
        or clean:match("[Hh]ardcore%s*[VvIiXx]*%s*([1-5])")
        or clean:match("[Hh]ardcore%s*([1-5])")
        or clean:match("[Ww]orld%s*[Tt]ier%s*[:%-]?%s*([1-5])")

    local mode
    if tier then
        mode = "HC" .. tier
    elseif clean:find("[Nn]ormal") then
        mode = "Normal"
    end

    local gain = clean:match("([%+%-]%d+%%)")
        or clean:match("[Mm]ultiplier%s*[:%-]?%s*([%+%-]?%d+%%)")

    local ash = clean:match("[Ss]oul%s*[Aa]sh[e]?[s]?%s*[:%-]?%s*([%d,]+)")
    if not ash then
        -- The compact server HUD often exposes only the edit-box number. Pick
        -- a plausible integer, excluding percentages, tier values and versions.
        for token in clean:gmatch("%f[%d]([%d,]+)%f[^%d,]") do
            local digits = token:gsub(",", "")
            if #digits >= 3 and tonumber(digits) then
                ash = token
                break
            end
        end
    end

    return {
        tier = tier and ("HC" .. tier) or nil,
        mode = mode,
        ash = ash,
        gain = gain,
        raw = clean,
    }
end

local function CollectSelectedDifficultyTexts(frame, out, seen, depth)
    out = out or {}
    seen = seen or {}
    depth = depth or 0
    if not frame or seen[frame] or depth > 8 then return out end
    seen[frame] = true

    local selected = false
    if type(frame.GetChecked) == "function" then
        local ok, value = pcall(frame.GetChecked, frame)
        selected = ok and value and true or false
    end

    if selected then
        CollectTexts(frame, out, {}, 0)
    elseif type(frame.GetChildren) == "function" then
        local ok, children = pcall(function() return { frame:GetChildren() } end)
        if ok then
            for i = 1, #children do
                CollectSelectedDifficultyTexts(children[i], out, seen, depth + 1)
            end
        end
    end
    return out
end

local function GetSelectedDifficultySummary()
    local hard = _G.HardmodeFrame
    if not hard then return nil end
    local texts = CollectSelectedDifficultyTexts(hard)
    if #texts == 0 then return nil end
    local parsed = ParseSummary(texts)
    if parsed and parsed.tier then return parsed end
    return nil
end

local function ReadIntensity()
    local data = _G.EbonholdIntensityData
    if type(data) ~= "table" then return nil, nil end
    local value = tonumber(data.intensity)
    if not value then return nil, nil end
    value = math.max(0, math.min(500, value))
    local level = math.floor(value / 100)
    if level > 5 then level = 5 end
    return value, level
end

local function EnsureDefaultMode()
    NexusDB = NexusDB or {}
    if NexusDB.soulAshHudMode ~= "server" and NexusDB.soulAshHudMode ~= "nexus" then
        NexusDB.soulAshHudMode = "nexus"
    end
end

local function UsingNexusHud()
    EnsureDefaultMode()
    return NexusDB.soulAshHudMode == "nexus"
end

-- The same answer WITHOUT normalizing the stored value. EnsureDefaultMode
-- writes the default into the profile, which is right when this owner is
-- applying the preference and wrong when something is merely reading it: a
-- support report must not store a setting just by describing one.
local function SavedModeIsNexus()
    local saved = type(NexusDB) == "table" and NexusDB.soulAshHudMode or nil
    return saved ~= "server"
end

-- Can the Nexus HUD actually display right now? Asked of the panel owner,
-- which is the only place that knows whether a render has committed. A panel
-- that is merely hidden -- by the player, or by an open dialog -- is still
-- able to display and still counts as the replacement; a panel that has never
-- committed, has failed, or was never loaded does not.
--
-- Protected, and false when unknown: if this owner cannot get an answer, the
-- stock widget keeps its place rather than being hidden on an assumption.
-- The READ is inside the protection, not only the call: another addon can
-- replace this global with a table whose __index raises, and this runs on a
-- timer, so an unprotected field access would raise once a second.
local function PanelFacts()
    local ok, facts = pcall(function()
        local panel = Nexus and Nexus.Panel
        if type(panel) ~= "table" then return nil end
        if type(panel.VisibilityFacts) ~= "function" then
            -- An older or partially loaded panel: only its own visibility is
            -- knowable, and that is enough to prove it is displaying.
            if type(panel.IsShown) == "function" then
                local shown = panel.IsShown() == true
                return {ready = shown, committed = shown}
            end
            return nil
        end
        local raw = panel.VisibilityFacts()
        if type(raw) ~= "table" then return nil end
        -- The two scalars are copied out INSIDE the protection, and the
        -- foreign table is never handed to a caller. Returning it would put
        -- every later field read outside this pcall, which is how the same
        -- hazard came back once already: the rule is not "protect the call",
        -- it is "never let a foreign table out of here".
        return {ready = raw.ready == true, committed = raw.committed == true}
    end)
    if not ok then return nil end
    return facts
end

local function ReplacementAvailable()
    local facts = PanelFacts()
    return facts ~= nil and facts.ready == true
end

-- Whether the replacement is positively GONE, which is a stronger statement
-- than "not available right now". A panel part-way through applying a render
-- is briefly unavailable while its committed model still stands; treating
-- that instant as gone would hand the stock widget back and take it away
-- again on the next scan.
local function ReplacementGone()
    local facts = PanelFacts()
    return facts == nil or facts.committed ~= true
end

-- Whether the stock widget should be standing aside for the Nexus HUD. Both
-- halves must hold: the player asked for the Nexus HUD, and that HUD can
-- display. Nothing here is decided from the mode alone.
local function ReplacingServerHud()
    return UsingNexusHud() and ReplacementAvailable()
end

-- Returns whether the frame really did what was asked. A widget with no Hide,
-- or one whose Hide raises, has NOT been taken away by us, and claiming it
-- would later "give back" something we never had.
local function SetShown(frame, shown)
    if not frame then return false end
    if shown then
        local done = false
        if type(frame.Show) == "function" then done = pcall(frame.Show, frame) end
        if type(frame.SetAlpha) == "function" then pcall(frame.SetAlpha, frame, 1) end
        if type(frame.EnableMouse) == "function" then pcall(frame.EnableMouse, frame, true) end
        return done
    end
    if type(frame.Hide) ~= "function" then return false end
    return pcall(frame.Hide, frame)
end

local function ApplyVisibility()
    if not rootFrame then return end

    -- Four states. The stock widget is hidden only while a replacement is
    -- really taking its place; it is shown because the player asked for it;
    -- it is GIVEN BACK when this module hid it for a replacement that can no
    -- longer display; and otherwise it is left exactly as it is. That last
    -- case matters: forcing it to show every second would fight the game and
    -- would override a player who closed it themselves.
    if ReplacingServerHud() then
        -- The confirmed Project Ebonhold root is the complete stock widget.
        -- Hide/show it as one unit; never touch unrelated global addon frames.
        -- Only a hide that actually took something away is remembered as
        -- ours: hiding an already-hidden widget takes nothing, and claiming
        -- it would let a later give-back put back something the player -- or
        -- the game -- had closed for their own reasons.
        local wasShown = nil
        if type(rootFrame.IsShown) == "function" then
            local okShown, value = pcall(rootFrame.IsShown, rootFrame)
            if okShown then wasShown = value and true or false end
        end
        local hid = SetShown(rootFrame, false)
        suppressedFrame = (hid and wasShown ~= false) and rootFrame or nil
    elseif not UsingNexusHud() then
        SetShown(rootFrame, true)
        suppressedFrame = nil
    elseif suppressedFrame == rootFrame and ReplacementGone() then
        -- We took THIS widget away for a replacement, and the replacement is
        -- gone: a committed render failed, or the panel stopped being able to
        -- display. Give it back ONCE and stop claiming it, so nothing is
        -- forced every second and a later hide is not fought. A different
        -- widget object -- after a zone change, or a rebuild by the game --
        -- is not one we hid, so it is left alone.
        SetShown(rootFrame, true)
        suppressedFrame = nil
    end

    local hookTarget = rootFrame
    if hookTarget and not hideHooked and type(hookTarget.HookScript) == "function" then
        hideHooked = true
        hookTarget:HookScript("OnShow", function(self)
            -- The same question as above: a widget that comes back while no
            -- replacement can display is left where the game put it.
            if ReplacingServerHud() then self:Hide() end
        end)
    end
end

function M.Init()
    NexusDB = NexusDB or {}
    EnsureDefaultMode()
    if scanner then return end

    scanner = CreateFrame("Frame", "NexusServerStatusScanner", UIParent)
    scanner:RegisterEvent("PLAYER_ENTERING_WORLD")
    scanner:SetScript("OnEvent", function()
        rootFrame = nil
        hideHooked = false
    end)
    scanner:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (tonumber(dt) or 0)
        if elapsed < 1.0 then return end
        elapsed = 0

        if not rootFrame then FindFrames() end
        ApplyVisibility()
        local summary = ParseSummary(GetAllSourceTexts())
        local selectedDifficulty = GetSelectedDifficultySummary()
        if selectedDifficulty and selectedDifficulty.tier then
            summary.tier = selectedDifficulty.tier
            summary.mode = selectedDifficulty.mode or selectedDifficulty.tier
        end
        summary.intensity, summary.intensityLevel = ReadIntensity()
        local sig = table.concat({ tostring(summary.mode), tostring(summary.tier), tostring(summary.ash), tostring(summary.gain), tostring(summary.intensity), tostring(summary.intensityLevel), tostring(UsingNexusHud()) }, "|")
        if sig ~= cachedSignature then
            cachedSignature = sig
            cachedSummary = summary
            if Nexus.Panel and Nexus.Panel.Refresh then Nexus.Panel.Refresh() end
        end
    end)
end

function M.GetSummary()
    if cachedSignature == "" then
        if not rootFrame then FindFrames() end
        cachedSummary = ParseSummary(GetAllSourceTexts())
        local selectedDifficulty = GetSelectedDifficultySummary()
        if selectedDifficulty and selectedDifficulty.tier then
            cachedSummary.tier = selectedDifficulty.tier
            cachedSummary.mode = selectedDifficulty.mode or selectedDifficulty.tier
        end
        cachedSummary.intensity, cachedSummary.intensityLevel = ReadIntensity()
        cachedSignature = table.concat({ tostring(cachedSummary.mode), tostring(cachedSummary.tier), tostring(cachedSummary.ash), tostring(cachedSummary.gain), tostring(cachedSummary.intensity), tostring(cachedSummary.intensityLevel), tostring(UsingNexusHud()) }, "|")
    end
    return cachedSummary
end

function M.IsDetected()
    if not rootFrame then FindFrames() end
    return rootFrame ~= nil
end

function M.IsUsingNexusHud()
    return UsingNexusHud()
end

-- Whether the stock widget is currently standing aside, and why or why not.
-- Read-only, bounded, and derived from owners that are already running: it
-- starts nothing, rescans nothing and writes nothing.
function M.VisibilityFacts()
    local detected = rootFrame ~= nil
    local shown = nil
    if detected and type(rootFrame.IsShown) == "function" then
        local ok, value = pcall(rootFrame.IsShown, rootFrame)
        if ok then shown = value and true or false end
    end
    local alpha = nil
    if detected and type(rootFrame.GetAlpha) == "function" then
        local ok, value = pcall(rootFrame.GetAlpha, rootFrame)
        if ok then alpha = tonumber(value) end
    end
    local nexusMode = SavedModeIsNexus()
    local available = ReplacementAvailable()
    return {
        mode = nexusMode and "nexus" or "server",
        detected = detected,
        stockShown = shown,
        stockAlpha = alpha,
        replacementAvailable = available,
        replacing = nexusMode and available or false,
    }
end

function M.SetMode(mode)
    NexusDB = NexusDB or {}
    NexusDB.soulAshHudMode = mode == "server" and "server" or "nexus"
    ApplyVisibility()
    if Nexus.Panel and Nexus.Panel.Refresh then Nexus.Panel.Refresh() end
end

local function CollectClickableChildren(frame, out, seen, depth)
    out = out or {}
    seen = seen or {}
    depth = depth or 0
    if not frame or seen[frame] or depth > 8 then return out end
    seen[frame] = true

    if type(frame.GetScript) == "function" then
        local ok, onClick = pcall(frame.GetScript, frame, "OnClick")
        if ok and type(onClick) == "function" then
            out[#out + 1] = frame
        end
    end

    if type(frame.GetChildren) == "function" then
        local ok, children = pcall(function() return { frame:GetChildren() } end)
        if ok then
            for i = 1, #children do
                CollectClickableChildren(children[i], out, seen, depth + 1)
            end
        end
    end
    return out
end

local function ClickServerDifficultyControl()
    if not rootFrame then FindFrames() end
    if not rootFrame then return false end

    local buttons = CollectClickableChildren(rootFrame)
    local rootLeft = type(rootFrame.GetLeft) == "function" and rootFrame:GetLeft() or nil
    local rootBottom = type(rootFrame.GetBottom) == "function" and rootFrame:GetBottom() or nil
    local rootWidth = type(rootFrame.GetWidth) == "function" and rootFrame:GetWidth() or 0
    local rootHeight = type(rootFrame.GetHeight) == "function" and rootFrame:GetHeight() or 0

    table.sort(buttons, function(a, b)
        local function score(btn)
            local x, y = nil, nil
            if type(btn.GetCenter) == "function" then x, y = btn:GetCenter() end
            local sx, sy = 0, 0
            if x and rootLeft and rootWidth > 0 then sx = (x - rootLeft) / rootWidth end
            if y and rootBottom and rootHeight > 0 then sy = (y - rootBottom) / rootHeight end
            -- The stock Hardcore skull control is the upper-right clickable
            -- child of ProjectEbonholdPlayerRunFrame. Prefer that location.
            return sx * 100 + sy * 25
        end
        return score(a) > score(b)
    end)

    for i = 1, #buttons do
        local button = buttons[i]
        local ok, onClick = pcall(button.GetScript, button, "OnClick")
        if ok and type(onClick) == "function" then
            local clicked = pcall(onClick, button, "LeftButton")
            if clicked then
                local hard = _G.HardmodeFrame
                if hard and type(hard.IsShown) == "function" and hard:IsShown() then
                    return true
                end
            end
        end
    end
    return false
end

function M.OpenHardcoreMenu()
    local hard = _G.HardmodeFrame
    if hard and type(hard.IsShown) == "function" and hard:IsShown() then
        if type(hard.Hide) == "function" then pcall(hard.Hide, hard) end
        return true
    end

    -- Use the stock Project Ebonhold button's own click handler first. The
    -- server initializes and opens its Hardcore panel through this control;
    -- simply calling HardmodeFrame:Show() bypasses that setup on some clients.
    if ClickServerDifficultyControl() then return true end

    -- Safe fallback for clients where the panel is already initialized but the
    -- stock child button cannot be resolved.
    hard = _G.HardmodeFrame
    if hard and type(hard.Show) == "function" then
        local ok = pcall(hard.Show, hard)
        if ok then
            if type(hard.Raise) == "function" then pcall(hard.Raise, hard) end
            return true
        end
    end
    return false
end

function M.Rescan()
    rootFrame = nil
    hideHooked = false
    cachedSignature = ""
    local found = FindFrames()
    ApplyVisibility()
    return found
end

return M
