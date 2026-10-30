-- Nexus: ui/ServerStatus.lua
-- Two-mode integration for Project Ebonhold's difficulty / Soul Ash HUD.
-- Default: hide the server HUD and mirror its values on the Nexus panel.
-- #126: the difficulty mirrored here is only the hardmode service's own
-- confirmed value, read passively (ReadDifficulty below). HUD text and the
-- Hardcore window's selected draft are never read as the difficulty.

Nexus = Nexus or {}
local M = {}
Nexus.ServerStatus = M

-- Full-UI localization (issues #143-#148): the one chat notice below
-- resolves through Nexus.Localization when printed; while the seam is absent
-- or its key answers "unavailable" the exact English is shown. The summary's
-- mode and tier values ("Normal", "HC1".."HC5") are compared by the panel and
-- are never translated here; the panel owns their display.
local function Say(key, english)
    local localization = Nexus.Localization
    if type(localization) == "table" and type(localization.Text) == "function" then
        local text, source = localization.Text(key)
        if type(text) == "string" and source ~= "unavailable" then return text end
    end
    return english
end

local rootFrame
local scanner
local elapsed = 0
-- #33: the frames that already carry the OnShow hook. The client chains
-- hooks and never removes them, so the guard is the frame OBJECT, not a flag
-- that a world entry resets. Weak keys: a frame the game discards is not kept.
local hookedFrames = setmetatable({}, { __mode = "k" })
-- The exact widget THIS module hid, or nil. Holding the frame rather than a
-- flag answers both questions at once: whether we are the reason something is
-- hidden, and WHICH something. It is deliberately not cleared when the world
-- changes -- a widget we took away and have not given back is still ours to
-- give back, and client frames survive a zone change -- but a different frame
-- object is not the one we hid and is never given back on its behalf.
local suppressedFrame = nil
-- Issue #164 give-back readback. A Show that returns is not proof that the
-- widget is on screen: another addon can wrap Show, or the game can refuse
-- it. `restorePending` is the widget we hid whose give-back has not read back
-- as shown: it stays ours (suppressedFrame), is re-read on every scan, and
-- its Show is retried only at an explicit lifecycle point (a mode change, a
-- panel hide/show, a rescan, or the first scan after a world entry), never
-- every second. `restoreUnknown` is a widget whose Show ran but which cannot
-- report IsShown: no readback can ever confirm it, so the claim ends and the
-- fact stays unknown, never "restored".
local restorePending = nil
local restoreUnknown = nil
local retryAfterWorld = false
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

-- The Soul Ash balance from the HUD's own named field, read before any text
-- scan: the provider's soulPointsText (PlayerRunUI.GetUIElements), else the
-- root frame's field of that name. nil: the HUD names no such field. false: it
-- does, and the field does not hold a plain balance (a percentage or any other
-- text is never taken as the balance). Read under protection: these are
-- another addon's tables.
local function NamedSoulAsh()
    local ok, field = pcall(function()
        local pe = _G.ProjectEbonhold
        local ui = type(pe) == "table" and pe.PlayerRunUI or nil
        local elements = type(ui) == "table" and type(ui.GetUIElements) == "function"
            and ui.GetUIElements() or nil
        local named = type(elements) == "table" and elements.soulPointsText or nil
        if named == nil and rootFrame then named = rootFrame.soulPointsText end
        return named
    end)
    if not ok or field == nil then return nil end
    local text = SafeText(field)
    return text and text:match("^%d[%d,]*$") or false
end

-- `namedAsh` (NamedSoulAsh): the named field's balance, false when the named
-- field holds no balance, nil when there is none and the texts are scanned.
-- #126: the texts give the Soul Ash balance, its multiplier and the raw text
-- only. They are never read as the difficulty: the compact tier label starts
-- as a literal Normal and is repainted on its own schedule, and numbers,
-- Roman numerals, multipliers, levels and tooltips beside it confirm nothing.
-- mode and tier are left unknown here; ReadDifficulty supplies them.
local function ParseSummary(texts, namedAsh)
    local clean = Strip(table.concat(texts or {}, "  "))

    local gain = clean:match("([%+%-]%d+%%)")
        or clean:match("[Mm]ultiplier%s*[:%-]?%s*([%+%-]?%d+%%)")

    local ash
    if namedAsh ~= nil then
        ash = namedAsh or nil
    else
        ash = clean:match("[Ss]oul%s*[Aa]sh[e]?[s]?%s*[:%-]?%s*([%d,]+)")
    end
    if not ash and namedAsh == nil then
        -- The compact server HUD often exposes only the edit-box number. Pick
        -- a plausible integer, excluding percentages, signed values, tier
        -- values and versions: a multiplier such as "+150%" is never a
        -- balance.
        local unsigned = clean:gsub("[%+%-]?[%d,%.]+%%", " "):gsub("[%+%-][%d,]+", " ")
        for token in unsigned:gmatch("%f[%d]([%d,]+)%f[^%d,]") do
            local digits = token:gsub(",", "")
            if #digits >= 3 and tonumber(digits) then
                ash = token
                break
            end
        end
    end

    return {
        tier = nil,
        mode = nil,
        ash = ash,
        gain = gain,
        raw = clean,
    }
end

-- #126: the difficulty, from Project Ebonhold's hardmode service alone and
-- read passively: ProjectEbonhold.HardmodeService.IsDifficultyKnown() and
-- GetCurrentDifficulty(), both called with no arguments under protection,
-- from the current globals on every read, so a service that loads late or is
-- replaced is the one read. The service's cached value is a placeholder 1
-- until a reply confirms it, so the value is trusted only once
-- IsDifficultyKnown() answers exactly true, and only as a finite integer
-- 1..6: 1 is Normal, 2..6 are Hardcore I..V (HC1..HC5). Anything else -- no
-- service, a missing or raising function, readiness that is not exactly true,
-- a value of another type, a fraction, NaN, an infinity or a value outside
-- 1..6 -- is unknown (nil, nil), and the panel shows its generic Difficulty
-- caption. Nothing is coerced or remembered, and no earlier answer stands in.
-- The known flag means last confirmed this session (the service does not
-- clear it at world entry), not confirmed in this zone, and the service itself
-- turns a malformed nonempty reply into 1; neither is visible to this reader,
-- so it claims no more than the service does. It requests, sets, registers
-- and hooks nothing: the service routes its replies through one handler per
-- id, and registering for them would replace the service's own handler.
local DIFFICULTY_MODES = {
    [1] = "Normal", [2] = "HC1", [3] = "HC2", [4] = "HC3", [5] = "HC4", [6] = "HC5",
}

local function ReadDifficulty()
    local ok, value = pcall(function()
        local pe = _G.ProjectEbonhold
        local service = type(pe) == "table" and pe.HardmodeService or nil
        if type(service) ~= "table" then return nil end
        local isKnown = service.IsDifficultyKnown
        local getCurrent = service.GetCurrentDifficulty
        if type(isKnown) ~= "function" or type(getCurrent) ~= "function" then
            return nil
        end
        if isKnown() ~= true then return nil end
        local current = getCurrent()
        if type(current) ~= "number" or current ~= current
            or current ~= math.floor(current) or current < 1 or current > 6 then
            return nil
        end
        return current
    end)
    local mode = ok and value ~= nil and DIFFICULTY_MODES[value] or nil
    if not mode then return nil, nil end
    return mode, value > 1 and mode or nil
end

-- The game's Intensity constants (ProjectEbonhold.Constants: MAX_INTENSITY
-- and INTENSITY_LEVEL_1..5). Used only when each is a finite number, the five
-- levels rise strictly from above zero, and the maximum is at least level 5;
-- otherwise nil: no level or maximum is made up.
local function IntensityConstants()
    local ok, maximum, thresholds = pcall(function()
        local pe = _G.ProjectEbonhold
        local constants = type(pe) == "table" and pe.Constants or nil
        if type(constants) ~= "table" then return nil end
        local levels, previous = {}, 0
        for i = 1, 5 do
            local value = constants["INTENSITY_LEVEL_" .. i]
            if type(value) ~= "number" or value ~= value or value >= math.huge
                or value <= previous then return nil end
            levels[i], previous = value, value
        end
        local top = constants.MAX_INTENSITY
        if type(top) ~= "number" or top ~= top or top >= math.huge
            or top < previous then return nil end
        return top, levels
    end)
    if not ok or not maximum then return nil, nil end
    return maximum, thresholds
