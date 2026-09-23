-- Nexus: ui/SupportReport.lua
-- One support page: read an incident, copy a compact summary, or prepare the
-- report file. Reading is passive. Only the explicitly labelled preparation
-- touches the isolated NexusSupport storage, and even that writes nothing into
-- NexusDB, no receipt, no assignment and no gameplay state.
--
-- The window never reloads, logs out or closes the client, and it never claims
-- a file exists on disk: WoW writes SavedVariables at its own save boundary.

Nexus = Nexus or {}
local UI = {}
Nexus.SupportReportUI = UI

local frame = nil
local selectedIncident = nil
local preparing = nil
local lastPrepared = nil

local function text(parent, x, y, w, h, value)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f:SetPoint("TOPLEFT", x, y); f:SetSize(w, h)
    f:SetJustifyH("LEFT"); f:SetJustifyV("TOP")
    f:SetText(value or ""); return f
end

local function button(parent, x, y, w, label, fn)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 24); b:SetPoint("TOPLEFT", x, y); b:SetText(label)
    b:SetScript("OnClick", fn)
    b:SetFrameLevel(parent:GetFrameLevel() + 2); b:EnableMouse(true)
    return b
end

local function report() return Nexus.SupportReport end
local function incidents()
    local support = Nexus.SupportIncidents
    return support and support.History() or {}
end

