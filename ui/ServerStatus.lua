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
        NexusDB.soulAshHudMode = Nexus.Release
            and Nexus.Release.preferStockServerHud == true
            and "server" or "nexus"
    end
end

local function UsingNexusHud()
    EnsureDefaultMode()
    -- Emergency isolation is a hard override. The Beta 3 stock-HUD flag is
    -- only a safe default: once the player explicitly chooses a HUD in the
    -- Nexus menu, honor that choice instead of making the button a no-op.
    if Nexus.Release and Nexus.Release.emergencyCommunityOff == true then
        return false
    end
    if Nexus.Release and Nexus.Release.preferStockServerHud == true
        and NexusDB.soulAshHudModeExplicit ~= true then return false end
    return NexusDB.soulAshHudMode == "nexus"
end

local function SetShown(frame, shown)
    if not frame then return end
    if shown then
        if type(frame.Show) == "function" then pcall(frame.Show, frame) end
        if type(frame.SetAlpha) == "function" then pcall(frame.SetAlpha, frame, 1) end
        if type(frame.EnableMouse) == "function" then pcall(frame.EnableMouse, frame, true) end
    else
        if type(frame.Hide) == "function" then pcall(frame.Hide, frame) end
    end
end

local function ApplyVisibility()
    if not rootFrame then return end
    local hideServer = UsingNexusHud()

    -- The confirmed Project Ebonhold root is the complete stock widget.
    -- Hide/show it as one unit; never touch unrelated global addon frames.
    SetShown(rootFrame, not hideServer)

    local hookTarget = rootFrame
    if hookTarget and not hideHooked and type(hookTarget.HookScript) == "function" then
        hideHooked = true
        hookTarget:HookScript("OnShow", function(self)
            if UsingNexusHud() then self:Hide() end
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

function M.SetMode(mode)
    NexusDB = NexusDB or {}
    NexusDB.soulAshHudMode = mode == "server" and "server" or "nexus"
    NexusDB.soulAshHudModeExplicit = true
    -- Capture PEH's current text before hiding its root so the first Nexus HUD
    -- repaint can merge Difficulty, Soul Ash, multiplier, and Intensity now.
    if NexusDB.soulAshHudMode == "nexus" then M.GetSummary() end
    ApplyVisibility()
    if Nexus.Panel and Nexus.Panel.Refresh then Nexus.Panel.Refresh() end
    return NexusDB.soulAshHudMode
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