end

-- The current Intensity (never negative), its level -- the highest constant
-- threshold reached, as the game's own HUD counts it -- and the constants. With
-- valid constants the value is held to their maximum; without them the level,
-- the maximum and the thresholds are unknown (nil) and the value is as read.
local function ReadIntensity()
    local data = _G.EbonholdIntensityData
    if type(data) ~= "table" then return nil, nil end
    local value = tonumber(data.intensity)
    if not value or value ~= value or value >= math.huge or value <= -math.huge then
        return nil, nil
    end
    value = math.max(0, value)
    local maximum, thresholds = IntensityConstants()
    if not maximum then return value, nil end
    value = math.min(maximum, value)
    local level = 0
    for i = 1, 5 do
        if value >= thresholds[i] then level = i end
    end
    return value, level, maximum, thresholds
end

-- The table the HUD mode is kept in: the saved root, or for a read-only saved
-- root the Store owner's session-only table (starting with the saved mode).
local MODE_SAVED_KEYS = {"soulAshHudMode"}
local function ModeRoot()
    NexusDB = NexusDB or {}
    local writable = Nexus.MainInternals and Nexus.MainInternals.WritableRootV1
    local root = type(writable) == "function"
        and writable(NexusDB, MODE_SAVED_KEYS) or nil
    return type(root) == "table" and root or NexusDB
