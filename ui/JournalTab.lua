-- Nexus: ui/JournalTab.lua
-- A "Nexus Progress" tab (formerly "Nexus Advisor") inside ProjectEbonhold's
-- Echo Journal: a read-only Build Progress summary first, then the sections
-- supplied by an injected dataProvider callback behind Show details: plain
-- text, or icon rows where a section supplies structured tomeRows.
-- Structures relied on (captured live against this exact client):
--   frame  ProjectEbonholdEchoJournal
--   tabs   ProjectEbonholdEchoJournalTab1..N (CharacterFrameTabButton
--          textures), parent = the journal frame
--   scroll ProjectEbonholdEchoJournalScroll = content area
-- The journal UI is built LAZILY on first open: a login-time install
-- succeeds only after /reload with the journal already built, so
-- "frames not present" is the NORMAL, SILENT state until the hooked
-- EchoJournal.Show/Toggle fires and the install retries. Our tab index
-- is existing-tab-count + 1 (a leftover EchoOptimizer Tab4 shifts us
-- to 5 instead of colliding).
-- SOFT-FAIL CONTRACT: TryInstall pcall-wraps everything and returns
-- false on any failure -- no tab, no error, retried on next Show.
-- All DATA arrives through the provider; this file touches journal
-- FRAMES only (documented presentation-layer exception), never
-- PerkService.

Nexus = Nexus or {}
local M = {}
Nexus.JournalTab = M

local installed = false
local hooked = false
local provider                -- dataProvider() -> { sections={ {title,lines={}} }, version }
local ourTab, panel, scroll, child
local associationPanel
local scanFrame, associationVisible = nil, false
local wishlistPicker, wishlistPickerRows = nil, {}
local HideWishlistPicker
local theirTabCount = 0
local linePool, linesUsed = {}, 0

local ASSET ="Interface\\AddOns\\ProjectEbonhold\\assets\\"
local NOTE1 = "Compares the assigned Wishlist with the ACTIVE Saved Build."
local NOTE2 = "|cff8a8a8aSet associations in My Builds. Saved Build activation requires the server's supported level and state.|r"
-- Build Progress (the tab was "Nexus Advisor"): a short read-only intro, the
-- takeaway and display-only Echo rows first, every provider section unchanged
-- behind Show details. The full explanations sit in the intro tooltip and in
-- the details. The page only reads.
local TAB_LABEL = "Nexus Progress"
local HEADER = "Build Progress"
local INTRO = "Assigned Wishlist vs active Saved Build. Read-only."
local PURPOSE = "See what your assigned Wishlist still needs. This page only shows information: opening it "
    .. "does not roll, spend Orbs, lock Echoes, or save or activate a Saved Build."
local FAMILY_NOTE = "Family coverage, not copies: a family counts as represented once one copy is known, "
    .. "so it may still need more requested copies."
local NO_TARGET = "No Wishlist is assigned. Assign one in My Builds to see its progress."
local MISSING_EXPLAIN = "no known copy of this requested Echo family."
local OFF_EXPLAIN = "in the active Saved Build, but the assigned Wishlist does not request this family."
-- The off-Wishlist list is filled only from an active Saved Build whose
-- contents are confirmed, and it arrives empty when none was. An empty list
-- therefore shows nothing about the Saved Build, so it is never shown as 0.
local OFF_LISTED = "Off Wishlist: families in the active Saved Build that the assigned Wishlist does not request."
local OFF_NONE = "Off Wishlist: none listed. These families are listed only when the active Saved Build's "
    .. "contents are confirmed, so an empty list can also mean nothing was compared yet (for example "
    .. "on a first run). It does not show that there are none."
local OFF_UNAVAILABLE = "Off Wishlist: unavailable. The list of these families could not be read, "
    .. "so nothing is assumed about them."
local NEUTRAL_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local ROW_H, TILE = 26, 24
local detailsShown = false
-- Set by M.Invalidate after a semantic change; cleared by every page refresh.
local refreshPending = false
local detailsButton, buildsButton, introHover, countsHover
local rowPool, rowsUsed = {}, 0
-- Tome state rows behind Show details have their own pool, so their theme
-- colours and tooltip entries never carry over into the Missing rows.
local tomePool, tomesUsed = {}, 0
local TOME_STATUS_W = 120
-- The provider's request section. Its title does not begin with "Pending",
-- which Summarize reads as the Wishlist's missing-family list.
local TOME_REQUESTS = "Tome requests awaiting confirmation"
local PENDING_BADGE = { enable = "Enable pending", disable = "Disable pending" }
local TOME_SCOPE = "Observed when this page was refreshed; server state and freshness are unverified."
local TOME_STALE = "This reading may be stale; Tome state coverage gives the reason."
local DeselectOurTab
-- Assignment only records the target. The automatic save (Auto ON, autoSave,
-- Ratchet.Dominates) is what may replace the active Saved Build. A changed
-- assignment marks the adapter's data dirty (MarkWishlistProjectionDirty);
-- Auto's next update step (AutomationRuntime RunUpdate -> StepSave) then
-- checks a finished level-80 run not yet saved this visit against the newly
-- assigned Wishlist. M4 (FN7): the copy states that trigger, not a latency.
local ASSIGN_NOTE = "Assigning by itself does not change any Saved Build."
-- An empty numbered Saved Build holds no Wishlist of its own and refuses an
-- assignment. The name the Journal shows beside it is the retained first-run
-- Wishlist, which the gear opens for editing without a destination. These
-- wordings say that; no action behind them changes.
local EMPTY_SLOT_ASSIGN = "This Saved Build is empty, so assigning a Wishlist to it is refused until it holds Echoes. "
    .. ASSIGN_NOTE
local EMPTY_SLOT_SELECTOR = "This Saved Build is empty, so no Wishlist can be assigned to it until it holds Echoes. "
    .. "A name shown here is the first-run Wishlist, not an assignment to this Saved Build. " .. ASSIGN_NOTE
local AUTO_SAVE_WARNING = "With Auto ON, Nexus may replace the active Saved Build with a finished run that "
    .. "has more overall Wishlist progress, or equal progress after cleanup or an even swap of requested "
    .. "copies. At level 80, a changed assignment makes Auto check a finished run it has not saved yet. "
    .. "Saving edits to the assigned Wishlist can also lead to a replacement without a new run."
local AUTO_SAVE_ORBS = "The replaced build may hold an Echo you value, even one obtained with Orbs: "
    .. "Orb investment is not compared. Keep Auto OFF to leave the Saved Build unchanged."

-- UX-05: an assignment to a numbered Saved Build while Auto is selected (ON,
-- also while held) asks first, naming the Wishlist, the target captured when
-- the player chose it and the conditional replacement (no timing promise).
-- Cancel changes nothing; nothing here changes Auto. With Auto OFF the choice
-- assigns at once. Used by the Journal picker and the editor's candidates.
StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["NEXUS_ASSIGN_WISHLIST_AUTO_ON"] = {
    text = "Assign '%s' to %s?\n" .. "Auto is ON. Assigning by itself does not change the Saved Build. But "
        .. "when it is active and a finished run at level 80 passes Auto's checks, Nexus may replace it with "
        .. "the run. Cancel changes nothing. To avoid that, choose Cancel, turn Auto OFF, then assign.",
    button1 = "Assign",
    button2 = "Cancel",
    OnAccept = function(_, data)
        if type(data) == "table" and type(data.assign) == "function" then data.assign() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true,
}

-- Whether Auto is selected (ON, also while held), from the runtime's
-- counters (memory only).
function M.AutoSelected()
    if type(Nexus.RecomputeStats) ~= "function" then return false end
    local ok, stats = pcall(Nexus.RecomputeStats)
    return ok and type(stats) == "table" and stats.autoEnabled == true
end

-- A Wishlist or Saved Build name as it may be shown in chat or a dialog.
function M.SafeName(text, fallback)
    local display = Nexus.Identity and Nexus.Identity.DisplaySafeText
    local shown = display and display(tostring(text or ""), 1024, false) or nil
    if type(shown) ~= "string" or shown == "" then shown = tostring(fallback or "") end
    return shown
end

local function OwnerKeyNow()
    local store = Nexus.Store
    if not (store and type(store.CurrentOwnerKey) == "function") then return nil end
    local ok, owner = pcall(store.CurrentOwnerKey)
    return ok and owner or nil
end

-- One assignment the player chose. `assign` performs it (and every role
-- choice it starts) for the target captured when the player chose it. A
-- numbered, non-empty target with Auto selected asks first; the first-run
-- target has no Saved Build to replace, and an empty one is refused by the
-- assignment itself. When the confirmation cannot be shown, nothing is
-- assigned (never assigned unasked while Auto is selected). One accept
-- performs it once; an accept after the character's saved data changed
-- assigns nothing. Returns true when it asked, false when it assigned at
-- once, nil and a reason when it refused.
function M.AssignWithConsent(wishlistName, targetLabel, numbered, assign)
    if not numbered or not M.AutoSelected() then
        assign()
        return false
    end
    if type(StaticPopup_Show) ~= "function" or type(StaticPopupDialogs) ~= "table"
        or type(StaticPopupDialogs["NEXUS_ASSIGN_WISHLIST_AUTO_ON"]) ~= "table" then
        print("|cffff6060Nexus:|r Nothing was assigned: Auto is ON and the confirmation that names its "
            .. "consequence could not be shown. Turn Auto OFF to assign, or try again later.")
        return nil, "consent_unavailable"
    end
    local owner, answered = OwnerKeyNow(), false
    StaticPopup_Show("NEXUS_ASSIGN_WISHLIST_AUTO_ON", wishlistName, targetLabel, {assign = function()
        if answered then return end
        answered = true
        if OwnerKeyNow() ~= owner then
            print("|cffff6060Nexus:|r Nothing was assigned: this character's saved data changed after you "
                .. "were asked. Open the Wishlist chooser again.")
            return
        end
        assign()
    end})
    return true
end

------------------------------------------------------------------------
-- Text lines
------------------------------------------------------------------------

local function AcquireLine()
    linesUsed = linesUsed + 1
    local fs = linePool[linesUsed]
    if not fs then
        fs = child:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetJustifyH("LEFT")
        fs:SetJustifyV("TOP")
        linePool[linesUsed] = fs
    end
    fs:Show()
    return fs
end