local function selected()
    local list = incidents()
    if selectedIncident then
        for _, entry in ipairs(list) do
            if entry.id == selectedIncident then return entry end
        end
    end
    return list[#list]
end

local function storageLine()
    local builder = report()
    if not builder then return "The report builder is unavailable." end
    local status = builder.StorageStatus()
    if not status.loaded then
        return "Support storage: not loaded. Prepare report file loads it on demand."
    end
    if status.incompatible then
        return "Support storage: left untouched (" .. tostring(status.incompatible)
            .. "). Use Copy summary instead."
    end
    local latest = _G.NexusSupportStorage and _G.NexusSupportStorage.Latest()
    if latest then
        return "Support storage: report " .. tostring(latest.id) .. ", "
            .. tostring(latest.bytes) .. " bytes in " .. tostring(latest.chunkCount)
            .. " chunk(s), checksum " .. tostring(latest.checksum)
            .. ". Preparing another one replaces it."
    end
    return "Support storage: ready; no report has been prepared yet."
end

-- Load-on-demand, and only for an explicit request. A missing component is not
-- an error: the copy route stays available and says so.
local function ensureStorage()
    if _G.NexusSupportStorage then return true end
    if type(LoadAddOn) ~= "function" then
        return false, "this client cannot load the support component on demand"
    end
    local ok, loaded = pcall(LoadAddOn, "NexusSupport")
    if not ok or not loaded then
        return false, "the NexusSupport component is not installed or is disabled"
    end
    return _G.NexusSupportStorage ~= nil,
        _G.NexusSupportStorage == nil and "the support component did not register its storage" or nil
end

local function refresh()
    if not frame or not frame:IsShown() then return end
    local list = incidents()
    local incident = selected()
    frame.status:SetText("Retained incidents this session: " .. #list
        .. (incident and ("; showing #" .. tostring(incident.id)) or "; none to show"))
    local builder = report()
    local lines = builder and builder.IncidentLines(incident) or {"unavailable"}
    frame.incident:SetText(table.concat(lines, "\n"))
    frame.storage:SetText(storageLine())
    frame.prepared:SetText(lastPrepared or "")
    frame.previous:Enable(); frame.next:Enable()
    if #list <= 1 then frame.previous:Disable(); frame.next:Disable() end
end

local function selectDelta(delta)
    local list = incidents()
    if #list == 0 then return end
    local index = #list
    local incident = selected()
    for position, entry in ipairs(list) do
        if incident and entry.id == incident.id then index = position end
    end
    index = math.max(1, math.min(#list, index + delta))
    selectedIncident = list[index].id
    refresh()
end

local function showCopy(body, note)
    frame.copyNote:SetText(note or "")
    frame.copyBox:SetText(body or "")
    frame.copyBox:SetCursorPosition(0)
    frame.copyScroll:Show()
end

local function ensure()
    if frame then return end
    frame = CreateFrame("Frame", "NexusSupportReport", UIParent)
    frame:Hide()
    frame:SetSize(720, 560)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG"); frame:SetFrameLevel(50); frame:EnableMouse(true)
    frame:SetMovable(true); frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=14,
        insets={left=4, right=4, top=4, bottom=4}})
    frame:SetBackdropColor(.035, .04, .05, 1)

    text(frame, 20, -14, 600, 22, "Nexus support report")
    text(frame, 20, -36, 660, 30,
        "Copy a summary for a ticket, or prepare a report file WoW writes at your next reload or logout.")
    frame.status = text(frame, 20, -70, 660, 20)
    frame.previous = button(frame, 20, -92, 90, "Previous", function() selectDelta(-1) end)
    frame.next = button(frame, 116, -92, 90, "Next", function() selectDelta(1) end)
    frame.incident = text(frame, 20, -124, 680, 150)

    frame.storage = text(frame, 20, -282, 680, 32)
    button(frame, 20, -318, 130, "Copy summary", function()
        local builder = report()
        if not builder then return end
        local body, meta = builder.Summary(selected())
        showCopy(body, "Select this text and copy it (Ctrl+A, Ctrl+C). "
            .. meta.bytes .. " of " .. builder.SUMMARY_MAX_BYTES
            .. " bytes. Nothing was sent anywhere.")
    end)
    button(frame, 156, -318, 160, "Prepare report file", function()
        UI.PrepareFile(false)
    end)
    frame.advanced = CreateFrame("CheckButton", "NexusSupportExtended", frame,
        "UICheckButtonTemplate")
    frame.advanced:SetSize(22, 22); frame.advanced:SetPoint("TOPLEFT", 330, -316)
    text(frame, 356, -320, 340, 20, "Advanced: full retained report (private)")
    button(frame, 20, -348, 200, "Inspect prepared report", function()
        local storage = _G.NexusSupportStorage
        local latest = storage and storage.Latest()
        if not latest then
            frame.prepared:SetText("No prepared report is stored for this account.")
            return
        end
        local readOk, stored = pcall(storage.Read)
        if not readOk then stored = nil end
        local builder = report()
        local sum = stored and builder and builder.Checksum(stored.chunks) or nil
        frame.prepared:SetText("Stored report " .. tostring(latest.id) .. ": "
            .. tostring(latest.bytes) .. " bytes, " .. tostring(latest.chunkCount)
            .. " chunk(s), checksum " .. tostring(latest.checksum)
            .. (sum and (sum == latest.checksum
                and "; matches its own checksum in memory"
                or "; CHECKSUM MISMATCH in the stored copy") or "")
            .. ". This reads the stored copy; it does not prove the session that made it still exists.")
    end)
    frame.prepared = text(frame, 20, -378, 680, 46)

    frame.copyNote = text(frame, 20, -428, 680, 20)
    frame.copyScroll = CreateFrame("ScrollFrame", "NexusSupportCopyScroll", frame,
        "UIPanelScrollFrameTemplate")
    frame.copyScroll:SetPoint("TOPLEFT", 20, -448)
    frame.copyScroll:SetSize(660, 70)
    frame.copyBox = CreateFrame("EditBox", nil, frame.copyScroll)
    frame.copyBox:SetMultiLine(true)
    frame.copyBox:SetMaxLetters(0)
    frame.copyBox:SetAutoFocus(false)
    frame.copyBox:SetFontObject(ChatFontNormal)
    frame.copyBox:SetWidth(646)
    frame.copyBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.copyScroll:SetScrollChild(frame.copyBox)

    button(frame, 500, -520, 100, "Clear focus", function() frame.copyBox:ClearFocus() end)
    button(frame, 605, -520, 85, "Close", function() frame:Hide() end)
    frame:SetScript("OnShow", function() refresh() end)
    UISpecialFrames = UISpecialFrames or {}
    UISpecialFrames[#UISpecialFrames + 1] = "NexusSupportReport"
end

-- Prepare in bounded steps, then hand the COMPLETE snapshot over. A failure or
-- a missing component leaves the previous stored report exactly as it was.
function UI.PrepareFile(extended)
    ensure()
    local builder = report()
    if not builder then return nil, "the report builder is unavailable" end
    if frame and frame.advanced and frame.advanced:GetChecked() then
        extended = true
    end
    local ok, why = ensureStorage()
    if not ok then
        lastPrepared = "Not prepared: " .. tostring(why)
            .. ". Use Copy summary instead; nothing was changed."
        refresh()
        return nil, why
    end
    local status = builder.StorageStatus()
    if status.incompatible then
        -- Known before any work is done: do not build a report that cannot be
        -- stored, and leave the existing data exactly as it is.
        lastPrepared = "Not prepared: existing support data was left untouched ("
            .. tostring(status.incompatible) .. "). Use Copy summary instead."
        refresh()
        return nil, status.incompatible
    end
    local prepared, snapshot, failure = pcall(builder.Prepare, {
        incident = selected(), extended = extended == true,
    })
    if not prepared then
        lastPrepared = "Not prepared: the report could not be built ("
            .. tostring(snapshot) .. "). The previously stored report was kept."
        refresh()
        return nil, snapshot
    end
    if not snapshot then
        lastPrepared = "Not prepared: " .. tostring(failure)
            .. ". The previously stored report was kept."
        refresh()
        return nil, failure
    end
    local ok, stored, meta = pcall(builder.Store, snapshot)
    if not ok then
        lastPrepared = "Not prepared: the support component refused the report ("
            .. tostring(stored) .. "). The previously stored report was kept."
        refresh()
        return nil, stored
    end
    if not stored then
        lastPrepared = "Not prepared: " .. tostring(meta)
            .. ". The previously stored report was kept."
        refresh()
        return nil, meta
    end
    lastPrepared = builder.WrittenNotice(meta) .. "\nAfter that, attach "
        .. builder.FilePathHint()
        .. " (the account folder is the one you played on)."
        .. (meta.partial and "\nThis report is partial: " .. tostring(meta.omissions) or "")
    refresh()
    return meta
end

function UI.Show()
    ensure()
    frame:Show()
    refresh()
    return frame
end

function UI.Hide() if frame then frame:Hide() end end

return UI