end

local function EnsureDefaultMode()
    local root = ModeRoot()
    if root.soulAshHudMode ~= "server" and root.soulAshHudMode ~= "nexus" then
        root.soulAshHudMode = "nexus"
    end
end

local function UsingNexusHud()
    EnsureDefaultMode()
    return ModeRoot().soulAshHudMode == "nexus"
end

-- The same answer WITHOUT normalizing the stored value. EnsureDefaultMode
-- writes the default into the profile, which is right when this owner is
-- applying the preference and wrong when something is merely reading it: a
-- support report must not store a setting just by describing one.
local function SavedModeIsNexus()
    local saved = type(NexusDB) == "table" and ModeRoot().soulAshHudMode or nil
    return saved ~= "server"
end

-- Is the Nexus HUD standing in for the stock widget right now? Asked of the
-- panel owner, which is the only place that knows whether a render has
-- committed and whether the player wants the panel. A panel suppressed by an
-- open dialog is still able to display, is still wanted, and still counts as
-- the replacement. Issue #164: a panel the PLAYER hid (`wanted` false, a
-- saved choice) is not replacing anything, so the game's own widget keeps its
-- place; a panel that has never committed, has failed, or was never loaded
-- does not count either. An owner that does not report `wanted` is treated
-- as wanting the panel, as before.
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
                return {ready = shown, committed = shown, wanted = true}
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
        return {ready = raw.ready == true, committed = raw.committed == true,
            wanted = raw.wanted ~= false}
    end)
    if not ok then return nil end
    return facts
end

local function ReplacementAvailable()
    local facts = PanelFacts()
    return facts ~= nil and facts.ready == true and facts.wanted == true
end