-- The provider section with this title (or title prefix), if any.
local function Section(sections, title, prefix)
    for i = 1, #sections do
        local sec = sections[i]
        local t = type(sec) == "table" and tostring(sec.title or "") or ""
        if t == title or (prefix and t:sub(1, #title) == title) then return sec end
    end
end

-- The provider's Target line, read only in the exact form JournalData writes
-- it. Counts are taken from the anchored end, never from the Wishlist name.
local TARGET_COUNTS = ": (%d+) Echo families %-%- (%d+) represented, (%d+) missing, "
    .. "(%d+) off%-Wishlist families in the saved build$"
local TARGET_TAGS = { [""] = true, [" (Echo Wishlist build)"] = true, [" (active loadout)"] = true }
-- The explanations JournalData appends to an off-Wishlist family name.
local OFF_SUFFIXES = { "  (not on the target plan; compare after the next run)",
    "  (a later run may reduce these extras)" }
local NOTES_FIRST = "Compares the assigned Wishlist with the active Saved Build; "
    .. "planned locked targets are not proof of ownership."
-- The estimate texts JournalData and Ratchet.RunsEstimate write when there is
-- nothing to estimate: no Wishlist, no requested family, or no result.
local NO_ESTIMATE = { ["no estimate (advisor mode)"] = true, ["estimate unavailable"] = true,
    ["no wishlist target - advisor mode"] = true }
local UNKNOWN_NO_PENDING = "the list of missing families was not received."
local UNKNOWN_BAD_PENDING = "the list of missing families could not be read or does not match its count."
local UNKNOWN_CONTRADICTORY = "the supplied counts and lists do not agree."
local UNKNOWN_GRAMMAR = "the Wishlist summary line could not be read."

-- A provider list, or nil unless it is a plain sequence of non-empty strings.
local function TextLines(lines)
    if type(lines) ~= "table" then return nil end
    local count = 0
    for _ in pairs(lines) do count = count + 1 end
    if count ~= #lines then return nil end
    for i = 1, #lines do
        if type(lines[i]) ~= "string" or lines[i] == "" then return nil end
    end
    return lines
end

-- What the provider's sections establish, and nothing more. `known` needs the
-- Target counts in their exact form, one Pending list matching its title and
-- those counts, and an off-Wishlist list that does not contradict them. Any
-- gap or disagreement leaves the family progress unknown. A family is
-- represented when one copy is known; copies are never compared here.
local function Summarize(sections)
    local s = {}
    local target = Section(sections, "Target")
    local first = target and type(target.lines) == "table" and target.lines[1]
    if type(first) ~= "string" or first == "" then return s end
    if first:find("No wishlist set", 1, true) == 1 then s.noTarget = true return s end
    s.targetLine = first

    local pendingSec, pendingSections = nil, 0
    for i = 1, #sections do
        local sec = sections[i]
        if type(sec) == "table" and tostring(sec.title or ""):sub(1, 7) == "Pending" then
            pendingSec = pendingSec or sec
            pendingSections = pendingSections + 1
        end
    end
    local pending, n
    if pendingSec then
        n = tonumber(tostring(pendingSec.title):match("^Pending %((%d+)%)$"))
        pending = TextLines(pendingSec.lines)
    end
    local offSec = Section(sections, "Extra copies compared with the plan")
    local off = offSec and TextLines(offSec.lines)

    local at, _, total, rep, miss, offN = first:find(TARGET_COUNTS)
    local head = at and first:sub(1, at - 1)
    local name, tag
    if head then name, tag = head:match("^Wishlist '(.*)'(.*)$") end
    total, rep, miss, offN = tonumber(total), tonumber(rep), tonumber(miss), tonumber(offN)
    if pendingSections > 1 then s.problem = UNKNOWN_CONTRADICTORY
    elseif not pendingSec then s.problem = UNKNOWN_NO_PENDING
    elseif not (n and pending and #pending == n) then s.problem = UNKNOWN_BAD_PENDING
    elseif not (name and TARGET_TAGS[tag]) then s.problem = UNKNOWN_GRAMMAR
    elseif total ~= rep + miss or miss ~= n or (off and #off ~= offN) then
        s.problem = UNKNOWN_CONTRADICTORY
    else
        s.known, s.title, s.pending, s.off = true, head, pending, off
        s.total, s.represented, s.missing, s.offCount = total, rep, miss, offN
        -- The one section these Missing rows were validated from (Show
        -- details draws it without repeating them).
        s.pendingSection = pendingSec
    end
    return s
end

-- The first line of the page: what is still missing, or why that is unknown.
local function Takeaway(s)
    if s.noTarget then return NO_TARGET end
    if not s.targetLine then
        return "Build Progress is unavailable: the Wishlist summary line is missing. "
            .. "The lines that were received are under Show details."
    end
    if not s.known then
        return "Family progress is unknown: " .. s.problem
            .. " Nothing is treated as complete; the original lines are under Show details."
    end
    -- A Wishlist that requests no family has no family progress, so nothing
    -- is said to be represented or missing.
    if s.total == 0 then
        return "This Wishlist requests no Echo families, so there is no family progress to show."
    end
    local names = s.pending
    if #names == 0 then
        return "No requested Echo family is missing: each has at least one known copy. "
            .. "That is family coverage, not copy completeness; requested copies may still be missing."
    end
    local shown = {}
    for i = 1, math.min(3, #names) do shown[i] = names[i] end
    return "Still missing " .. #names .. (#names == 1 and " Echo family: " or " Echo families: ")
        .. table.concat(shown, ", ") .. (#names > 3 and (" and " .. (#names - 3) .. " more") or "") .. "."
end

-- The Notes estimate, only in the exact two-line form JournalData writes. The
-- raw Notes section stays unchanged in the details either way.
local function EstimateLine(sections)
    local notes = Section(sections, "Notes")
    local lines = notes and TextLines(notes.lines)
    if not (lines and #lines == 2 and lines[1] == NOTES_FIRST) then return nil end
    local est = lines[2]
    if NO_ESTIMATE[est] then return "Estimate: unavailable." end
    return "Estimate, not a prediction: " .. est
        .. ". Based only on what is known to be missing; no future offer is assumed."
end

-- An off-Wishlist line is a family name plus one of the provider's known
-- explanations. With any other ending the whole line is the label.
local function SplitOffLine(line)
    for i = 1, #OFF_SUFFIXES do
        local suffix = OFF_SUFFIXES[i]
        if #line > #suffix and line:sub(-#suffix) == suffix then
            return line:sub(1, #line - #suffix)
        end
    end
    return line
end

local function CurrentCatalog()
    local A = Nexus.GameAdapter
    if not (A and type(A.Catalog) == "function") then return nil end
    local ok, catalog = pcall(A.Catalog)
    return ok and type(catalog) == "table" and catalog or nil
end

-- Row icons. A name resolves only when it is exactly one catalog family's
-- name; the icon is the GetSpellInfo texture of a member linked back to that
-- family. The name index is built once per catalog table (a rebuilt catalog
-- is a new table), not on each refresh. Anything else, including a name two
-- families share, gets the neutral tile. Nothing here requests or changes
-- anything.
local iconIndex = {}

local function FamilyIcon(catalog, name)
    if type(catalog) ~= "table" or type(name) ~= "string" or name == "" then return nil end
    local names, members = catalog.familyName, catalog.familyMembers
    local familyOf, rows = catalog.familyOf, catalog.rows
    if type(names) ~= "table" or type(members) ~= "table" or type(familyOf) ~= "table"
        or type(rows) ~= "table" then return nil end
    if iconIndex.catalog ~= catalog then
        local byName = {}
        for key, familyName in pairs(names) do
            if type(familyName) == "string" and familyName ~= "" then
                byName[familyName] = byName[familyName] == nil and key or false
            end
        end
        iconIndex.catalog, iconIndex.byName, iconIndex.icons = catalog, byName, {}
    end
    local icon = iconIndex.icons[name]
    if icon == nil then
        icon = false
        local key = iconIndex.byName[name]
        local list = key and members[key]
        if type(list) == "table" and type(GetSpellInfo) == "function" then
            for i = 1, #list do
                local id = list[i]
                local row = rows[id]
                if type(id) == "number" and familyOf[id] == key and type(row) == "table" and row.spellId == id then
                    local ok, _, _, texture = pcall(GetSpellInfo, id)
                    if ok and ((type(texture) == "string" and texture ~= "") or type(texture) == "number") then
                        icon = texture
                        break
                    end
                end
            end
        end
        iconIndex.icons[name] = icon
    end
    return icon or nil
end

-- Display-only Echo rows in the Orb history's visual language: a subtle
-- separator, the icon tile on the left, the family text and a short status
-- word. Frames and scripts are created once and reused on every refresh; the
-- complete text is always in the row tooltip.
local function RowEnter(self)
    if self.hover then self.hover:Show() end
    if not (GameTooltip and self.tipName) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(self.tipName, 1, 1, 1, true)
    GameTooltip:AddLine(self.tipStatus, 0.82, 0.82, 0.82, true)
    if self.tipRaw then GameTooltip:AddLine("Source text: " .. self.tipRaw, 0.82, 0.82, 0.82, true) end
    if self.tipIcon then GameTooltip:AddLine(self.tipIcon, 0.6, 0.6, 0.6, true) end
    GameTooltip:Show()
end

local function RowLeave(self)
    if self.hover then self.hover:Hide() end
    if GameTooltip then GameTooltip:Hide() end
end

-- A provider string worth showing, or nil.
local function Filled(value)
    return type(value) == "string" and value ~= "" and value or nil
end

local function RequestText(pending)
    local request = pending == "enable" and "Enable requested"
        or pending == "disable" and "Disable requested" or "Request direction unknown"
    return request .. "; awaiting confirmation. A request is not a confirmed change."
end

-- The complete tome entry: the observation and any request kept apart, the
-- supplied reason and plan, its Echoes, the raw control ID and where the icon
-- came from. Only the supplied entry is read.
local function TomeRowEnter(self)
    if self.hover then self.hover:Show() end
    local t = self.tome
    if not (GameTooltip and type(t) == "table") then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(t.name, 1, 1, 1, true)
    local observed = Filled(t.status) or "Unknown"
    if self.tomeRequest then
        GameTooltip:AddLine(RequestText(t.pending), 1, 0.82, 0, true)
        GameTooltip:AddLine("Last observed in the client mirror: " .. observed, 0.82, 0.82, 0.82, true)
    else
        GameTooltip:AddLine("Client mirror: " .. observed, 0.82, 0.82, 0.82, true)
        if t.pending ~= nil then GameTooltip:AddLine(RequestText(t.pending), 1, 0.82, 0, true) end
    end
    if Filled(t.reason) then GameTooltip:AddLine(t.reason, 0.82, 0.82, 0.82, true) end
    if Filled(t.plan) then GameTooltip:AddLine(t.plan, 0.82, 0.82, 0.82, true) end
    local names = {}
    if type(t.echoNames) == "table" then
        for i = 1, #t.echoNames do names[#names + 1] = Filled(t.echoNames[i]) end
    end
    if #names > 0 then
        GameTooltip:AddLine((#names == 1 and "Echo: " or "Echoes: ") .. table.concat(names, ", "),
            0.82, 0.82, 0.82, true)
    end
    if t.leverId ~= nil then GameTooltip:AddLine("Control ID: " .. tostring(t.leverId), 0.6, 0.6, 0.6, true) end
    local icon = not self.tomeIcon and "No icon was supplied, so a neutral icon is shown."
        or t.iconSource == "tome spell" and "Icon: the tome's spell icon."
        or t.iconSource == "representative Echo spell"
            and "Icon: a member Echo's spell icon; the tome's own icon was unavailable."
        or "Icon: as supplied; its source was not stated."
    GameTooltip:AddLine(icon, 0.6, 0.6, 0.6, true)
    if t.stale == true then GameTooltip:AddLine(TOME_STALE, 1, 0.63, 0.25, true) end
    GameTooltip:AddLine(TOME_SCOPE, 0.6, 0.6, 0.6, true)
    GameTooltip:Show()
end

-- A section's structured tome rows, or nil so that its text lines are shown:
-- a plain non-empty sequence whose every entry carries a readable name.
local function TomeRows(list)
    if type(list) ~= "table" or #list == 0 then return nil end
    local count = 0
    for _ in pairs(list) do count = count + 1 end
    if count ~= #list then return nil end
    for i = 1, #list do
        if type(list[i]) ~= "table" or not Filled(list[i].name) then return nil end
    end
    return list
end

-- One row frame for either pool. A striped row (the tome rows) also gets a
-- background whose faint shade alternates with its neighbours.
local function NewRow(statusWidth, striped)
    local row = CreateFrame("Frame", nil, child)
    row:SetHeight(ROW_H)
    row:EnableMouse(true)
    if striped then
        row.background = row:CreateTexture(nil, "BACKGROUND")
        row.background:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.background:SetAllPoints(row)
    end
    row.hover = row:CreateTexture(nil, "BACKGROUND")
    row.hover:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.hover:SetAllPoints(row)
    row.hover:SetVertexColor(0.30, 0.40, 0.52, 0.18)
    row.separator = row:CreateTexture(nil, "BORDER")
    row.separator:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.separator:SetHeight(1)
    row.separator:SetPoint("BOTTOMLEFT", 0, 0)
    row.separator:SetPoint("BOTTOMRIGHT", 0, 0)
    row.separator:SetVertexColor(0.22, 0.24, 0.28, 0.55)
    row.tile = row:CreateTexture(nil, "ARTWORK")
    row.tile:SetTexture("Interface\\Buttons\\WHITE8X8")
    row.tile:SetSize(TILE, TILE)
    row.tile:SetPoint("LEFT", 2, 0)
    row.tile:SetVertexColor(0.08, 0.10, 0.13, 0.95)
    row.icon = row:CreateTexture(nil, "OVERLAY")
    row.icon:SetSize(TILE - 4, TILE - 4)
    row.icon:SetPoint("CENTER", row.tile, "CENTER", 0, 0)
    row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    row.status = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.status:SetPoint("RIGHT", -4, 0)
    row.status:SetWidth(statusWidth)
    row.status:SetJustifyH("RIGHT")
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row.tile, "RIGHT", 6, 0)
    row.label:SetPoint("RIGHT", row.status, "LEFT", -6, 0)
    row.label:SetJustifyH("LEFT")
    -- Both texts keep one line at the row's height, so neither can grow
    -- into the next row; the row tooltip has the complete name.
    if Nexus.LayoutMetrics then
        pcall(Nexus.LayoutMetrics.OneLineLabel, row.label, nil, ROW_H - 6)
        pcall(Nexus.LayoutMetrics.OneLineLabel, row.status, nil, ROW_H - 6)
    end
    return row
end

local function AcquireRow()
    rowsUsed = rowsUsed + 1
    local row = rowPool[rowsUsed]
    if not row then
        row = NewRow(78)
        row:SetScript("OnEnter", RowEnter)
        row:SetScript("OnLeave", RowLeave)
        rowPool[rowsUsed] = row
    end
    row.hover:Hide()
    row:Show()
    return row
end

local function AcquireTomeRow()
    tomesUsed = tomesUsed + 1
    local row = tomePool[tomesUsed]
    if not row then
        row = NewRow(TOME_STATUS_W, true)
        -- Names take the style's readable text colour; each badge's role is
        -- set per entry. The theme repaints both when either choice changes.
        if Nexus.Theme then pcall(Nexus.Theme.StyleLabel, row.label, "text") end
        row:SetScript("OnEnter", TomeRowEnter)
        row:SetScript("OnLeave", RowLeave)
        tomePool[tomesUsed] = row
    end
    row.hover:Hide()
    row:Show()
    return row
end

-- The short intro keeps the full purpose and notes in its tooltip.
local function IntroHover()
    if introHover then return introHover end
    introHover = CreateFrame("Frame", nil, child)
    introHover:EnableMouse(true)
    introHover:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(HEADER, 1, 0.82, 0)
        GameTooltip:AddLine(PURPOSE, 0.82, 0.82, 0.82, true)
        GameTooltip:AddLine(NOTE1, 0.82, 0.82, 0.82, true)
        GameTooltip:AddLine(NOTE2, 0.82, 0.82, 0.82, true)
        GameTooltip:AddLine(FAMILY_NOTE, 0.82, 0.82, 0.82, true)
        GameTooltip:Show()
    end)
    introHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return introHover
end

-- The counts line explains itself in a tooltip, including what an empty or
-- unreadable off-Wishlist list does and does not show.
local function CountsHover()
    if countsHover then return countsHover end
    countsHover = CreateFrame("Frame", nil, child)
    countsHover:EnableMouse(true)
    countsHover:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Wishlist family counts", 1, 0.82, 0)
        GameTooltip:AddLine(FAMILY_NOTE, 0.82, 0.82, 0.82, true)
        if self.offTip then GameTooltip:AddLine(self.offTip, 0.82, 0.82, 0.82, true) end
        GameTooltip:Show()
    end)
    countsHover:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return countsHover
end

-- The page's buttons, created once in the scrolled content.
local function PageButton(kind)
    local b = kind == "details" and detailsButton or kind == "help" and M._pageHelpButton
        or kind == "builds" and buildsButton or nil
    if b then return b end
    b = CreateFrame("Button", nil, child, "UIPanelButtonTemplate")
    if kind == "help" then
        -- M7: contextual Help, passive. It opens the Wishlists Help page above
        -- the Journal and changes nothing here: it assigns, saves, sends,
        -- rolls, spends and turns nothing on. Kept on the module table.
        M._pageHelpButton = b
        b:SetSize(56, 22)
        b:SetText("Help")
        b:SetScript("OnClick", function()
            if Nexus.Help and Nexus.Help.Show then Nexus.Help.Show("wishlists") end
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Help", 1, 1, 1)
            GameTooltip:AddLine("Opens Help on Wishlists and locked targets. Opening it changes nothing on this page.",
                0.82, 0.82, 0.82, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    elseif kind == "details" then
        detailsButton = b
        b:SetSize(112, 22)
        b:SetScript("OnClick", function()
            detailsShown = not detailsShown
            M.Refresh()
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(detailsShown and "Hide details" or "Show details", 1, 1, 1)
            GameTooltip:AddLine("The full page notes and every section as received: target, pending, "
                .. "extra copies, tome states and their coverage, notes, estimate and version. Tome states "
                .. "are listed as rows; hover a row for its complete entry.", 0.82, 0.82, 0.82, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        buildsButton = b
        b:SetSize(150, 22)
        b:SetText("Assign in My Builds")
        b:SetScript("OnClick", function()
            pcall(function() if panel and panel:IsShown() then DeselectOurTab(true) end end)
        end)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Assign in My Builds", 1, 1, 1)
            GameTooltip:AddLine("Closes this page onto the Journal's own assignment controls. " .. ASSIGN_NOTE,
                0.82, 0.82, 0.82, true)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end
    return b
end

local function DoRefresh()
    local data, failed
    if type(provider) == "function" then
        local okP, res = pcall(provider)
        if okP and type(res) == "table" then data = res elseif not okP then failed = true end
    end

    -- Pooled family and tome rows may be rebound below to other entries, and
    -- the counts hover's off-Wishlist note may change; a tooltip one of them
    -- owns would keep describing the old entry. The static intro and any
    -- other owner's tooltip stay.
    if GameTooltip and type(GameTooltip.GetOwner) == "function" then
        local okOwner, owner = pcall(GameTooltip.GetOwner, GameTooltip)
        if okOwner and owner ~= nil then
            local owned = countsHover ~= nil and owner == countsHover
            for i = 1, #rowPool do
                if owned then break end
                owned = rowPool[i] == owner
            end
            for i = 1, #tomePool do
                if owned then break end
                owned = tomePool[i] == owner
            end
            if owned then GameTooltip:Hide() end
        end
    end

    linesUsed, rowsUsed, tomesUsed = 0, 0, 0
    local width = math.floor((scroll and scroll:GetWidth()) or 0)
    if width < 100 then width = 292 end
    width = width - 12
    local cy = -6
    local catalog, catalogRead = nil, false

    -- `plain` keeps provider names exactly as supplied (no public rewording).
    local function AddLine(text, font, indent, plain)
        if not plain then text = Nexus.UserText and Nexus.UserText.Message(text) or text end
        indent = indent or 0
        local fs = AcquireLine()
        fs:SetFontObject(font or "GameFontHighlightSmall")
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", child, "TOPLEFT", 6 + indent, cy)
        fs:SetWidth(width - indent)
        -- Height 0 + fixed width = word-wrap; GetStringHeight is then
        -- the wrapped height.
        fs:SetHeight(0)
        fs:SetText(text or "")
        local h = fs:GetStringHeight()
        if not h or h < 12 then h = 12 end
        cy = cy - h - 2
        return fs
    end

    -- One display-only row for a supplied family name. `name` is looked up
    -- for an icon by exact family name only; `raw` is the provider's line.
    local function AddRow(name, status, explain, raw)
        if not catalogRead then catalog, catalogRead = CurrentCatalog(), true end
        local icon = FamilyIcon(catalog, name)
        local row = AcquireRow()
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 6, cy)
        row:SetWidth(width)
        row.icon:SetTexture(icon or NEUTRAL_ICON)
        row.icon:SetAlpha(icon and 1 or 0.5)
        row.label:SetText(name)
        row.status:SetText(status)
        if status == "Missing" then row.status:SetTextColor(1, 0.63, 0.25)
        else row.status:SetTextColor(0.62, 0.70, 0.80) end
        row.tipName, row.tipStatus = name, status .. ": " .. explain
        row.tipRaw = raw ~= name and raw or nil
        row.tipIcon = not icon and "No single Echo family has exactly this name, so a neutral icon is shown."
            or nil
        cy = cy - ROW_H
    end

    -- One tome row from the supplied entry only: its icon, name and
    -- observation, or in the request section the request direction. Nothing
    -- here reads the catalog or the game; the tooltip has the full entry.
    local function AddTomeRow(t, index, requests)
        local row = AcquireTomeRow()
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 14, cy)
        row:SetWidth(width - 8)
        local icon = t.icon
        if not ((type(icon) == "string" and icon ~= "") or type(icon) == "number") then icon = nil end
        row.icon:SetTexture(icon or NEUTRAL_ICON)
        row.icon:SetAlpha(icon and 1 or 0.5)
        row.background:SetVertexColor(0.55, 0.60, 0.68, index % 2 == 1 and 0.08 or 0.03)
        local request = requests and t.pending ~= nil
        row.label:SetText(t.name)
        row.status:SetText(request and (PENDING_BADGE[t.pending] or "Request pending")
            or Filled(t.status) or "Unknown")
        -- Requests and clean observations take the palette accent; mixed,
        -- unknown, undiscovered and possibly stale readings are muted.
        local clean = t.stale ~= true and (t.observed == "disabled"
            or (t.observed == "enabled" and t.known == true))
        local role = (request or clean) and "accent" or "muted"
        if row.badgeRole ~= role and Nexus.Theme then
            row.badgeRole = role
            pcall(Nexus.Theme.StyleLabel, row.status, role)
        end
        row.tome, row.tomeRequest, row.tomeIcon = t, request, icon ~= nil
        cy = cy - ROW_H
    end

    AddLine(HEADER, "GameFontNormal")
    local intro = AddLine(INTRO)
    local hover = IntroHover()
    hover:ClearAllPoints()
    hover:SetPoint("TOPLEFT", intro, "TOPLEFT", 0, 0)
    hover:SetPoint("BOTTOMRIGHT", intro, "BOTTOMRIGHT", 0, 0)
    hover:Show()
    cy = cy - 4

    local sections = data and data.sections
    local hasSections = type(sections) == "table" and #sections > 0
    local s = hasSections and Summarize(sections) or {}
    local noTarget = s.noTarget == true
    local countsShown = false
    if hasSections then
        AddLine(Takeaway(s), "GameFontNormalSmall", nil, true)
        if s.known and #s.pending > 0 then AddLine("|cff8a8a8a" .. FAMILY_NOTE .. "|r") end
        if s.known then
            AddLine(s.title, nil, 8, true)
            -- A listed count is shown as supplied; an empty list is "none
            -- listed", never 0 (see OFF_NONE).
            local off, offTip = "|cff9eb2c8Off Wishlist:|r unavailable", OFF_UNAVAILABLE
            if s.off and #s.off > 0 then off, offTip = "|cff9eb2c8Off Wishlist|r " .. s.offCount, OFF_LISTED
            elseif s.off then off, offTip = "|cff9eb2c8Off Wishlist:|r none listed", OFF_NONE end
            local counts = AddLine("|cff7fd17fRepresented|r " .. s.represented .. " of " .. s.total
                .. "   |cffffa040Missing|r " .. s.missing .. "   " .. off, nil, 8, true)
            local hit = CountsHover()
            hit:ClearAllPoints()
            hit:SetPoint("TOPLEFT", counts, "TOPLEFT", 0, 0)
            hit:SetPoint("BOTTOMRIGHT", counts, "BOTTOMRIGHT", 0, 0)
            hit.offTip = offTip
            hit:Show()
            countsShown = true
        elseif s.targetLine then
            -- Unknown form or contradicted counts: the raw line, as supplied.
            AddLine(s.targetLine, nil, 8, true)
        end
    elseif failed then
        AddLine("|cff8a8a8aBuild Progress data could not be read. Nothing is assumed.|r")
    else
        AddLine("|cff8a8a8ano data yet|r")
    end
    if countsHover and not countsShown then countsHover:Hide() end

    -- Only the families the provider names. The represented families are a
    -- count in the line above: the provider does not list them.
    if s.known and #s.pending > 0 then
        cy = cy - 4
        AddLine("Missing (" .. #s.pending .. ")", "GameFontNormalSmall")
        for i = 1, #s.pending do AddRow(s.pending[i], "Missing", MISSING_EXPLAIN, s.pending[i]) end
    end
    if s.known and s.off and #s.off > 0 then
        cy = cy - 4
        AddLine("Off Wishlist (" .. #s.off .. ")", "GameFontNormalSmall")
        for i = 1, #s.off do AddRow(SplitOffLine(s.off[i]), "Off Wishlist", OFF_EXPLAIN, s.off[i]) end
    end
    local estimate = s.targetLine and EstimateLine(sections)
    if estimate then
        cy = cy - 4
        AddLine("|cff8a8a8a" .. estimate .. "|r", nil, nil, true)
    end
    cy = cy - 4

    -- Show details keeps the full notes, every provider section, the estimate
    -- and the version; Assign in My Builds closes this page onto the Journal's
    -- own assignment controls, exactly like a second click on the tab.
    local toggle = PageButton("details")
    toggle:ClearAllPoints()
    toggle:SetPoint("TOPLEFT", child, "TOPLEFT", 6, cy)
    toggle:SetText(detailsShown and "Hide details" or "Show details")
    toggle:Show()
    local builds = PageButton("builds")
    if noTarget then
        builds:ClearAllPoints()
        builds:SetPoint("TOPLEFT", child, "TOPLEFT", 124, cy)
        builds:Show()
    else
        builds:Hide()
    end
    -- Help joins the same row after the shown buttons; where the row is too
    -- narrow for it (content width + 12, at least 292), it takes a row of its
    -- own below, so it never covers another button or line.
    local help = PageButton("help")
    local helpX, helpY = noTarget and 280 or 124, cy
    if helpX + 56 > width + 6 then
        helpX, helpY = 6, cy - 26
        cy = cy - 26
    end
    help:ClearAllPoints()
    help:SetPoint("TOPLEFT", child, "TOPLEFT", helpX, helpY)
    help:Show()
    cy = cy - 30

    if detailsShown then
        AddLine("About this page", "GameFontNormalSmall")
        AddLine(PURPOSE, nil, 8)
        AddLine(NOTE1, nil, 8)
        AddLine(NOTE2, nil, 8)
        AddLine(FAMILY_NOTE, nil, 8)
        AddLine("Change the assigned Wishlist in My Builds.", nil, 8)
        cy = cy - 6
        if not hasSections then
            AddLine(failed and "|cff8a8a8aBuild Progress data could not be read, so there are no sections to show.|r"
                or "|cff8a8a8aNo sections were received.|r")
        end
        if hasSections then
            for i = 1, #sections do
                local sec = sections[i]
                if type(sec) == "table" then
                    AddLine(tostring(sec.title or ""), "GameFontNormalSmall")
                    -- Structured tome rows stand in for the same entries'
                    -- text lines; every other section keeps its lines.
                    local tomes = TomeRows(sec.tomeRows)
                    if tomes then
                        local requests = sec.title == TOME_REQUESTS
                        for j = 1, #tomes do AddTomeRow(tomes[j], j, requests) end
                    elseif s.known and sec == s.pendingSection and #s.pending > 0 then
                        -- This exact section validated the summary, so its
                        -- families are already the Missing rows above; they
                        -- are not listed twice. Any other section, or a
                        -- Pending list the summary did not validate, keeps
                        -- its lines as received. The data is not changed.
                        AddLine("|cff8a8a8aListed above under Missing (" .. #s.pending .. ").|r", nil, 8)
                    else
                        local lines = sec.lines
                        if type(lines) == "table" then
                            for j = 1, #lines do
                                AddLine(tostring(lines[j] or ""), nil, 8)
                            end
                        end
                    end
                    cy = cy - 4
                end
            end
        end

        if data and data.version ~= nil then
            cy = cy - 2
            AddLine("|cff8a8a8a" .. tostring(data.version) .. "|r")
        end
    end

    for i = linesUsed + 1, #linePool do linePool[i]:Hide() end
    for i = rowsUsed + 1, #rowPool do rowPool[i]:Hide() end
    for i = tomesUsed + 1, #tomePool do
        tomePool[i]:Hide()
        tomePool[i].tome = nil
    end
    child:SetWidth(width + 12)
    child:SetHeight(-cy + 8)
end

function M.Refresh()
    if not (installed and panel and panel:IsShown()) then return end
    -- Consumed first: a change marked during this refresh is kept for the next.
    refreshPending = false
    pcall(DoRefresh)
end

-- A semantic change (GameAdapter) marks the page. Only a bit: no provider,
-- adapter or service read and no frame work here. The association scanner
-- refreshes a visible page with its details open on its next beat; a hidden
-- or collapsed page reads nothing until its normal refresh on opening. A
-- newer client mirror shown this way is still no server acknowledgment.
function M.Invalidate()
    refreshPending = true
end


local function MenuOpen(items, anchor)
    if type(EasyMenu) ~= "function" then return end
    M._menuFrame = M._menuFrame or CreateFrame("Frame", "NexusJournalAssociationMenu", UIParent, "UIDropDownMenuTemplate")
    EasyMenu(items, M._menuFrame, anchor, 0, 0, "MENU")
end

local function FrameText(frame)
    local out = {}
    local function Walk(f, depth)
        if not f or depth > 5 then return end
        if f.GetText then
            local ok, v = pcall(f.GetText, f)
            if ok and type(v) == "string" and v ~= "" then out[#out + 1] = v end
        end
        if f.GetRegions then
            local regs = { f:GetRegions() }
            for i = 1, #regs do
                local r = regs[i]
                if r and r.GetText then
                    local ok, v = pcall(r.GetText, r)
                    if ok and type(v) == "string" and v ~= "" then out[#out + 1] = v end
                end
            end
        end
        if f.GetChildren then
            local kids = { f:GetChildren() }
            for i = 1, #kids do Walk(kids[i], depth + 1) end
        end
    end
    Walk(frame, 0)
    return table.concat(out, "\n")
end

local function NormalizedText(frame)
    return FrameText(frame):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function HasVisibleText(root, wanted)
    local found = false
    local function Walk(f, depth)
        if found or not f or depth > 16 then return end
        local shown = true
        if f.IsShown then
            local ok, v = pcall(f.IsShown, f)
            if ok then shown = v and true or false end
        end
        if shown then
            if f.GetText then
                local ok, text = pcall(f.GetText, f)
                if ok and type(text) == "string" then
                    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                    if text:find(wanted, 1, true) then found = true return end
                end
            end
            if f.GetRegions then
                local regs = { f:GetRegions() }
                for i = 1, #regs do
                    local r = regs[i]
                    if r and r.GetText then
                        local ok, text = pcall(r.GetText, r)
                        if ok and type(text) == "string" then
                            text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                            if text:find(wanted, 1, true) then found = true return end
                        end
                    end
                end
            end
        end
        if f.GetChildren then
            local kids = { f:GetChildren() }
            for i = 1, #kids do Walk(kids[i], depth + 1) end
        end
    end
    Walk(root, 0)
    return found
end

local function IsLoadoutsVisible(journal)
    if not journal or not journal.IsShown or not journal:IsShown() then return false end
    -- The stock page always exposes this section title. This is intentionally
    -- independent of card frame names, dimensions, verification flags, and
    -- Project Ebonhold client revisions.
    if HasVisibleText(journal, "Your loadouts") then return true end
    if HasVisibleText(journal, "Empty slot 2") or HasVisibleText(journal, "Empty slot 3") then return true end
    return false
end

local function FindLoadoutsTab(journal)
    local function IsWantedButton(f)
        if not f or not f.GetObjectType or f:GetObjectType() ~= "Button" then return false end
        local txt = NormalizedText(f)
        for line in txt:gmatch("[^\n]+") do
            line = line:gsub("^%s+", ""):gsub("%s+$", "")
            if line == "Loadouts" then return true end
        end
        return false
    end

    -- Prefer the stock named tabs when present. On the current client the
    -- Loadouts button is Tab3, but validate the visible label rather than
    -- assuming the index.
    for i = 1, 12 do
        local t = _G["ProjectEbonholdEchoJournalTab" .. tostring(i)]
        if IsWantedButton(t) then return t end
    end

    local exact
    local function Walk(f, depth)
        if exact or not f or depth > 18 then return end
        if IsWantedButton(f) then exact = f return end
        if f.GetChildren then
            local kids = { f:GetChildren() }
            for i = 1, #kids do Walk(kids[i], depth + 1) end
        end
    end
    Walk(journal, 0)
    if not exact and UIParent and UIParent ~= journal then Walk(UIParent, 0) end
    return exact
end

local function ShortName(name, maxLen)
    name = tostring(name or "")
    maxLen = tonumber(maxLen) or 28
    if #name <= maxLen then return name end
    return name:sub(1, maxLen - 3) .. "..."
end



-- The selector sits in the Journal header near the screen top, so its tall
-- ANCHOR_TOP tooltip does not fit above it and the screen clamp moves it down
-- over the picker area. The open picker (TOOLTIP strata, higher level) then
-- covers the warning. While the picker is open, place the tooltip beside the
-- picker instead: right when there is room, else on the side with more room.
-- GameTooltip strata, level and parent are not changed.
local function ShowSelectorTooltip(selector)
    local besidePicker = wishlistPicker and wishlistPicker:IsShown()
    GameTooltip:SetOwner(selector, besidePicker and "ANCHOR_NONE" or "ANCHOR_TOP")
    GameTooltip:AddLine("Automation Wishlist", 0.35, 0.8, 1)
    GameTooltip:AddLine(associationPanel and associationPanel.emptySlot and EMPTY_SLOT_SELECTOR
        or ("Assigns a wishlist reference to the Saved Build currently selected in the server dropdown. "
        .. ASSIGN_NOTE), 0.82, 0.82, 0.82, true)
    GameTooltip:AddLine(AUTO_SAVE_WARNING, 1, 0.82, 0.25, true)
    GameTooltip:AddLine(AUTO_SAVE_ORBS, 1, 0.82, 0.25, true)
    GameTooltip:Show()
    if not besidePicker then return end
    local gap = 4
    local left, right = wishlistPicker:GetLeft(), wishlistPicker:GetRight()
    if not (left and right) then
        -- Picker layout not resolved yet (it was just shown). Its TOPLEFT is
        -- the selector's BOTTOMLEFT, and the hovered selector is laid out.
        local selectorLeft = selector:GetLeft()
        if selectorLeft then
            left = selectorLeft * (selector:GetEffectiveScale() or 1) / (wishlistPicker:GetEffectiveScale() or 1)
            right = left + (wishlistPicker:GetWidth() or 0)
        end
    end
    local screenRight = UIParent:GetRight() or UIParent:GetWidth() or 0
    -- Tooltip width in UIParent units (the picker is a scale-1 UIParent child).
    local width = (GameTooltip:GetWidth() or 0) * (GameTooltip:GetEffectiveScale() or 1)
        / (UIParent:GetEffectiveScale() or 1)
    local roomRight = right and (screenRight - right) or math.huge
    local roomLeft = left or 0
    GameTooltip:ClearAllPoints()
    if roomRight < width + gap and roomLeft > roomRight then
        GameTooltip:SetPoint("TOPRIGHT", wishlistPicker, "TOPLEFT", -gap, 0)
    else
        GameTooltip:SetPoint("TOPLEFT", wishlistPicker, "TOPRIGHT", gap, 0)
    end
end

-- The picker opens and closes on a selector click while the mouse stays on
-- the selector: place its shown tooltip again for the new picker state.
local function RefreshSelectorTooltip()
    local selector = associationPanel and associationPanel.selector
    if selector and selector:IsVisible() and GameTooltip:IsShown()
        and GameTooltip:GetOwner() == selector then
        ShowSelectorTooltip(selector)
    end
end

local function EnsureAssociationPanel(journal)
    if not journal then return nil end
    if not associationPanel then
        associationPanel = CreateFrame("Frame", "NexusLoadoutAssociationPanel", journal)
        associationPanel:SetSize(360, 56)
        associationPanel:SetFrameStrata("DIALOG")
        associationPanel:SetFrameLevel((journal:GetFrameLevel() or 0) + 24)
        associationPanel:EnableMouse(true)
        associationPanel:SetClampedToScreen(true)
        if associationPanel.SetBackdrop then
            associationPanel:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 11,
                insets = { left = 3, right = 3, top = 3, bottom = 3 },
            })
            associationPanel:SetBackdropColor(0.018, 0.024, 0.032, 0.97)
            associationPanel:SetBackdropBorderColor(0.28, 0.58, 0.76, 0.95)
        end

        associationPanel.label = associationPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        associationPanel.label:SetPoint("TOPLEFT", 10, -9)
        associationPanel.label:SetWidth(145)
        associationPanel.label:SetJustifyH("LEFT")
        associationPanel.label:SetTextColor(0.72, 0.72, 0.72)

        associationPanel.selector = CreateFrame("Button", "NexusActiveWishlistSelector", associationPanel)
        associationPanel.selector:SetSize(169, 21)
        associationPanel.selector:SetPoint("TOPRIGHT", -31, -5)
        associationPanel.selector:RegisterForClicks("LeftButtonUp")
        if associationPanel.selector.SetBackdrop then
            associationPanel.selector:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = false, edgeSize = 9,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            associationPanel.selector:SetBackdropColor(0.035, 0.045, 0.06, 0.99)
            associationPanel.selector:SetBackdropBorderColor(0.25, 0.31, 0.38, 0.95)
        end
        associationPanel.selector.text = associationPanel.selector:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        associationPanel.selector.text:SetPoint("LEFT", 9, 0)
        associationPanel.selector.text:SetPoint("RIGHT", -25, 0)
        associationPanel.selector.text:SetJustifyH("LEFT")
        -- One line inside the 21 px selector; the picker lists complete names.
        if Nexus.LayoutMetrics then Nexus.LayoutMetrics.OneLineLabel(associationPanel.selector.text, nil, 21) end
        associationPanel.selector.arrow = associationPanel.selector:CreateTexture(nil, "ARTWORK")
        associationPanel.selector.arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
        associationPanel.selector.arrow:SetSize(16, 16)
        associationPanel.selector.arrow:SetPoint("RIGHT", -5, 0)

        associationPanel.design = CreateFrame("Button", "NexusAssociatedWishlistDesignButton", associationPanel)
        associationPanel.design:SetSize(20, 20)
        associationPanel.design:SetPoint("TOPRIGHT", -7, -6)
        associationPanel.design:RegisterForClicks("LeftButtonUp")
        associationPanel.design.icon = associationPanel.design:CreateTexture(nil, "ARTWORK")
        associationPanel.design.icon:SetAllPoints()
        associationPanel.design.icon:SetTexture("Interface\\Buttons\\WHITE8X8")
        associationPanel.design.icon:SetVertexColor(0.08, 0.11, 0.15, 0.98)
        associationPanel.design.glyph = associationPanel.design:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        associationPanel.design.glyph:SetPoint("CENTER", 0, 1)
        associationPanel.design.glyph:SetText("...")
        associationPanel.design.glyph:SetTextColor(1, 0.82, 0.2)
        associationPanel.design:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        associationPanel.newWishlist = CreateFrame("Button", nil, associationPanel, "UIPanelButtonTemplate")
        associationPanel.newWishlist:SetSize(150, 19)
        associationPanel.newWishlist:SetPoint("BOTTOMRIGHT", -7, 5)
        associationPanel.newWishlist:SetText("New Wishlist")
        associationPanel.newWishlist:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("New Wishlist", 0.35, 0.8, 1)
            GameTooltip:AddLine("Open a blank Nexus Wishlist Editor for a new run.", 0.82, 0.82, 0.82, true)
            GameTooltip:Show()
        end)
        associationPanel.newWishlist:SetScript("OnLeave", function() GameTooltip:Hide() end)

        associationPanel.design:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            if associationPanel and associationPanel.emptySlot then
                GameTooltip:AddLine("Edit first-run Wishlist", 0.35, 0.8, 1)
                GameTooltip:AddLine("Open the first-run Wishlist for editing. This Saved Build is empty and has no Wishlist of its own, so nothing is assigned to it. This does not activate another build.", 0.82, 0.82, 0.82, true)
            else
                GameTooltip:AddLine("Edit assigned Wishlist", 0.35, 0.8, 1)
                GameTooltip:AddLine("Open the Wishlist assigned to this Saved Build. This does not activate another build.", 0.82, 0.82, 0.82, true)
            end
            GameTooltip:Show()
        end)
        associationPanel.design:SetScript("OnLeave", function() GameTooltip:Hide() end)
        associationPanel.selector:SetScript("OnEnter", function(self)
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.42, 0.72, 0.95, 1) end
            ShowSelectorTooltip(self)
        end)
        associationPanel.selector:SetScript("OnLeave", function(self)
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.25, 0.31, 0.38, 0.95) end
            GameTooltip:Hide()
        end)

        associationPanel:SetScript("OnHide", function()
            HideWishlistPicker()
            if M._menuFrame then M._menuFrame:Hide() end
        end)
    end

    associationPanel:SetParent(journal)
    associationPanel:ClearAllPoints()
    -- Keep the control centered in the unused top header strip. This avoids
    -- the Echo row, search field, and the server loadout dropdown/menu.
    associationPanel:SetPoint("TOP", journal, "TOP", 85, 2)
    return associationPanel
end

local function HideRowButtons()
    if associationPanel then associationPanel:Hide() end
end

HideWishlistPicker = function()
    if wishlistPicker and wishlistPicker:IsShown() then
        wishlistPicker:Hide()
        RefreshSelectorTooltip()
    end
end

-- Display only: which picker row is the resolved assignment. The resolver
-- copies the stored assignmentId onto the live server row it found, but the
-- picker lists fresh live rows that carry none. So: equal assignmentIds on both
-- sides decide; a row stamped with another assignment is never selected;
-- otherwise the current resolved server slot and content key must both match.
-- Equal contents in another slot, or a name, identify nothing.
local function IsAssignedPickerRow(linked, c)
    if type(linked) ~= "table" or type(c) ~= "table" then return false end
    if linked.assignmentId and c.assignmentId then
        return linked.assignmentId == c.assignmentId
    end
    if c.assignmentId then return false end
    local slot = tonumber(linked.slot)
    return slot ~= nil and slot == tonumber(c.slot)
        and type(linked.key) == "string" and linked.key ~= "" and linked.key == c.key
end

-- `emptySlot` is the empty-Saved-Build context `active` and `loadoutName` were taken
-- in. The picker's tooltips use it, not the live Journal context, so their words
-- always describe the target its click handlers act on while it stays open.
local function ShowWishlistPicker(anchor, wishes, linked, active, loadoutName, A, emptySlot)
    if not wishlistPicker then
        wishlistPicker = CreateFrame("Frame", "NexusWishlistOnlyPicker", UIParent)
        wishlistPicker:SetFrameStrata("TOOLTIP")
        -- Native high-level rendering put this opaque parent above Unassign.
        -- TOOLTIP supplies the overlay order; keep its child levels low.
        wishlistPicker:SetFrameLevel(50)
        wishlistPicker:SetToplevel(true)
        wishlistPicker:SetClampedToScreen(true)
        wishlistPicker:EnableMouse(true)
        if wishlistPicker.SetBackdrop then
            wishlistPicker:SetBackdrop({ bgFile="Interface\\Buttons\\WHITE8X8", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=12, insets={left=3,right=3,top=3,bottom=3} })
            wishlistPicker:SetBackdropColor(0.02,0.025,0.035,0.99)
            wishlistPicker:SetBackdropBorderColor(0.25,0.55,0.75,1)
        end
        wishlistPicker.bg = wishlistPicker:CreateTexture(nil, "BACKGROUND")
        wishlistPicker.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
        wishlistPicker.bg:SetAllPoints()
        wishlistPicker.bg:SetVertexColor(0.02, 0.025, 0.035, 0.99)
        wishlistPicker.border = CreateFrame("Frame", nil, wishlistPicker)
        wishlistPicker.border:SetAllPoints()
        wishlistPicker.border:SetFrameLevel(wishlistPicker:GetFrameLevel() + 1)
        wishlistPicker.title = wishlistPicker:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        wishlistPicker.title:SetPoint("TOPLEFT", 10, -8)
        wishlistPicker.title:SetText("Wishlists")
    end
    -- The title names the target this picker's clicks act on (the context
    -- captured with it), not only that these are Wishlists.
    wishlistPicker.title:SetText(emptySlot and "Empty Saved Build: assigning is refused"
        or ((tonumber(active) or 0) < 1 and "Assign to: first-run target")
        or ("Assign to: " .. ShortName(tostring(loadoutName or ""), 24)))
    for i=1,#wishlistPickerRows do wishlistPickerRows[i]:Hide() end
    if wishlistPicker.emptyRow then wishlistPicker.emptyRow:Hide() end
    if wishlistPicker.clearRow then wishlistPicker.clearRow:Hide() end
    wishlistPicker:ClearAllPoints()
    wishlistPicker:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    -- The selector already names the selected Wishlist, so the list offers
    -- only the others. Only that one identity (IsAssignedPickerRow) is left
    -- out: a row with the same name or contents is another Wishlist and stays.
    -- With no name on the selector the selection stays listed and marked.
    local shown = wishes
    if linked and tostring(linked.name or "") ~= "" then
        shown = {}
        for i=1,#wishes do
            if not IsAssignedPickerRow(linked, wishes[i]) then shown[#shown+1] = wishes[i] end
        end
    end
    local width, rowH = 245, 24
    wishlistPicker:SetWidth(width)
    local count = math.max(1, #shown)
    wishlistPicker:SetHeight(26 + count * rowH + (linked and 24 or 0) + 6)

    if #shown == 0 then
        local row = wishlistPicker.emptyRow
        if not row then
            row = wishlistPicker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            wishlistPicker.emptyRow = row
        end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 10, -28)
        row:SetText(#wishes == 0 and "No server wishlists found" or "No other wishlists found"); row:Show()
    else
        for i=1,#shown do
            local c = shown[i]
            local cSlot = c.slot
            local cName = c.name
            local cKey = c.key
            local row = wishlistPickerRows[i]
            if not row or not row.nameButton then
                row = CreateFrame("Frame", nil, wishlistPicker)
                row:SetFrameLevel(wishlistPicker:GetFrameLevel() + 2)
                row:EnableMouse(true)
                row:SetSize(width-12, rowH)
                row.nameButton = CreateFrame("Button", nil, row)
                row.nameButton:SetFrameLevel(row:GetFrameLevel() + 1)
                row.nameButton:RegisterForClicks("LeftButtonUp")
                row.nameButton:EnableMouse(true)
                row.nameButton:SetPoint("LEFT", 0, 0); row.nameButton:SetPoint("RIGHT", -28, 0); row.nameButton:SetHeight(rowH-2)
                row.nameButton.text = row.nameButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.nameButton.text:SetPoint("LEFT", 6, 0); row.nameButton.text:SetPoint("RIGHT", -4, 0); row.nameButton.text:SetJustifyH("LEFT")
                -- One line per row; a shortened name is complete in the row tooltip.
                if Nexus.LayoutMetrics then Nexus.LayoutMetrics.OneLineLabel(row.nameButton.text, nil, rowH-2) end
                row.nameButton:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                row.gear = CreateFrame("Button", nil, row)
                row.gear:SetFrameLevel(row:GetFrameLevel() + 2)
                row.gear:RegisterForClicks("LeftButtonUp")
                row.gear:EnableMouse(true)
                row.gear:SetSize(20,20); row.gear:SetPoint("RIGHT", -2, 0)
                row.gear.icon = row.gear:CreateTexture(nil, "ARTWORK"); row.gear.icon:SetAllPoints(); row.gear.icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
                row.gear.glyph = row.gear:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.gear.glyph:SetPoint("CENTER", 0, 1)
                row.gear.glyph:SetText("...")
                row.gear.glyph:SetTextColor(1, 0.82, 0.2)
                row.gear:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
                row.gear:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:AddLine("Edit wishlist", .35,.8,1); GameTooltip:Show()
                end)
                row.gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
                wishlistPickerRows[i] = row
            end
            row:ClearAllPoints(); row:SetPoint("TOPLEFT", 6, -24 - (i-1)*rowH)
            local selected = IsAssignedPickerRow(linked, c)
            local editor=Nexus.WishlistEditor
            local hint=editor and editor.UnresolvedRoleHint and editor.UnresolvedRoleHint() or "choose locked targets"
            local evidenceSuffix = c.lockEvidenceStatus == "unavailable"
                and ("  |cffff9040("..hint..")|r") or ""
            row.nameButton.text:SetText((selected and "|cff55ff55[Selected] |r" or "")
                .. ((cName ~= "" and cName) or "Unnamed Wishlist")
                .. evidenceSuffix)
            local cEchoes = c.echoes
            local cSnapshot = {
                slot=cSlot, name=cName, key=cKey,
                lockEvidenceVersion=c.lockEvidenceVersion,
                lockEvidenceStatus=c.lockEvidenceStatus,
                evidenceSource=c.evidenceSource,
                assignmentId=c.assignmentId,designTargets=c.designTargets,
                echoes={},
            }
            for echoIndex = 1, #(cEchoes or {}) do
                local echo = cEchoes[echoIndex]
                cSnapshot.echoes[echoIndex] = {
                    spellId=echo.spellId, quality=echo.quality,
                    stacks=echo.stacks, locked=echo.locked,
                }
            end
            local function AssociateWishlistOnly()
                local numbered = tonumber(active) and tonumber(active) > 0
                local shownName = M.SafeName(cName, "Unnamed Wishlist")
                local target = numbered and ("Saved Build '" .. M.SafeName(loadoutName, tostring(active)) .. "'")
                    or "the first-run target"
                if cSnapshot.lockEvidenceStatus=="unavailable" and Nexus.WishlistEditor
                    and Nexus.WishlistEditor.ResolveAndAssignWishlist then
                    -- A Wishlist without lock evidence: its role choice (the
                    -- current-lock default or the role picker) and the
                    -- assignment it ends in wait for the same Auto-ON
                    -- confirmation; Cancel writes neither.
                    M.AssignWithConsent(shownName, target, numbered and not emptySlot, function()
                        HideWishlistPicker()
                        Nexus.WishlistEditor.ResolveAndAssignWishlist(cSnapshot,tonumber(active) or 0)
                    end)
                    return
                end
                -- The captured target, candidate and empty-slot refusal as
                -- before; Auto selected asks first (M.AssignWithConsent).
                M.AssignWithConsent(shownName, target, numbered and not emptySlot, function()
                    local ok, err
                    if numbered then
                        ok, err = A.SetLoadoutWishlist(active, cSlot, cSnapshot)
                    elseif type(A.SetFirstRunWishlist) == "function" then
                        ok, err = A.SetFirstRunWishlist(cSlot, cSnapshot)
                    else
                        ok, err = false, "first-run association unavailable"
                    end
                    if not ok then
                        print("|cffff6060Nexus:|r " .. tostring(err or "could not select wishlist"))
                        return
                    end
                    HideWishlistPicker()
                    M.RefreshAssociations()
                    if Nexus.Panel and Nexus.Panel.Refresh then pcall(Nexus.Panel.Refresh) end
                    -- A visible confirmation of what changed, and only that.
                    print("|cff4dff80Nexus:|r '" .. shownName .. "' is now the Wishlist for " .. target
                        .. ". No Saved Build was changed or activated.")
                end)
            end
            local function OpenWishlistEditorOnly()
                HideWishlistPicker()
                local editor = Nexus and Nexus.WishlistEditor
                if editor and type(editor.OpenForWishlist) == "function" then
                    editor.OpenForWishlist({
                        slot = cSlot,
                        name = cName,
                        key = cKey,
                        echoes = cEchoes,
                        lockEvidenceVersion = c.lockEvidenceVersion,
                        lockEvidenceStatus = c.lockEvidenceStatus,
                        evidenceSource=c.evidenceSource,
                        assignmentId=c.assignmentId,designTargets=c.designTargets,
                        loadoutName = loadoutName,
                    }, (tonumber(active) and tonumber(active) > 0) and active or nil)
                else
                    print("|cffff6060Nexus:|r Nexus Wishlist Editor is unavailable.")
                end
            end
            row.nameButton:SetScript("OnClick", AssociateWishlistOnly)
            row.nameButton:SetScript("OnEnter", function(self)
                -- Anchor at the row edge: the name button ends 28 px inside
                -- the picker, which shares the TOOLTIP strata.
                GameTooltip:SetOwner(self:GetParent() or self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Assign Wishlist", .35, .8, 1)
                GameTooltip:AddLine("Target: " .. tostring(loadoutName or ""), 1, 1, 1, true)
                GameTooltip:AddLine(emptySlot and EMPTY_SLOT_ASSIGN
                    or ("Sets this Wishlist as the target for this loadout. " .. ASSIGN_NOTE),
                    .82, .82, .82, true)
                GameTooltip:AddLine(AUTO_SAVE_WARNING, 1, .82, .25, true)
                GameTooltip:AddLine(AUTO_SAVE_ORBS, 1, .82, .25, true)
                if Nexus.LayoutMetrics and Nexus.LayoutMetrics.Shortened(self.text) then
                    GameTooltip:AddLine(self.text:GetText(), 1, 1, 1, true)
                end
                GameTooltip:Show()
            end)
            row.nameButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row.gear:SetScript("OnClick", OpenWishlistEditorOnly)
            row:Show()
        end
    end

    if linked then
        local row = wishlistPicker.clearRow
        if not row then
            row = CreateFrame("Button", nil, wishlistPicker)
            row:SetHeight(20)
            row.text = row:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
            row.text:SetPoint("LEFT",6,0); row.text:SetText("Unassign Wishlist")
            row:SetScript("OnEnter",function(self)
                GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
                GameTooltip:AddLine("Unassign Wishlist",1,1,1)
                GameTooltip:AddLine(self.emptySlot
                    and "This Saved Build has no Wishlist of its own. This does not remove the first-run Wishlist."
                    or "Keeps the Wishlist; stops using it for this loadout.",.8,.8,.8,true)
                GameTooltip:AddLine("Does not change or restore the Saved Build.",.8,.8,.8,true)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave",function()GameTooltip:Hide()end)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            wishlistPicker.clearRow = row
        end
        row:SetFrameLevel(wishlistPicker:GetFrameLevel() + 2)
        row.emptySlot = emptySlot
        row:ClearAllPoints(); row:SetPoint("TOPLEFT",6,-24-count*rowH); row:SetPoint("RIGHT",-6,0)
        row:SetScript("OnClick", function()
            if tonumber(active) and tonumber(active) > 0 then A.ClearLoadoutWishlist(active)
            elseif A.ClearFirstRunWishlist then A.ClearFirstRunWishlist() end
            HideWishlistPicker(); M.RefreshAssociations()
        end)
        row:Show()
    end
    wishlistPicker:Show()
    RefreshSelectorTooltip()
end

local function RefreshAssociationRows()
    local journal = _G["ProjectEbonholdEchoJournal"]
    if not journal or not journal.IsShown or not journal:IsShown() then HideRowButtons(); return end
    if installed and panel and panel:IsShown() then HideRowButtons(); return end

    local A = Nexus and Nexus.GameAdapter
    local slots = A and A.Slots and A.Slots()
    if not slots then HideRowButtons(); return end

    -- The Saved Build this panel targets (GameAdapter.SelectedSavedBuild): the
    -- native active slot when it is a Saved Build, or the Saved Build Nexus kept
    -- while a Wishlist is natively active. 0 when there is none, so a Wishlist
    -- number above the Saved Build range never reaches a callback below.
    local active = A.SelectedSavedBuild and A.SelectedSavedBuild(slots) or 0
    local maxSlots = tonumber(slots.maxSlots) or 5
    local activeRow = slots.bySlot and slots.bySlot[active]
    local populated = activeRow and type(activeRow.echoes) == "table" and #activeRow.echoes > 0
    local firstRun = active < 1 or active > maxSlots or not populated
    -- A numbered Saved Build that holds no Echoes (see EMPTY_SLOT_*).
    local emptySlot = firstRun and active >= 1 and active <= maxSlots

    local host = EnsureAssociationPanel(journal)
    host.emptySlot = emptySlot
    -- The scanner calls this every 0.75 s while the Journal is open. The
    -- Wishlist candidates are the most expensive adapter read of a refresh
    -- and only the picker shows them, so they are read when the picker
    -- opens (below), as the store is at that moment. The slots and the
    -- assignment are still read on every refresh: the label and the
    -- selector follow every change, announced or not.
    local linked = firstRun and (A.GetFirstRunWishlist and A.GetFirstRunWishlist())
        or (A.GetLoadoutWishlist and A.GetLoadoutWishlist(active))
    local loadoutName = (active < 1 or active > maxSlots) and "No Saved Build selected"
        or not populated and "Empty Saved Build slot" or tostring(activeRow.name or "")
    if not firstRun and loadoutName == "" then loadoutName = "Saved Build " .. tostring(active) end
    host.label:SetText("|cffffffff" .. ShortName(loadoutName, 21) .. ":|r")

    local linkedName = linked and tostring(linked.name or "") or ""
    if linkedName ~= "" then
        host.selector.text:SetText("|cffffffff" .. ShortName(linkedName, 20) .. "|r")
        host.design:Enable()
        if host.design.icon then host.design.icon:SetDesaturated(false); host.design.icon:SetAlpha(1) end
    else
        host.selector.text:SetText("|cff8a8a8aSelect wishlist...|r")
        host.design:Disable()
        if host.design.icon then host.design.icon:SetDesaturated(true); host.design.icon:SetAlpha(0.45) end
    end
    host.design:SetScript("OnClick", function()
        local editor = Nexus and Nexus.WishlistEditor
        if not linked then
            print("|cffff6060Nexus:|r Associate a wishlist first.")
        elseif editor and type(editor.OpenForWishlist) == "function" then
            HideWishlistPicker()
            -- Zero/empty slots use the first-run assignment. Lua's
            -- `firstRun and nil or active` would pass slot 0 as a loadout.
            editor.OpenForWishlist({
                slot = linked.slot,
                name = linked.name,
                key = linked.key,
                echoes = linked.echoes,
                lockEvidenceVersion=linked.lockEvidenceVersion,
                lockEvidenceStatus=linked.lockEvidenceStatus,
                evidenceSource=linked.evidenceSource,
                assignmentId=linked.assignmentId,designTargets=linked.designTargets,
                loadoutName = loadoutName,
            }, not firstRun and active or nil)
        else
            print("|cffff6060Nexus:|r Nexus Wishlist Editor is unavailable.")
        end
    end)

    host.selector:SetScript("OnClick", function(self)
        if wishlistPicker and wishlistPicker:IsShown() then HideWishlistPicker(); return end
        local wishes = A.GetWishlistCandidates and A.GetWishlistCandidates() or {}
        ShowWishlistPicker(self, wishes, linked, active, loadoutName, A, emptySlot)
    end)
    host.newWishlist:SetScript("OnClick", function()
        HideWishlistPicker()
        local editor = Nexus and Nexus.WishlistEditor
        if editor and type(editor.NewWishlist) == "function" then editor.NewWishlist()
        else print("|cffff6060Nexus:|r Nexus Wishlist Editor is unavailable.") end
    end)
    host:Show()
end

function M.RefreshAssociations()
    pcall(RefreshAssociationRows)
end

local function EnsureAssociationScanner()
    if scanFrame then return end
    scanFrame = CreateFrame("Frame", "NexusLoadoutAssociationScanner", UIParent)
    local elapsed = 0
    scanFrame:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (tonumber(dt) or 0)
        if elapsed < 0.75 then return end
        elapsed = 0
        pcall(function()
            local journal = _G["ProjectEbonholdEchoJournal"]
            if journal and journal.IsShown and journal:IsShown() then
                RefreshAssociationRows()
            else
                HideRowButtons()
            end
        end)
        -- At most one coalesced page refresh per beat, and only for a marked
        -- page that is visible (ancestor-aware) with its details open.
        if refreshPending and detailsShown and installed and panel then
            local okVisible, visible = pcall(panel.IsVisible, panel)
            if okVisible and visible then pcall(M.Refresh) end
        end
    end)
end

------------------------------------------------------------------------
-- Tab select / deselect
------------------------------------------------------------------------

local function SelectOurTab()
    if PanelTemplates_SelectTab then pcall(PanelTemplates_SelectTab, ourTab) end
    for i = 1, theirTabCount do
        local t = _G["ProjectEbonholdEchoJournalTab" .. i]
        if t and PanelTemplates_DeselectTab then
            pcall(PanelTemplates_DeselectTab, t)
        end
    end
    panel:Show()
    associationVisible = false
    HideRowButtons()
    M.Refresh()
end

function DeselectOurTab(showAssociation)
    if ourTab and PanelTemplates_DeselectTab then
        pcall(PanelTemplates_DeselectTab, ourTab)
    end
    if panel then panel:Hide() end
    associationVisible = showAssociation ~= false
    if associationVisible then pcall(RefreshAssociationRows) else HideRowButtons() end
    if ourTab then ourTab:Show() end
end
------------------------------------------------------------------------
-- Install
------------------------------------------------------------------------

-- Advisor tab attachment. The tab is always anchored to another frame, never
-- to screen coordinates, so it moves with whatever window carries the journal.
-- Client evidence (echo_journal.lua): the journal is reparented into
-- CollectionsJournal on first embed, that reparenting resets its children's
-- frame levels, and the hub hides the journal's own numbered tabs there. The
-- hub's replacement navigation is not in the available client evidence, so no
-- hub control is named or searched for here.
local Attach = {mode = "none", hookedTabs = {}, hookedJournal = nil}

-- The last numbered tab the client still shows, else the journal frame, which
-- is the one host known to be on screen whenever the Advisor tab is.
function Attach.Resolve(journal)
    local last
    for i = 1, theirTabCount do
        local t = _G["ProjectEbonholdEchoJournalTab" .. i]
        if t and t.IsShown and t:IsShown() then last = t end
    end
    if last then return last, "journal-tabs" end
    return journal, "journal-frame"
end

-- Idempotent. Changes the anchor only when the resolved target changed, and
-- reasserts the frame levels every time because a reparent resets them.
function Attach.Apply()
    local journal = _G["ProjectEbonholdEchoJournal"]
    if not (journal and ourTab) then return false end
    local target, mode = Attach.Resolve(journal)
    if Attach.target ~= target or Attach.mode ~= mode then
        ourTab:ClearAllPoints()
        if mode == "journal-tabs" then
            -- Same row as their tabs, standard -16 overlap after the last one.
            ourTab:SetPoint("TOPLEFT", target, "TOPRIGHT", -16, 0)
        else
            -- Their tab row hangs 12 below the journal's bottom edge and starts
            -- at its left. The right end of that same edge is used instead.
            ourTab:SetPoint("RIGHT", journal, "BOTTOMRIGHT", -12, -12)
        end
        Attach.target, Attach.mode = target, mode
    end
    ourTab:SetFrameLevel(mode == "journal-tabs" and target:GetFrameLevel()
        or journal:GetFrameLevel() + 2)
    if panel then panel:SetFrameLevel(journal:GetFrameLevel() + 10) end
    return true
end

-- For the diagnostic snapshot and the native drag/reopen check.
function M.AttachmentStatus()
    local journal = _G["ProjectEbonholdEchoJournal"]
    local parent = journal and journal.GetParent and journal:GetParent() or nil
    return {
        installed = installed, mode = Attach.mode,
        anchor = Attach.target and Attach.target.GetName and Attach.target:GetName() or "none",
        journalParent = parent and parent.GetName and parent:GetName() or "none",
        hubNavigation = "not in client evidence; not used",
    }
end

local function Install()
    local journal = _G["ProjectEbonholdEchoJournal"]
    local jScroll = _G["ProjectEbonholdEchoJournalScroll"]
    local tab1 = _G["ProjectEbonholdEchoJournalTab1"]
    if not (journal and jScroll and tab1) then
        error("journal frames not present")
    end
    EnsureAssociationScanner()

    local n = 0
    while _G["ProjectEbonholdEchoJournalTab" .. (n + 1)] do
        n = n + 1
    end
    theirTabCount = n

    -- A second Install after a partial failure reuses every frame and hook.
    ourTab = ourTab or CreateFrame("Button", "NexusJournalTab",
        journal, "CharacterFrameTabButtonTemplate")
    ourTab:SetText(TAB_LABEL)
    Attach.target, Attach.mode = nil, "none"
    Attach.Apply()
    -- A fresh template tab shows BOTH texture sets until its state is
    -- set; without this it renders as a mangled sliver.
    pcall(function() PanelTemplates_TabResize(ourTab, 0) end)
    pcall(function() PanelTemplates_DeselectTab(ourTab) end)
    ourTab:Show()
    -- A second click closes the Advisor again. When the host hides the
    -- numbered tabs, no stock tab click is left to do that.
    ourTab:SetScript("OnClick", function()
        pcall(function()
            if panel and panel:IsShown() then DeselectOurTab(true) else SelectOurTab() end
        end)
    end)

    -- Their tab numbering differs between client revisions. Never assume
    -- Tab1 is Loadouts: inspect the clicked tab after the stock handler runs.
    for i = 1, theirTabCount do
        local t = _G["ProjectEbonholdEchoJournalTab" .. i]
        if t then
            if t.HookScript and not Attach.hookedTabs[t] then
                Attach.hookedTabs[t] = true
                -- The host hides or restores these tabs at its own time.
                -- Event-driven: no scan and no per-frame work.
                t:HookScript("OnHide", function() pcall(Attach.Apply) end)
                t:HookScript("OnShow", function() pcall(Attach.Apply) end)
                t:HookScript("OnClick", function()
                    pcall(function()
                        DeselectOurTab(false)
                        associationVisible = true
                        if associationVisible then RefreshAssociationRows() else HideRowButtons() end
                    end)
                end)
            end
        end
    end
    -- Some client builds use bottom navigation buttons that are not named
    -- ProjectEbonholdEchoJournalTabN. The scanner determines visibility from
    -- actual loadout cards, so opening/rebuilding the journal remains safe.
    if journal.HookScript and Attach.hookedJournal ~= journal then
        Attach.hookedJournal = journal
        journal:HookScript("OnShow", function()
            pcall(function()
                -- The host may have embedded the journal or hidden its tabs
                -- since the last open.
                Attach.Apply()
                DeselectOurTab(false)
                associationVisible = true
            end)
        end)
        journal:HookScript("OnHide", function() associationVisible = false; HideRowButtons() end)
    end

    -- Our panel covers the journal's ENTIRE content region below the
    -- title bar: the per-tab top sections belong to THEIR tabs and
    -- their switcher rightly ignores our tab -- so we occlude rather
    -- than fight their state. EnableMouse blocks click-through.
    if not panel then
        panel = CreateFrame("Frame", "NexusJournalPanel", journal)
        panel:SetPoint("TOPLEFT", journal, "TOPLEFT", 10, -32)
        panel:SetPoint("BOTTOMRIGHT", journal, "BOTTOMRIGHT", -8, 8)
        panel:EnableMouse(true)
        local bg = panel:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetTexture(ASSET .. "UI-Background-Rock")
    end
    panel:SetFrameLevel(journal:GetFrameLevel() + 10)

    if not scroll then
        scroll = CreateFrame("ScrollFrame", "NexusJournalScroll",
            panel, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -6)
        scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 4)
        child = CreateFrame("Frame", nil, scroll)
        child:SetSize(292, 100)
        scroll:SetScrollChild(child)
    end

    panel:Hide()
end

-- Runs inside the client's own (pcall'd) handler paths: body must be
-- pcall-wrapped and minimal, or an error here aborts the remainder of
-- THEIR handler and gets misattributed to ProjectEbonhold.
local function OnJournalLifecycle()
    pcall(function()
        if not installed and pcall(Install) then
            installed = true
        end
        if installed then
            Attach.Apply()
            DeselectOurTab(true)
        end
    end)
end

local function EnsureLifecycleHooks()
    if hooked then return end
    if type(hooksecurefunc) ~= "function" then return end
    local pe = _G["ProjectEbonhold"]
    local ej = pe and pe.EchoJournal
    if type(ej) ~= "table" then return end
    local any = false
    if type(ej.Show) == "function" then
        hooksecurefunc(ej, "Show", OnJournalLifecycle)
        any = true
    end
    if type(ej.Toggle) == "function" then
        hooksecurefunc(ej, "Toggle", OnJournalLifecycle)
        any = true
    end
    hooked = any
end

-- The live menu-bar button that opens Character Progression -> Echoes, or nil.
-- Read-only: it finds the button and clicks nothing.
local function FindEchoesMicroButton()
    local button = _G["EchoJournalMicroButton"]
    if button and type(button.Click) == "function" then return button end
    local function walk(frame, depth)
        if not frame or depth > 6 then return nil end
        local name = frame.GetName and frame:GetName() or nil
        if type(name) == "string" then
            local lower = string.lower(name)
            if string.find(lower, "echojournalmicrobutton", 1, true)
                and type(frame.Click) == "function" then
                return frame
            end
        end
        local children = { frame.GetChildren and frame:GetChildren() }
        for i = 1, #children do
            local found = walk(children[i], depth + 1)
            if found then return found end
        end
        return nil
    end
    return walk(_G["UIParent"], 0)
end

-- Whether the Echoes page can be opened now (read-only). Callers check this
-- before closing their own window for the route, so a missing button loses
-- nothing.
function M.CanOpenBuilds()
    local ok, button = pcall(FindEchoesMicroButton)
    return ok and button ~= nil
end

local function ClickCurrentEchoesMicroButton()
    -- The server update moved Echoes into Character Progression. Calling the
    -- legacy ProjectEbonhold.EchoJournal.Show() still opens the retired
    -- standalone journal, so always enter through the live menu-bar button.
    local button = _G["EchoJournalMicroButton"]
    if button and type(button.Click) == "function" then
        local ok = pcall(button.Click, button)
        if ok then return true end
    end

    -- Be tolerant of a renamed/reparented button while still refusing to open
    -- the obsolete standalone frame. Search only actual clickable buttons.
    local function walk(frame, depth)
        if not frame or depth > 6 then return nil end
        local name = frame.GetName and frame:GetName() or nil
        if type(name) == "string" then
            local lower = string.lower(name)
            if string.find(lower, "echojournalmicrobutton", 1, true)
                and type(frame.Click) == "function" then
                return frame
            end
        end
        local children = { frame.GetChildren and frame:GetChildren() }
        for i = 1, #children do
            local found = walk(children[i], depth + 1)
            if found then return found end
        end
        return nil
    end

    local found = walk(_G["UIParent"], 0)
    if found and type(found.Click) == "function" then
        local ok = pcall(found.Click, found)
        if ok then return true end
    end
    return false
end

-- The Wishlist chooser of the attached strip, opened through the selector's
-- own click handler (the same candidates, target and checks as a player's
-- click). Opening it assigns nothing; only a row click does. True when the
-- chooser is open.
local function OpenChooserNow()
    local host = associationPanel
    if not (host and host:IsVisible() and host.selector and host.selector:IsVisible()) then
        return false
    end
    if wishlistPicker and wishlistPicker:IsShown() then return true end
    local click = host.selector:GetScript("OnClick")
    if type(click) ~= "function" then return false end
    click(host.selector)
    return wishlistPicker ~= nil and wishlistPicker:IsShown()
end

local CHOOSER_COACH = "The Echoes page is open. Click the Nexus Wishlist selector at its top to choose a "
    .. "Wishlist; nothing is assigned until you choose one."

-- `openChooser`: also open the Wishlist chooser once the strip is attached
-- (Assign Wishlist, Set up current build, Help and the editor's Assign now);
-- when the strip cannot be shown, say what to click instead. Without it the
-- existing behaviour is unchanged. Returns true when the Echoes page opened.
-- `beforeOpen` (optional): the caller's own step before the page opens (the
-- HUD's Assign Wishlist closes its other windows). It runs only when the
-- game's Character Progression entry is there; otherwise nothing runs and
-- false, "unavailable" is returned, so the caller says why and loses nothing.
function M.OpenBuilds(openChooser, beforeOpen)
    if type(beforeOpen) == "function" then
        if not M.CanOpenBuilds() then return false, "unavailable" end
        beforeOpen()
    end
    EnsureAssociationScanner()

    local opened = ClickCurrentEchoesMicroButton()
    if not opened then
        print("|cffff6060Nexus:|r Could not find the server Character Progression button. Open Character Progression → Echoes manually.")
        return false
    end

    local chooserPending = openChooser == true
    -- Let the server finish constructing/selecting its new Echoes page before
    -- attaching Nexus beside the live loadout dropdown.
    local function finish(last)
        pcall(function()
            if not installed and pcall(Install) then installed = true end
            if installed then
                Attach.Apply()
                DeselectOurTab(false)
            end
            RefreshAssociationRows()
            if chooserPending then
                if OpenChooserNow() then
                    chooserPending = false
                elseif last then
                    chooserPending = false
                    -- Truthful about the page: "open" only when Nexus sees its
                    -- strip there. The game's button toggles the page, so one
                    -- that was already open can close again (native behaviour,
                    -- not observed offline); then no claim is made.
                    local strip = associationPanel
                    local shown = strip and strip.IsVisible and strip:IsVisible()
                    print("|cffffd200Nexus:|r " .. (shown and CHOOSER_COACH
                        or ("Nexus could not confirm that the Echoes page is open (if it was already open, "
                            .. "the game's button may have closed it). Open Character Progression -> Echoes "
                            .. "and click the Nexus Wishlist selector at its top; nothing is assigned until "
                            .. "you choose one.")))
                end
            end
        end)
    end
    local timers = C_Timer and C_Timer.After
    finish(not timers)
    if timers then
        C_Timer.After(0.10, function() finish(false) end)
        C_Timer.After(0.35, function() finish(true) end)
    end
    return true
end

function M.DebugSnapshot()
    local journal = _G["ProjectEbonholdEchoJournal"]
    local A = Nexus and Nexus.GameAdapter
    local slots = A and A.Slots and A.Slots()
    local visible = journal and IsLoadoutsVisible(journal) or false
    local tab = journal and FindLoadoutsTab(journal) or nil
    local tabText = tab and NormalizedText(tab) or "none"
    local lines = {}
    lines[#lines + 1] = "journal=" .. tostring(journal ~= nil) .. " shown=" .. tostring(journal and journal:IsShown() or false)
    lines[#lines + 1] = "loadoutsVisible=" .. tostring(visible) .. " tab=" .. tostring(tabText)
    local attachment = M.AttachmentStatus()
    lines[#lines + 1] = "advisorTab mode=" .. tostring(attachment.mode) .. " anchor=" .. tostring(attachment.anchor)
        .. " journalParent=" .. tostring(attachment.journalParent) .. " hubNavigation=" .. attachment.hubNavigation
    lines[#lines + 1] = "associationPanel=" .. tostring(associationPanel ~= nil)
        .. " shown=" .. tostring(associationPanel and associationPanel:IsShown() or false)
    if slots then
        lines[#lines + 1] = "activeSlot=" .. tostring(slots.activeSlot) .. " maxSlots=" .. tostring(slots.maxSlots)
        for i = 1, tonumber(slots.maxSlots or 5) do
            local r = slots.bySlot and slots.bySlot[i]
            lines[#lines + 1] = "slot" .. i .. " echoes=" .. tostring(r and r.echoes and #r.echoes or 0) .. " linked=" .. tostring(A.GetLoadoutWishlistSlot and A.GetLoadoutWishlistSlot(i) or "none")
        end
    else
        lines[#lines + 1] = "slots=nil"
    end
    return lines
end

-- Attach to the live journal (or arm the lazy Show/Toggle hooks and
-- attach on first open). Safe to call repeatedly; never errors.
function M.TryInstall(dataProvider)
    local ok = pcall(function()
        if type(dataProvider) == "function" then
            provider = dataProvider
        end
        EnsureAssociationScanner()
        EnsureLifecycleHooks()
        if not installed and pcall(Install) then
            installed = true
        end
    end)
    if not ok then return false end
    return installed and true or false
end

-- Dark-theme Nexus controls embedded in the server Echo Journal.
do
    local originalRefreshAssociations = M.RefreshAssociations
    M.RefreshAssociations = function(...)
        local result = originalRefreshAssociations(...)
        if associationPanel and Nexus.Theme then Nexus.Theme.StyleTree(associationPanel) end
        return result
    end
end
