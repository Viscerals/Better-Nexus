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

-- Full UI localization (issues #143-#148): this page's labels, buttons and
-- status sentences come from Nexus.Localization, looked up when shown. The
-- incident lines, the copyable summary and the prepared report are support
-- payload: they are never translated and their bytes are unchanged. Values
-- (IDs, sizes, checksums, reasons) are escaped and inserted verbatim.
local function T(key) return (Nexus.Localization.Text(key)) end
-- legacy: the exact English the page showed, used only when a value is too
-- long for the template (so the English output never changes).
local function TF(key, args, legacy)
    local text, source = Nexus.Localization.Format(key, args)
    if source == "unavailable" and legacy ~= nil then return legacy end
    return text
end
-- The raw reasons this page and its builder produce stay the values that
-- are returned and compared; only their display is looked up here. A
-- reason not listed (a support component's own note) is shown as it is.
local REASON_KEYS = {
    ["this client cannot load the support component on demand"] = "support.reason.cannot_load_on_demand",
    ["the NexusSupport component is not installed or is disabled"] = "support.reason.component_not_installed",
    ["the support component did not register its storage"] = "support.reason.storage_not_registered",
    ["the support component is not loaded"] = "support.reason.component_not_loaded",
    ["the support component did not answer"] = "support.reason.component_no_answer",
    ["the report was not completed, so the previous one was kept"] = "support.reason.report_not_completed",
    ["the support component refused the report"] = "support.reason.component_refused",
    ["preparation did not finish within its step budget"] = "support.reason.step_budget",
}
-- The refusals companion/NexusSupport/Storage.lua writes (its loader, its
-- report check and Replace), every fixed and composed one at this version:
-- exact texts and its own formats (%d a count: chunk index, byte limit;
-- %s a code value: format number, meta field name; a nested reason through
-- this same book). The component keeps and returns them raw; a note it
-- writes that is not listed is shown as it is.
local STORAGE_PHRASES = {exact = {
    ["the saved value is not a table"] = "support.reason.storage_not_table",
    ["the saved data has no known format marker"] = "support.reason.storage_no_format",
    ["report must be a table"] = "support.reason.report_not_table",
    ["report carries a metatable"] = "support.reason.report_metatable",
    ["report has no meta section"] = "support.reason.report_no_meta",
    ["report has no chunks"] = "support.reason.report_no_chunks",
    ["report has no content"] = "support.reason.report_no_content",
    ["report has too many chunks"] = "support.reason.report_too_many_chunks",
    ["support storage is unavailable"] = "support.reason.storage_unavailable",
    ["the support component is not loaded"] = "support.reason.component_not_loaded",
}, formats = {
    {format = "the saved data was written by a newer version (%s)", key = "support.reason.storage_newer_format", fields = {"format"}},
    {format = "the saved data uses an earlier format (%s)", key = "support.reason.storage_earlier_format", fields = {"format"}},
    {format = "meta field is not a scalar: %s", key = "support.reason.report_meta_not_scalar", fields = {"field"}},
    {format = "chunk %d is not text", key = "support.reason.report_chunk_not_text", fields = {"index"}},
    {format = "chunk %d is larger than the supported %d bytes", key = "support.reason.report_chunk_too_large", fields = {"index", "limit"}},
    {format = "the report is larger than the supported %d bytes", key = "support.reason.report_too_large", fields = {"limit"}},
    {format = "existing support data was left untouched: %s", key = "support.reason.storage_left_untouched",
        fields = {"reason"}, nested = {reason = true}},
}}
local storageBook
local function ReasonText(raw)
    local key = type(raw) == "string" and REASON_KEYS[raw]
    if key then return T(key) end
    local L = Nexus.Localization
    if type(raw) == "string" and type(L) == "table" and type(L.PhraseBook) == "function" then
        if not storageBook or storageBook.seam ~= L then
            storageBook = L.PhraseBook(STORAGE_PHRASES)
            storageBook.seam = L
        end
        return (L.Phrase(raw, storageBook))
    end
    return raw
end

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
    if not builder then return T("support.status.builder_unavailable") end
    local status = builder.StorageStatus()
    if not status.loaded then
        return T("support.status.storage_not_loaded")
    end
    if status.incompatible then
        local reason = builder.Escape(ReasonText(status.incompatible))
        return TF("support.status.storage_left_untouched", {reason = reason},
            "Support storage: left untouched (" .. reason .. "). Use Copy summary instead.")
    end
    -- Through the builder, which owns the shape: the page never reaches into
    -- the storage component itself, whatever that component turns out to be.
    local latest = type(builder.StoredSummary) == "function" and builder.StoredSummary() or nil
    if latest then
        return TF("support.status.storage_holds_report", {
            id = builder.Escape(latest.id), bytes = builder.Escape(latest.bytes),
            chunks = builder.Escape(latest.chunkCount),
            checksum = builder.Escape(latest.checksum)})
    end
    if not status.ready then
        if not status.reason then return T("support.status.storage_not_ready") end
        return TF("support.status.storage_not_ready_reason",
            {reason = builder.Escape(ReasonText(status.reason))})
    end
    return T("support.status.storage_ready_none")
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
    local shown = incident and tostring(incident.id) or nil
    frame.status:SetText(incident
        and TF("support.status.incidents_showing", {count = tostring(#list), id = shown},
            "Retained incidents this session: " .. #list .. "; showing #" .. shown)
        or TF("support.status.incidents_none", {count = tostring(#list)}))
    local builder = report()
    -- The incident lines are the report's own payload, shown as they are.
    local lines = builder and builder.IncidentLines(incident) or {T("support.value.unavailable")}
    -- A font string interprets pipe sequences, so a recorded label is escaped
    -- HERE. The copyable text is never escaped: see core/SupportReport.lua.
    frame.incident:SetText(builder and builder.Escape(table.concat(lines, "\n"))
        or table.concat(lines, "\n"))
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

    text(frame, 20, -14, 600, 22, T("support.title.support_report"))
    text(frame, 20, -36, 660, 30, T("support.body.copy_or_prepare"))
    frame.status = text(frame, 20, -70, 660, 20)
    frame.previous = button(frame, 20, -92, 90, T("support.button.previous_incident"), function() selectDelta(-1) end)
    frame.next = button(frame, 116, -92, 90, T("support.button.next_incident"), function() selectDelta(1) end)
    frame.incident = text(frame, 20, -124, 680, 150)

    frame.storage = text(frame, 20, -282, 680, 32)
    -- Help quotes these two labels by name; help_action_first finds them as
    -- reviewed keys bound here with the exact English.
    button(frame, 20, -318, 130, T("support.button.copy_summary"), function()
        local builder = report()
        if not builder then return end
        local body, meta = builder.Summary(selected())
        local size, limit = meta.bytes .. "", builder.SUMMARY_MAX_BYTES .. ""
        showCopy(body, TF("support.status.copy_summary_note", {bytes = size, max = limit},
            "Select this text and copy it (Ctrl+A, Ctrl+C). " .. size .. " of " .. limit
            .. " bytes. Nothing was sent anywhere."))
    end)
    button(frame, 156, -318, 160, T("support.button.prepare_report_file"), function()
        UI.PrepareFile(false)
    end)
    frame.advanced = CreateFrame("CheckButton", "NexusSupportExtended", frame,
        "UICheckButtonTemplate")
    frame.advanced:SetSize(22, 22); frame.advanced:SetPoint("TOPLEFT", 330, -316)
    text(frame, 356, -320, 340, 20, T("support.label.advanced_private"))
    button(frame, 20, -348, 200, T("support.button.inspect_prepared"), function()
        -- Through the builder, like every other component read on this page.
        local builder = report()
        local latest = builder and type(builder.StoredReport) == "function"
            and builder.StoredReport() or nil
        if not latest then
            frame.prepared:SetText(T("support.status.no_prepared_report"))
            return
        end
        -- One whole sentence for each checksum outcome (not compared, the
        -- same, different).
        local key = latest.matches == nil and "support.status.stored_report"
            or latest.matches and "support.status.stored_report_matches"
            or "support.status.stored_report_mismatch"
        frame.prepared:SetText(TF(key, {id = builder.Escape(latest.id),
            bytes = builder.Escape(latest.bytes),
            chunks = builder.Escape(latest.chunkCount),
            checksum = builder.Escape(latest.checksum)}))
    end)
    frame.prepared = text(frame, 20, -378, 680, 46)

    frame.copyNote = text(frame, 20, -428, 680, 20)
    -- Fixed boxes; a text longer than its box is complete in a tooltip.
    if Nexus.LayoutMetrics then
        for _, fs in ipairs({frame.incident, frame.storage, frame.prepared, frame.copyNote}) do
            Nexus.LayoutMetrics.FullTextTooltip(fs, frame)
        end
    end
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

    button(frame, 500, -520, 100, T("support.button.clear_focus"), function() frame.copyBox:ClearFocus() end)
    button(frame, 605, -520, 85, T("support.button.close"), function() frame:Hide() end)
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
    -- The returned reasons stay raw; only the page's sentence is looked up.
    local ok, why = ensureStorage()
    if not ok then
        local reason = builder.Escape(ReasonText(why))
        lastPrepared = TF("support.status.not_prepared_use_copy", {reason = reason},
            "Not prepared: " .. reason .. ". Use Copy summary instead; nothing was changed.")
        refresh()
        return nil, why
    end
    local status = builder.StorageStatus()
    if status.incompatible then
        -- Known before any work is done: do not build a report that cannot be
        -- stored, and leave the existing data exactly as it is.
        local reason = builder.Escape(ReasonText(status.incompatible))
        lastPrepared = TF("support.status.not_prepared_left_untouched", {reason = reason},
            "Not prepared: existing support data was left untouched ("
            .. reason .. "). Use Copy summary instead.")
        refresh()
        return nil, status.incompatible
    end
    local prepared, snapshot, failure = pcall(builder.Prepare, {
        incident = selected(), extended = extended == true,
    })
    if not prepared then
        local raw = tostring(snapshot)
        lastPrepared = TF("support.status.not_prepared_build_failed", {error = raw},
            "Not prepared: the report could not be built ("
            .. raw .. "). The previously stored report was kept.")
        refresh()
        return nil, snapshot
    end
    if not snapshot then
        local reason = builder.Escape(ReasonText(failure))
        lastPrepared = TF("support.status.not_prepared_kept", {reason = reason},
            "Not prepared: " .. reason .. ". The previously stored report was kept.")
        refresh()
        return nil, failure
    end
    local ok, stored, meta = pcall(builder.Store, snapshot)
    if not ok then
        local raw = tostring(stored)
        lastPrepared = TF("support.status.not_prepared_component_refused", {error = raw},
            "Not prepared: the support component refused the report ("
            .. raw .. "). The previously stored report was kept.")
        refresh()
        return nil, stored
    end
    if not stored then
        local reason = builder.Escape(ReasonText(meta))
        lastPrepared = TF("support.status.not_prepared_kept", {reason = reason},
            "Not prepared: " .. reason .. ". The previously stored report was kept.")
        refresh()
        return nil, meta
    end
    local partial = type(meta) == "table" and meta.partial
        and builder.Escape(meta.omissions) or nil
    lastPrepared = builder.Escape(builder.WrittenNotice(meta)) .. "\n"
        .. TF("support.status.attach_file", {path = builder.FilePathHint()})
        .. (partial and ("\n" .. TF("support.status.report_partial", {omissions = partial},
            "This report is partial: " .. partial)) or "")
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