-- Whether the replacement is positively GONE, which is a stronger statement
-- than "not available right now". A panel part-way through applying a render
-- is briefly unavailable while its committed model still stands; treating
-- that instant as gone would hand the stock widget back and take it away
-- again on the next scan. A panel the player hid is gone as a replacement at
-- once (issue #164), whatever its render state.
local function ReplacementGone()
    local facts = PanelFacts()
    return facts == nil or facts.committed ~= true or facts.wanted == false
end

-- Whether the stock widget should be standing aside for the Nexus HUD. Both
-- halves must hold: the player asked for the Nexus HUD, and that HUD can
-- display. Nothing here is decided from the mode alone.
local function ReplacingServerHud()
    return UsingNexusHud() and ReplacementAvailable()
end

-- Returns whether the frame really did what was asked. A widget with no Hide,
-- or one whose Hide raises, has NOT been taken away by us, and claiming it
-- would later "give back" something we never had. Only what this module
-- changed is put back: it takes the widget away with Hide alone, so it gives
-- it back with Show alone. Its alpha, mouse and anchors were never touched
-- and are not rewritten to a guessed default (issue #164: the stock widget
-- returns exactly where and as the game left it).
local function SetShown(frame, shown)
    if not frame then return false end
    if shown then
        if type(frame.Show) ~= "function" then return false end
        return pcall(frame.Show, frame)
    end
    if type(frame.Hide) ~= "function" then return false end
    return pcall(frame.Hide, frame)
end

-- The widget's own shown flag: true, false, or nil when it cannot say.
local function ReadShown(frame)
    if not frame or type(frame.IsShown) ~= "function" then return nil end
    local ok, value = pcall(frame.IsShown, frame)
    if not ok then return nil end
    return value and true or false
end

-- Gives back the widget this module hid, with Show alone (when `attempt`),
-- and then reads it back. "restored": it reports itself shown; the claim
-- ends. "unknown": Show ran but the widget cannot report IsShown; the claim
-- ends (no readback could ever confirm a retry) and the state stays unknown.
-- "pending": Show is missing, raised or did nothing visible; the widget is
-- still hidden because of us, so the claim is kept for a later readback or
-- lifecycle retry. Nothing else about the widget is touched.
local function GiveBack(frame, attempt)
    local ran = false
    if attempt then ran = SetShown(frame, true) == true end
    local shown = ReadShown(frame)
    if shown == true then
        suppressedFrame, restorePending, restoreUnknown = nil, nil, nil
        return "restored"
    end
    if shown == nil and ran then
        suppressedFrame, restorePending, restoreUnknown = nil, nil, frame
        return "unknown"
    end
    suppressedFrame, restorePending, restoreUnknown = frame, frame, nil
    return "pending"
end

-- `retry`: an explicit lifecycle point may repeat a pending give-back's Show.
local function ApplyVisibility(retry)
    if not rootFrame then return end

    -- Four states. The stock widget is hidden only while a replacement is
    -- really taking its place; it is GIVEN BACK, once, when this module hid
    -- it and the player chose the server HUD; it is given back, once, when
    -- this module hid it for a replacement that can no longer display or
    -- that the player hid; and otherwise it is left exactly as it is. That
    -- last case matters: forcing it to show every second would fight the
    -- game and would override a player who closed it themselves.
    if ReplacingServerHud() then
        -- The confirmed Project Ebonhold root is the complete stock widget.
        -- Hide/show it as one unit; never touch unrelated global addon frames.
        -- Only a hide that actually took something away is remembered as
        -- ours: hiding an already-hidden widget takes nothing, and claiming
        -- it would let a later give-back put back something the player -- or
        -- the game -- had closed for their own reasons.
        --
        -- That question is asked ONCE, on the scan that takes the widget
        -- away. This branch runs every second while the replacement is
        -- displaying, and on every later scan the widget is hidden BECAUSE
        -- WE HID IT; re-asking would make the module forget its own hide one
        -- second after making it, and the give-back would never fire again.
        --
        -- Nor is a hidden widget hidden again. A widget we already took away
        -- is re-hidden only when it reports itself shown; the OnShow hook
        -- below owns the game showing it again, so a widget that cannot say
        -- (unknown state) is left to that hook rather than written every
        -- second. One that was already hidden when the replacement arrived
        -- has nothing to take away and is not touched; an unknown state there
        -- is hidden and claimed, as before.
        local wasShown = ReadShown(rootFrame)
        -- Standing aside again: a give-back still pending is no longer
        -- wanted (the widget is meant to be hidden now), and an unknown one
        -- is superseded by this decision.
        restorePending, restoreUnknown = nil, nil
        if suppressedFrame ~= rootFrame then
            if wasShown == false then
                suppressedFrame = nil
            else
                local hid = SetShown(rootFrame, false)
                suppressedFrame = hid and rootFrame or nil
            end
        elseif wasShown == true then
            SetShown(rootFrame, false)
        end
    elseif not UsingNexusHud() then
        -- The player chose the server HUD. The widget this module hid comes
        -- back once; one the game or the player hid stays theirs. It is not
        -- re-shown every second (issue #164: no recurring Show fighting the
        -- server's own state). The give-back is read back: only a widget
        -- that reports itself shown ends our claim (GiveBack); a pending one
        -- is re-read each scan and its Show is repeated only at a lifecycle
        -- point.
        if suppressedFrame == rootFrame then
            GiveBack(rootFrame, restorePending ~= rootFrame or retry == true)
        else
            suppressedFrame, restorePending = nil, nil
        end
    elseif suppressedFrame == rootFrame and ReplacementGone() then
        -- We took THIS widget away for a replacement, and the replacement is
        -- gone: a committed render failed, the panel stopped being able to
        -- display, or the player hid it. Give it back ONCE and stop claiming
        -- it once it reads back shown, so nothing is forced every second and
        -- a later hide is not fought. A different widget object -- after a
        -- zone change, or a rebuild by the game -- is not one we hid, so it
        -- is left alone.
        GiveBack(rootFrame, restorePending ~= rootFrame or retry == true)
    end

    local hookTarget = rootFrame
    if hookTarget and not hookedFrames[hookTarget]
        and type(hookTarget.HookScript) == "function" then
        hookedFrames[hookTarget] = true
        hookTarget:HookScript("OnShow", function(self)
            -- The same question as above: a widget that comes back while no
            -- replacement can display is left where the game put it. A hide
            -- here takes a widget that was just shown away, so it is ours to
            -- give back, exactly like the scanner's own hide: recorded only
            -- when it really happened, and only for the current widget.
            if ReplacingServerHud() then
                local hid = SetShown(self, false)
                if hid and self == rootFrame then suppressedFrame = self end
            elseif self == restorePending and self == suppressedFrame
                and ReadShown(self) == true then
                -- A pending give-back the game completed itself: it is on
                -- screen again, and no longer ours.
                suppressedFrame, restorePending = nil, nil
            end
        end)
    end
end

-- #126: one summary, built the same way for the cold GetSummary read and for
-- every scanner pass, so the two cannot disagree about where a value comes
-- from. Soul Ash, gain and raw text come from the HUD, the difficulty from
-- ReadDifficulty alone, and Intensity from its own data and constants.
local function BuildSummary()
    if not rootFrame then FindFrames() end
    local summary = ParseSummary(GetAllSourceTexts(), NamedSoulAsh())
    summary.mode, summary.tier = ReadDifficulty()
    summary.intensity, summary.intensityLevel, summary.intensityMax,
        summary.intensityThresholds = ReadIntensity()
    return summary
end

local function SummarySignature(summary)
    return table.concat({ tostring(summary.mode), tostring(summary.tier), tostring(summary.ash), tostring(summary.gain), tostring(summary.intensity), tostring(summary.intensityLevel), tostring(summary.intensityMax), tostring(UsingNexusHud()) }, "|")
end

function M.Init()
    NexusDB = NexusDB or {}
    EnsureDefaultMode()
    if scanner then return end

    scanner = CreateFrame("Frame", "NexusServerStatusScanner", UIParent)
    scanner:RegisterEvent("PLAYER_ENTERING_WORLD")
    -- World entry only drops the frame reference. The difficulty is not reset
    -- here: the next scan reads the service's own known flag again.
    scanner:SetScript("OnEvent", function()
        rootFrame = nil
        -- A world entry is a lifecycle point: the first scan after it may
        -- repeat a pending give-back once (ApplyVisibility's retry).
        retryAfterWorld = true
    end)
    scanner:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (tonumber(dt) or 0)
        if elapsed < 1.0 then return end
        elapsed = 0

        if not rootFrame then FindFrames() end
        local retry = retryAfterWorld
        retryAfterWorld = false
        ApplyVisibility(retry)
        local summary = BuildSummary()
        local sig = SummarySignature(summary)
        if sig ~= cachedSignature then
            cachedSignature = sig
            cachedSummary = summary
            if Nexus.Panel and Nexus.Panel.Refresh then Nexus.Panel.Refresh() end
        end
    end)
end

function M.GetSummary()
    if cachedSignature == "" then
        cachedSummary = BuildSummary()
        cachedSignature = SummarySignature(cachedSummary)
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
    -- Issue #164: whether this module still holds the current widget hidden,
    -- and a give-back that has not read back as shown ("pending") or could
    -- not be read back at all ("unknown"). nil: no give-back is outstanding.
    local restore = nil
    if detected and restorePending == rootFrame then
        restore = "pending"
    elseif detected and restoreUnknown == rootFrame then
        restore = "unknown"
    end
    return {
        mode = nexusMode and "nexus" or "server",
        detected = detected,
        stockShown = shown,
        stockAlpha = alpha,
        replacementAvailable = available,
        replacing = nexusMode and available or false,
        hiddenByNexus = detected and suppressedFrame == rootFrame or false,
        restore = restore,
    }
end

function M.SetMode(mode)
    ModeRoot().soulAshHudMode = mode == "server" and "server" or "nexus"
    ApplyVisibility(true)
    if Nexus.Panel and Nexus.Panel.Refresh then Nexus.Panel.Refresh() end
end

-- Issue #164: the panel owner says the player hid or showed the Nexus panel.
-- The scanner's own decision, made now rather than on its next one-second
-- pass: the widget stands aside for a panel that is wanted and can display,
-- and the one this module hid comes back at once when it is not. Nothing is
-- rescanned, requested or sent; the difficulty itself is never touched.
function M.PanelVisibilityChanged()
    if not rootFrame then FindFrames() end
    ApplyVisibility(true)
    return rootFrame ~= nil
end

-- #32: no stock click handler is found by searching. Project Ebonhold creates
-- HardmodeFrame only inside its own toggle, which also asks the server for the
-- current tier and Soul Ash pool and rebuilds the panel; it publishes the one
-- control that runs that toggle as ProjectEbonhold.HardmodeButton, a child of
-- the run HUD's header. Nexus calls that control's handler and nothing else,
-- and only when the button really sits in ProjectEbonholdPlayerRunFrame.
-- HardmodeFrame:Show() alone would open nothing before the first toggle and
-- show stale data after it, so it is never used to open the panel.
local hardcoreUnavailableNoted = false

-- The published Hardcore control, or nil. Every read of the foreign tables is
-- protected: another addon can replace these globals with anything.
local function HardcoreControl()
    local ok, onClick, button = pcall(function()
        local pe = _G.ProjectEbonhold
        if type(pe) ~= "table" then return nil end
        local b = pe.HardmodeButton
        local root = _G.ProjectEbonholdPlayerRunFrame
        if type(b) ~= "table" or type(root) ~= "table" then return nil end
        local header = b:GetParent()
        if type(header) ~= "table" or header:GetParent() ~= root then return nil end
        local fn = b:GetScript("OnClick")
        if type(fn) ~= "function" then return nil end
        return fn, b
    end)
    if not ok then return nil end
    return onClick, button
end

local function HardcoreShown()
    local ok, shown = pcall(function()
        local hard = _G.HardmodeFrame
        return type(hard) == "table" and hard:IsShown() and true or false
    end)
    return ok and shown or false
end

-- An error raised inside the stock toggle is still reported, not swallowed.
local function ReportError(err)
    local handler = type(geterrorhandler) == "function" and geterrorhandler() or nil
    if type(handler) == "function" then pcall(handler, err) end
end

function M.OpenHardcoreMenu()
    local wasShown = HardcoreShown()
    local onClick, button = HardcoreControl()
    if onClick then
        -- The stock toggle: opens with a fresh request, or closes when open.
        -- What counts is whether the panel changed, even if the toggle
        -- raised after showing it.
        local ok, err = pcall(onClick, button, "LeftButton")
        if not ok then ReportError(err) end
        if HardcoreShown() ~= wasShown then return true end
    end
    if wasShown then
        -- Closing needs no identified control; nothing is requested or built.
        if pcall(function() local hard = _G.HardmodeFrame; hard:Hide() end)
            and not HardcoreShown() then
            return true
        end
    end
    if not hardcoreUnavailableNoted and type(print) == "function" then
        hardcoreUnavailableNoted = true
        pcall(print, "|cff7fd5ffNexus:|r " .. Say("server.chat.hardcore_menu_unavailable",
            "The Hardcore menu is not available yet. Choose 'Use Server Difficulty / Soul Ash HUD' "
            .. "in the Nexus menu and open it from the server HUD."))
    end
    return false
end

function M.Rescan()
    rootFrame = nil
    cachedSignature = ""
    local found = FindFrames()
    ApplyVisibility(true)
    return found
end

return M
