-- Nexus: ui/Panel.lua v2.13
-- Adaptive main HUD. The panel changes shape for setup, active progress,
-- completed builds, and live Echo rolls instead of showing every section
-- at all times.

Nexus = Nexus or {}
local M = {}
Nexus.Panel = M

local frame, minimapBtn, callbacks
local panelWantedVisible = true
local menuSuppressed = false
local menuTransition = false
local attachedMenuFrames = {}
local missingNamesCache, shedNamesCache, unknownTomesCache, toLockNamesCache = {}, {}, {}, {}

local buildHeaderText, switchBtn, wishlistMenu
local rollArea, statusText, cardTexts, recText, rollDivider = nil, nil, {}, nil, nil
local progressLabel, progressValue, needLabel, needText, needHit
local tomesLabel, tomesValue, tomesHit
local shedLabel, shedText, shedHit
local performanceLabel, setLabelText
local dummyLabel, dummyValue, dummyGlobal, dummyGlobalValue, dummyHit
local lkLabel, lkPersonalLabel, lkValue, lkGlobal, lkGlobalValue, lkHit
local completeBadge, completeSubtext
local setupText, setupHint, setupGetStartedBtn, setupImportBtn
local autoBtn, planBtn, exploreBtn, menuBtn, versionText, worldStatusBox, worldStatusText, worldStatusAsh, worldStatusGain, worldStatusHit, bestDpsText, bestDpsHit
local showPerformance = false
local renderState = {
    committed=false,applying=false,signatures=nil,hadFailure=false,
    -- The roll block the last committed render showed, while Auto is ON in
    -- one rolling context: {context=..., cards=bool}, or nil. Memory only,
    -- one entry; see RollPresentation.
    roll=nil,
    -- The committed model's status and recommendation before the user-text
    -- conversion (it is not idempotent), for a render of that same model.
    rawText=nil,
    statusPresentation=nil, -- committed, validated localization result only
    -- Destination character observation (ObserveDestinationCharacter):
    -- the world-session phase (nil before an entered world, "entered",
    -- "leaving", "loggedOut") and the latest validated capture in it.
    -- Memory only; presentation only.
    destinationWorld=nil,
    destinationCharacter=nil,
}
-- Destination world-session revision: a private monotonic count of
-- ObserveDestinationCharacter's world invalidations (leave, logout, enter),
-- published at each one as the view-only scalar M.destinationSessionRevision
-- (nil before the first, while the count is still 0). Views bind their
-- observations to the counted session, never to a character name. The
-- writable public scalar stays for compatibility and diagnostics and cannot
-- alone show the current session: a view holds an observation only while
-- that scalar equals this count (read through the pure
-- M.DestinationSessionCount) and the view's held stamp. The count only grows
-- and is never reissued, so a restored earlier public value no longer
-- matches it; equality cannot detect a value written equal to the current
-- count (0 before the first publication included). Memory only;
-- presentation only.
local destinationSessionCounter = 0
local renderStats = {
    calls=0, layouts=0, skipped=0, statusOnly=0,
    performancePasses=0, noticePasses=0, themeTreeWalks=0,
    commits=0,failures=0,recoveries=0,recoveryRequests=0,
    hiddenUncommitted=0,
}

StaticPopupDialogs["NEXUS_UPDATE_RELEASES"] = {
    -- Owner-approved item 12 (issue #175): what to do next, in plain words.
    -- The box below keeps the full Releases address, selected for copying.
    text = "%s\n\nTo check or update, copy this Releases page address into your web browser. "
        .. "Installation is manual: Nexus downloads and installs nothing.",
    button1 = "Close",
    hasEditBox = true,
    editBoxWidth = 380,
    OnShow = function(self)
        local url = Nexus.Updates and Nexus.Updates.ReleaseUrl
            and Nexus.Updates.ReleaseUrl() or "https://github.com/Viscerals/Better-Nexus/releases"
        -- The popup's edit box: its editBox key, or else the named child
        -- "<popup name>EditBox" that a template without that key provides.
        -- Only a box with the three EditBox methods used here is filled.
        local function Usable(candidate)
            return type(candidate) == "table" and type(candidate.SetText) == "function"
                and type(candidate.HighlightText) == "function"
                and type(candidate.SetFocus) == "function"
        end
        local box = self.editBox
        if not box and type(self.GetName) == "function" then
            local okName, name = pcall(self.GetName, self)
            if okName and type(name) == "string" and name ~= "" then
                box = _G[name .. "EditBox"]
            end
        end
        if Usable(box) then
            box:SetText(url)
            box:HighlightText()
            box:SetFocus()
        end
    end,
    EditBoxOnEnterPressed = function(self) self:HighlightText() end,
    EditBoxOnEscapePressed = function(self) self:ClearFocus() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function SafeText(v) return v ~= nil and tostring(v) or "" end

-- Full-UI localization (panel family): code-owned English reaches the
-- display through the reviewed seam, looked up at call time (never cached
-- at load, so the session's language and a swapped module both apply).
-- LT: a static meaning. LF: a named template whose slots this code fills
-- (text slots take a string, count slots take LC(n): unknown shows "?").
-- Colour codes, bullets, padding and separators stay in code. EnsureFrame
-- is at the 60-upvalue limit: it calls Nexus.Localization directly.
local function LT(key) return (Nexus.Localization.Text(key)) end
local function LF(key, fields)
    -- A seam without the template formatter (a partial test seam) gives the
    -- seam's documented safe status, never an error and never a guess.
    local L = Nexus.Localization
    if type(L.Format) ~= "function" then return L.UNAVAILABLE or "" end
    return (L.Format(key, fields))
end
local function LC(value) return Nexus.Localization.Count(value) end

------------------------------------------------------------------------
-- Destination row: a reusable one-line strip of four disjoint cells, in
-- UserText.DestinationFields order (character, Saved Build, Wishlist,
-- state). It words only the descriptor its caller already captured,
-- through that pure formatter, and changes only its own row and cells: it
-- reads no game, Store or assignment state, resolves nothing and schedules
-- nothing. The caller anchors the row (never to one of its cells) and owns
-- its width and height. The do block keeps these locals out of the main
-- chunk's scope and out of EnsureFrame.
--
-- M.CreateDestinationRow(parent[, firstText]) -> row
--   row: a new Frame, child of parent, not anchored.
--   row.cells: the four FontStrings, created once. cells[1] is firstText
--   when given (it keeps its font); the others are row children in the
--   LayoutMetrics normal font.
--   row.hits: one LayoutMetrics.FullTextTooltip hover area per cell,
--   created once and hidden until the first successful update; then each
--   shows all DestinationFields tooltip lines, stored by the update in
--   every cell's _nexusFullText.
-- M.UpdateDestinationRow(row, descriptor, width, height[, forceFirstText])
--   -> refit
--   Sizes the row to width x height (height at least 17 px: one line, no
--   wrapping) and fits the cells in it, left to right. refit is false for
--   a settled update (same formatter output, width, height,
--   LayoutMetrics.RuntimeKey and per-cell GetFont): it calls no cell
--   setter and measures nothing, except that forceFirstText re-applies the
--   shown first text with a real cells[1]:SetText. Widget errors are not
--   caught. The view cache (row._nexusDestinationView) is cleared before
--   the first widget call and committed only after every cell operation
--   succeeded, so a failed update is redone in full by the next one.
--
-- Fit: each text is measured in its own cell (GetStringWidth). A cell
-- tries "Label: value", "Label: compact", a short cue with compact (C:,
-- B:, W:; a state alternative is its own cue), then the cue with minimum
-- (Wishlist, state); the widest cell steps down first. A state shows one
-- whole alternative and is never cut. Only names are shortened: the
-- character and Saved Build compact values and a Wishlist minimum longer
-- than one character (the formatter's assigned name; its refusal, unknown
-- and unavailable markers are one character). A Wishlist compact value is
-- shown whole or replaced by its minimum, unless the name cut below
-- applies. A name is tried
-- whole first, with its cue and then without it; only then is it cut. A
-- cut falls at a UTF-8 character, an escaped pipe pair "||" counting as
-- one, keeps the leading token (up to 3 characters; a slot token, "#" and
-- all its digits such as "#123", always whole, never "#" or "#1" of "#12")
-- and adds "..." when that still fits, else omits the "...", else the cue.
-- The name cut follows its own rules: when the Wishlist cell would show a
-- minimum that begins its compact value within the value's leading token
-- (up to its first space), such as "?" of "?: name", and its shortest cut
-- fits beside every other cell's whole alternative short of the minima,
-- that cut is shown instead, such as "W:?: Starter..." for "W:?", and the
-- other cells show those alternatives. It keeps the cue, the whole token
-- and at least its next 4 characters (the space and 3 more; trailing
-- spaces dropped), falls at a UTF-8 character as above, adds "..." and is
-- the longest such cut that fits the room the other cells leave. A
-- compact that such a cut would not narrow, or one that its minimum does
-- not begin, is shown whole or as its minimum; a state and a
-- one-character marker are never cut.
-- Below the whole floors (a slot token alone included) the cells stay
-- disjoint in the row and the client shortens them, the state last; the
-- tooltip keeps every full line.
------------------------------------------------------------------------
do
    local DEST_MIN_HEIGHT, DEST_GAP, DEST_SLACK, DEST_LEAD = 17, 4, 1, 3
    local DEST_ELLIPSIS = "..."
    local DEST_CUES = {character = "C:", savedBuild = "B:", wishlist = "W:", state = ""}
    -- The value a cell may cut (names only, see above). A Wishlist compact
    -- is not listed: only the name cut shortens it, and only while its
    -- minimum is the Wishlist value listed here (see above).
    local DEST_CLIP = {character = "compact", savedBuild = "compact", wishlist = "minimum"}

    local function DestLayout()
        local layout = Nexus.LayoutMetrics
        if type(layout) ~= "table" or type(layout.FontObject) ~= "function"
            or type(layout.OneLineLabel) ~= "function"
            or type(layout.FullTextTooltip) ~= "function"
            or type(layout.RuntimeKey) ~= "function"
            or type(layout.RuntimeMetrics) ~= "function"
            or type(layout.ConservativeText) ~= "function" then
            error("Nexus destination row: Nexus.LayoutMetrics is not loaded", 3)
        end
        return layout
    end

    local function DestFields(descriptor)
        local userText = Nexus.UserText
        local formatter = type(userText) == "table" and userText.DestinationFields
        if type(formatter) ~= "function" then
            error("Nexus destination row: Nexus.UserText.DestinationFields is not loaded", 3)
        end
        local fields, tooltip = formatter(descriptor)
        if type(fields) ~= "table" or #fields ~= 4 or type(tooltip) ~= "table" then
            error("Nexus destination row: DestinationFields did not return four cells", 3)
        end
        return fields, tooltip
    end

    local function DestRowParts(row)
        local cells = type(row) == "table" and row.cells
        local hits = type(row) == "table" and row.hits
        if type(cells) ~= "table" or type(hits) ~= "table" or #cells ~= 4 or #hits ~= 4 then
            error("Nexus.Panel.UpdateDestinationRow: not a row from CreateDestinationRow", 3)
        end
        return cells, hits
    end

    -- Bytes of the display character at index: one UTF-8 character, an
    -- escaped pipe pair "||", or a lone pipe with the character after it, so
    -- that a cut never splits a character or an escape.
    local function DestStep(text, index)
        local byte = text:byte(index)
        if byte == 124 then
            local following = text:byte(index + 1)
            if following == nil then return 1 end
            if following == 124 then return 2 end
            return 1 + DestStep(text, index + 1)
        end
        if byte < 0xC0 then return 1 end
        if byte < 0xE0 then return 2 end
        if byte < 0xF0 then return 3 end
        return 4
    end

    -- The last byte of each display character of text.
    local function DestUnitEnds(text)
        local ends, index, length = {}, 1, #text
        while index <= length do
            index = math.min(length, index + DestStep(text, index) - 1) + 1
            ends[#ends + 1] = index - 1
        end
        return ends
    end

    -- The fitted width of text in this cell's own font, measured once per
    -- update; while the client reports no width, the LayoutMetrics
    -- conservative character width stands in.
    local function DestMeasure(cell, text, memo, fallback)
        local width = memo[text]
        if width then return width end
        cell:SetText(text)
        local measured = tonumber(cell:GetStringWidth())
        if not measured or measured ~= measured or measured <= 0 or measured >= math.huge then
            measured = #DestUnitEnds(text) * fallback
        end
        width = math.ceil(measured) + DEST_SLACK
        memo[text] = width
        return width
    end

    -- A cell's alternatives, each strictly narrower than the one before.
    local function DestLadder(cell, field, memo, fallback)
        local key = field.key
        local label = SafeText(field.label)
        local full = label ~= "" and (label .. ": ") or ""
        local cue = DEST_CUES[key] or (label ~= "" and (label:sub(1, 1) .. ":") or "")
        local value = SafeText(field.value)
        local compact = field.compact ~= nil and SafeText(field.compact) or value
        local wanted = {
            {text = full .. value},
            {text = full .. compact},
            {text = cue .. compact, cue = cue, value = compact, clip = DEST_CLIP[key] == "compact"},
        }
        if field.minimum ~= nil then
            local minimum = SafeText(field.minimum)
            wanted[4] = {text = cue .. minimum, cue = cue, value = minimum,
                clip = DEST_CLIP[key] == "minimum"}
        end
        local ladder, kept = {}, {}
        for index = 1, #wanted do
            local rung = wanted[index]
            local same = kept[rung.text]
            if same ~= nil then
                if same and rung.clip then
                    same.clip, same.cue, same.value = true, rung.cue, rung.value
                end
            else
                rung.width = DestMeasure(cell, rung.text, memo, fallback)
                local last = ladder[#ladder]
                if not last or rung.width < last.width then
                    ladder[#ladder + 1] = rung
                    kept[rung.text] = rung
                else
                    kept[rung.text] = false
                end
            end
        end
        return ladder
    end

    -- A name rung fitted to limit (see the policy above): its text and
    -- fitted width. The whole value is tried first, with its cue and then
    -- without it; only a value that does not fit whole is cut. A leading
    -- slot token ("#" and its digits, then a space or the end, such as
    -- "#12") is atomic: a cut keeps it whole and shortens only the name
    -- after it, and a token that does not fit even alone is shown whole
    -- (the client then shortens the cell).
    local function DestClip(cell, rung, limit, memo, fallback)
        local value, cue = rung.value, rung.cue
        local width = DestMeasure(cell, cue .. value, memo, fallback)
        if width <= limit then return cue .. value, width end
        width = DestMeasure(cell, value, memo, fallback)
        if width <= limit then return value, width end
        local ends = DestUnitEnds(value)
        local count, lead, start = #ends, #ends, 1
        for unit = 1, count do
            if ends[unit] == start and value:byte(start) == 32 then
                lead = unit - 1
                break
            end
            start = ends[unit] + 1
        end
        -- A slot token has one byte per character: it is the leading token
        -- exactly when its length is lead.
        local slot = value:match("^#%d+")
        local atomic = slot ~= nil and #slot == lead
        local need = atomic and lead or math.max(1, math.min(DEST_LEAD, lead, count - 1))
        if need >= count then
            -- The slot token is the whole value: it is never cut.
            return value, width
        end
        local function Shown(units, withCue, ellipsis)
            local prefix = value:sub(1, ends[units])
            if ellipsis then prefix = (prefix:gsub(" +$", "")) .. DEST_ELLIPSIS end
            return (withCue and cue or "") .. prefix
        end
        local function Largest(withCue, ellipsis)
            local low, high, best = 1, count - 1, 0
            while low <= high do
                local middle = math.floor((low + high) / 2)
                if DestMeasure(cell, Shown(middle, withCue, ellipsis), memo, fallback) <= limit then
                    best, low = middle, middle + 1
                else
                    high = middle - 1
                end
            end
            return best
        end
        local units, withCue, ellipsis = Largest(true, true), true, true
        if units < need then
            local bare = Largest(true, false)
            if bare >= need then
                units, ellipsis = bare, false
            else
                local alone = cue ~= "" and Largest(false, false) or bare
                if atomic and alone < need then
                    -- Not even the slot token fits alone: it stays whole.
                    units, withCue, ellipsis = need, false, false
                elseif alone > bare then
                    units, withCue, ellipsis = alone, false, false
                elseif bare >= 1 then
                    units, ellipsis = bare, false
                else
                    units, withCue, ellipsis = 1, false, false
                end
            end
        end
        local text = Shown(units, withCue, ellipsis)
        return text, DestMeasure(cell, text, memo, fallback)
    end

    -- Cell texts, widths and left offsets for a row width. Each cell first
    -- steps down its own ladder, the widest first. When the narrowest whole
    -- alternatives short of the minima (a minimum is the Wishlist or state
    -- cue with minimum) fit together, no cell takes its minimum, so a whole
    -- compact state such as a captured "first-run target" is not replaced
    -- by its minimum ("C:1") while it fits beside the other cells' compact
    -- alternatives; otherwise each ladder runs to its minimum, still the
    -- widest first. When that discards a name into its minimum (the
    -- Wishlist "W:?" of a "?: name" compact) and a name cut lets those
    -- whole alternatives fit together, the cut is shown instead: every
    -- other cell takes its whole alternative short of the minima again
    -- (labels yield before a name is cut, and no cell keeps a minimum) and
    -- the cut takes the room they leave, so a long plan name is shortened,
    -- not lost, beside a whole captured state. A name cut needs a minimum
    -- that is a name rung (DEST_CLIP) whose text, with the same cue,
    -- begins the cue-with-compact text within the value's leading token
    -- (up to its first space). It keeps that token whole, the space and at
    -- least DEST_LEAD more characters, cut at a display character
    -- (DestUnitEnds) with "...", so it shows all the minimum shows plus a
    -- name prefix; the tooltip keeps the whole name. It is the only cut of
    -- a Wishlist compact value (the policy above otherwise shows it whole
    -- or as its minimum); a refusal or other marker that does not begin its
    -- compact is never cut. A row still too wide then
    -- reserves every floor before a name is shortened: a cell that is not
    -- cut (a state, a one-glyph marker such as the refusal "!") keeps its
    -- whole alternative, and a name keeps at least what DestClip shows at no
    -- width (its slot token such as "#123" whole, else its leading
    -- character). Only when those floors do not fit, and only when the
    -- following together make them fit, optional parts yield in turn, each
    -- no further than needed: the colon of a cue before a one-glyph
    -- punctuation marker ("W:!" becomes "W!"), the gaps, then each box's
    -- slack. The names then share the rest. Every text stays a whole
    -- formatter alternative, a DestClip cut of a name or a name cut;
    -- nothing is parsed out of a state, slot token or marker.
    local function DestFit(layout, cells, fields, width)
        local gap = math.max(0, math.min(DEST_GAP, math.floor((width - 4) / 3)))
        local budget = width - 3 * gap
        local fallback = (layout.ConservativeText((layout.RuntimeMetrics())))
        local ladders, level, memos, total = {}, {}, {}, 0
        for index = 1, 4 do
            memos[index] = {}
            ladders[index] = DestLadder(cells[index], fields[index], memos[index], fallback)
            level[index] = 1
            total = total + ladders[index][1].width
        end
        -- Step the widest cell that has a narrower alternative down first
        -- (on a tie, the later cell), each no further than its stop: while
        -- the narrowest whole alternatives of all four cells fit together,
        -- that alternative (the rung before a minimum); otherwise its
        -- narrowest. A minimum is a cue rung after another cue rung:
        -- DestLadder gives a cue only to the cue-with-compact and
        -- cue-with-minimum alternatives and keeps one rung where they are
        -- the same text.
        local stops, wholeWidth = {}, 0
        for index = 1, 4 do
            local ladder = ladders[index]
            local stop = #ladder
            if stop > 1 and ladder[stop - 1].cue ~= nil then stop = stop - 1 end
            stops[index], wholeWidth = stop, wholeWidth + ladder[stop].width
        end
        -- whole: those stops short of the minima, kept for a name cut.
        local whole = {}
        if wholeWidth > budget then
            for index = 1, 4 do
                whole[index], stops[index] = stops[index], #ladders[index]
            end
        end
        while total > budget do
            local pick, widest = nil, -1
            for index = 1, 4 do
                local rung = ladders[index][level[index]]
                if level[index] < stops[index] and rung.width >= widest then
                    pick, widest = index, rung.width
                end
            end
            if not pick then break end
            local ladder = ladders[pick]
            total = total - ladder[level[pick]].width + ladder[level[pick] + 1].width
            level[pick] = level[pick] + 1
        end
        local texts, widths = {}, {}
        for index = 1, 4 do
            local rung = ladders[index][level[index]]
            texts[index], widths[index] = rung.text, rung.width
        end
        -- A name discarded into its minimum (see above): when its name cut
        -- at its floor fits beside every other cell's stop short of the
        -- minima, each cell takes that stop again and each cut takes the
        -- room the others leave, keeping the floors of the cuts after it:
        -- its largest cut that fits, never below its floor.
        if wholeWidth > budget then
            local cuts, cutting, cutNeed = {}, false, 0
            local function NameCut(cut, units)
                return cut.cue .. (cut.value:sub(1, cut.ends[units]):gsub(" +$", ""))
                    .. DEST_ELLIPSIS
            end
            for index = 1, 4 do
                local ladder = ladders[index]
                local rung, least = ladder[whole[index]], ladder[#ladder]
                if level[index] == #ladder and whole[index] < #ladder and least.clip
                    and not rung.clip and rung.cue == least.cue
                    and rung.text:sub(1, #least.text) == least.text then
                    local value = rung.value
                    local ends = DestUnitEnds(value)
                    local lead, start = nil, 1
                    for unit = 1, #ends do
                        if ends[unit] == start and value:byte(start) == 32 then
                            lead = unit - 1
                            break
                        end
                        start = ends[unit] + 1
                    end
                    local units = lead and lead + 1 + DEST_LEAD
                    if units and lead >= 1 and units < #ends
                        and #least.value <= ends[lead] then
                        local cut = {cue = rung.cue, value = value, ends = ends, units = units}
                        cut.floor = DestMeasure(cells[index], NameCut(cut, units),
                            memos[index], fallback)
                        if cut.floor < rung.width then cuts[index], cutting = cut, true end
                    end
                end
                cutNeed = cutNeed + (cuts[index] and cuts[index].floor or rung.width)
            end
            if cutting and cutNeed <= budget then
                local room = budget - cutNeed
                total = 0
                for index = 1, 4 do
                    local cut = cuts[index]
                    if cut then
                        room = room + cut.floor
                        local low, high, best = cut.units + 1, #cut.ends - 1, cut.units
                        while low <= high do
                            local middle = math.floor((low + high) / 2)
                            if DestMeasure(cells[index], NameCut(cut, middle), memos[index],
                                fallback) <= room then
                                best, low = middle, middle + 1
                            else
                                high = middle - 1
                            end
                        end
                        texts[index] = NameCut(cut, best)
                        widths[index] = DestMeasure(cells[index], texts[index],
                            memos[index], fallback)
                        room = room - widths[index]
                    else
                        local rung = ladders[index][whole[index]]
                        texts[index], widths[index] = rung.text, rung.width
                    end
                    total = total + widths[index]
                end
            end
        end
        -- Still too wide: every cell is at its narrowest alternative. Each
        -- floor is reserved before a name is shortened (see above).
        local slackYields = false
        if total > budget then
            local open, isOpen, floors, need = {}, {}, {}, 0
            for index = 1, 4 do
                local rung = ladders[index][level[index]]
                if rung.clip and #DestUnitEnds(rung.value) >= 2 then
                    open[#open + 1] = index
                    isOpen[index] = true
                    local _, least = DestClip(cells[index], rung, 0, memos[index], fallback)
                    floors[index] = least
                else
                    floors[index] = widths[index]
                end
                need = need + floors[index]
            end
            -- Optional parts yield only when the floors do not fit and they
            -- together make them fit, each no further than needed.
            if need > budget then
                local marks, saving, room = {}, 0, 0
                for index = 1, 4 do
                    local rung = ladders[index][level[index]]
                    local cue, value, least = rung.cue, rung.value, floors[index]
                    if not isOpen[index] and type(cue) == "string" and cue:sub(-1) == ":"
                        and type(value) == "string" and value:find("^%p$") then
                        local text = cue:sub(1, -2) .. value
                        local narrow = DestMeasure(cells[index], text, memos[index], fallback)
                        if narrow < least then
                            marks[#marks + 1] = {index = index, text = text, width = narrow}
                            saving, least = saving + least - narrow, narrow
                        end
                    end
                    room = room + math.min(DEST_SLACK, least - 1)
                end
                if need - saving - room <= budget + 3 * gap then
                    for position = 1, #marks do
                        if need <= budget then break end
                        local mark = marks[position]
                        need = need - floors[mark.index] + mark.width
                        floors[mark.index] = mark.width
                        texts[mark.index], widths[mark.index] = mark.text, mark.width
                    end
                    if need > budget then
                        local less = math.min(gap, math.ceil((need - budget) / 3))
                        gap, budget = gap - less, budget + 3 * less
                    end
                    slackYields = need > budget
                end
            end
            -- The names share the rest, the shortest first, each shortened
            -- only when it exceeds its share; a share never takes the floors
            -- kept for the names after it.
            local remaining, reserved = budget, 0
            for index = 1, 4 do
                if isOpen[index] then
                    reserved = reserved + floors[index]
                else
                    remaining = remaining - widths[index]
                end
            end
            table.sort(open, function(a, b)
                if widths[a] ~= widths[b] then return widths[a] < widths[b] end
                return a < b
            end)
            for position = 1, #open do
                local index = open[position]
                reserved = reserved - floors[index]
                local share = math.min(math.floor(remaining / (#open - position + 1)),
                    remaining - reserved)
                if widths[index] > share then
                    texts[index], widths[index] = DestClip(cells[index],
                        ladders[index][level[index]], share, memos[index], fallback)
                end
                remaining = remaining - widths[index]
            end
        end
        local used = 0
        for index = 1, 4 do used = used + widths[index] end
        -- The last optional part: each box's slack, character first.
        if slackYields then
            for index = 1, 4 do
                if used <= budget then break end
                local cut = math.min(used - budget, DEST_SLACK, widths[index] - 1)
                widths[index], used = widths[index] - cut, used - cut
            end
        end
        -- Below the floors: narrow the boxes (character first, state last)
        -- so that the cells stay disjoint inside the row.
        for index = 1, 4 do
            if used <= budget then break end
            local cut = math.min(used - budget, widths[index] - 1)
            widths[index], used = widths[index] - cut, used - cut
        end
        local offsets, x = {}, 0
        for index = 1, 4 do
            offsets[index] = x
            x = x + widths[index] + gap
        end
        return texts, widths, offsets
    end

    local function DestPart(parts, value)
        if value == nil then
            parts[#parts + 1] = "~"
        else
            value = tostring(value)
            parts[#parts + 1] = #value .. ":" .. value
        end
    end

    -- Everything the row shows or discloses, from the formatter's output.
    local function DestSemanticKey(fields, tooltip)
        local parts = {}
        for index = 1, #fields do
            local field = fields[index]
            DestPart(parts, field.key)
            DestPart(parts, field.label)
            DestPart(parts, field.value)
            DestPart(parts, field.compact)
            DestPart(parts, field.minimum)
        end
        DestPart(parts, #tooltip)
        for index = 1, #tooltip do DestPart(parts, tooltip[index]) end
        return table.concat(parts, "/")
    end

    -- The row geometry and effective fonts: LayoutMetrics.RuntimeKey (point
    -- size, UI scale and revision) and each cell's own font path, size and
    -- flags, which tell apart faces of the same size.
    local function DestGeometryKey(layout, cells, width, height)
        local parts = {}
        DestPart(parts, layout.RuntimeKey("NexusDestinationRow", width, height))
        for index = 1, #cells do
            local path, size, flags = cells[index]:GetFont()
            DestPart(parts, path)
            DestPart(parts, size)
            DestPart(parts, flags)
        end
        return table.concat(parts, "/")
    end

    function M.CreateDestinationRow(parent, firstText)
        if firstText ~= nil and (type(firstText) ~= "table"
            or type(firstText.SetText) ~= "function") then
            error("Nexus.Panel.CreateDestinationRow: firstText must be a FontString", 2)
        end
        local layout = DestLayout()
        local row = CreateFrame("Frame", nil, parent)
        local cells, hits = {}, {}
        for index = 1, 4 do
            local cell = index == 1 and firstText or nil
            if not cell then
                cell = row:CreateFontString(nil, "OVERLAY")
                cell:SetFontObject(layout.FontObject("normal"))
                cell:SetJustifyH("LEFT")
            end
            local hit = layout.FullTextTooltip(cell, row)
            hit:Hide()
            cells[index], hits[index] = cell, hit
        end
        row.cells, row.hits = cells, hits
        return row
    end

    function M.UpdateDestinationRow(row, descriptor, width, height, forceFirstText)
        local cells, hits = DestRowParts(row)
        width = tonumber(width)
        if not width or width ~= width or width == math.huge or width == -math.huge then
            error("Nexus.Panel.UpdateDestinationRow: width must be a finite number", 2)
        end
        width = math.max(4, math.floor(width))
        height = tonumber(height)
        if not height or height ~= height or height == math.huge then
            height = DEST_MIN_HEIGHT
        end
        height = math.max(DEST_MIN_HEIGHT, math.floor(height))
        local layout = DestLayout()
        local fields, tooltip = DestFields(descriptor)
        local semantic = DestSemanticKey(fields, tooltip)
        local geometry = DestGeometryKey(layout, cells, width, height)
        local view = row._nexusDestinationView
        if view and view.semantic == semantic and view.geometry == geometry then
            if forceFirstText then
                row._nexusDestinationView = nil
                cells[1]:SetText(view.texts[1])
                row._nexusDestinationView = view
            end
            return false
        end
        row._nexusDestinationView = nil
        local texts, widths, offsets = DestFit(layout, cells, fields, width)
        local full = table.concat(tooltip, "\n")
        row:SetWidth(width)
        row:SetHeight(height)
        for index = 1, 4 do
            local cell = cells[index]
            cell:SetText(texts[index])
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", row, "LEFT", offsets[index], 0)
            cell:SetWidth(widths[index])
            cell:SetJustifyH("LEFT")
            layout.OneLineLabel(cell, nil, height)
            cell._nexusFullText = full
        end
        for index = 1, 4 do hits[index]:Show() end
        row._nexusDestinationView = {semantic = semantic, geometry = geometry,
            texts = texts, widths = widths, offsets = offsets}
        return true
    end
end

------------------------------------------------------------------------
-- Header line 1, right to left (Claude Design full UI, "Main panel (Play)":
-- the Auto chip, the More menu, then Close): Close in the corner
-- (M.EnsureHeaderClose), Options at its left, and the Auto control, or the
-- Auto state words while it is hidden, at Options' left. The title keeps the
-- rest of the line (182 px at 420 px). Issue #165: the menu reads Options,
-- not an ellipsis alone, and "! Options" while a trusted update notice is
-- shown. Its 80 px label room holds "! Options" on one line at 125% text even
-- in the LayoutMetrics conservative model (9 x 8.75 px = 78.75 px; "Options"
-- 61.25 px). Only a larger face or a longer label is shortened; its hover
-- then names it in full first, and the leading "!" is never the part cut.
-- The label is the localized "panel.button.options" (M.OptionsLabel); the
-- "! " is code-owned and added only for the trusted notice the model carries.
-- Every slot is an offset from the panel's right edge, so a wider panel keeps
-- the same order. Geometry and words only: placing it opens, sends and
-- changes nothing.
------------------------------------------------------------------------
-- design/current "Nexus Main Panel - Compact Redesign": line 1 holds only the
-- drag grip and the title at the left and Auto, Options and Close at
-- the right, with 8 px between the three controls (4 px before) so each is a
-- distinct target; Close is the design's square-ish 24 px. The title starts
-- after the grip (titleLeft) and keeps the rest: 150 px at 420 px.
do
    local EDGE, TOP, HEIGHT, GAP, CAPS = 10, 7, 22, 8, 12
    local CLOSE_W, OPTIONS_W, AUTO_W = 24, 92, 84
    local GRIP_X, GRIP_W = 8, 22
    local SLOTS = {top = TOP, height = HEIGHT, gap = GAP, caps = CAPS, edge = EDGE, closeWidth = CLOSE_W,
        gripX = GRIP_X, gripWidth = GRIP_W, titleLeft = GRIP_X + GRIP_W + 6,
        options = EDGE + CLOSE_W + GAP, optionsWidth = OPTIONS_W,
        auto = EDGE + CLOSE_W + GAP + OPTIONS_W + GAP, autoWidth = AUTO_W}
    -- The width line 1 keeps for its right-hand controls, gap included.
    SLOTS.reserved = SLOTS.auto + AUTO_W + GAP

    -- The button's own name: the active language's text for the key. Only
    -- M.OptionsText adds the "!" mark, so a resolved label that already
    -- begins with one is not shown; the English base is, and a "!" on the
    -- button keeps meaning a trusted update notice.
    function M.OptionsLabel()
        local L = Nexus.Localization
        local label = L.Text("panel.button.options")
        if label:find("^%s*!") then label = (L.Resolve("panel.button.options")) end
        return label
    end

    function M.OptionsText(notice)
        local label = M.OptionsLabel()
        return notice and ("! " .. label) or label
    end

    -- The line-1 slots (read only; the same table every call).
    function M.HeaderSlots() return SLOTS end

    -- Places the Options button in its slot with a one-line label bounded
    -- to the button less its end caps (LayoutMetrics.OneLineLabel, as for
    -- My Builds). Returns the slots.
    function M.PlaceOptionsButton()
        local menu = frame and frame._menuBtn
        if not menu then return SLOTS end
        menu:ClearAllPoints()
        menu:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -SLOTS.options, -TOP)
        menu:SetSize(OPTIONS_W, HEIGHT)
        menu:Show()
        local label = menu:GetFontString()
        local metrics = Nexus.LayoutMetrics
        if label and metrics and type(metrics.OneLineLabel) == "function" then
            label:SetWidth(OPTIONS_W - CAPS)
            metrics.OneLineLabel(label, nil, HEIGHT)
        end
        return SLOTS
    end
end

-- The compact four-cell destination row remains an internal formatter and
-- diagnostic source. The Play header gives its two actionable facts one row
-- each instead of trying to fit four cells beside a 68px button.
function M.CreateContextHeader(parent)
    local slots = M.HeaderSlots()
    local function Line(y, font)
        local label = parent:CreateFontString(nil, "OVERLAY", font)
        label:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -y)
        label:SetJustifyH("LEFT")
        label:SetSize(280, 20)
        label:SetWordWrap(false)
        local hit = CreateFrame("Frame", nil, parent)
        hit:SetPoint("TOPLEFT", label, "TOPLEFT", 0, 0)
        hit:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 0, 0)
        hit:EnableMouse(true)
        hit:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self._nexusFull or LT("panel.tooltip.context_unavailable"), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        hit:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        return label, hit
    end
    parent._contextTitle, parent._contextTitleHit = Line(8, "GameFontNormal")
    parent._contextBuild, parent._contextBuildHit = Line(32, "GameFontNormal")
    parent._contextWishlist, parent._contextWishlistHit = Line(57, "GameFontNormal")
    parent._contextAutoState = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    -- The Auto control's slot, used while that control is hidden.
    parent._contextAutoState:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -slots.auto, -(slots.top + 2))
    parent._contextAutoState:SetSize(slots.autoWidth, 18)
    parent._contextAutoState:SetJustifyH("RIGHT")
    parent._contextChange = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    parent._contextChange:SetText(LT("panel.button.change_wishlist"))
    parent._contextChange:SetScript("OnClick", function(self)
        M.ShowHub("plan", self)
    end)
    parent._contextChange:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(LT("panel.tooltip.change_wishlist_heading"), 1, 1, 1)
        GameTooltip:AddLine(LT("panel.tooltip.change_wishlist_plan"), .8, .8, .8, true)
        GameTooltip:Show()
    end)
    parent._contextChange:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function M.UpdateContextHeader(model, settled)
    if not (frame and frame._contextTitle) then return false end
    local facts = M.DestinationFacts(model) or {}
    local fields, tooltip = Nexus.UserText.DestinationFields(facts)
    local width = math.max(240, tonumber(frame:GetWidth()) or 420)
    local labelWidth = math.max(100, width - 134)
    -- The title runs from after the grip to the Auto slot (M.HeaderSlots):
    -- 150 px at 420 px, more on a wider panel.
    local slots = M.HeaderSlots()
    local titleWidth = math.max(100, width - slots.reserved - slots.titleLeft)
    -- Put high-priority state before names: truncation at 420px must not
    -- silently turn a Community preview into an apparent assignment or hide
    -- an empty Saved Build's refusal. The complete facts remain on hover.
    local cue = facts.preview and LT("panel.label.cue_preview") or nil
    if facts.empty then
        cue = cue and (cue .. "; " .. LT("panel.label.cue_empty")) or LT("panel.label.cue_empty")
    elseif not cue and (facts.unconfirmed or facts.kind == "unconfirmed") then
        cue = LT("panel.label.cue_unconfirmed")
    elseif not cue and facts.kind == "unknown" then
        cue = LT("panel.label.cue_not_known")
    end
    -- Line 1 is the title and its state cue only (the design's "Nexus"); the
    -- character stays first on the title's hover (tooltip[1]).
    -- Issue #171: a confirmed session pause (M.PauseStatus) is said first.
    local title = (model and model._nexusSessionPaused and LT("panel.label.title_paused") or "Nexus")
        .. (cue and (" [" .. cue .. "]") or "")
    local build = facts.preview and facts.kind == "none" and LT("panel.value.build_none_captured")
        or (facts.slot and fields[2].compact) or fields[2].value
    local wishlist = facts.empty and fields[3].compact or fields[3].value
    local lines = {
        {frame._contextTitle, frame._contextTitleHit, title},
        {frame._contextBuild, frame._contextBuildHit, LF("panel.label.context_build", {build = SafeText(build)})},
        {frame._contextWishlist, frame._contextWishlistHit, LF("panel.label.context_wishlist", {wishlist = SafeText(wishlist)})},
    }
    -- C-03 (as M.UpdateDestinationRow): on a settled render (no layout pass)
    -- whose header words, hovers, widths and Auto state are the ones already
    -- applied, nothing is re-anchored, refitted or set again. A layout pass
    -- always applies the header: it places the My Builds button itself.
    local autoShown = frame._autoBtn:IsShown() and true or false
    local autoState = not autoShown and (model.auto == nil and LT("panel.label.auto_state_unknown")
        or (model.auto and LT("panel.label.auto_state_on") or LT("panel.label.auto_state_off"))) or nil
    local key = table.concat({tostring(width), tostring(titleWidth), tostring(labelWidth),
        lines[1][3], lines[2][3], lines[3][3], tostring(tooltip[1]), tostring(tooltip[2]),
        tostring(tooltip[3]), tostring(tooltip[4]), tostring(autoState)}, "\031")
    if settled and frame._nexusHeaderKey == key then return true end
    frame._nexusHeaderKey = nil
    frame._contextTitle:ClearAllPoints()
    frame._contextTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", slots.titleLeft, -8)
    M.EnsureHeaderGrip()
    for index = 1, #lines do
        local line = lines[index]
        line[1]:SetWidth(index == 1 and titleWidth or labelWidth)
        line[1]:SetText(line[3])
        line[2]._nexusFull = index == 1
            and (tooltip[1] .. "\n" .. tooltip[4]) or tooltip[index]
        if Nexus.LayoutMetrics and Nexus.LayoutMetrics.OneLineLabel then
            Nexus.LayoutMetrics.OneLineLabel(line[1], nil, 20)
        end
    end
    frame._switchBtn:ClearAllPoints()
    frame._switchBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -30)
    frame._switchBtn:SetSize(106, 22)
    frame._contextChange:ClearAllPoints()
    frame._contextChange:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -55)
    frame._contextChange:SetSize(106, 22)
    local switchLabel = frame._switchBtn:GetFontString()
    if switchLabel and Nexus.LayoutMetrics and Nexus.LayoutMetrics.OneLineLabel then
        switchLabel:SetWidth(94)
        Nexus.LayoutMetrics.OneLineLabel(switchLabel, nil, 22)
    end
    M.EnsureHeaderClose()
    local state = frame._contextAutoState
    if autoShown then
        state:Hide()
    else
        state:SetText(autoState)
        state:Show()
    end
    frame._nexusHeaderKey = key
    return true
end

-- M4 (UX-04): the destination this panel's run belongs to, as lines, from the
-- facts the shown model already carries: the verified active Saved Build
-- (progress.activeSlot / activeSlotName), the run's Wishlist and the saved
-- assignment state and note. Pure: it reads only the model it is given and
-- calls no adapter, service or request (UserText.DestinationLines words it).
-- M7: the facts (M.DestinationFacts) are kept apart from their wording so the
-- setup checklist reads the same facts; the lines are unchanged.
function M.DestinationLines(model)
    local text = Nexus.UserText
    if type(model) ~= "table" or not (text and type(text.DestinationLines) == "function") then
        return {}
    end
    return text.DestinationLines(M.DestinationFacts(model))
end

-- The destination facts behind M.DestinationLines (the UserText d table), or
-- nil without a model.
function M.DestinationFacts(model)
    if type(model) ~= "table" then return nil end
    local pr = type(model.progress) == "table" and model.progress or {}
    local assignment = type(model.assignment) == "table" and model.assignment or {}
    local slot = tonumber(pr.activeSlot) or 0
    local state = assignment.state
    -- A Community Build preview names the previewed build in
    -- progress.wishlistName. Then only the actual assignment's name is this
    -- destination's Wishlist (unknown without one), and the preview is said
    -- as one (d.preview, presentation only).
    local preview = pr.isCommunityPreview and true or false
    local d = {wishlist = (not preview and pr.wishlistName) or assignment.name}
    if preview then d.preview = true end
    -- The HUD always shows the logged-in character's run (J3: the destination
    -- names its character): the name Main captured into this model
    -- (model.character), else nil, said as not known. No client read, and no
    -- earlier name stands in.
    if type(model.character) == "string" and model.character ~= "" then
        d.character = model.character
    end
    -- The adapter's own first-run facts (GameAdapter A.Wishlist: its first-run
    -- return and its unavailable first-run mirror), copied by Main into the
    -- HUD model as assignment.note. A missing verified active row is not
    -- evidence of first-run (M4 final review B1).
    local note = type(assignment.note) == "string" and assignment.note or ""
    local unavailableFirstRun = "First-run wishlist data is temporarily unavailable"
    local firstRun = note == "First-run wishlist target"
        or note:sub(1, #unavailableFirstRun) == unavailableFirstRun
    if state == "loading" then
        d.kind = "unknown"
    elseif assignment.emptySlot == true then
        -- The selected numbered Saved Build holds no Echoes (named when the
        -- verified active row is known).
        d.kind, d.empty = "savedBuild", true
        if slot > 0 then d.slot, d.name = slot, pr.activeSlotName end
    elseif slot > 0 then
        d.kind, d.slot, d.name, d.active = "savedBuild", slot, pr.activeSlotName, true
    elseif firstRun then
        d.kind = "firstRun"
    elseif state == "restoring" then
        -- Unknown is said as unknown, not as nothing captured (review NB2).
        d.kind, d.reason = "unknown", "restoring"
    elseif state == "ready" or note:find("^Loadout %d+ ") then
        -- A Saved Build's plan with no verified active row: a kept Saved
        -- Build while a native Wishlist slot is active, or a slot payload
        -- without the verified field. Which Saved Build, and whether it is
        -- active, is not in this model, so neither is claimed (review B1).
        d.kind, d.unconfirmed = "savedBuild", true
    elseif state == "unavailable" or (not preview and pr.wishlistName) then
        -- The model does not say whether this plan is the first-run target
        -- or a Saved Build's: neither is claimed. A Community Build
        -- preview's title names the previewed build, never this
        -- destination's plan, so it alone claims nothing.
        d.kind = "unconfirmed"
    else
        d.kind = "none"
    end
    d.wishlistState = (state == "ready" and "assigned") or (state == "unassigned" and "unassigned")
        or (state == "unavailable" and "unavailable")
        or ((state == "restoring" or state == "loading") and "restoring") or nil
    -- An empty Saved Build holds no Wishlist of its own (assigning to it is
    -- refused); a name beside it would be the first-run Wishlist, so none is
    -- presented as its assignment.
    if d.empty then d.wishlist, d.wishlistState = nil, nil end
    return d
end

-- The Orb fact of the setup status, from OrbRuntime.ReasonView: a passive
-- projection that initializes, reads, observes, pumps and writes nothing.
-- Returns orb, observed. orb: false (an observed owner with no approved run),
-- a new table of validated plain scalars, or nil (unknown). observed: false
-- when the owner was not initialized this session (an unresolved saved
-- receipt is then not ruled out), true when it was, nil when unreadable. A
-- field that is not a plain bounded value of its kind is left out, never
-- converted or guessed.
local function OrbFacts(runtime)
    if type(runtime.ReasonView) ~= "function" then return nil end
    local ok, view = pcall(runtime.ReasonView)
    if not ok or type(view) ~= "table" then return nil end
    if view.observed == false then return nil, false end
    if view.observed ~= true then return nil end
    if view.run == false then return false, true end
    if view.run ~= true then return nil end
    local orb = {}
    local state = view.state
    if type(state) == "string" and #state <= 32 and state:match("^[%u_]+$") then orb.state = state end
    for _, key in ipairs({"running", "pending", "restored"}) do
        if type(view[key]) == "boolean" then orb[key] = view[key] end
    end
    local reason, operation = view.reason, view.operation
    if type(reason) == "string" and reason ~= "" and #reason <= 4096 then orb.reason = reason end
    if type(operation) == "string" and operation ~= "" and #operation <= 512 then orb.operation = operation end
    return orb, true
end

-- View observation of the character Main's existing capture validated, for
-- the destination strip. event: "PLAYER_LEAVING_WORLD" / "PLAYER_LOGOUT"
-- clear and block the cache; "PLAYER_ENTERING_WORLD" clears it and admits a
-- later capture; "capture" stores that capture (nil included) only inside an
-- entered world. Memory only: no read, no model, Store or assignment change.
function M.ObserveDestinationCharacter(character, event)
    if event == "PLAYER_LEAVING_WORLD" or event == "PLAYER_LOGOUT"
        or event == "PLAYER_ENTERING_WORLD" then
        -- Each existing world invalidation starts a new view session
        -- revision: the private count is first moved past any larger valid
        -- public value, so that value is never reissued, then advanced and
        -- published. No other read; a capture leaves it unchanged.
        local published = M.destinationSessionRevision
        if type(published) == "number" and published > destinationSessionCounter
            and published < 4503599627370496
            and published == math.floor(published) then
            destinationSessionCounter = published
        end
        destinationSessionCounter = destinationSessionCounter + 1
        M.destinationSessionRevision = destinationSessionCounter
    end
    if event == "PLAYER_LEAVING_WORLD" then
        renderState.destinationWorld, renderState.destinationCharacter = "leaving", nil
    elseif event == "PLAYER_LOGOUT" then
        renderState.destinationWorld, renderState.destinationCharacter = "loggedOut", nil
    elseif event == "PLAYER_ENTERING_WORLD" then
        renderState.destinationWorld, renderState.destinationCharacter = "entered", nil
    elseif event == "capture" and renderState.destinationWorld == "entered" then
        renderState.destinationCharacter =
            (type(character) == "string" and character ~= "") and character or nil
    end
end

-- The raw private destination world-session count, read only: one value,
-- 0 before the first publication (while M.destinationSessionRevision is
-- nil), else the value last published to that scalar. It validates,
-- captures, writes and advances nothing and reads nothing else. Views hold
-- an observation only while the public scalar equals this count and their
-- held stamp, so a public value that differs, such as a restored earlier
-- one, is rejected; equality cannot detect a value written equal to it.
-- Memory only; presentation only.
function M.DestinationSessionCount()
    return destinationSessionCounter
end

-- The latest validated capture in the current world session, else nil.
-- Pure: it initializes, reads and updates nothing else, and no earlier
-- model or saved name stands in.
function M.CachedDestinationCharacter()
    local character = renderState.destinationCharacter
    if renderState.destinationWorld == "entered"
        and type(character) == "string" and character ~= "" then
        return character
    end
    return nil
end

-- M7 (UX setup checklist and status): the current facts the checklist words
-- (UserText.SetupChecklist / StatusLines). Read-only: start-up status, the
-- last committed HUD model (its destination, Wishlist, Auto selection and
-- hold), the saved Sync mode and the passive Orb reason view (OrbFacts). Each
-- fact that cannot be read stays nil (unknown), apart from false or an empty
-- value. It never reads whether the Welcome was seen or dismissed, and it
-- gates, requests, sends and writes nothing; its Orb fact starts no Orb work.
function M.SetupFacts()
    local f = {}
    local okReady, ready = false, nil
    if type(Nexus.StartupStatus) == "function" then okReady, ready = pcall(Nexus.StartupStatus) end
    if okReady and type(ready) == "table" then
        f.startup = ready.coreReady == true and "ready" or "loading"
    end
    local model = type(M._lastModel) == "table" and M._lastModel or nil
    if f.startup == "ready" and model then
        f.destination = M.DestinationFacts(model)
        f.destinationLines = M.DestinationLines(model)
        if type(model.auto) == "boolean" then f.auto = model.auto end
        f.paused = type(model.paused) == "string" and model.paused ~= "" and model.paused or nil
        local okNote, note = pcall(M.AutoNoteFor, model)
        f.autoNote = okNote and type(note) == "string" and note ~= "" and note or nil
    end
    local policy = Nexus.SyncModePolicy
    if policy and type(policy.Mode) == "function" then
        local okMode, mode = pcall(policy.Mode)
        if okMode and type(mode) == "string" then f.syncMode = mode end
        local okChoice, choice = false, nil
        if type(policy.Choice) == "function" then okChoice, choice = pcall(policy.Choice) end
        if okChoice and type(choice) == "table" then f.syncExplicit = choice.explicit ~= nil end
    end
    local runtime = Nexus.OrbRuntime
    if f.startup == "ready" and runtime then
        local okOrb, orb, observed = pcall(OrbFacts, runtime)
        if okOrb then f.orb, f.orbObserved = orb, observed end
    end
    return f
end

-- Read-only. Opening it marks the shown target as seen, so its chat notice is
-- not repeated. It changes nothing else.
function M.ShowUpdateStatus()
    local updates = Nexus.Updates
    if not (updates and updates.Status) then return false end
    local status = updates.Status()
    -- The dialog's own words resolve at show time; "%s" (the Updates
    -- detail) and the blank line stay code-owned, and a "%" in a
    -- translation is kept literal for the dialog's format pass.
    local dialog = StaticPopupDialogs["NEXUS_UPDATE_RELEASES"]
    if type(dialog) == "table" then
        dialog.text = "%s\n\n" .. (LT("panel.popup.releases_copy_address"):gsub("%%", "%%%%"))
        dialog.button1 = LT("panel.popup.close")
    end
    StaticPopup_Show("NEXUS_UPDATE_RELEASES", status.detail, status.url)
    if status.candidate and updates.Dismiss then updates.Dismiss() end
    -- Seeing the unverified hint is enough: it is not announced again this
    -- session. This dismissal is session state and writes no saved data.
    if status.hint and updates.DismissHint then updates.DismissHint() end
    return true, status
end

local function DefensiveCopy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local out = {}
    seen[value] = out
    for key, child in pairs(value) do
        out[DefensiveCopy(key, seen)] = DefensiveCopy(child, seen)
    end
    return out
end

local function Signature(value, seen)
    local kind = type(value)
    if kind ~= "table" then
        local text = SafeText(value)
        return kind .. ":" .. tostring(#text) .. ":" .. text
    end
    seen = seen or { _nextId=0 }
    if seen[value] then return "cycle:" .. tostring(seen[value]) end
    seen._nextId = seen._nextId + 1
    seen[value] = seen._nextId
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(left, right)
        return type(left) .. ":" .. tostring(left)
            < type(right) .. ":" .. tostring(right)
    end)
    local out = {"{"}
    for _, key in ipairs(keys) do
        out[#out + 1] = Signature(key, seen)
        out[#out + 1] = "="
        out[#out + 1] = Signature(value[key], seen)
        out[#out + 1] = ";"
    end
    out[#out + 1] = "}"
    return table.concat(out)
end

-- The difficulty card's shown values (C-02): its difficulty word, Soul Ash,
-- multiplier and Intensity, and the Intensity level its hover states. They
-- change no geometry: the layout signature keeps only whether each is there
-- (the card's visibility and the bar's), and a change of the values alone is
-- applied without a layout pass (M.RefreshServerStatusValues). Every other
-- field, an unknown one included, stays in the layout signature.
M.SERVER_STATUS_VALUES = {tier = "truthy", mode = "truthy", ash = "truthy", gain = "truthy",
    intensity = "present", intensityLevel = "present"}
function M.ServerStatusLayout(ss)
    if type(ss) ~= "table" then return ss end
    local out = {}
    for key, value in pairs(ss) do
        local kind = M.SERVER_STATUS_VALUES[key]
        if kind == "truthy" then out[key] = value and true or false
        elseif kind == "present" then out[key] = true
        else out[key] = value end
    end
    return out
end

-- The card's words and hover facts from a summary; false (and nothing set)
-- when the summary shows no card. Geometry, the bar's scale and ticks and
-- the card's visibility stay with the layout pass.
function M.RenderServerStatusValues(ss, complete)
    worldStatusBox._summary = DefensiveCopy(ss)
    if not (ss and (ss.tier or ss.mode or ss.ash or ss.gain or ss.intensity ~= nil)) then return false end
    local difficulty = ss.tier or ss.mode or LT("panel.label.difficulty_fallback")
    -- Parse and format the ash number for compact display
    local function FmtAsh(raw)
        if not raw then return "—" end
        local stripped = tostring(raw):gsub(",", "")
        local n = tonumber(stripped)
        if not n then return tostring(raw) end
        if n >= 1000000 then
            local m = n / 1000000
            local ms = string.format("%.1f", m); return (ms:match("%.0$") and ms:gsub("%.0$","") or ms) .. "M"
        elseif n >= 1000 then
            local k = n / 1000
            local ks = string.format("%.1f", k); return (ks:match("%.0$") and ks:gsub("%.0$","") or ks) .. "k"
        end
        return tostring(math.floor(n))
    end
    local ashFmt = FmtAsh(ss.ash)
    -- Only the scanner's validated distinction is used: a Hardcore tier
    -- (ServerStatus tier HC1-HC5) keeps the original red; a known Normal
    -- (mode "Normal", no tier) is neutral, as the game's own widget shows
    -- it; an unknown mode keeps the card's former red caption.
    worldStatusText:SetText(((ss.tier == nil and ss.mode == "Normal")
        and "|cffd9d9d9" or "|cffff6b5f") .. difficulty .. "|r")
    worldStatusAsh:SetText((complete and ("|cff8ec9d6" .. LT("panel.label.soul_ash") .. "  |r")
        or ("|cffb8b8b8" .. LT("panel.label.ash_short") .. " |r")) .. "|cffffffff" .. ashFmt .. "|r")
    worldStatusGain:SetText(ss.gain and ("|cff35e635" .. ss.gain .. "|r") or "")
    return true
end

-- A settled render whose card values changed (C-02): the words, the hover
-- facts and the bar's value, on the scale the last layout pass set.
function M.RefreshServerStatusValues(model)
    local ss = type(model.serverStatus) == "table" and model.serverStatus or nil
    local pr = type(model.progress) == "table" and model.progress or {}
    local total, owned = tonumber(pr.total) or 0, tonumber(pr.owned) or 0
    local complete = total > 0 and owned >= total
        and #(type(pr.toLock) == "table" and pr.toLock or {}) == 0
    if not M.RenderServerStatusValues(ss, complete) then return false end
    local scale = worldStatusBox._intensityScale
    if scale and ss.intensity ~= nil then
        worldStatusBox.intensityBar:SetValue(
            math.max(0, math.min(scale.max, tonumber(ss.intensity) or 0)))
    end
    return true
end

local function ModelSignatures(model)
    local source = type(model.progress) == "table" and model.progress or {}
    -- The destination descriptor, projected once for this candidate (pure,
    -- from the model's own fields). Its signature covers everything the
    -- destination row shows (a renamed slot, the current character, the
    -- actual assignment, Preview); ApplyModel words this same table.
    local destination = M.DestinationFacts(model)
    local layoutKey = "legacy"
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.RuntimeKey then
        local ok, key = pcall(Nexus.LayoutMetrics.RuntimeKey,"panel",272,0)
        if ok then layoutKey = key end
    end
    local progress = {
        wishlistName=source.wishlistName,
        owned=source.owned,
        total=source.total,
        missing=source.missing,
        shed=source.shed,
        unknownTomes=source.unknownTomes,
        toLock=source.toLock,
        activeSlot=source.activeSlot,
        isCommunityPreview=source.isCommunityPreview,
    }
    return {
        layout = Signature({
            progress=progress,
            cards=model.cards,
            recommendation=model.recommendation,
            level=model.level,
            serverStatus=M.ServerStatusLayout(model.serverStatus),
            showPerformance=showPerformance,
            layoutRevision=layoutKey,
            assignment=model.assignment,
            orbGuidance=model.orbGuidance,
            paused=model.paused,
            sessionPaused=model._nexusSessionPaused,
            -- The heading's wait word (Auto waiting / Auto rechecking) can
            -- change while the pause text stays the same; nil otherwise.
            heading=model.auto and model.paused and type(model.effective) == "table"
                and (model.effective.state == "waiting"
                    or model.effective.state == "rechecking")
                and model.effective.state or nil,
            -- With roll content shown, the Auto OFF heading and the card
            -- marker follow the selection; between boards it changes nothing.
            autoOff=model.auto == false and ((type(model.cards) == "table" and #model.cards > 0)
                or SafeText(model.recommendation) ~= "") or nil,
            -- The Auto scope row (M.RenderAutoScope) follows a selected Auto
            -- with roll content; a reserved gap is in the roll suffix.
            autoOn=model.auto == true and ((type(model.cards) == "table" and #model.cards > 0)
                or SafeText(model.recommendation) ~= "" or type(model.orbGuidance) == "table"
                or SafeText(model.autoNote) ~= "") or nil,
            -- The compact charges line follows the charge facts the model carries.
            charges=model.charges, chargeLine=model._nexusChargeLine,
            -- The inline Auto line (M.AutoNoteFor) is roll content too.
            autoNote=model.autoNote,
            -- The Play summary's rows: Details open (memory only) and whether
            -- an Orb run line is shown; the line's words refresh on every
            -- render (M.RefreshOrbLine).
            playDetails=M._playDetails == true or nil,
            orbLine=type(model._nexusOrbLine) == "table" or nil,
            -- The destination row's whole descriptor, Preview included.
            destination=destination,
            callboard=Nexus.CallboardStatus and Nexus.CallboardStatus.GetSummary
                and Nexus.CallboardStatus.GetSummary() or nil,
        }),
        performance = Signature({
            performance=type(model.progress) == "table" and model.progress.performance or nil,
            bestDps=model.bestDps,
        }),
        notice = Signature(model.updateNotice),
        serverValues = Signature(model.serverStatus),
        status = Signature(model.status),
        auto = Signature(model.auto),
        destination = destination,
    }
end

-- The destination row cells' effective font path, size and flags, as a
-- layout signature part ("none" before the row exists). A same-size
-- replacement face is not in LayoutMetrics.RuntimeKey. Reads fonts only.
function M.DestinationRowFonts()
    local row = frame and frame._destinationRow
    local cells = type(row) == "table" and row.cells or nil
    if type(cells) ~= "table" then return "none" end
    local parts = {}
    for index = 1, #cells do
        local path, size, flags = cells[index]:GetFont()
        parts[#parts + 1] = Signature(path) .. Signature(size) .. Signature(flags)
    end
    return table.concat(parts, "/")
end

-- Keep the roll block's space through an ordinary gap between Echo choices.
-- Between boards the runtime renders no cards and no recommendation; without
-- this the block collapsed and the panel resized (moving the title and the
-- footer buttons) until the next board. The block is reserved only while
-- Auto is ON with an assigned, unfinished build, and only when the last
-- committed render showed it in the same context (Wishlist, active slot,
-- preview, layout metrics). The reserved block shows no old card or
-- recommendation: its content is cleared. Auto OFF, a finished build, no
-- build or a context change release it.
local function RollPresentation(model)
    local pr = type(model.progress) == "table" and model.progress or {}
    local name = pr.wishlistName
    local total = tonumber(pr.total) or 0
    local owned = tonumber(pr.owned) or 0
    local complete = total > 0 and owned >= total
        and #(type(pr.toLock) == "table" and pr.toLock or {}) == 0
    local noBuild = total <= 0 or not name
    local cards = type(model.cards) == "table" and model.cards or {}
    local guide = type(model.orbGuidance) == "table" and model.orbGuidance or nil
    local guideText = (guide and total > 0 and name) and SafeText(guide.text) or ""
    local hasContent = #cards > 0 or SafeText(model.recommendation) ~= ""
        or guideText ~= ""
    local layoutKey = "legacy"
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.RuntimeKey then
        local ok, key = pcall(Nexus.LayoutMetrics.RuntimeKey,"panel",272,0)
        if ok then layoutKey = tostring(key) end
    end
    local context = table.concat({tostring(name), tostring(pr.activeSlot),
        pr.isCommunityPreview and "preview" or "own", layoutKey}, "|")
    local continuing = model.auto == true and not noBuild and not complete
    local held = continuing and renderState.roll or nil
    if held and held.context ~= context then held = nil end
    local reserved = not hasContent and held ~= nil
    local cardRows = #cards > 0 or (held ~= nil and held.cards == true)
    return {
        reserved=reserved,cardRows=cardRows,
        -- What a successful commit of this render leaves for the next one.
        nextRoll=continuing and (hasContent or reserved)
            and {context=context,cards=cardRows,reserved=reserved} or nil,
    }
end

local function ShortName(v, maxChars)
    local s = SafeText(v)
    maxChars = maxChars or 30
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.Truncate then
        s = Nexus.LayoutMetrics.Truncate(s, maxChars)
    elseif #s > maxChars then
        s = s:sub(1, math.max(1, maxChars - 3)) .. "..."
    end
    local displayText = Nexus and Nexus.Identity
        and Nexus.Identity.DisplaySafeText
    return displayText and displayText(s, 1024, false) or ""
end

-- Auto button labels (plain text; AutoLabel adds the state colour) and their
-- fit. This code sets no width limit on the label, so `inset` is a chosen
-- per-side margin kept clear of the button's end caps (not a template value).
-- AUTO_LABEL.Fit (below) measures the widest label with the button's own font
-- object and reduces only that object's size when it does not fit, never
-- below minSize. The tooltip names the full control.
-- on/off/unknown are the labels' English base (the reviewed English of
-- AUTO_LABEL.keys in data/LocalizationEnglish.lua); what is shown and
-- measured is each key's text in the active language (AutoLabel, Fit).
local AUTO_LABEL = { on = "Auto ON", off = "Auto OFF", unknown = "Auto --",
    keys = { on = "panel.button.auto_on", off = "panel.button.auto_off", unknown = "panel.button.auto_unknown" },
    inset = 6, minSize = 9, font = "NexusAutoButtonFont" }

-- Auto OFF releases a roll-block reservation at once. The runtime does not
-- render for a toggle, so the last committed model is rendered again with
-- the new selection (the ordinary render transaction). Nothing else changes.
local function ReleaseRollOnAutoOff(auto)
    local roll = renderState.roll
    if auto or not (roll and roll.reserved) or type(M._lastModel) ~= "table" then
        return
    end
    local model = DefensiveCopy(M._lastModel)
    local rawText = renderState.rawText or {}
    model.status, model.recommendation = rawText.status, rawText.recommendation
    model.auto = false
    -- A failed render stays a failed render (hidden, counted, retried by the
    -- next ordinary refresh); it is recorded, not raised into the toggle.
    local ok, why = pcall(M.Render, model)
    if not ok and Nexus.Errors and type(Nexus.Errors.Record) == "function" then
        pcall(Nexus.Errors.Record, "Panel.ReleaseRollOnAutoOff", why)
    end
end

-- The words carry the state (ON / OFF / --); colour only adds to them. OFF
-- is a neutral, readable light grey (design/current "Nexus Main Panel -
-- Compact Redesign": Auto OFF is the ordinary, recommendations-only state,
-- not an alarm), ON keeps its green.
local function AutoLabel(auto)
    if auto == nil then return LT("panel.button.auto_unknown") end
    if auto then return "|cff2ee62e" .. LT("panel.button.auto_on") .. "|r" end
    return "|cffd9d9d9" .. LT("panel.button.auto_off") .. "|r"
end

local function FmtDps(dps)
    dps = tonumber(dps)
    if not dps or dps <= 0 then return "—" end
    if dps >= 1000000 then return string.format("%.2fM", dps / 1000000) end
    if dps >= 1000 then return string.format("%dk", math.floor(dps / 1000)) end
    return tostring(math.floor(dps))
end

local function HitFrame(parent, fs)
    local hit = CreateFrame("Frame", nil, parent)
    hit:SetAllPoints(fs)
    hit:EnableMouse(true)
    return hit
end

-- Split out of EnsureFrame() to keep that giant widget-builder function
-- under WoW 3.3.5's 60-upvalue-per-function limit. Stores the widgets as
-- fields on the frame itself (f.toLockLabel etc.) instead of new module
-- locals, so EnsureFrame only pays one upvalue (this function reference)
-- to wire them in, and M.Render/ShowCoreProgress read them off `frame`
-- (already a heavily-used upvalue there) instead of adding their own.
local function CreateToLockWidgets(f)
    local layout = Nexus.LayoutMetrics
    f.toLockLabel = f:CreateFontString(nil, "OVERLAY",
        layout and layout.FontObject("small") or "GameFontDisableSmall")
    f.toLockLabel:SetText((Nexus.Localization.Text("panel.heading.locked_targets")))
    f.toLockLabel:SetTextColor(0.7, 0.45, 1)
    f.toLockText = f:CreateFontString(nil, "OVERLAY",
        layout and layout.FontObject("small") or "GameFontHighlightSmall")
    f.toLockText:SetJustifyH("LEFT")
    f.toLockText:SetJustifyV("TOP")
    f.toLockText:SetTextColor(0.72, 0.45, 1)
    f.toLockHit = HitFrame(f, f.toLockText)
    f.toLockHit:SetScript("OnEnter", function(self)
        if #toLockNamesCache == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local metrics, heading = Nexus.LayoutMetrics, self:GetParent().toLockLabel
        if metrics and metrics.Shortened and heading and metrics.Shortened(heading) then
            GameTooltip:AddLine(tostring(heading:GetText() or ""), 1, 1, 1, true)
        end
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.locked_remaining"), 1, 1, 1)
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.locked_plan"), 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.locked_acquire"), 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.locked_placement"), 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.locked_not_freeze"), 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.locked_acquire_list"), 0.85, 0.6, 1)
        for i, name in ipairs(toLockNamesCache) do
            GameTooltip:AddLine("  • " .. name, 0.85, 0.7, 1)
            if i >= 25 then
                if #toLockNamesCache > 25 then
                    GameTooltip:AddLine("  " .. LF("panel.tooltip.more_count", {count = LC(#toLockNamesCache - 25)}), 0.6, 0.6, 0.6)
                end
                break
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.open_wishlist_editor"), 0.4, 0.8, 1)
        GameTooltip:Show()
    end)
    f.toLockHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    f.toLockHit:SetScript("OnMouseUp", function() if Nexus.WishlistEditor then Nexus.WishlistEditor.Show() end end)
    -- Issue #143: the heading keeps one line in its fixed layout box
    -- (LayoutMetrics.OneLineLabel, with no owner); ApplyPanelLayout still owns
    -- its box. While the client shortens it, this row's own OnEnter above adds
    -- the complete heading first, right after its single SetOwner, and its own
    -- lines follow unchanged. The OneLineLabel owner hook is not attached: it
    -- would run after that OnEnter and take the tooltip again with its own
    -- SetOwner.
    if layout and type(layout.OneLineLabel) == "function" then
        layout.OneLineLabel(f.toLockLabel, nil, 11)
    end
end

local function SetVisible(widget, shown)
    if not widget then return end
    if shown then widget:Show() else widget:Hide() end
end

local function SetPoint(widget, point, relative, relativePoint, x, y)
    widget:ClearAllPoints()
    widget:SetPoint(point, relative or frame, relativePoint or point, x or 0, y or 0)
end

local function SetOwnedFont(widget, font)
    if widget and type(widget.SetFontObject) == "function" then
        pcall(widget.SetFontObject, widget, font)
    end
end

local function SetOwnedButtonFont(widget, font)
    if not widget then return end
    if type(widget.SetNormalFontObject) == "function" then
        pcall(widget.SetNormalFontObject, widget, font)
    end
    if type(widget.SetHighlightFontObject) == "function" then
        pcall(widget.SetHighlightFontObject, widget, font)
    end
    if type(widget.SetDisabledFontObject) == "function" then
        pcall(widget.SetDisabledFontObject, widget, font)
    end
end

-- Fit of the Auto labels to this button (see AUTO_LABEL). The button uses its
-- own font object, a copy of the owned normal font: the shared objects are
-- never changed. Runs from the one-shot font pass and the footer layout, not
-- per frame; the result is cached until the base font or the button width
-- changes. Returns { width, budget, fits, size, baseSize, adjustable }.
function AUTO_LABEL.Fit(force)
    if not autoBtn then return nil end
    local layout = Nexus.LayoutMetrics
    local base = layout and _G[layout.FontObject("normal")]
    local path, size, flags
    if base and type(base.GetFont) == "function" then
        local ok, p, s, f = pcall(base.GetFont, base)
        if ok then path, size, flags = p, tonumber(s), f end
    end
    local width = tonumber(autoBtn:GetWidth()) or 72
    local labels = { LT(AUTO_LABEL.keys.on), LT(AUTO_LABEL.keys.off), LT(AUTO_LABEL.keys.unknown) }
    local key = tostring(path) .. "|" .. tostring(size) .. "|" .. tostring(width)
        .. "|" .. table.concat(labels, "|")
    if not force and autoBtn._nexusFit and autoBtn._nexusFitKey == key then
        return autoBtn._nexusFit
    end
    local font = _G[AUTO_LABEL.font]
    if not font and base and path and type(CreateFont) == "function" then
        local ok, created = pcall(CreateFont, AUTO_LABEL.font)
        if ok and created then
            font = created
            -- Colour and shadow come from the owned normal font.
            if type(font.SetFontObject) == "function" then
                pcall(font.SetFontObject, font, base)
            end
        end
    end
    -- A font string needs a font before SetText; with neither font there is
    -- nothing to measure, and the button keeps the owned normal font.
    if not (font or base) then return nil end
    local probe = autoBtn._nexusFitProbe
    if not probe then
        probe = autoBtn:CreateFontString(nil, "OVERLAY")
        if not probe then return nil end
        probe:Hide()
        autoBtn._nexusFitProbe = probe
    end
    local budget = width - 2 * AUTO_LABEL.inset
    local fitSize, widest = size, 0
    for _ = 1, 8 do
        if font and path and fitSize and type(font.SetFont) == "function" then
            pcall(font.SetFont, font, path, fitSize, flags or "")
        end
        if type(probe.SetFontObject) == "function" then
            pcall(probe.SetFontObject, probe, font or base)
        end
        widest = 0
        for _, text in ipairs(labels) do
            probe:SetText(text)
            widest = math.max(widest, tonumber(probe:GetStringWidth()) or 0)
        end
        if widest <= budget or not (font and path and fitSize)
            or fitSize <= AUTO_LABEL.minSize then break end
        fitSize = math.max(AUTO_LABEL.minSize,
            math.floor(fitSize * budget / widest))
    end
    if font then SetOwnedButtonFont(autoBtn, font) end
    autoBtn._nexusFitKey = key
    autoBtn._nexusFit = { width = widest, budget = budget, fits = widest <= budget,
        size = fitSize, baseSize = size, adjustable = font ~= nil }
    return autoBtn._nexusFit
end

-- Only the new compact navigation label needs to share the existing Orb row.
-- Cache its private font fit by base font, label and width; shared fonts and
-- the Open Orbs control are unchanged. No measurement on an unchanged render.
function M.FitOrbMiniButton(button)
    local layout = Nexus.LayoutMetrics
    local base = layout and _G[layout.FontObject("small")]
    if not (button and base and type(base.GetFont) == "function") then return end
    local ok, path, size, flags = pcall(base.GetFont, base)
    size = ok and tonumber(size) or nil
    if not (path and size) then return end
    local budget = button:GetWidth() - 20
    local label = button:GetText() or ""
    local key = table.concat({path,tostring(size),flags or "",label,tostring(budget)}, "|")
    if button._nexusMiniFitKey == key then return button._nexusMiniFit end
    local font = button._nexusMiniFont
    if not font and type(CreateFont) == "function" then
        local made, value = pcall(CreateFont, "NexusHudOrbMiniFont")
        if made and value then font = value; button._nexusMiniFont = font end
    end
    if not font then return end
    local probe = button._nexusMiniProbe
    if not probe then
        probe = button:CreateFontString(nil, "OVERLAY")
        probe:Hide(); button._nexusMiniProbe = probe
    end
    local fitSize, measured = size, 0
    for _ = 1, 8 do
        pcall(font.SetFont, font, path, fitSize, flags or "")
        probe:SetFontObject(font); probe:SetText(label)
        measured = tonumber(probe:GetStringWidth()) or 0
        if measured <= budget or fitSize <= 8 then break end
        fitSize = math.max(8, math.floor(fitSize * budget / measured))
    end
    SetOwnedButtonFont(button, font)
    button._nexusMiniFitKey = key
    button._nexusMiniFit = {width=measured,budget=budget,size=fitSize,fits=measured<=budget}
    return button._nexusMiniFit
end

function M.ApplyOwnedFonts()
    local layout = Nexus.LayoutMetrics
    if not (layout and frame) then return false end
    local small = layout.FontObject("small")
    local normal = layout.FontObject("normal")
    local large = layout.FontObject("large")
    if not frame._nexusOwnedFonts then
        frame._nexusOwnedFonts = true
        for _, widget in ipairs({
            statusText,recText,progressLabel,needLabel,needText,tomesLabel,
            tomesValue,shedLabel,shedText,performanceLabel,setLabelText,
            dummyLabel,dummyGlobal,lkLabel,lkPersonalLabel,lkGlobal,
            completeSubtext,setupHint,bestDpsText,versionText,
            worldStatusGain,worldStatusBox and worldStatusBox.intensityText,
        }) do SetOwnedFont(widget, small) end
        for _, widget in ipairs(cardTexts) do SetOwnedFont(widget, small) end
        for _, widget in ipairs({
            buildHeaderText,worldStatusText,worldStatusAsh,progressValue,
            dummyValue,dummyGlobalValue,lkValue,lkGlobalValue,completeBadge,
            frame._contextTitle,frame._contextBuild,frame._contextWishlist,
        }) do SetOwnedFont(widget, normal) end
        SetOwnedFont(frame._contextAutoState, small)
        SetOwnedFont(setupText, large)
        for _, widget in ipairs({
            switchBtn,setupGetStartedBtn,setupImportBtn,autoBtn,planBtn,
            exploreBtn,menuBtn,frame._orbsHubBtn,frame._contextChange,
        }) do SetOwnedButtonFont(widget, normal) end
        SetOwnedButtonFont(frame._orbsBtn, small)
        SetOwnedButtonFont(frame._orbMiniBtn, small)
        -- The Auto button then takes its own fitted font (AUTO_LABEL.Fit);
        -- if none can be made it keeps the owned normal font above.
        AUTO_LABEL.Fit(true)
    end
    if frame.toLockLabel and not frame.toLockLabel._nexusOwnedFont then
        SetOwnedFont(frame.toLockLabel, small)
        SetOwnedFont(frame.toLockText, small)
        frame.toLockLabel._nexusOwnedFont = true
    end
    return true
end

-- C-03: the scripts are bound once; each performance render only replaces
-- the facts the hover reads (widget._nexusDpsTip).
local function AddDpsTooltip(widget, title, personal, global)
    widget._nexusDpsTip = {title = title, personal = personal, global = global}
    if widget._nexusDpsBound then return end
    widget._nexusDpsBound = true
    widget:SetScript("OnEnter", function(self)
        local tip = self._nexusDpsTip or {}
        local title, personal, global = tip.title, tip.personal, tip.global
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(title, 1, 1, 1)
        if personal then
            GameTooltip:AddLine(LF("panel.tooltip.dps_your_best", {dps = FmtDps(personal.dps)}), 0.35, 1, 0.45)
            if personal.duration then GameTooltip:AddLine(LF("panel.tooltip.dps_duration", {seconds = tostring(personal.duration)}), 0.75, 0.75, 0.75) end
        else
            GameTooltip:AddLine(LT("panel.tooltip.dps_no_personal"), 0.65, 0.65, 0.65, true)
        end
        local text = Nexus.UserText
        if global then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(LF("panel.tooltip.dps_best_shared", {dps = FmtDps(global.dps)}), 1, 0.82, 0)
            local player = global.displayPlayer
                or ShortName(global.player or LT("panel.value.unknown_player"), 80)
            GameTooltip:AddLine(LF("panel.tooltip.dps_held_by", {player = SafeText(player)}), 0.8, 0.8, 0.8)
            -- M4 (UX-14): only the facts the record carries (duration,
            -- level, date) and its own owner flag; unknown stays unsaid.
            local parts = text and text.RecordDetailParts and text.RecordDetailParts(global) or {}
            if #parts > 0 then GameTooltip:AddLine(table.concat(parts, " - "), 0.75, 0.75, 0.75, true) end
            local ownerLine = text and text.OwnerLine and text.OwnerLine(global)
            if ownerLine then GameTooltip:AddLine(ownerLine, 0.75, 0.75, 0.75) end
        else
            GameTooltip:AddLine(LT("panel.tooltip.dps_no_shared"), 0.65, 0.65, 0.65, true)
        end
        GameTooltip:AddLine(" ")
        if text and text.RECORD_SCOPE then GameTooltip:AddLine(text.RECORD_SCOPE, 0.45, 0.75, 1, true) end
        GameTooltip:AddLine(LT("panel.tooltip.dps_exact_match"), 0.45, 0.75, 1, true)
        GameTooltip:Show()
    end)
    widget:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function CloseOtherNexusWindows(exceptName)
    local names = {
        "NexusCommunityBuildsFrame", "NexusLeaderboardFrame", "NexusEditorFrame",
        "NexusLogViewer", "NexusQuickStart", "NexusChangelogPopup", "NexusSharedStartupFrame",
        "ProjectEbonholdEchoJournal",
    }
    for i = 1, #names do
        local f = _G[names[i]]
        if names[i] ~= exceptName and f and f.Hide then pcall(f.Hide, f) end
    end
    if _G.DropDownList1 and _G.DropDownList1.Hide then pcall(_G.DropDownList1.Hide, _G.DropDownList1) end
    if _G.DropDownList2 and _G.DropDownList2.Hide then pcall(_G.DropDownList2.Hide, _G.DropDownList2) end
end

-- The windows that hold the HUD's menu suppression: the attached ones
-- (AttachMenuFrame), whose hide retries the restore. QuickStart is not
-- attached and never hides the HUD, so it does not hold it hidden either:
-- its hide retries nothing, and a restore it blocked would never come.
local function AnyNexusMenuShown()
    local names = {
        "NexusCommunityBuildsFrame", "NexusLeaderboardFrame", "NexusEditorFrame",
        "NexusLogViewer", "NexusChangelogPopup", "NexusSharedStartupFrame",
    }
    for i = 1, #names do
        local f = _G[names[i]]
        if f and f.IsShown and f:IsShown() then return true end
    end
    return false
end

-- Issue #164: Hide Nexus Panel is the player's saved choice, kept with the
-- panel's other presentation keys (PANEL_SAVED_KEYS, M.SavedLayoutRoot, so a
-- read-only saved root keeps it for this session only). `panelHidden` is true
-- only while the player has hidden the panel and absent otherwise: a profile
-- that never hid it carries no new key, and an older build ignores the key
-- and shows the panel. It is read once per saved root -- never at file load,
-- because the client replaces NexusDB when the saved data loads -- and
-- written only by the player's own hide or show (M.Hide, M.Show, M.Toggle).
-- It is a display choice: no Auto or gameplay setting is read or changed.
local wantedSource = nil
local function LoadWantedVisibility()
    if type(NexusDB) ~= "table" or wantedSource == NexusDB then return end
    wantedSource = NexusDB
    panelWantedVisible = M.SavedLayoutRoot().panelHidden ~= true
end

local function SetWantedVisibility(wanted)
    panelWantedVisible = wanted and true or false
    local saved = M.SavedLayoutRoot()
    if panelWantedVisible then
        if saved.panelHidden ~= nil then saved.panelHidden = nil end
    elseif saved.panelHidden ~= true then
        saved.panelHidden = true
    end
    wantedSource = NexusDB
end

-- The stock Difficulty / Soul Ash owner stands its widget aside only for a
-- panel that can display AND that the player wants (M.VisibilityFacts). Tell
-- it at once when the player's choice changes, so the game's own widget comes
-- back with the hide instead of on its next one-second scan. Protected:
-- another addon can replace that global.
local function NotifyStockHud()
    pcall(function()
        local status = Nexus.ServerStatus
        if type(status) == "table" and type(status.PanelVisibilityChanged) == "function" then
            status.PanelVisibilityChanged()
        end
    end)
end

-- A show the player asks for re-checks the menu suppression against the
-- windows that really hold it, so a suppression whose window never opened
-- cannot keep the panel hidden behind that request. A window whose state
-- cannot be read keeps the suppression.
local function ReleaseStaleMenuSuppression()
    if not menuSuppressed or menuTransition or AnyNexusMenuShown() then return end
    for menuFrame in pairs(attachedMenuFrames) do
        local ok, shown = pcall(function() return menuFrame:IsShown() end)
        if not ok or shown then return end
    end
    menuSuppressed = false
end

local function ApplyWantedVisibility()
    if not frame then return false end
    LoadWantedVisibility()
    if not frame._nexusCallboardCoverage then
        frame._nexusCallboardCoverage = true
        local function publish()
            local status = Nexus.CallboardStatus
            if status and type(status.PublishCoverage) == "function" then
                status.PublishCoverage()
            end
        end
        frame:HookScript("OnShow", publish)
        frame:HookScript("OnHide", publish)
    end
    if panelWantedVisible and not menuSuppressed
        and renderState.committed and not renderState.applying then
        frame:Show()
        return true
    end
    if panelWantedVisible and not menuSuppressed and not renderState.committed then
        renderStats.hiddenUncommitted = renderStats.hiddenUncommitted + 1
    end
    frame:Hide()
    return false
end

local function RequestDisplayRecovery()
    LoadWantedVisibility()
    if renderState.committed or not panelWantedVisible or not callbacks
        then
        return false
    end
    local request = type(callbacks.RequestFirstDisplay) == "function"
        and callbacks.RequestFirstDisplay or callbacks.RefreshDisplay
    if type(request) ~= "function" then return false end
    renderStats.recoveryRequests = renderStats.recoveryRequests + 1
    local ok, result = pcall(request)
    return ok and result ~= false
end

local function RestoreHudAfterMenus()
    if menuTransition or AnyNexusMenuShown() then return end
    menuSuppressed = false
    RequestDisplayRecovery()
    ApplyWantedVisibility()
end

function M.AttachMenuFrame(menuFrame)
    if not menuFrame or attachedMenuFrames[menuFrame] then return end
    attachedMenuFrames[menuFrame] = true
    local oldShow = menuFrame:GetScript("OnShow")
    local oldHide = menuFrame:GetScript("OnHide")
    menuFrame:SetScript("OnShow", function(self, ...)
        if oldShow then oldShow(self, ...) end
        menuSuppressed = true
        if frame and frame:IsShown() then frame:Hide() end
    end)
    menuFrame:SetScript("OnHide", function(self, ...)
        if oldHide then oldHide(self, ...) end
        RestoreHudAfterMenus()
    end)
end

function M.CloseOtherWindows(exceptName)
    menuTransition = true
    menuSuppressed = true
    if frame then frame:Hide() end
    CloseOtherNexusWindows(exceptName)
    menuTransition = false
end

-- The panel's own saved keys (position, DPS-records toggle, minimap angle,
-- and the player's Hide Nexus Panel choice) live in the saved root, or for a
-- read-only saved root in the Store owner's session-only table, which starts
-- with copies of the saved values.
-- It is a module field rather than a local because EnsureFrame is at the Lua
-- 5.1 upvalue limit.
local PANEL_SAVED_KEYS = {"panelX", "panelY", "uiShowPerformance", "minimapAngle", "panelHidden", "panelScale"}
function M.SavedLayoutRoot()
    NexusDB = NexusDB or {}
    local writable = Nexus.MainInternals and Nexus.MainInternals.WritableRootV1
    local root = type(writable) == "function"
        and writable(NexusDB, PANEL_SAVED_KEYS) or nil
    return type(root) == "table" and root or NexusDB
end

local function Finite(v) return type(v) == "number" and v == v and v > -math.huge and v < math.huge end

-- Main panel size (issue #170): the player's chosen size of this panel and
-- its children, 50% to 150% in 5% steps, saved as panelScale. An absent key
-- is 100%, and reading writes no default; a saved value that is not a
-- number in range reads as 100% and is left as it is. Only an explicit
-- choice writes: clamped and stepped, or removed by Reset to 100%. Other
-- windows, the Wishlist overlay and the game's UI scale keep their own.
local SCALE_MIN, SCALE_MAX = 0.5, 1.5
function M.PanelScale()
    local value = rawget(M.SavedLayoutRoot(), "panelScale")
    if Finite(value) and value >= SCALE_MIN and value <= SCALE_MAX then return value end
    return 1
end

function M.SetPanelScale(value)
    if not Finite(value) then return false end
    local steps = math.max(SCALE_MIN * 20, math.min(SCALE_MAX * 20, math.floor(value * 20 + 0.5)))
    M.SavedLayoutRoot().panelScale = steps / 20
    M.ApplyPanelScale()
    return true
end

-- One 5% step larger (1) or smaller (-1) than the chosen size.
function M.StepPanelScale(direction)
    return M.SetPanelScale((math.floor(M.PanelScale() * 20 + 0.5) + direction) / 20)
end

function M.ResetPanelScale()
    M.SavedLayoutRoot().panelScale = nil
    M.ApplyPanelScale()
    return true
end

-- The chosen size and the size applied at the last fit; reduced while the
-- screen holds less than the chosen size. Never saved.
function M.PanelScaleStatus()
    local requested = M.PanelScale()
    local last = M._panelScaleStatus
    local effective = last and last.requested == requested and last.effective or requested
    return {requested = requested, effective = effective, reduced = effective < requested - 0.001}
end

-- Anchors the panel by its top-left corner, given in screen units, at its
-- current scale, moved only as far as needed to stay whole on the screen.
function M.PlacePanelTopLeft(left, top)
    local okS, scale = pcall(frame.GetEffectiveScale, frame)
    if not (okS and Finite(scale) and scale > 0 and Finite(left) and Finite(top)) then return false end
    local x, y = left / scale, top / scale
    local width, height = tonumber(frame:GetWidth()) or 0, tonumber(frame:GetHeight()) or 0
    local okU, uiScale = pcall(UIParent.GetEffectiveScale, UIParent)
    local uiW, uiH = tonumber(UIParent:GetWidth()), tonumber(UIParent:GetHeight())
    if okU and Finite(uiScale) and uiScale > 0 and Finite(uiW) and Finite(uiH) and uiW >= 640 and uiH >= 480 then
        local screenW, screenH = uiW * uiScale / scale, uiH * uiScale / scale
        x = math.max(0, math.min(x, screenW - width))
        y = math.min(screenH, math.max(y, height))
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    return true
end

-- The applied size: the chosen size is the fit ceiling (LayoutMetrics
-- .FitToScreen, margin 24). A change of the applied size keeps the panel's
-- physical top-left corner, then clamps it to the screen; no position is
-- saved. Unreadable screen dimensions keep a finite applied size. Nothing
-- rescales or re-anchors while the player moves the panel.
function M.ApplyPanelScale()
    if not frame or M._panelDrag then return nil end
    local requested = M.PanelScale()
    local okB, before = pcall(frame.GetEffectiveScale, frame)
    local okL, left = pcall(frame.GetLeft, frame)
    local okT, top = pcall(frame.GetTop, frame)
    local metrics = Nexus.LayoutMetrics
    local effective = metrics and type(metrics.FitToScreen) == "function"
        and metrics.FitToScreen(frame, nil, requested) or nil
    local fitted = effective ~= nil
    if not effective then
        local current = tonumber(frame:GetScale())
        if not (Finite(current) and current >= SCALE_MIN and current <= SCALE_MAX) then
            frame:SetScale(math.min(1, requested))
        end
        effective = tonumber(frame:GetScale()) or 1
    end
    M._panelScaleStatus = {requested = requested, effective = effective}
    local okA, after = pcall(frame.GetEffectiveScale, frame)
    local restore = M._restorePlacement
    if restore and fitted then
        M._restorePlacement = nil
        local okU, uiScale = pcall(UIParent.GetEffectiveScale, UIParent)
        if restore.x and okA and okU and Finite(after) and after > 0 and Finite(uiScale) and uiScale > 0 then
            local ratio = after / uiScale
            frame:ClearAllPoints()
            frame:SetPoint("CENTER", UIParent, "CENTER", restore.x / ratio, restore.y / ratio)
        end
        return effective
    end
    if okB and okA and okL and okT and Finite(before) and Finite(after) and before > 0
        and math.abs(before - after) > 0.0005 and Finite(left) and Finite(top) then
        M.PlacePanelTopLeft(left * before, top * before)
    end
    return effective
end

-- The saved position at the chosen size (EnsureFrame): panelX / panelY are
-- UIParent units, a point offset is in the panel's own.
-- The first fit after this restore places the saved centre again at the
-- size that fit applies (M._restorePlacement), instead of keeping the
-- corner of this provisional placement: a saved centre is not moved by a
-- reduction to fit (review of e1183fd). The default placement keeps its
-- right-edge anchor.
function M.RestorePanelPosition()
    local saved = M.SavedLayoutRoot()
    local scale = M.PanelScale()
    frame:SetScale(scale)
    frame:ClearAllPoints()
    local x, y = tonumber(saved.panelX), tonumber(saved.panelY)
    if Finite(x) and Finite(y) then
        frame:SetPoint("CENTER", UIParent, "CENTER", x / scale, y / scale)
        M._restorePlacement = {x = x, y = y}
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
        M._restorePlacement = {default = true}
    end
end

-- The panel's centre as an offset from UIParent's centre, in UIParent units
-- (panelX / panelY). The frame's own centre is in its own scale, so it is
-- converted through both effective scales first. nil unless every read is a
-- finite number and both scales are positive.
function M.PanelCenterOffset()
    if not frame then return nil end
    local okF, x, y = pcall(frame.GetCenter, frame)
    local okU, ux, uy = pcall(UIParent.GetCenter, UIParent)
    local okS, fs = pcall(frame.GetEffectiveScale, frame)
    local okP, us = pcall(UIParent.GetEffectiveScale, UIParent)
    if not (okF and okU and okS and okP) then return nil end
    if not (Finite(x) and Finite(y) and Finite(ux) and Finite(uy) and Finite(fs) and Finite(us)
        and fs > 0 and us > 0) then return nil end
    local ratio = fs / us
    return math.floor(x * ratio - ux + 0.5), math.floor(y * ratio - uy + 0.5)
end

-- Moving the panel (issue #168). One owner: the root and every passive
-- surface that takes the mouse (M.PassiveDragSurface) start and finish the
-- same move of the root, with the client's drag threshold (RegisterForDrag)
-- keeping a plain click a click. Only a left drag starts; a second start
-- while one is active is refused. Finishing is idempotent: the move is
-- cleared and stopped first, then the position is read and saved once,
-- only when it changed and every read is valid. A release, the root's hide
-- or the hide of the surface the move began on finishes it.
function M.BeginPanelDrag(origin, button)
    if M._panelDrag or not frame or (button ~= nil and button ~= "LeftButton") then return false end
    if not frame:IsShown() then return false end
    local x, y = M.PanelCenterOffset()
    if not pcall(frame.StartMoving, frame) then return false end
    M._panelDrag = {origin = origin or frame, x = x, y = y}
    M._restorePlacement = nil
    M.HidePanelTooltip(origin)
    return true
end

function M.FinishPanelDrag()
    local drag = M._panelDrag
    if not drag then return false end
    M._panelDrag = nil
    if frame then pcall(frame.StopMovingOrSizing, frame) end
    local ok, x, y = pcall(M.PanelCenterOffset)
    if ok and x and y and (x ~= drag.x or y ~= drag.y) then
        local saved = M.SavedLayoutRoot()
        saved.panelX, saved.panelY = x, y
    end
    -- A shown paused banner keeps to the side of the moved panel with room.
    if frame and frame._pauseBanner and frame._pauseBanner:IsShown() then pcall(M.PlacePauseBanner) end
    return true
end

-- After a render: a move continues only while the panel is shown and the
-- surface it began on is still visible, a hidden ancestor (the roll area of
-- a board without an offer) included (IsVisible, not only its own shown
-- flag); otherwise it is finished (stopped, and saved once if it moved) as
-- a real hide would.
function M.SettlePanelDrag()
    local drag = M._panelDrag
    if not drag then return false end
    local origin = drag.origin
    local okF, shown = pcall(frame.IsShown, frame)
    local okO, originVisible = true, true
    if origin and origin ~= frame then okO, originVisible = pcall(origin.IsVisible, origin) end
    if okF and shown and okO and originVisible then return false end
    return M.FinishPanelDrag()
end

-- Closes the shared tooltip only while `owner` (a panel surface) owns it.
function M.HidePanelTooltip(owner)
    if not (owner and GameTooltip) then return end
    local ok, owned = pcall(function() return rawequal(GameTooltip:GetOwner(), owner) end)
    if ok and owned == true then GameTooltip:Hide() end
end

-- A passive label's hover area covers the text it shows, not its whole box
-- (issue #168): from the box's justified edge, the measured text width plus
-- a 4 px pad, never wider than the box; the box's height. A shortened text
-- keeps the whole visible box (and its complete text on hover). An empty
-- text takes no mouse; one this made mouse-less takes it again once it has
-- text. Mouse input set by the label's owner is otherwise left alone.
local PASSIVE_PAD = 4
function M.FitPassiveHover(hit, text, wrapped)
    if not (hit and text) then return nil end
    local box = tonumber(text:GetWidth()) or 0
    local value = text:GetText()
    local ok, width = pcall(text.GetStringWidth, text)
    width = ok and tonumber(width) or nil
    if value == nil or value == "" then width = 0 end
    if not width or width ~= width or width > box then width = box end
    local justify = text.GetJustifyH and text:GetJustifyH() or "LEFT"
    local point = justify == "RIGHT" and "TOPRIGHT" or justify == "CENTER" and "TOP" or "TOPLEFT"
    local fitted = width > 0 and math.min(box, width + (justify == "CENTER" and 2 or 1) * PASSIVE_PAD) or 0
    local height = tonumber(text:GetHeight()) or 1
    if wrapped and fitted > 0 then
        -- A wrapped text box (top-aligned): the rows its text needs, never
        -- taller than the box; measured at height 0 and the box restored,
        -- as LayoutMetrics.Overflows does.
        text:SetHeight(0)
        local okH, measured = pcall(text.GetStringHeight, text)
        text:SetHeight(height)
        measured = okH and tonumber(measured) or nil
        if measured and measured == measured and measured > 0 and measured < height then height = measured end
    end
    hit:ClearAllPoints()
    hit:SetPoint(point, text, point, 0, 0)
    hit:SetSize(math.max(1, fitted), math.max(1, height))
    if fitted <= 0 then
        if not hit._nexusFitEmpty then hit._nexusFitEmpty = true; hit:EnableMouse(false) end
    elseif hit._nexusFitEmpty then
        hit._nexusFitEmpty = nil
        hit:EnableMouse(true)
    end
    return fitted
end

-- Every passive label hover of the main panel, after a render has set its
-- texts and boxes. The Charges line, the recommendation, the Details
-- headings and the Extra copies list are fitted only while shown (a hidden
-- one takes no input). The destination row's hovers stay with their hidden
-- row; the counts that open the Wishlist Editor are not passive.
-- C-03: `settled` (no layout pass ran, so nothing else re-anchored a hover)
-- refits only a hover whose text, box, justification or face changed since
-- its last fit (M.PassiveHoverKey); a layout pass refits every one.
-- The face is the nominal path, size and flags its GetFont reports
-- (M.PassiveHoverKey), and the GetFont the text answers with. A face whose
-- metrics differ under the same nominal font is installed with a new
-- reader, so a new reader is a changed face: the fit is not kept from the
-- earlier one. That reader is held by the hit itself and compared by
-- identity (never by its printed address), so a collected one cannot seem
-- to come back. It costs no call: the client's own reader is one fixed
-- method, so a settled render still measures and re-anchors nothing.
function M.PassiveHoverKey(text, wrapped)
    local okFont, path, size, flags = pcall(text.GetFont, text)
    return table.concat({tostring(text:GetText()), tostring(text:GetWidth()), tostring(text:GetHeight()),
        tostring(text.GetJustifyH and text:GetJustifyH() or "LEFT"), wrapped and "wrap" or "line",
        tostring(okFont and path), tostring(okFont and size), tostring(okFont and flags)}, "\031")
end

function M.FitPassiveHovers(settled)
    if not frame then return end
    local p = frame._play or {}
    local function Fit(hit, text, wrapped)
        if not (hit and text) then return end
        local key, face = M.PassiveHoverKey(text, wrapped), text.GetFont
        if settled and hit._nexusFitKey == key and rawequal(hit._nexusFitFace, face) then return end
        hit._nexusFitKey, hit._nexusFitFace = nil, nil
        M.FitPassiveHover(hit, text, wrapped)
        hit._nexusFitKey, hit._nexusFitFace = key, face
    end
    local pairs_ = {
        {frame._contextTitleHit, frame._contextTitle}, {frame._contextBuildHit, frame._contextBuild},
        {frame._contextWishlistHit, frame._contextWishlist},
        {p.tomesHit, p.tomes}, {p.extraHit, p.extra}, {p.bestHit, p.bestLabel}, {p.orbHit, p.orb},
        {frame._callboardTitleHit, frame._callboardTitle}, {frame._callboardLineHit, frame._callboardLine},
    }
    for i = 1, #pairs_ do Fit(pairs_[i][1], pairs_[i][2]) end
    local shownOnly = {
        {frame._chargesHover, frame._chargesText}, {frame._recommendationHover, recText, true},
        {frame._progressLabelHit, progressLabel}, {frame._needLabelHit, needLabel},
        {frame._shedLabelHit, shedLabel}, {shedHit, shedText, true},
    }
    for i = 1, #shownOnly do
        local hit = shownOnly[i][1]
        if hit and hit:IsShown() then Fit(hit, shownOnly[i][2], shownOnly[i][3])
        elseif hit then hit._nexusFitKey, hit._nexusFitFace = nil, nil end
    end
end

-- A passive surface that takes the mouse for its hover (a label, count,
-- card or icon with no click of its own) also starts and finishes the
-- panel's move: its release reaches it as OnDragStop (the client's own
-- child-to-parent drag, FloatingChatFrame.xml, build 12340). It gets no
-- click or mouse-up script. Its own scripts are kept; while a move is active
-- its hover does not keep a tooltip open. Never for a control with its own
-- action.
function M.PassiveDragSurface(hit)
    if not hit or hit._nexusPassiveDrag then return hit end
    hit._nexusPassiveDrag = true
    hit:RegisterForDrag("LeftButton")
    hit:SetScript("OnDragStart", function(self, button) M.BeginPanelDrag(self, button) end)
    hit:SetScript("OnDragStop", function() M.FinishPanelDrag() end)
    -- A render can hide this surface while it applies (a row it no longer
    -- shows) and show it again in the same call; that hide is not a
    -- removal. M.SettlePanelDrag checks the origin once the render is done.
    hit:HookScript("OnHide", function(self)
        local drag = M._panelDrag
        if drag and drag.origin == self and not renderState.applying then M.FinishPanelDrag() end
    end)
    hit:HookScript("OnEnter", function(self)
        if M._panelDrag then M.HidePanelTooltip(self) end
    end)
    return hit
end

-- Adds one reviewed meaning to GameTooltip, one AddLine per line of its
-- text: an English block keeps exactly the lines it always had, and a
-- translation breaks its whole sentence where it reads best. EnsureFrame's
-- hovers reach it through M (they may capture no new local).
function M.AddLocalizedLines(key, r, g, b, wrap)
    for line in (LT(key) .. "\n"):gmatch("(.-)\n") do
        GameTooltip:AddLine(line, r, g, b, wrap)
    end
end

local function EnsureFrame()
    if frame then return frame end

    frame = CreateFrame("Frame", "NexusPanel", UIParent)
    frame:SetSize(420, 210)
    frame:SetClampedToScreen(true)
    M.RestorePanelPosition()
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self, button) M.BeginPanelDrag(self, button) end)
    frame:SetScript("OnDragStop", function() M.FinishPanelDrag() end)
    frame:SetScript("OnMouseUp", function() M.FinishPanelDrag() end)
    frame:Hide()

    buildHeaderText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame._buildHeaderText = buildHeaderText
    buildHeaderText:SetPoint("TOP", 0, -8)
    buildHeaderText:SetSize(244, 17)
    buildHeaderText:SetJustifyH("CENTER")
    buildHeaderText:SetTextColor(0.45, 0.84, 1)
    -- The destination row (character, Saved Build, Wishlist, state) replaces
    -- the single Wishlist heading, which is its first cell. It is anchored
    -- here once, independently of its cells, in the header's own space
    -- (x 40, clear of the menu, at the header's top); ApplyModel sizes and
    -- fits it after every other header and layout operation.
    frame._destinationRow = M.CreateDestinationRow(frame, buildHeaderText)
    frame._destinationRow:SetPoint("TOPLEFT", frame, "TOPLEFT", 40, -8)
    frame._destinationRow:Hide()
    buildHeaderText:Hide() -- first cell belongs to frame, unlike the row's other cells

    switchBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame._switchBtn = switchBtn
    switchBtn:SetSize(90, 19)
    switchBtn:SetPoint("TOPLEFT", 10, -26)
    switchBtn:SetText((Nexus.Localization.Text("panel.button.my_builds")))
    -- The game's own page (M.OpenMyBuilds), also offered by the Plan hub.
    switchBtn:SetScript("OnClick", function() M.OpenMyBuilds() end)
    switchBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        -- Issue #143: while the client shortens this button's one-line label
        -- (its own FontString, bounded to the button in ApplyModel), its own
        -- hover shows the complete label first. Nothing below takes the
        -- tooltip again, so every line of its own follows unchanged. The
        -- OneLineLabel owner hook is not attached: it would run after these
        -- lines and take the tooltip again with its own SetOwner.
        local metrics = Nexus.LayoutMetrics
        if metrics and metrics.Shortened and metrics.Shortened(self:GetFontString()) then
            GameTooltip:AddLine(tostring(self:GetText() or ""), 1, 1, 1, true)
        end
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.open_my_builds"), 1, 1, 1)
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.my_builds_destination"), 0.75, 0.75, 0.75, true)
        -- M4 (UX-04): what this panel's run belongs to, from the facts the
        -- shown model already carries (M.DestinationLines). Read-only.
        local lines = M.DestinationLines(M._lastModel)
        if #lines > 0 then
            GameTooltip:AddLine(" ")
            for _, line in ipairs(lines) do GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true) end
        end
        GameTooltip:Show()
    end)
    switchBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    M.CreateContextHeader(frame)

    -- Clickable compact replacement for Project Ebonhold's difficulty / Soul
    -- Ash HUD. In-progress builds use a slim header treatment. Completed builds
    -- expand this into the primary status card so the familiar server metrics
    -- remain the most visible information.
    worldStatusBox = CreateFrame("Frame", nil, frame)
    -- Protected card: no style or colour choice repaints it (Theme.Exempt).
    worldStatusBox._nexusThemeExempt = true
    worldStatusBox:SetFrameLevel(frame:GetFrameLevel() + 3)
    pcall(function()
        worldStatusBox:SetBackdrop({
            bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true, tileSize=16, edgeSize=10,
            insets={left=2,right=2,top=2,bottom=2},
        })
        worldStatusBox:SetBackdropColor(0.018, 0.035, 0.045, 0.96)
        worldStatusBox:SetBackdropBorderColor(0.16, 0.34, 0.40, 0.9)
    end)

    worldStatusText = worldStatusBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    worldStatusText:SetJustifyH("LEFT")
    worldStatusText:SetText("")

    worldStatusAsh = worldStatusBox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    worldStatusAsh:SetJustifyH("LEFT")
    worldStatusAsh:SetText("")

    worldStatusGain = worldStatusBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    worldStatusGain:SetJustifyH("RIGHT")
    worldStatusGain:SetText("")

    -- Live server Intensity meter. Keep these widgets attached to the status
    -- box instead of adding more module upvalues; WoW 3.3.5 Lua has a strict
    -- 60-upvalue compiler limit for functions.
    worldStatusBox.intensityBar = CreateFrame("StatusBar", nil, worldStatusBox)
    worldStatusBox.intensityBar:SetMinMaxValues(0, 500)
    worldStatusBox.intensityBar:SetValue(0)
    worldStatusBox.intensityBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    worldStatusBox.intensityBar:SetStatusBarColor(0.86, 0.24, 0.16, 1)
    worldStatusBox.intensityBar:SetFrameLevel(worldStatusBox:GetFrameLevel() + 2)

    worldStatusBox.intensityTrack = worldStatusBox.intensityBar:CreateTexture(nil, "BACKGROUND")
    worldStatusBox.intensityTrack:SetAllPoints()
    worldStatusBox.intensityTrack:SetTexture(0.07, 0.08, 0.09, 0.95)

    worldStatusBox.intensityText = worldStatusBox.intensityBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    worldStatusBox.intensityText:SetPoint("CENTER", worldStatusBox.intensityBar, "CENTER", 0, 0)
    worldStatusBox.intensityText:SetTextColor(1, 0.88, 0.72)
    worldStatusBox.intensityText:Hide()
    worldStatusBox.intensityText:SetText("")

    worldStatusBox.intensityTicks = {}
    for i = 1, 4 do
        local tick = worldStatusBox.intensityBar:CreateTexture(nil, "OVERLAY")
        tick:SetTexture(1, 1, 1, 0.28)
        tick:SetWidth(1)
        worldStatusBox.intensityTicks[i] = tick
    end

    -- The ticks mark the game's level thresholds 1-4 on the bar scaled to its
    -- maximum (worldStatusBox._intensityScale, from the validated constants
    -- of ServerStatus). Without a known scale there are no ticks.
    local function PositionIntensityTicks()
        local bar = worldStatusBox and worldStatusBox.intensityBar
        if not bar then return end
        local width = tonumber(bar:GetWidth()) or 0
        if width <= 0 then return end
        local scale = worldStatusBox._intensityScale
        for i = 1, 4 do
            local tick = worldStatusBox.intensityTicks[i]
            local threshold = scale and tonumber(scale.thresholds[i])
            if threshold then
                tick:ClearAllPoints()
                local x = math.floor((width * threshold / scale.max) + 0.5)
                tick:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
                tick:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x, 0)
                tick:Show()
            else
                tick:Hide()
            end
        end
    end
    worldStatusBox.PositionIntensityTicks = PositionIntensityTicks
    worldStatusBox.intensityBar:SetScript("OnSizeChanged", PositionIntensityTicks)

    worldStatusHit = CreateFrame("Button", nil, worldStatusBox)
    worldStatusHit:SetAllPoints(worldStatusBox)
    worldStatusHit:SetFrameLevel(worldStatusBox:GetFrameLevel() + 5)
    worldStatusHit:RegisterForClicks("LeftButtonUp")
    local statusHighlight = worldStatusHit:CreateTexture(nil, "HIGHLIGHT")
    statusHighlight:SetAllPoints()
    pcall(function() statusHighlight:SetTexture(1, 1, 1, 0.06) end)
    worldStatusHit:SetScript("OnClick", function()
        if Nexus.ServerStatus and Nexus.ServerStatus.OpenHardcoreMenu then
            Nexus.ServerStatus.OpenHardcoreMenu()
        end
    end)
    worldStatusHit:SetScript("OnEnter", function(self)
        local ss = worldStatusBox._summary or {}
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        -- A known Normal (no Hardcore tier) is neutral, as the game's own
        -- widget shows it; a Hardcore tier and an unknown mode keep the red.
        if ss.tier == nil and ss.mode == "Normal" then
            GameTooltip:AddLine("Normal", 0.85, 0.85, 0.85)
        else
            GameTooltip:AddLine(ss.tier or ss.mode or Nexus.Localization.Text("panel.tooltip.difficulty_fallback"), 1, 0.25, 0.25)
        end
        if ss.ash then GameTooltip:AddLine(Nexus.Localization.Format("panel.tooltip.soul_ash", {ash = (tostring(ss.ash):gsub(",",""))}), 1, 1, 1) end
        if ss.gain then GameTooltip:AddLine(Nexus.Localization.Format("panel.tooltip.soul_ash_multiplier", {multiplier = tostring(ss.gain)}), 0.2, 1, 0.2) end
        if ss.intensity ~= nil then
            -- The maximum and level come from the game's validated constants;
            -- without them neither is stated.
            local maximum = tonumber(ss.intensityMax)
            local level = tonumber(ss.intensityLevel)
            local intensity = tostring(math.floor(tonumber(ss.intensity) or 0))
            GameTooltip:AddLine(maximum and Nexus.Localization.Format("panel.tooltip.intensity_of_max",
                {intensity = intensity, maximum = tostring(math.floor(maximum))})
                or Nexus.Localization.Format("panel.tooltip.intensity", {intensity = intensity}), 1, 0.55, 0.25)
            GameTooltip:AddLine(Nexus.Localization.Format("panel.tooltip.intensity_level", {level = level and tostring(level)
                or Nexus.Localization.Text("panel.value.intensity_level_unknown")}), 0.85, 0.75, 0.65)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.difficulty_click"), 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    worldStatusHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    worldStatusBox:Hide()

    rollArea = CreateFrame("Frame", nil, frame)
    frame._rollArea = rollArea
    rollArea:SetPoint("TOPLEFT", 10, -98)
    rollArea:SetSize(280, 104)

    statusText = rollArea:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statusText:SetPoint("TOPLEFT", 2, -1)
    statusText:SetSize(276, 14)
    statusText:SetJustifyH("LEFT")
    frame._rollStatus = statusText
    -- Compact charges (Readout.ChargesLine), right-aligned in the heading
    -- row; shown only while the model itself carries charge facts.
    frame._chargesText = rollArea:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame._chargesText:SetPoint("TOPRIGHT", -2, -1)
    frame._chargesText:SetSize(72, 14)
    frame._chargesText:SetJustifyH("RIGHT")
    frame._chargesText:Hide()
    -- Its legend on hover (Readout.ChargesLegend): what B/R/F, "?" and "~"
    -- mean. Shown and hidden with the line; reading it changes nothing.
    -- A frame field, not a local (EnsureFrame is near the Lua limits).
    frame._chargesHover = CreateFrame("Frame", nil, rollArea)
    frame._chargesHover:SetPoint("TOPLEFT", frame._chargesText, "TOPLEFT", 0, 0)
    frame._chargesHover:SetPoint("BOTTOMRIGHT", frame._chargesText, "BOTTOMRIGHT", 0, 0)
    frame._chargesHover:EnableMouse(true)
    frame._chargesHover:SetScript("OnEnter", function(self)
        local readout = Nexus.Readout
        if not (GameTooltip and readout and type(readout.ChargesLegend) == "function") then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.charges_heading"), 1, 1, 1)
        -- Recover the complete current row even when its fixed label is short.
        GameTooltip:AddLine(frame._chargesText:GetText() or "", 1, 1, 1, true)
        for _, line in ipairs(readout.ChargesLegend()) do GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true) end
        GameTooltip:Show()
    end)
    frame._chargesHover:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    frame._chargesHover:Hide()

    for i = 1, 3 do
        local fs = rollArea:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 2, -19 - (i - 1) * 14)
        fs:SetSize(276, 13)
        fs:SetJustifyH("LEFT")
        cardTexts[i] = fs
    end

    -- Passive navigation only: it opens the Orb window, which reads and
    -- shows state. It starts, resumes, approves and spends nothing.
    local orbsBtn = CreateFrame("Button", nil, rollArea, "UIPanelButtonTemplate")
    -- The responsive layout gives it its own row (ApplyPanelLayout); this is
    -- only the initial placement.
    orbsBtn:SetSize(104, 17)
    orbsBtn:SetPoint("BOTTOMRIGHT", rollArea, "BOTTOMRIGHT", -2, 4)
    orbsBtn:SetText((Nexus.Localization.Text("panel.button.open_orbs")))
    orbsBtn:SetScript("OnClick", function()
        if Nexus.OrbPanel and Nexus.OrbPanel.Show then Nexus.OrbPanel.Show() end
    end)
    orbsBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.orbs_heading"), 1, 0.82, 0)
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.orbs_open_inspect"), 0.85, 0.85, 0.85, true)
        for _, b in ipairs(self.blockers or {}) do
            local guidance = Nexus.OrbGuidance
            GameTooltip:AddLine(tostring(guidance and guidance.Shown and guidance.Shown(b.text) or b.text), 1, 0.6, 0.4, true)
        end
        GameTooltip:Show()
    end)
    orbsBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    orbsBtn:Hide()
    frame._orbsBtn = orbsBtn

    local orbMiniBtn = CreateFrame("Button", nil, rollArea, "UIPanelButtonTemplate")
    orbMiniBtn:SetSize(118, 17)
    orbMiniBtn:SetPoint("RIGHT", orbsBtn, "LEFT", -6, 0)
    orbMiniBtn:SetText((Nexus.Localization.Text("panel.button.orb_mini")))
    orbMiniBtn:SetScript("OnClick", function()
        if Nexus.OrbPanel and Nexus.OrbPanel.ShowMini then Nexus.OrbPanel.ShowMini() end
    end)
    orbMiniBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.orb_mini_heading"), 1, 0.82, 0)
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.orb_mini_status"), 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    orbMiniBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    orbMiniBtn:Hide()
    frame._orbMiniBtn = orbMiniBtn

    recText = rollArea:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    recText:SetPoint("TOPLEFT", 2, -64)
    recText:SetSize(276, 30)
    recText:SetJustifyH("LEFT")
    recText:SetJustifyV("TOP")
    recText:SetTextColor(1, 0.82, 0)
    frame._rollRec = recText
    frame._recommendationHover = Nexus.LayoutMetrics.FullTextTooltip(recText, rollArea)

    rollDivider = rollArea:CreateTexture(nil, "ARTWORK")
    rollDivider:SetSize(278, 1)
    rollDivider:SetPoint("BOTTOMLEFT", 1, 0)
    pcall(function() rollDivider:SetTexture(0.3, 0.3, 0.3, 0.65) end)

    progressLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    progressLabel:SetText((Nexus.Localization.Text("panel.heading.progress")))
    -- Issue #143: each mapped heading stays one line in its fixed layout box.
    -- While the client shortens a longer heading, a hover over it shows the
    -- complete heading (LayoutMetrics.OneLineLabel). Created once here, shown
    -- and hidden with the heading (ShowCoreProgress). Frame fields, not new
    -- locals: EnsureFrame is at the Lua 5.1 upvalue limit.
    frame._progressLabelHit = HitFrame(frame, progressLabel)
    frame._progressLabelHit:Hide()
    Nexus.LayoutMetrics.OneLineLabel(progressLabel, frame._progressLabelHit, 11)
    progressValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    progressValue:SetTextColor(1, 0.5, 0.2)

    needLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    needLabel:SetText((Nexus.Localization.Text("panel.heading.still_needed")))
    frame._needLabelHit = HitFrame(frame, needLabel)
    frame._needLabelHit:Hide()
    Nexus.LayoutMetrics.OneLineLabel(needLabel, frame._needLabelHit, 11)

    tomesLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tomesLabel:SetText((Nexus.Localization.Text("panel.heading.missing_tomes_stacked")))
    tomesLabel:SetJustifyH("RIGHT")
            tomesLabel:SetJustifyV("TOP")
    tomesValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tomesValue:SetJustifyH("RIGHT")
    tomesValue:SetTextColor(1, 0.4, 0.4)
    tomesHit = CreateFrame("Frame", nil, frame)
    tomesHit:EnableMouse(true)
    tomesHit:SetScript("OnEnter", function(self)
        if #unknownTomesCache == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.missing_tomes_heading"), 1, 0.82, 0)
        GameTooltip:AddLine(" ")
        M.AddLocalizedLines("panel.tooltip.missing_tomes_undiscovered", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.missing_tomes_separate"), 0.6, 1, 0.6, true)
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.missing_tomes_where"), 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.missing_tomes_check"), 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.missing_tomes_no_source"), 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.missing_tomes_list"), 1, 0.8, 0.4)
        for i, name in ipairs(unknownTomesCache) do
            -- A generated "Tome of <Echo>" (GameAdapter marks it) through its
            -- key; a catalog tome name as it is.
            local generated = type(unknownTomesCache.generated) == "table" and unknownTomesCache.generated[i]
            if type(generated) == "table" then
                local shown, source = Nexus.Localization.Format("main.value.unknown_tome", {echo = tostring(generated.echo)})
                if source ~= "unavailable" then name = shown end
            end
            GameTooltip:AddLine("  • " .. name, 1, 0.45, 0.45)
            if i >= 25 then
                if #unknownTomesCache > i then
                    GameTooltip:AddLine("  " .. Nexus.Localization.Format("panel.tooltip.more_count", {count = Nexus.Localization.Count(#unknownTomesCache - i)}), 0.7, 0.7, 0.7)
                end
                break
            end
        end
        GameTooltip:Show()
    end)
    tomesHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    needText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    needText:SetSize(136, 52)
    needText:SetJustifyH("LEFT")
    needText:SetJustifyV("TOP")
    -- One line per name, so a long name never pushes "+N more" out of the
    -- box; the hover list carries every complete name.
    needText:SetWordWrap(false)
    needText:SetTextColor(1, 0.5, 0.2)
    needHit = HitFrame(frame, needText)
    needHit:SetScript("OnEnter", function(self)
        if #missingNamesCache == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.still_needed_heading"), 1, 1, 1)
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.still_needed_not_obtained"), 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        M.AddLocalizedLines("panel.tooltip.still_needed_off_wishlist", 0.75, 0.75, 0.75, true)
        GameTooltip:AddLine(" ")
        if #missingNamesCache > 0 then
            GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.still_needed_list"), 1, 0.65, 0.25)
            for i, name in ipairs(missingNamesCache) do
                -- Split "Echo Name ×N (Quality:×N ...)" into label and detail
                local label, detail = name:match("^(.-)%s+(%b())$")
                if label and detail then
                    GameTooltip:AddLine("  • " .. label, 0.9, 0.9, 0.9)
                    -- Strip outer parens and show quality breakdown indented
                    local inner = detail:sub(2, -2)
                    GameTooltip:AddLine("      " .. inner, 0.7, 0.7, 0.7)
                else
                    GameTooltip:AddLine("  • " .. name, 0.9, 0.9, 0.9)
                end
                if i >= 25 then
                    if #missingNamesCache > 25 then
                        GameTooltip:AddLine("  " .. Nexus.Localization.Format("panel.tooltip.more_count", {count = Nexus.Localization.Count(#missingNamesCache - 25)}), 0.6, 0.6, 0.6)
                    end
                    break
                end
            end
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.open_wishlist_editor"), 0.4, 0.8, 1)
        GameTooltip:Show()
    end)
    needHit:SetScript("OnLeave", function() GameTooltip:Hide() end)
    needHit:SetScript("OnMouseUp", function() if Nexus.WishlistEditor then Nexus.WishlistEditor.Show() end end)

    shedLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    shedLabel:SetText((Nexus.Localization.Text("panel.heading.extra_copies")))
    frame._shedLabelHit = HitFrame(frame, shedLabel)
    frame._shedLabelHit:Hide()
    Nexus.LayoutMetrics.OneLineLabel(shedLabel, frame._shedLabelHit, 11)
    shedText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    shedText:SetSize(136, 46)
    shedText:SetJustifyH("LEFT")
    shedText:SetJustifyV("TOP")
    shedText:SetWordWrap(false)
    shedText:SetTextColor(0.72, 0.52, 1)
    shedHit = HitFrame(frame, shedText)
    shedHit:SetScript("OnEnter", function(self)
        if #shedNamesCache == 0 then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.extra_heading"), 1, 1, 1)
        M.AddLocalizedLines("panel.tooltip.extra_above_targets", 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.extra_not_delete"), 0.9, 0.9, 0.9, true)
        GameTooltip:AddLine(" ")
        M.AddLocalizedLines("panel.tooltip.extra_locked_protected", 0.75, 0.75, 0.75, true)
        GameTooltip:AddLine(" ")
        for i, name in ipairs(shedNamesCache) do
            GameTooltip:AddLine("  • " .. name, 0.75, 0.6, 1)
            if i >= 25 then
                if #shedNamesCache > 25 then
                    GameTooltip:AddLine("  " .. Nexus.Localization.Format("panel.tooltip.more_count", {count = Nexus.Localization.Count(#shedNamesCache - 25)}), 0.6, 0.6, 0.6)
                end
                break
            end
        end
        -- Owner-approved item 7: where the complete list is.
        if #shedNamesCache > 2 then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.extra_show_all_where"), 0.4, 0.8, 1, true)
        end
        GameTooltip:Show()
    end)
    shedHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- The TO LOCK row's widgets are built lazily by M.Render (via
    -- CreateToLockWidgets), not here -- EnsureFrame is already at Lua
    -- 3.3.5's 60-upvalue ceiling (see the note on menuBtn's tooltip above),
    -- and even a single extra reference to that function tips it over.

    performanceLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    performanceLabel:SetText((Nexus.Localization.Text("panel.heading.dps_records")))
    setLabelText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    setLabelText:SetSize(164, 14)
    setLabelText:SetJustifyH("LEFT")

    dummyLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dummyLabel:SetText((Nexus.Localization.Text("panel.label.dummy_best")))
    dummyValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dummyValue:SetJustifyH("RIGHT")
    dummyGlobal = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    dummyGlobal:SetJustifyH("LEFT")
    dummyGlobalValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dummyGlobalValue:SetJustifyH("RIGHT")

    lkLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lkLabel:SetText((Nexus.Localization.Text("panel.label.lich_king_best")))
    lkPersonalLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lkPersonalLabel:SetText((Nexus.Localization.Text("panel.label.your_best")))
    lkPersonalLabel:SetJustifyH("LEFT")
    lkValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lkValue:SetJustifyH("RIGHT")
    lkGlobal = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    lkGlobal:SetJustifyH("LEFT")
    lkGlobalValue = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lkGlobalValue:SetJustifyH("RIGHT")

    dummyHit = CreateFrame("Frame", nil, frame)
    dummyHit:EnableMouse(true)
    lkHit = CreateFrame("Frame", nil, frame)
    lkHit:EnableMouse(true)

    completeBadge = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    completeBadge:SetTextColor(0.35, 1, 0.45)
    completeBadge:SetJustifyH("CENTER")
    completeSubtext = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    completeSubtext:SetJustifyH("CENTER")
    completeSubtext:SetTextColor(0.72, 0.72, 0.72)

    setupText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    setupText:SetJustifyH("CENTER")
    setupText:SetTextColor(0.45, 0.84, 1)
    setupHint = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    setupHint:SetSize(272, 34)
    setupHint:SetJustifyH("CENTER")
    setupHint:SetJustifyV("TOP")

    -- First-run primary action. Assignment used to be hidden behind the
    -- top-right Swap button while "Choose Build" opened an unrelated browser.
    -- Use the same server-backed assignment flow as Swap so the next required
    -- step is explicit and immediately reachable from onboarding.
    setupGetStartedBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    setupGetStartedBtn:SetSize(126, 24)
    setupGetStartedBtn:SetText((Nexus.Localization.Text("panel.button.assign_wishlist")))
    -- The assignment route (M.OpenAssignment), also offered by the Plan hub.
    setupGetStartedBtn:SetScript("OnClick", function() M.OpenAssignment() end)
    setupGetStartedBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        -- Issue #143: the complete label first while it is shortened (see My Builds).
        local metrics = Nexus.LayoutMetrics
        if metrics and metrics.Shortened and metrics.Shortened(self:GetFontString()) then
            GameTooltip:AddLine(tostring(self:GetText() or ""), 1, 1, 1, true)
        end
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.assignment_heading"), 1, 1, 1)
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.assignment_chooser"), 0.9, 0.9, 0.9, true)
        GameTooltip:Show()
    end)
    setupGetStartedBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    setupImportBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    setupImportBtn:SetSize(126, 24)
    setupImportBtn:SetText((Nexus.Localization.Text("panel.button.create_wishlist")))
    setupImportBtn:SetScript("OnClick", function()
        CloseOtherNexusWindows()
        if Nexus.WishlistEditor then Nexus.WishlistEditor.Show() end
    end)
    setupImportBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        -- Issue #143: the complete label first while it is shortened (see My Builds).
        local metrics = Nexus.LayoutMetrics
        if metrics and metrics.Shortened and metrics.Shortened(self:GetFontString()) then
            GameTooltip:AddLine(tostring(self:GetText() or ""), 1, 1, 1, true)
        end
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.create_wishlist_heading"), 1, 1, 1)
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.create_wishlist_source"), 0.9, 0.9, 0.9, true)
        -- M4 (M2 O1): this button only opens the editor. The editor's own
        -- Create & assign / Create unassigned actions are what save.
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.create_wishlist_draft"), 0.75, 0.75, 0.75, true)
        GameTooltip:Show()
    end)
    setupImportBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    autoBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame._autoBtn = autoBtn
    autoBtn:SetSize(72, 22)
    autoBtn:SetPoint("BOTTOMLEFT", 8, 7)
    autoBtn:SetText(AutoLabel(nil))
    autoBtn:SetScript("OnClick", function()
        if callbacks and type(callbacks.ToggleAuto) == "function" then
            local before = M.AutoSelectedNow()
            local ok, state = pcall(callbacks.ToggleAuto)
            -- The label, and at Auto OFF the release of a reserved roll block.
            if ok and state ~= nil then M.SetAuto(state and true or false) end
            -- A click that left Auto OFF says why in the roll block (UX-09).
            M.NoteAutoClick(before, ok, state)
        end
    end)
    -- Issue #169: a short hover (M.ShowAutoTooltip); the complete permission
    -- and safety text is one deliberate click away (Options > Auto explained).
    autoBtn:SetScript("OnEnter", function(self) M.ShowAutoTooltip(self) end)
    autoBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Footer hubs (issue #163, UI review P3): Plan, Explore and Orbs. Plan
    -- and Explore open a native dropdown of existing routes (M.ShowHub);
    -- Orbs opens the Orb window, as the Options menu item does. A hub only opens
    -- windows: it assigns, saves, shares, spends and enables nothing. Their
    -- scripts reach this file through M, not new upvalues (see menuBtn).
    planBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    planBtn:SetSize(54, 22)
    planBtn:SetText((Nexus.Localization.Text("panel.button.plan")))
    planBtn:SetScript("OnClick", function(self) M.ShowHub("plan", self) end)
    planBtn:SetScript("OnEnter", function(self) M.ShowHubTooltip("plan", self) end)
    planBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Explore holds the shared views: its label is greyed while shared data
    -- loads (LoadingStatus), as the Build Library button's was. The OnEnter
    -- set below replaces the binding's hover hook; the hub hover carries the
    -- loading explanation itself (M.ExploreLoadingLines, C-04).
    exploreBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    exploreBtn:SetSize(62, 22)
    exploreBtn:SetText((Nexus.Localization.Text("panel.button.explore")))
    if Nexus.LoadingStatus then Nexus.LoadingStatus.BindSharedButton(exploreBtn,(Nexus.Localization.Text("panel.button.explore"))) end
    exploreBtn:SetScript("OnClick", function(self) M.ShowHub("explore", self) end)
    exploreBtn:SetScript("OnEnter", function(self) M.ShowHubTooltip("explore", self) end)
    exploreBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local orbsHub = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    orbsHub:SetSize(52, 22)
    orbsHub:SetText((Nexus.Localization.Text("panel.button.orbs")))
    orbsHub:SetScript("OnClick", function(self) M.ShowHub("orbs", self) end)
    orbsHub:SetScript("OnEnter", function(self) M.ShowHubTooltip("orbs", self) end)
    orbsHub:SetScript("OnLeave", function() GameTooltip:Hide() end)
    frame._orbsHubBtn = orbsHub

    -- Options (issue #165): the menu of direct choices, named in words on
    -- header line 1 beside Close (M.PlaceOptionsButton). Navigation stays
    -- visible in the footer while infrequent tools live behind this button.
    menuBtn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    menuBtn:SetText(M.OptionsText(false))
    frame._menuBtn = menuBtn
    M.PlaceOptionsButton()
    menuBtn:SetFrameLevel(frame:GetFrameLevel() + 8)
    -- Its items are built by M.MoreMenuItems when it opens.
    menuBtn:SetScript("OnClick", function(self)
        if type(EasyMenu) ~= "function" then return end
        -- Issue #165: a second click while this button's menu shows closes it
        -- (EasyMenu initializes, hiding the list, before it toggles).
        local shown = M.MenuShownFrom(M._moreMenu, self)
        if type(CloseDropDownMenus) == "function" then CloseDropDownMenus() end
        if shown then return end
        NexusDB = NexusDB or {}
        M._moreMenu = M._moreMenu or CreateFrame("Frame", "NexusPanelMoreMenu", UIParent, "UIDropDownMenuTemplate")
        M.OpenMenu(M.MoreMenuItems(self), M._moreMenu, self)
    end)
    menuBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        -- M4 (UX-15, M3 NB9): one name for this button everywhere: the
        -- hover is headed by its own label, without the notice mark. Issue
        -- #146: while a larger face or a longer label shortens the button,
        -- the complete label is shown once: the heading itself (wrapped)
        -- when the button shows that label, with or without the trusted
        -- "! "; any other button text first, then the heading. Through the
        -- Nexus global and M: no new upvalue in EnsureFrame.
        local metrics = Nexus.LayoutMetrics
        local label, shown = M.OptionsLabel(), tostring(self:GetText() or "")
        local short = metrics and metrics.Shortened and metrics.Shortened(self:GetFontString()) or false
        if short and shown ~= M.OptionsText(false) and shown ~= M.OptionsText(true) then
            GameTooltip:AddLine(shown, 1, 1, 1, true)
        end
        GameTooltip:AddLine(label, 1, 1, 1, short or nil)
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.options_contents"), 0.8, 0.8, 0.8, true)
        -- model.status (Main.lua's statusLine, including "error (see /nexus
        -- err)") was set on every render but never read anywhere in this file --
        -- surfaced here so a real error is visible without knowing the slash
        -- command exists. Inlined with tostring (a global, not an upvalue)
        -- rather than the SafeText helper -- EnsureFrame sits right at Lua
        -- 3.3.5's 60-upvalue-per-function ceiling; SafeText was a new one.
        local lastModel = M._lastModel
        local st = lastModel and lastModel.status
        if st ~= nil and tostring(st) ~= "" then
            GameTooltip:AddLine(" ")
            local displayStatus = M.StatusTooltipText()
            -- Global seam call (EnsureFrame is at the 60-upvalue ceiling); a
            -- status the template cannot hold keeps the exact English line.
            local statusLine, statusSource = Nexus.Localization.Format("panel.tooltip.menu_status",
                {status = displayStatus})
            if statusSource == "unavailable" then statusLine = "Status: " .. displayStatus end
            GameTooltip:AddLine(statusLine, 0.6, 0.85, 1, true)
        end
        local notice = M._lastModel and M._lastModel.updateNotice
        if notice then
            GameTooltip:AddLine(" ")
            -- Only bundled release evidence reaches here (core/Updates.lua).
            GameTooltip:AddLine(Nexus.Localization.Format("panel.tooltip.update_available",
                {version = tostring(notice.display or notice.version)}), 1, 0.82, 0, true)
            GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.update_releases_link"), 0.8, 0.8, 0.8, true)
        end
        GameTooltip:Show()
    end)
    menuBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    bestDpsText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bestDpsText:SetPoint("BOTTOM", frame, "BOTTOM", 0, 33)
    bestDpsText:SetSize(280, 14)
    bestDpsText:SetJustifyH("CENTER")
    bestDpsText:SetText("|cff888888" .. Nexus.Localization.Text("panel.label.best_dps_none") .. "|r")
    bestDpsHit = HitFrame(frame, bestDpsText)
    bestDpsHit:SetScript("OnEnter", function(self)
        local info = M._lastModel and M._lastModel.bestDps
            and M._lastModel.bestDps.info
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.best_dps_heading"), 1, 1, 1)
        if info then
            GameTooltip:AddLine(Nexus.Localization.Format("panel.tooltip.best_dps_record", {dps = FmtDps(info.dps),
                target = (Nexus.Localization.Text(info.category == "lk" and "panel.value.target_lich_king" or "panel.value.target_training_dummy"))}), 0.35, 1, 0.45)
            if info.title then
                local displayText = Nexus and Nexus.Identity
                    and Nexus.Identity.DisplaySafeText
                local title = displayText
                    and displayText(tostring(info.title), 1024, false)
                    or Nexus.Localization.Text("panel.value.invalid_title")
                GameTooltip:AddLine(title, 0.65, 0.85, 1)
            end
        else
            GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.best_dps_none"), 0.7, 0.7, 0.7)
            GameTooltip:AddLine(Nexus.Localization.Text("panel.tooltip.best_dps_how"), 0.9, 0.9, 0.9, true)
        end
        GameTooltip:Show()
    end)
    bestDpsHit:SetScript("OnLeave", function() GameTooltip:Hide() end)

    versionText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    versionText:Hide() -- version remains in /nexus and tooltips; avoids bottom-row overlap

    showPerformance = M.SavedLayoutRoot().uiShowPerformance == true

    pcall(function()
        frame:SetBackdrop({
            bgFile="Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
            tile=true, tileSize=16, edgeSize=12,
            insets={left=3,right=3,top=3,bottom=3},
        })
        frame:SetBackdropColor(0.035, 0.035, 0.05, 0.94)
        frame:SetBackdropBorderColor(0.28, 0.28, 0.34, 0.9)
    end)

    -- The HUD shares appearance with the Orb windows. Its marked difficulty /
    -- Soul Ash child keeps its own backdrop and never joins the theme registry.
    if Nexus.Theme and Nexus.Theme.StyleWindow then Nexus.Theme.StyleWindow(frame, 0.94) end

    frame._footerButtons = {
        auto=autoBtn,plan=planBtn,explore=exploreBtn,orbs=orbsHub,
    }
    M.ApplyOwnedFonts()
    M.InstallPanelDrag()
    return frame
end

-- The root's hide finishes a move, and the passive surfaces EnsureFrame made
-- join it (lazily built ones join where they are made). The counts that open
-- the Wishlist Editor (needHit, toLockHit), the difficulty line and every
-- button keep their own input and are not drag surfaces.
function M.InstallPanelDrag()
    if not frame or frame._nexusDragInstalled then return end
    frame._nexusDragInstalled = true
    -- A shown panel stays shown while a render applies; a failed render
    -- hides it after applying ends, and that hide ends a move as any real
    -- hide does.
    frame:HookScript("OnHide", function()
        if not renderState.applying then M.FinishPanelDrag() end
    end)
    for _, hit in ipairs({frame._chargesHover, frame._recommendationHover, frame._progressLabelHit,
        frame._needLabelHit, frame._shedLabelHit, tomesHit, shedHit, dummyHit, lkHit, bestDpsHit,
        frame._contextTitleHit, frame._contextBuildHit, frame._contextWishlistHit}) do
        M.PassiveDragSurface(hit)
    end
    local row = frame._destinationRow
    for _, hit in ipairs(type(row) == "table" and type(row.hits) == "table" and row.hits or {}) do
        M.PassiveDragSurface(hit)
    end
end

------------------------------------------------------------------------
-- Navigation routes and menus (issue #163, UI review P2-P4). Each entry
-- opens an existing window through its existing route; none assigns, saves,
-- shares, removes, spends, loads a Saved Build or turns Auto ON. Building or
-- showing a menu, a hub tooltip or a status line only reads.
------------------------------------------------------------------------

local function ProtectVisiblePlanRoute()
    local plan = _G.NexusEditorFrame
    if not (plan and plan.IsShown and plan:IsShown()) then return true, false end
    local editor = Nexus.WishlistEditor
    if not (editor and type(editor.SuspendForWorkspace) == "function") then
        print("|cffffd200Nexus:|r " .. LT("panel.chat.plan_protection_unavailable"))
        return false, false
    end
    local allowed, reason = editor.SuspendForWorkspace()
    if not allowed then
        print("|cffffd200Nexus:|r " .. tostring(reason and Nexus.UserText.Recognized(reason) or LT("panel.chat.plan_action_open")))
        return false, false
    end
    return true, true
end

local function FinishPlanRoute(suspended, opened)
    if not suspended then return end
    local plan = _G.NexusEditorFrame
    local editor = Nexus.WishlistEditor
    if plan and plan.IsShown and plan:IsShown()
        and editor and editor.CancelWorkspaceSuspend then
        editor.CancelWorkspaceSuspend()
    elseif opened == false and editor and editor.ResumeWorkspaceDraft then
        -- The game button can disappear or refuse its click after the
        -- availability precheck has run the close callback. Restore Plan on
        -- that refusal; its suspended draft is still bound to the context.
        local restored, reason = editor.ResumeWorkspaceDraft()
        if not restored then
            print("|cffffd200Nexus:|r " .. LT("panel.chat.plan_not_reopened") .. " "
                .. tostring(reason and Nexus.UserText.Recognized(reason) or LT("panel.chat.plan_resume_draft")))
        end
    end
end

-- The game's own My Builds page (the header button and the Plan hub).
function M.OpenMyBuilds()
    local allowed, suspended = ProtectVisiblePlanRoute()
    if not allowed then return false end
    if Nexus.JournalTab and Nexus.JournalTab.OpenBuilds then
        -- Only dismiss the workspace after the live Character Progression
        -- entry has been found. A missing game button must not discard an
        -- unsaved Plan draft just because My Builds was requested.
        local opened, why = Nexus.JournalTab.OpenBuilds(false, CloseOtherNexusWindows)
        if opened == false and why == "unavailable" then
            print("|cffff6060Nexus:|r " .. LT("panel.chat.my_builds_button_missing"))
        end
        FinishPlanRoute(suspended, opened)
        return opened
    else
        -- The journal's Show(tab) is a dot-call whose argument is a tab
        -- index; no tab is established here, so none is passed (the
        -- journal opens its current tab).
        local pe = _G["ProjectEbonhold"]
        if pe and pe.EchoJournal and pe.EchoJournal.Show then
            local ok = pcall(pe.EchoJournal.Show)
            if ok then CloseOtherNexusWindows() end
            FinishPlanRoute(suspended, ok)
            return ok
        end
        FinishPlanRoute(suspended, false)
        return false
    end
end

-- Assign Wishlist (the setup view's button and the Plan hub).
function M.OpenAssignment()
    local allowed, suspended = ProtectVisiblePlanRoute()
    if not allowed then return false end
    local journal = Nexus.JournalTab
    if journal and journal.OpenBuilds then
        -- The present helper is the route: the Echo Journal with the
        -- Wishlist chooser opened for the Saved Build the Journal targets
        -- (nothing is assigned until one is chosen). It closes the other
        -- Nexus windows only once the game's Character Progression entry
        -- is there, so a refusal loses nothing and is said here.
        local opened, why = journal.OpenBuilds(true, CloseOtherNexusWindows)
        if opened == false and why == "unavailable" then
            print("|cffff6060Nexus:|r " .. LT("panel.chat.assignment_button_missing"))
        end
        FinishPlanRoute(suspended, opened)
        return opened
    else
        -- Show(tab) is a dot-call taking a tab index; no tab is passed
        -- (the journal opens its current tab).
        local pe = _G["ProjectEbonhold"]
        if pe and pe.EchoJournal and pe.EchoJournal.Show then
            local ok = pcall(pe.EchoJournal.Show)
            if ok then CloseOtherNexusWindows() end
            FinishPlanRoute(suspended, ok)
            return ok
        end
        FinishPlanRoute(suspended, false)
        return false
    end
end

local function OpenEditor()
    CloseOtherNexusWindows()
    if Nexus.WishlistEditor then Nexus.WishlistEditor.Show() end
end

local function OpenBuildLibrary()
    CloseOtherNexusWindows()
    if Nexus.CommunityBuilds then Nexus.CommunityBuilds.Show() end
end

local function OpenLeaderboard()
    CloseOtherNexusWindows()
    if Nexus.Leaderboard then Nexus.Leaderboard.Show() end
end

-- A menu click closes the menu first.
local function MenuAction(fn)
    return function()
        if type(CloseDropDownMenus) == "function" then CloseDropDownMenus() end
        fn()
    end
end

-- A section title may carry a stable semantic identity (nexusSection), and
-- a row its own (nexusId), so another window (ui/SettingsWindow.lua) selects
-- them without reading their shown, possibly translated, text.
local function MenuTitle(text, section)
    return {text = text, isTitle = true, notCheckable = true, nexusSection = section}
end
local function MenuNote(text) return {text = text, notCheckable = true, disabled = true} end

-- Options > Main panel size (issue #170): the chosen size, one 5% step either
-- way, five sizes and Reset to 100%. Building it only reads; a row click is
-- the one place a size is chosen. While the screen holds less, the list says
-- so and the choice stays.
function M.PanelSizeMenuItem()
    local status = M.PanelScaleStatus()
    local function Percent(v) return math.floor(v * 100 + 0.5) .. "%" end
    local rows = {}
    if status.reduced then
        rows[#rows + 1] = MenuNote(LF("panel.menu.size_reduced", {percent = Percent(status.effective)}))
    end
    rows[#rows + 1] = { text = LT("panel.menu.size_larger"), notCheckable = true, disabled = status.requested >= SCALE_MAX,
        func = MenuAction(function() M.StepPanelScale(1) end) }
    rows[#rows + 1] = { text = LT("panel.menu.size_smaller"), notCheckable = true, disabled = status.requested <= SCALE_MIN,
        func = MenuAction(function() M.StepPanelScale(-1) end) }
    for _, size in ipairs({0.5, 0.75, 1, 1.25, 1.5}) do
        rows[#rows + 1] = { text = Percent(size), checked = math.abs(status.requested - size) < 0.001,
            func = MenuAction(function() M.SetPanelScale(size) end) }
    end
    rows[#rows + 1] = { text = LT("panel.menu.size_reset"), notCheckable = true,
        func = MenuAction(function() M.ResetPanelScale() end) }
    return { text = LF("panel.menu.size_row", {percent = Percent(status.requested)}), notCheckable = true, hasArrow = true,
        menuList = rows, tooltipTitle = LT("panel.tooltip.size_title"),
        tooltipText = LT("panel.tooltip.size_explained") }
end

local function Say(kind, detail)
    local readout = Nexus.Readout
    if readout and type(readout.StatusText) == "function" then return readout.StatusText(kind, detail) end
    return tostring(detail or kind)
end

-- The shared data's state in the status vocabulary, from the start-up
-- snapshot the loading panel reads (Nexus.StartupStatus). Local Wishlist
-- tools are said ready only when that snapshot says so. Read only.
function M.SharedDataLine()
    local ok, status = false, nil
    if type(Nexus.StartupStatus) == "function" then ok, status = pcall(Nexus.StartupStatus) end
    if not ok or type(status) ~= "table" then return Say("unknown", LT("panel.status.shared_data")) end
    if status.state == "ready" then return Say("ready", LT("panel.status.shared_data")) end
    if status.state == "failed" then
        return Say("unavailable", LF("panel.status.shared_data_failed", {command = "/nexus status"}))
    end
    return Say("loading", LT(status.coreReady == true
        and "panel.status.shared_data_local_ready" or "panel.status.shared_data_local_wait"))
end

-- C-04: the explanation LoadingStatus.BindSharedButton gives a shared-view
-- button while its data is not ready (the view, the current step, what stays
-- available), in its own words and colours, for the Explore hub's hover.
-- EnsureFrame binds Explore before setting its OnEnter, which replaces that
-- hook, so the hub hover carries the explanation itself. Ready, or a status
-- that cannot be read, adds nothing. Reads only.
function M.ExploreLoadingLines()
    local loading = Nexus.LoadingStatus
    if not (loading and type(loading.PhaseText) == "function") then return {} end
    local ok, status = false, nil
    if type(Nexus.StartupStatus) == "function" then ok, status = pcall(Nexus.StartupStatus) end
    if not ok or type(status) ~= "table" or status.state == "ready" then return {} end
    return {
        {LF(status.state == "failed" and "loading.tooltip.view_unavailable" or "loading.tooltip.view_loading",
            {view = LT("panel.button.explore")}), .65, .65, .68},
        {loading.PhaseText(status), .9, .9, .9, true},
        {LT(status.coreReady and "loading.tooltip.local_tools_available"
            or "loading.tooltip.local_tools_unlock"), .8, .8, .8, true},
    }
end

-- The Orb run for the Orbs hub, from the passive reason view the setup
-- checklist reads (OrbFacts), and only once local start-up is ready. An
-- unread state is unknown, not "no run"; a pending offer is not a result,
-- and one restored after a reload is unconfirmed, never spent or confirmed.
function M.OrbHubLine()
    local okReady, ready = false, nil
    if type(Nexus.StartupStatus) == "function" then okReady, ready = pcall(Nexus.StartupStatus) end
    local runtime = Nexus.OrbRuntime
    if not (okReady and type(ready) == "table" and ready.coreReady == true and runtime) then
        return Say("unknown", LT("panel.status.orb_not_read_yet"))
    end
    local okOrb, orb, observed = pcall(OrbFacts, runtime)
    if not okOrb or orb == nil then
        return Say("unknown", LT(observed == false and "panel.status.orb_not_read_session"
            or "panel.status.orb_unreadable"))
    end
    if orb == false then return LT("panel.status.orb_none_approved") end
    local history = Nexus.OrbHistory
    local states = history and type(history.RUN_STATES) == "table" and history.RUN_STATES or {}
    -- The state's meaning through its key (OrbHistory.RUN_STATE_KEYS); the
    -- English label table only without one.
    local stateKeys = history and type(history.RUN_STATE_KEYS) == "table" and history.RUN_STATE_KEYS or {}
    local stateText = orb.state and (stateKeys[orb.state] and LT(stateKeys[orb.state]) or states[orb.state]
        or LF("panel.status.orb_state_undescribed", {state = tostring(orb.state)}))
        or LT("panel.status.orb_state_not_recorded")
    -- A restored receipt can precede the offer, selection and result. Do not
    -- call it a previous result merely because recovery is active.
    if orb.state == "RECOVERY" and orb.pending and orb.restored then
        stateText = LT("panel.status.orb_earlier_unresolved")
    end
    local text = LF("panel.status.orb_run", {state = tostring(stateText)})
    if orb.pending and orb.restored then
        text = text .. "; " .. Say("unconfirmed", LT("panel.status.orb_action_before_reload"))
    elseif orb.pending and orb.state == "WAIT_RESULT" then
        text = text .. "; " .. Say("awaiting")
    elseif orb.pending and orb.state ~= "WAIT_OFFER" then
        text = text .. "; " .. LT("panel.status.orb_action_may_settle")
    end
    return text
end

-- How a hidden panel comes back, and the Hide row's hover (resolved when
-- shown; "/nexus panel" is the command and is never translated).
local function HideNote()
    return LF("panel.tooltip.hide_note", {command = "/nexus panel"})
end
local function HideTooltip()
    return LT("panel.tooltip.hide_panel") .. " " .. HideNote()
end

-- Owner-approved item 8 (issue #164): the player's own hide from the panel
-- (its X or Options > Hide Nexus Panel). It hides as M.Hide does, and only
-- when it really hides the panel the player wanted shown it says once, in
-- chat, how the panel comes back, and lights the Nexus minimap button until
-- the panel is shown again or that button is pointed at. A second hide of an
-- already hidden panel says nothing more. Auto, the pause and every other
-- setting stay as they are; /nexus panel stays the command (not /nexus).
function M.HideByPlayer()
    LoadWantedVisibility()
    local wanted = panelWantedVisible
    M.Hide()
    if not wanted then return false end
    print("|cffffd200Nexus:|r " .. LF("panel.chat.panel_hidden_restore", {
        hidden = "|cffffffff" .. LT("panel.chat.panel_hidden") .. "|r",
        command = "|cffffffff/nexus panel|r"}))
    M.CueMinimapRestore(true)
    return true
end

-- Owner-approved item 15 (issue #169): the panel's direct FAQ shortcut, a
-- small "?" at the right end of the footer, beside the hubs and away from
-- Options and Close on header line 1 (design/current keeps that line to
-- Auto, Options and Close). It opens the existing FAQ page through Help's
-- own route, Help.Show("faq"), exactly as Options > Questions (FAQ) does;
-- the FAQ content and its styling stay Help's. Its hover also says where
-- the panel's numbers are explained (owner-approved item 14): each number's
-- own hover, with the facts that hover already carries. Opening the FAQ
-- reads only; it works while Nexus is paused. Built lazily (EnsureFrame is
-- at the upvalue ceiling).
function M.ShowFaq()
    local help = Nexus.Help
    if not (help and type(help.Show) == "function") then return false end
    help.Show("faq")
    return true
end
M.NUMBERS_HINT = "What a number means: point at it. The difficulty card shows the difficulty, Soul Ash, its "
    .. "multiplier and Intensity; a count lists its Echoes; a DPS row shows its records."
function M.EnsureFaqButton()
    if not frame then return nil end
    local faq = frame._faqBtn
    if faq then return faq end
    faq = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    faq:SetText("?")
    faq:SetScript("OnClick", function()
        if type(CloseDropDownMenus) == "function" then CloseDropDownMenus() end
        M.ShowFaq()
    end)
    faq:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
        GameTooltip:AddLine(LT("panel.tooltip.faq_title"), 1, 1, 1)
        GameTooltip:AddLine(LT("panel.tooltip.faq_opening"), 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine(LT("panel.tooltip.numbers_hint"), 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    faq:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    if Nexus.Theme and Nexus.Theme.StyleButton then pcall(Nexus.Theme.StyleButton, faq) end
    frame._faqBtn = faq
    return faq
end

-- The minimap button's restore cue: its own highlight, held while the panel
-- is hidden by the player. Memory only; no timer, frame update or saved data.
function M.CueMinimapRestore(on)
    local btn = minimapBtn
    M._restoreCue = on and true or nil
    if not btn then return false end
    local method = on and btn.LockHighlight or btn.UnlockHighlight
    if type(method) == "function" then pcall(method, btn) end
    return true
end

-- The Play header's close control (Claude Design full UI: "... and X" on
-- header line 1): it hides the panel exactly as Hide Nexus Panel does, and
-- its hover says that closing is not pausing. Built lazily (EnsureFrame is
-- at the upvalue ceiling) in the header's free right corner, clear of the
-- header Auto control.
function M.EnsureHeaderClose()
    if not frame then return nil end
    local close = frame._closeBtn
    if not close then
        close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        close:SetText("X")
        close:SetFrameLevel(frame:GetFrameLevel() + 8)
        close:SetScript("OnClick", function() M.HideByPlayer() end)
        close:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:AddLine(LT("panel.tooltip.close_panel"), 1, 1, 1)
            GameTooltip:AddLine(HideNote(), 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        close:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        if Nexus.Theme and Nexus.Theme.StyleButton then pcall(Nexus.Theme.StyleButton, close) end
        frame._closeBtn = close
    end
    local slots = M.HeaderSlots()
    close:ClearAllPoints()
    close:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -slots.edge, -slots.top)
    close:SetSize(slots.closeWidth, slots.height)
    close:Show()
    return close
end

-- The visible drag grip (design/current "Nexus Main Panel - Compact
-- Redesign"; design/PANEL_DIFFICULTY_SOURCE_REFERENCE.md "Discoverable panel
-- drag handle"): six dots in the header's left corner with a hover highlight
-- and a "Drag to move" tooltip. A plain left drag moves the panel through its
-- one drag owner (issue #168: M.BeginPanelDrag, clamped to the screen;
-- panelX / panelY saved as before), like the background and every passive
-- label; Shift is not needed. A plain click does nothing. Built lazily
-- (EnsureFrame is at the upvalue ceiling). Its dots are fixed colours, never
-- from the palette. Native pointer capture while dragging is NOT RUN.
function M.EnsureHeaderGrip()
    if not frame then return nil end
    local grip = frame._dragGrip
    if not grip then
        grip = CreateFrame("Button", nil, frame)
        grip._nexusThemeExempt = true
        grip:SetFrameLevel(frame:GetFrameLevel() + 8)
        grip:EnableMouse(true)
        grip:RegisterForDrag("LeftButton")
        grip.edge = grip:CreateTexture(nil, "BORDER")
        grip.edge:SetAllPoints()
        grip.edge:SetTexture(0.32, 0.32, 0.38, 0.55)
        grip.fill = grip:CreateTexture(nil, "ARTWORK")
        grip.fill:SetPoint("TOPLEFT", grip, "TOPLEFT", 1, -1)
        grip.fill:SetPoint("BOTTOMRIGHT", grip, "BOTTOMRIGHT", -1, 1)
        grip.fill:SetTexture(0.03, 0.03, 0.05, 0.9)
        grip.dots = {}
        for row = 1, 3 do
            for column = 1, 2 do
                local dot = grip:CreateTexture(nil, "OVERLAY")
                dot:SetSize(3, 3)
                dot:SetPoint("TOPLEFT", grip, "TOPLEFT", 6 + (column - 1) * 6, -5 - (row - 1) * 5)
                dot:SetTexture(0.72, 0.72, 0.78, 1)
                grip.dots[#grip.dots + 1] = dot
            end
        end
        local hover = grip:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetTexture(1, 1, 1, 0.12)
        grip.hover = hover
        grip:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
            GameTooltip:AddLine(LT("panel.tooltip.drag_title"), 1, 1, 1)
            GameTooltip:AddLine(LT("panel.tooltip.drag_explained"),
                0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        grip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        M.PassiveDragSurface(grip)
        frame._dragGrip = grip
    end
    local slots = M.HeaderSlots()
    grip:ClearAllPoints()
    grip:SetPoint("TOPLEFT", frame, "TOPLEFT", slots.gripX, -slots.top)
    grip:SetSize(slots.gripWidth, slots.height)
    grip:Show()
    return grip
end

-- The Options menu (owner-approved items 2 and 9, issue #165): a short top
-- level, grouped under titles. The everyday choices stay direct (the FAQ, the
-- guided setup, Auto explained, every setting, the session pause and the
-- panel); the optional windows wait one level down under "More help and
-- windows", each under its own label with its own guarded route. The former
-- "Help / Getting Started" entry opened the same coach at the same step as
-- Setup / Welcome (Help.OpenGuide and GuidedSetupUI.Show), so the coach has
-- one entry, Setup / Welcome, the name the guide, Help and the setup chat
-- lines already use. A setting row keeps its action words, which other
-- windows quote ("Show DPS records", "Use Server Difficulty / Soul Ash HUD"),
-- and adds the current value ("Show DPS records (now hidden)"); a row that
-- acts is never ticked, and a tick marks only the current choice inside a
-- list. Appearance keeps its direct entry
-- (design/current "Nexus Main Panel - Compact Redesign"). Opening it only
-- reads current labels and never changes a setting or starts automation.
-- No fixed row cap is assumed: the 3.3.5a export of UIDropDownMenu.lua starts
-- with 8 buttons per level and creates further rows as items are added
-- (build 12340, UIDropDownMenu.lua L1-5 and L178-229). Whether the whole
-- top level fits the screen at a given UI scale is a native check, not
-- established here.
function M.MoreMenuItems(anchor)
    local items = {}
    local function Add(item) items[#items + 1] = item end
    Add(MenuTitle(LT("panel.menu.section_help"), "help"))
    -- Short answers (also the panel's "?" button, M.ShowFaq).
    Add({ text = LT("panel.menu.faq"), notCheckable = true,
        tooltipTitle = LT("panel.tooltip.faq_title"),
        tooltipText = LT("panel.tooltip.faq_reading"),
        func = MenuAction(function() M.ShowFaq() end) })
    -- Setup / Welcome is the guided setup coach itself, as /nexus help and
    -- Help's own Setup / Welcome (the original guided design: "Reopen: Nexus
    -- menu > Setup / Welcome"). It resumes at the step it left, with its
    -- choices read again from what Nexus lists and every result checked again
    -- (core/GuidedSetup.lua). Opening it assigns, saves, sends, spends and
    -- changes Auto nothing. It does not open over an Auto warning that waits
    -- for its answer, says so and queues nothing.
    Add({ text = LT("panel.menu.setup_welcome"), notCheckable = true,
        tooltipTitle = LT("panel.tooltip.setup_welcome_title"),
        tooltipText = LF("panel.tooltip.setup_welcome_explained", {command = "/nexus help"}),
        func = MenuAction(function()
            local ui = Nexus.GuidedSetupUI
            local shown, why
            if ui and ui.Show then shown, why = ui.Show() end
            if not shown then
                print("|cffffd200Nexus:|r " .. LT(why == "warning-open"
                    and "panel.chat.setup_welcome_warning_open"
                    or "panel.chat.setup_welcome_unavailable"))
            end
        end) })
    -- Issue #169: the complete Auto explanation (every permission with its
    -- current value, the hold and each consequence). Reading it changes nothing.
    Add({ text = LT("panel.menu.auto_explained"), notCheckable = true,
        tooltipTitle = LT("panel.tooltip.auto_explained_title"),
        tooltipText = LT("panel.tooltip.auto_explained_body"),
        func = MenuAction(function() if Nexus.Help then Nexus.Help.Show("rolling") end end) })
    Add({ text = LT("panel.menu.more_windows"), notCheckable = true, hasArrow = true,
        tooltipTitle = LT("panel.tooltip.more_windows_title"),
        tooltipText = LT("panel.tooltip.more_windows_body"),
        menuList = M.MoreWindowsItems() })

    Add(MenuTitle(LT("panel.menu.section_settings"), "settings"))
    -- design/current "Nexus Main Panel - Compact Redesign": Options opens
    -- Appearance directly. Its list is the shared Theme choice
    -- (Theme.MenuItems: the same saved style and colour the Orb windows use),
    -- the current one checked; building the menu writes nothing, and only a
    -- row click chooses (Theme.SetStyle / SetPalette through the settings
    -- owner).
    local appearance = { text = LF("panel.menu.appearance", {summary = tostring((Nexus.Theme and Nexus.Theme.Summary)
            and Nexus.Theme.Summary() or LT("panel.value.appearance_default"))}), notCheckable = true,
        tooltipTitle = LT("panel.tooltip.appearance_title"), tooltipText = Nexus.Theme and Nexus.Theme.HELP or nil }
    if Nexus.Theme and type(Nexus.Theme.MenuItems) == "function" then
        appearance.hasArrow = true
        appearance.menuList = Nexus.Theme.MenuItems(CloseDropDownMenus)
    else
        appearance.disabled = true
    end
    Add(appearance)
    Add({ text = LT("panel.menu.open_settings"), notCheckable = true,
        tooltipTitle = LT("panel.tooltip.settings_title"),
        tooltipText = LT("panel.tooltip.settings_body"),
        func = MenuAction(function()
            if Nexus.SettingsWindow and Nexus.SettingsWindow.Show then
                Nexus.SettingsWindow.Show()
            end
        end) })
    -- What Auto may do, with each permission's current value; only the
    -- existing setters change one (M.AutomationMenuItems).
    Add({ text = LT("panel.menu.automation_settings"), notCheckable = true, hasArrow = true,
        menuList = M.AutomationMenuItems(MenuAction) })
    -- Issue #123: the Nexus-only language chooser (M.LanguageMenuItems).
    -- Building and showing it reads only; a row click is the one place a
    -- choice is submitted, through the lifecycle callback.
    Add({ text = M.LanguageMenuLabel(), notCheckable = true, hasArrow = true,
        menuList = M.LanguageMenuItems(MenuAction) })
    Add({ text = LT(showPerformance and "panel.menu.dps_records_hide" or "panel.menu.dps_records_show"),
        notCheckable = true, nexusId = "dps_records",
        tooltipTitle = LT("panel.tooltip.dps_records_title"),
        tooltipText = LT("panel.tooltip.dps_records_body"),
        func = MenuAction(function()
            showPerformance = not showPerformance
            M.SavedLayoutRoot().uiShowPerformance = showPerformance
            if M.Refresh then M.Refresh() end
        end) })
    Add(M.HudModeMenuItem())

    Add(MenuTitle(LT("panel.menu.section_notices"), "notices"))
    -- Never disabled: the Releases page and the installed build are
    -- available with no report, no peer and no Community catalog.
    Add({ text = (Nexus.Updates and Nexus.Updates.Status)
            and Nexus.Updates.Status().menu or LT("panel.menu.open_releases"),
        notCheckable = true,
        func = MenuAction(function() M.ShowUpdateStatus() end) })
    Add(M.UpdateNoticesMenuItem())

    Add(MenuTitle(LT("panel.menu.section_session"), "session"))
    for _, item in ipairs(M.SessionMenuItems()) do Add(item) end

    Add(MenuTitle(LT("panel.menu.section_panel"), "panel"))
    Add(M.PanelSizeMenuItem())
    Add({ text = LT("panel.menu.reset_position"), notCheckable = true,
        func = MenuAction(function()
            local saved = M.SavedLayoutRoot()
            saved.panelX, saved.panelY = nil, nil
            M._restorePlacement = nil
            frame:ClearAllPoints()
            frame:SetPoint("RIGHT", UIParent, "RIGHT", -40, 0)
            M.PlacePauseBanner()
        end) })
    -- Hiding is not pausing: it says how the panel comes back.
    Add({ text = LT("panel.menu.hide_panel"), notCheckable = true,
        tooltipTitle = LT("panel.tooltip.hide_panel_title"), tooltipText = HideTooltip(),
        func = MenuAction(function() M.HideByPlayer() end) })
    return items
end

-- Options > More help and windows: the optional windows, each its existing
-- route under its own label. Each only opens a window; nothing is assigned,
-- saved, sent or spent by opening one.
function M.MoreWindowsItems()
    local rows = {}
    local function Add(item) rows[#rows + 1] = item end
    -- The optional long manual (ui/Help.lua pages, also /nexus reference),
    -- from its first page. Read only; its own buttons only navigate.
    Add({ text = LT("panel.menu.reference"), notCheckable = true,
        tooltipTitle = LT("panel.tooltip.reference_title"),
        tooltipText = LF("panel.tooltip.reference_body", {command = "/nexus reference"}),
        func = MenuAction(function() if Nexus.Help then Nexus.Help.Show("start") end end) })
    -- Secondary reference: the information-only overview of the entry
    -- routes (QuickStart.ShowSetup). It records nothing and never turns Auto
    -- ON; its own Guided setup button opens the coach.
    Add({ text = LT("panel.menu.setup_information"), notCheckable = true,
        tooltipTitle = LT("panel.tooltip.setup_information_title"),
        tooltipText = LT("panel.tooltip.setup_information_body"),
        func = MenuAction(function()
            local quick = Nexus.QuickStart
            local shown, why
            if quick and quick.ShowSetup then shown, why = quick.ShowSetup() end
            if not shown then
                print("|cffffd200Nexus:|r " .. LT(why == "warning-open"
                    and "panel.chat.setup_information_warning_open"
                    or "panel.chat.setup_information_unavailable"))
            end
        end) })
    -- Read-only: what Nexus can read now about setup and status
    -- (QuickStart.ShowChecklist); it completes nothing for you.
    Add({ text = LT("panel.menu.setup_checklist"), notCheckable = true,
        func = MenuAction(function()
            if Nexus.QuickStart and Nexus.QuickStart.ShowChecklist then Nexus.QuickStart.ShowChecklist() end
        end) })
    -- The page /nexus report opens. Opening it reads; only its own Prepare
    -- report file writes, to the separate support storage.
    Add({ text = LT("panel.menu.support_report"), notCheckable = true,
        func = MenuAction(function()
            if Nexus.SupportReportUI and Nexus.SupportReportUI.Show then
                Nexus.SupportReportUI.Show()
            else
                print("|cffff6060Nexus:|r " .. LT("panel.chat.support_report_not_loaded"))
            end
        end) })
    -- The viewer /nexus log opens; opening it changes nothing.
    Add({ text = LT("panel.menu.log_viewer"), notCheckable = true,
        func = MenuAction(function() if Nexus.LogViewer and Nexus.LogViewer.Show then Nexus.LogViewer.Show() end end) })
    -- The same windows as the footer's Orbs and Plan, under their old labels.
    Add({ text = LT("panel.menu.orbs"), notCheckable = true,
        tooltipTitle = LT("panel.tooltip.orbs_heading"), tooltipText = LT("panel.tooltip.orbs_also_footer"),
        func = MenuAction(function() if Nexus.OrbPanel then Nexus.OrbPanel.Show() end end) })
    Add({ text = LT("panel.menu.wishlist_editor"), notCheckable = true,
        tooltipTitle = LT("panel.tooltip.wishlist_editor_title"), tooltipText = LT("panel.tooltip.wishlist_editor_also_plan"),
        func = MenuAction(OpenEditor) })
    return rows
end

-- Options > the difficulty / Soul Ash HUD choice: the switch, then which HUD
-- shows now. Without a detected game HUD the choice is disabled and says so;
-- without its owner the HUD in use is not known. Reads only.
function M.HudModeMenuItem()
    local status = Nexus.ServerStatus
    if not (status and type(status.IsDetected) == "function" and type(status.IsUsingNexusHud) == "function") then
        return { text = LT("panel.menu.hud_not_known"), notCheckable = true, disabled = true,
            nexusId = "hud_mode" }
    end
    local nexus = status.IsUsingNexusHud() and true or false
    if not status.IsDetected() then
        return { text = LT(nexus and "panel.menu.hud_use_server_undetected" or "panel.menu.hud_use_nexus_undetected"),
            notCheckable = true, disabled = true, nexusId = "hud_mode" }
    end
    return { text = LT(nexus and "panel.menu.hud_use_server_now_nexus" or "panel.menu.hud_use_nexus_now_server"),
        notCheckable = true, nexusId = "hud_mode",
        func = MenuAction(function()
            if Nexus.ServerStatus then
                Nexus.ServerStatus.SetMode(Nexus.ServerStatus.IsUsingNexusHud() and "server" or "nexus")
            end
        end) }
end

-- Options > Update notices: the current state on the row itself and two
-- small choices inside it, each ticked at its current value: notices on or
-- off (Updates.SetEnabled) and which builds are announced
-- (Updates.SetPreference). Each row calls only its own existing setter, so
-- the announced builds are kept while notices are off. Reads only until a
-- row is clicked.
function M.UpdateNoticesMenuItem()
    local updates = Nexus.Updates
    if not (updates and type(updates.IsEnabled) == "function" and type(updates.Preference) == "function"
        and type(updates.SetEnabled) == "function" and type(updates.SetPreference) == "function") then
        return { text = LT("panel.menu.notices_unavailable"), notCheckable = true, disabled = true }
    end
    local enabled = updates.IsEnabled() and true or false
    local stable = updates.Preference() == "stable"
    local row = not enabled and "panel.menu.notices_row_off"
        or (stable and "panel.menu.notices_row_on_stable" or "panel.menu.notices_row_on_test")
    return { text = LT(row), notCheckable = true,
        hasArrow = true, tooltipTitle = LT("panel.tooltip.notices_title"),
        tooltipText = LT("panel.tooltip.notices_body"),
        menuList = {
            MenuTitle(LT("panel.menu.notices_title")),
            { text = LT("panel.menu.notices_on"), checked = enabled, func = MenuAction(function() updates.SetEnabled(true) end) },
            { text = LT("panel.menu.notices_off"), checked = not enabled, func = MenuAction(function() updates.SetEnabled(false) end) },
            MenuTitle(LT(enabled and "panel.menu.notices_announce" or "panel.menu.notices_announce_when_on")),
            { text = LT("panel.menu.notices_stable_and_test"), checked = not stable,
                func = MenuAction(function() updates.SetPreference("test") end) },
            { text = LT("panel.menu.notices_stable_only"), checked = stable,
                func = MenuAction(function() updates.SetPreference("stable") end) },
        } }
end

-- The Plan and Explore hub menus. Each consequence note is a visible row:
-- the 3.3.5 dropdown shows item tooltips only with beginner tips on.
function M.HubMenuItems(kind)
    local L = Nexus.Localization
    local function Text(key) return L and type(L.Text) == "function" and (L.Text(key)) or nil end
    local items = {}
    local function Add(item) items[#items + 1] = item end
    if kind == "plan" then
        Add(MenuTitle(Text("panel.menu.plan_title")))
        Add({ text = Text("panel.menu.wishlist_editor"), notCheckable = true, tooltipTitle = Text("panel.tooltip.wishlist_editor_title"),
            tooltipText = Text("panel.tooltip.create_wishlist_draft"), func = MenuAction(OpenEditor) })
        Add({ text = Text("panel.menu.assign_wishlist"), notCheckable = true, tooltipTitle = Text("panel.tooltip.assignment_heading"),
            tooltipText = Text("panel.tooltip.assignment_chooser"), func = MenuAction(M.OpenAssignment) })
        Add({ text = Text("panel.menu.my_builds_game_page"), notCheckable = true, tooltipTitle = Text("panel.tooltip.open_my_builds"),
            tooltipText = Text("panel.tooltip.my_builds_destination"), func = MenuAction(M.OpenMyBuilds) })
        Add(MenuNote(Text("panel.note.plan_opens_only")))
    elseif kind == "explore" then
        Add(MenuTitle(Text("panel.menu.explore_title")))
        Add({ text = Text("panel.menu.build_library"), notCheckable = true, tooltipTitle = Text("panel.tooltip.build_library_title"),
            tooltipText = Text("panel.tooltip.build_library_body"),
            func = MenuAction(OpenBuildLibrary) })
        Add({ text = Text("panel.menu.leaderboard"), notCheckable = true, tooltipTitle = Text("panel.tooltip.leaderboard_title"),
            tooltipText = Text("panel.tooltip.leaderboard_body"), func = MenuAction(OpenLeaderboard) })
        Add(MenuNote(M.SharedDataLine()))
        Add(MenuNote(Text("panel.note.best_known_scope")))
    end
    return items
end

-- The lines of a hub's hover, title first. Reads only.
function M.HubTooltipLines(kind)
    if kind == "plan" then
        return {LT("panel.tooltip.plan_title"), LT("panel.tooltip.plan_contents"),
            LT("panel.tooltip.plan_opens_only")}
    elseif kind == "explore" then
        return {LT("panel.tooltip.explore_title"), LT("panel.tooltip.explore_build_library"),
            LT("panel.tooltip.explore_leaderboard"), M.SharedDataLine(),
            LT("panel.note.best_known_scope")}
    elseif kind == "orbs" then
        return {LT("panel.tooltip.orbs_heading"), LT("panel.tooltip.orbs_open_inspect"),
            M.OrbHubLine(),
            LT("panel.tooltip.orbs_closing_continues")}
    end
    return {}
end

-- A hub's hover stands beside the panel, never over its own content: right of
-- the panel when the screen has room for the whole tooltip there, else left,
-- else above, else below (in screen units, any scale); with no room anywhere
-- it stays right of the panel and the client keeps it on screen. Every line
-- is shown whole (wrapped). M._hubTipPlacement records the side used.
function M.ShowHubTooltip(kind, owner)
    if not GameTooltip then return end
    local panel = _G.NexusPanel
    GameTooltip:SetOwner(owner, panel and "ANCHOR_NONE" or "ANCHOR_TOP")
    for index, line in ipairs(M.HubTooltipLines(kind)) do
        if index == 1 then GameTooltip:AddLine(line, 1, 1, 1)
        else GameTooltip:AddLine(line, 0.85, 0.85, 0.85, true) end
    end
    -- C-04: while shared data loads, Explore's hover also gives the loading
    -- explanation (M.ExploreLoadingLines), placed with the rest.
    if kind == "explore" then
        for _, line in ipairs(M.ExploreLoadingLines()) do
            GameTooltip:AddLine(line[1], line[2], line[3], line[4], line[5])
        end
    end
    GameTooltip:Show()
    if not panel then M._hubTipPlacement = "top"; return end
    local function Read(region, method)
        local ok, value = pcall(region[method], region)
        return ok and tonumber(value) or nil
    end
    local ps = Read(panel, "GetEffectiveScale") or 1
    local ts = Read(GameTooltip, "GetEffectiveScale") or 1
    local us = Read(UIParent, "GetEffectiveScale") or 1
    local left, right = (Read(panel, "GetLeft") or 0) * ps, (Read(panel, "GetRight") or 0) * ps
    local top, bottom = (Read(panel, "GetTop") or 0) * ps, (Read(panel, "GetBottom") or 0) * ps
    local w, h = (Read(GameTooltip, "GetWidth") or 0) * ts, (Read(GameTooltip, "GetHeight") or 0) * ts
    local sw, sh = (Read(UIParent, "GetWidth") or 0) * us, (Read(UIParent, "GetHeight") or 0) * us
    local gap = 4 * ps
    local where
    if sw - right >= w + gap then where = "right"
    elseif left >= w + gap then where = "left"
    elseif sh - top >= h + gap then where = "above"
    elseif bottom >= h + gap then where = "below"
    else where = "right" end
    GameTooltip:ClearAllPoints()
    if where == "right" then GameTooltip:SetPoint("BOTTOMLEFT", panel, "BOTTOMRIGHT", 4, 0)
    elseif where == "left" then GameTooltip:SetPoint("BOTTOMRIGHT", panel, "BOTTOMLEFT", -4, 0)
    elseif where == "above" then GameTooltip:SetPoint("BOTTOMLEFT", panel, "TOPLEFT", 0, 4)
    else GameTooltip:SetPoint("TOPLEFT", panel, "BOTTOMLEFT", 0, -4) end
    M._hubTipPlacement = where
end

-- A hub click: Orbs opens the Orb window (passive, as Open Orbs...); Plan
-- and Explore open their menu in the stock dropdown.
function M.ShowHub(kind, anchor)
    if kind == "orbs" then
        if not (Nexus.OrbPanel and Nexus.OrbPanel.Show) then return false end
        if type(CloseDropDownMenus) == "function" then CloseDropDownMenus() end
        Nexus.OrbPanel.Show()
        return true
    end
    if kind ~= "plan" and kind ~= "explore" then return false end
    -- The full UI keeps the existing controllers and their guarded actions,
    -- but opens their real workspace surface directly from the footer.
    local workspaces = Nexus.FullUIWorkspaces
    if workspaces then
        if type(CloseDropDownMenus) == "function" then CloseDropDownMenus() end
        if kind == "plan" then return workspaces.ShowPlan() == true end
        return workspaces.ShowExplore() == true
    end
    if type(EasyMenu) ~= "function" then return false end
    if type(CloseDropDownMenus) == "function" then CloseDropDownMenus() end
    M._hubMenu = M._hubMenu or CreateFrame("Frame", "NexusPanelHubMenu", UIParent, "UIDropDownMenuTemplate")
    M.OpenMenu(M.HubMenuItems(kind), M._hubMenu, anchor or "cursor")
    return true
end

-- True only while `menuFrame`'s menu is on screen now, opened from `anchor`:
-- its root list is shown and the stock open-menu global names it. That global
-- outlives a close, so the list's own visibility decides (contract item 6).
-- The client answers 1 or nil (Theme.ClientBool).
function M.MenuShownFrom(menuFrame, anchor)
    local list = _G.DropDownList1
    return menuFrame ~= nil and menuFrame._nexusOpener == anchor
        and _G.UIDROPDOWNMENU_OPEN_MENU == menuFrame
        and list ~= nil and list.IsShown ~= nil
        and Nexus.Theme.ClientBool(list:IsShown()) == true
end

-- Every Panel menu opens through Theme.OpenMenu: the same EasyMenu call, with
-- the shared list that shows it opaque while it is this Nexus menu (Theme:
-- native menus Nexus opens). Without Theme it is the plain EasyMenu call.
function M.OpenMenu(items, menuFrame, anchor)
    if menuFrame then menuFrame._nexusOpener = anchor end
    local theme = Nexus.Theme
    if theme and type(theme.OpenMenu) == "function" then
        return theme.OpenMenu(items, menuFrame, anchor, 0, 0)
    end
    EasyMenu(items, menuFrame, anchor, 0, 0, "MENU")
    return true
end

local function EnsureMinimapButton()
    if minimapBtn then return minimapBtn end
    local saved = M.SavedLayoutRoot()
    saved.minimapAngle = saved.minimapAngle or 220

    local btn = CreateFrame("Button", "NexusMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:RegisterForDrag("LeftButton")

    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20); icon:SetPoint("CENTER"); icon:SetTexture("Interface\\AddOns\\Nexus\\ui\\Textures\\NexusMinimap.tga")
    pcall(function()
        local border = btn:CreateTexture(nil, "OVERLAY")
        border:SetSize(54,54); border:SetPoint("TOPLEFT",-3,3); border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    end)

    local function Reposition()
        local angle = math.rad(M.SavedLayoutRoot().minimapAngle or 220)
        local r = 80
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER", r * math.cos(angle), r * math.sin(angle))
    end
    Reposition()

    btn:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local px, py = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            px, py = px / scale, py / scale
            M.SavedLayoutRoot().minimapAngle = math.deg(math.atan2(py - my, px - mx))
            Reposition()
        end)
    end)
    btn:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    btn:SetScript("OnClick", function(_, button)
        if button == "RightButton" and Nexus.WishlistEditor then Nexus.WishlistEditor.Show() else M.Toggle() end
    end)
    btn:SetScript("OnEnter", function(self)
        -- Pointing at it is enough: the restore cue has been seen.
        if M._restoreCue then M.CueMinimapRestore(false) end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff7fd5ffNexus|r  |cff888888" .. SafeText(Nexus.VERSION) .. "|r")
        GameTooltip:AddLine(LT("panel.tooltip.minimap_summary"), 0.6,0.8,1,true)
        GameTooltip:AddLine(" ")
        -- The "  |  " separators are code-owned (a translation holds no "|").
        GameTooltip:AddLine(LT("panel.tooltip.minimap_left_click") .. "  |  " .. LT("panel.tooltip.minimap_right_click")
            .. "  |  " .. LT("panel.tooltip.minimap_drag"),
            0.7,0.7,0.7,true)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    minimapBtn = btn
    return btn
end

local function PositionPerformance(topY, completed, metrics)
    local small = metrics and metrics.small or 11
    local normal = metrics and metrics.normal or 14
    local gap = metrics and metrics.gap or 6
    if completed then
        -- Compact centered record table sized to stay inside the narrower HUD.
        -- Keep headings centered while pulling value columns inward so long DPS
        -- values do not hang off the right edge.
        local left, width = 24, 224
        local labelW, valueW = 120, 72

        local dummyTop = topY - small - gap
        local dummyGlobalTop = dummyTop - normal - math.max(3,math.floor(gap/2))
        local lkHeadingTop = dummyGlobalTop - normal - gap
        local lkTop = lkHeadingTop - small - gap
        local lkGlobalTop = lkTop - normal - math.max(3,math.floor(gap/2))

        SetPoint(performanceLabel, "TOP", frame, "TOP", 0, topY)
        performanceLabel:SetSize(width, small)
        performanceLabel:SetJustifyH("CENTER")

        SetPoint(dummyLabel, "TOPLEFT", frame, "TOPLEFT", left, dummyTop)
        dummyLabel:SetSize(labelW, normal); dummyLabel:SetJustifyH("LEFT")
        SetPoint(dummyValue, "TOPLEFT", frame, "TOPLEFT", left + labelW, dummyTop)
        dummyValue:SetSize(valueW, normal); dummyValue:SetJustifyH("RIGHT")
        SetPoint(dummyGlobal, "TOPLEFT", frame, "TOPLEFT", left, dummyGlobalTop)
        dummyGlobal:SetSize(labelW, normal); dummyGlobal:SetJustifyH("LEFT")
        SetPoint(dummyGlobalValue, "TOPLEFT", frame, "TOPLEFT", left + labelW, dummyGlobalTop)
        dummyGlobalValue:SetSize(valueW, normal); dummyGlobalValue:SetJustifyH("RIGHT")

        SetPoint(lkPersonalLabel, "TOP", frame, "TOP", 0, lkHeadingTop)
        lkPersonalLabel:SetSize(width, small); lkPersonalLabel:SetJustifyH("CENTER")
        SetPoint(lkLabel, "TOPLEFT", frame, "TOPLEFT", left, lkTop)
        lkLabel:SetSize(labelW, normal); lkLabel:SetJustifyH("LEFT")
        SetPoint(lkValue, "TOPLEFT", frame, "TOPLEFT", left + labelW, lkTop)
        lkValue:SetSize(valueW, normal); lkValue:SetJustifyH("RIGHT")
        SetPoint(lkGlobal, "TOPLEFT", frame, "TOPLEFT", left, lkGlobalTop)
        lkGlobal:SetSize(labelW, normal); lkGlobal:SetJustifyH("LEFT")
        SetPoint(lkGlobalValue, "TOPLEFT", frame, "TOPLEFT", left + labelW, lkGlobalTop)
        lkGlobalValue:SetSize(valueW, normal); lkGlobalValue:SetJustifyH("RIGHT")
    else
        -- Expanded active-build performance is a separate section below progress.
        -- Keeping it out of the progress columns prevents every optional state
        -- (tomes, shed Echoes, live rolls) from competing for the same space.
        local left, right = 20, 160
        local colW = 120
        local setTop = topY - small - math.max(3,math.floor(gap/2))
        local rowTop = setTop - small - gap
        local globalTop = rowTop - normal - math.max(3,math.floor(gap/2))
        SetPoint(performanceLabel, "TOP", frame, "TOP", 0, topY)
        performanceLabel:SetSize(260, small)
        performanceLabel:SetJustifyH("CENTER")
        SetPoint(setLabelText, "TOP", frame, "TOP", 0, setTop)
        setLabelText:SetSize(260, small)
        setLabelText:SetJustifyH("CENTER")

        SetPoint(dummyLabel, "TOPLEFT", frame, "TOPLEFT", left, rowTop)
        dummyLabel:SetSize(70, normal); dummyLabel:SetJustifyH("LEFT")
        SetPoint(dummyValue, "TOPLEFT", frame, "TOPLEFT", left + 70, rowTop)
        dummyValue:SetSize(50, normal); dummyValue:SetJustifyH("RIGHT")
        SetPoint(dummyGlobal, "TOPLEFT", frame, "TOPLEFT", left, globalTop)
        dummyGlobal:SetSize(colW, normal); dummyGlobal:SetJustifyH("LEFT")

        SetPoint(lkLabel, "TOPLEFT", frame, "TOPLEFT", right, rowTop)
        lkLabel:SetSize(70, normal); lkLabel:SetJustifyH("LEFT")
        SetPoint(lkValue, "TOPLEFT", frame, "TOPLEFT", right + 70, rowTop)
        lkValue:SetSize(50, normal); lkValue:SetJustifyH("RIGHT")
        SetPoint(lkGlobal, "TOPLEFT", frame, "TOPLEFT", right, globalTop)
        lkGlobal:SetSize(colW, normal); lkGlobal:SetJustifyH("LEFT")
    end

    dummyHit:ClearAllPoints()
    dummyHit:SetPoint("TOPLEFT", dummyLabel, "TOPLEFT", 0, 2)
    dummyHit:SetPoint("BOTTOMRIGHT", completed and dummyGlobalValue or dummyGlobal, "BOTTOMRIGHT", 0, -2)
    lkHit:ClearAllPoints()
    lkHit:SetPoint("TOPLEFT", completed and lkPersonalLabel or lkLabel, "TOPLEFT", 0, 2)
    lkHit:SetPoint("BOTTOMRIGHT", completed and lkGlobalValue or lkGlobal, "BOTTOMRIGHT", 0, -2)
end

local function RenderPerformance(pr, completed)
    local performance = type(pr.performance) == "table" and pr.performance or {}
    local dummy = type(performance.dummy) == "table" and performance.dummy or {}
    local lk = type(performance.lk) == "table" and performance.lk or {}
    local myDummy, myLK = dummy.personal, lk.personal
    local topDummy, topLK = dummy.global, lk.global

    local count = tonumber(pr.total) or 0
    -- M4 (UX-14): the shared column is the best record this client knows for
    -- these exact Echoes, not a global ranking (UserText.BEST_KNOWN).
    local text = Nexus.UserText
    local bestKnown = text and text.BEST_KNOWN or LT("panel.label.best_known")
    if completed then
        performanceLabel:SetText(LT("panel.heading.training_dummy"))
        setLabelText:SetText("")
        dummyLabel:SetText(LT("panel.label.your_best"))
        dummyGlobal:SetText(bestKnown)
        lkPersonalLabel:SetText(LT("panel.heading.lich_king"))
        lkLabel:SetText(LT("panel.label.your_best"))
        lkGlobal:SetText(bestKnown)
    else
        performanceLabel:SetText(LT("panel.heading.dps_records"))
        -- M4 (UX-13): the plan's rolled copies, not Echo rows or names.
        setLabelText:SetText(LF("panel.label.target_build_copies", {count = tostring(count)}))
        dummyLabel:SetText(LT("panel.label.your_dummy"))
        lkLabel:SetText(LT("panel.label.your_lich_king"))
    end
    dummyValue:SetText(myDummy and ("|cff4dff80" .. FmtDps(myDummy.dps) .. "|r") or "|cff777777—|r")
    lkValue:SetText(myLK and ("|cff4dff80" .. FmtDps(myLK.dps) .. "|r") or "|cff777777—|r")
    if completed then
        dummyGlobalValue:SetText(topDummy and ("|cffffd200" .. FmtDps(topDummy.dps) .. "|r") or "|cff777777—|r")
        lkGlobalValue:SetText(topLK and ("|cffffd200" .. FmtDps(topLK.dps) .. "|r") or "|cff777777—|r")
    else
        dummyGlobal:SetText(topDummy and (bestKnown .. "  |cffffd200" .. FmtDps(topDummy.dps) .. "|r") or (bestKnown .. "  —"))
        lkGlobal:SetText(topLK and (bestKnown .. "  |cffffd200" .. FmtDps(topLK.dps) .. "|r") or (bestKnown .. "  —"))
    end

    AddDpsTooltip(dummyHit, LT("panel.value.target_training_dummy"), myDummy, topDummy)
    AddDpsTooltip(lkHit, LT("panel.value.target_lich_king"), myLK, topLK)
end

------------------------------------------------------------------------
-- The STILL NEEDED and EXTRA COPIES name columns (native acceptance of
-- test.163009, default scale: with many distinct missing or extra Echoes the
-- expanded Details face showed only the first name, with neither the second
-- name nor "+N more"). The face was one no-wrap FontString holding
-- "first\nsecond\n+N more" in a box modelled at three 11-unit rows. Whether
-- the client drew one line because of no-wrap, its line height or that box
-- is not established, so the face no longer depends on any of them: each
-- line is its own one-line FontString (the column's own FontString is the
-- first; two more are made once, in its font and colour), measured by the
-- client at its final font and width and stacked by those heights, and
-- LayoutMetrics.Panel reserves that measured stack when it is taller than
-- the modelled rows (M.PanelLayout). The column keeps its box, so its hover
-- (HitFrame) still covers every line and lists every complete name; the
-- words, counts, colours and the two-names-then-"+N more" rule are as
-- before. Built lazily, through M and frame fields: EnsureFrame is at the
-- Lua 5.1 upvalue ceiling.
------------------------------------------------------------------------
-- The face's lines: the first two names, then "+N more" for the rest. A
-- name stays one line (a line break inside it is a space); `stripDetail`
-- drops a " (Quality:xN ...)" breakdown, which the hover shows.
function M.DetailNameLines(names, stripDetail)
    names = type(names) == "table" and names or {}
    local lines = {}
    local shown = math.min(#names, 2)
    for i = 1, shown do
        local name = (tostring(names[i]):gsub("[\r\n]+", " "))
        if stripDetail then name = (name:gsub("%s+%b()", "")) end
        lines[#lines + 1] = name
    end
    if #names > shown then lines[#lines + 1] = LF("panel.label.more_count", {count = LC(#names - shown)}) end
    return lines
end

-- The column's three one-line rows: the column itself, then two made once.
function M.DetailRows(column, r, g, b)
    local rows = column._nexusRows
    if rows then return rows end
    local metrics = Nexus.LayoutMetrics
    local font = metrics and metrics.FontObject and metrics.FontObject("small") or "GameFontHighlightSmall"
    rows = {column}
    for index = 2, 3 do
        local row = frame:CreateFontString(nil, "OVERLAY", font)
        row:SetJustifyH("LEFT")
        row:SetJustifyV("TOP")
        if type(row.SetWordWrap) == "function" then pcall(row.SetWordWrap, row, false) end
        row:SetTextColor(r, g, b)
        row:Hide()
        rows[index] = row
    end
    column._nexusRows = rows
    return rows
end

-- The client's height of one row's text at its width, by the measurement
-- LayoutMetrics.WrapHeight and Overflows already use (height 0, then
-- GetStringHeight; the box height is restored). Without a measurement, the
-- conservative model's line.
function M.DetailLineHeight(row)
    local height = row:GetHeight()
    row:SetHeight(0)
    local ok, measured = pcall(row.GetStringHeight, row)
    row:SetHeight(height)
    measured = ok and tonumber(measured) or nil
    if measured and measured > 0 and measured < math.huge then return math.ceil(measured) end
    local metrics = Nexus.LayoutMetrics
    if metrics and metrics.ConservativeText and metrics.RuntimeMetrics then
        local _, line = metrics.ConservativeText((metrics.RuntimeMetrics()))
        return line
    end
    return 17
end

-- Rows two and three, each under the one above at its measured height, at
-- the column's width. Returns the height of the column's lines.
function M.PlaceDetailRows(column)
    local rows = column and column._nexusRows
    if not rows then return 0 end
    local width = math.max(1, tonumber(column:GetWidth()) or 1)
    local top = 0
    for index = 1, #rows do
        local row = rows[index]
        if (row:GetText() or "") ~= "" then
            if index > 1 then row:SetWidth(width) end
            local height = M.DetailLineHeight(row)
            if index > 1 then
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", column, "TOPLEFT", 0, -top)
                row:SetSize(width, height)
            end
            top = top + height
        end
    end
    return top
end

-- Rows two and three follow the column's own visibility while they hold a
-- line.
function M.ShowDetailRows(column)
    local rows = column and column._nexusRows
    if not rows then return end
    local shown = column:IsShown() and true or false
    for index = 2, #rows do
        SetVisible(rows[index], shown and (rows[index]:GetText() or "") ~= "")
    end
    if column == shedText then M.SyncExtraListLink() end
end

function M.SetDetailNames(column, lines, empty, r, g, b)
    if not column then return 0 end
    local rows = M.DetailRows(column, r, g, b)
    for index = 1, #rows do
        rows[index]:SetText(lines[index] or (index == 1 and empty) or "")
    end
    M.ShowDetailRows(column)
    return M.PlaceDetailRows(column)
end

-- Both columns' lines from the run's lists; returns the taller column's
-- measured lines.
function M.RenderDetailNames(missing, shed)
    local need = M.SetDetailNames(needText, M.DetailNameLines(missing, true),
        "|cff888888" .. LT("panel.label.no_remaining_demand") .. "|r", 1, 0.5, 0.2)
    local lines = M.DetailNameLines(shed, false)
    -- A longer list than the face shows names its complete-list route on
    -- the "+N more" row itself (M.SyncExtraListLink): one whole row.
    if lines[3] then lines[3] = LF("panel.label.more_count_show_all", {count = LC(#shed - 2)}) end
    local extra = M.SetDetailNames(shedText, lines, "|cff888888" .. LT("panel.label.no_extra_copies") .. "|r", 0.72, 0.52, 1)
    M.SyncExtraListLink()
    return math.max(need, extra)
end

------------------------------------------------------------------------
-- Owner-approved item 7 (issue #174): the complete extra-copies list. The
-- Details column shows two names and "+N more - Show all"; that row is a
-- button which opens a read-only window with every name of the last
-- committed model's progress.shed, whole, in order, numbered, with the same
-- comparison facts the column's hover gives (exact-quality targets; locked
-- copies protected by the Saved Build are never listed). The names are the
-- run's own cached strings: nothing is recomputed, read from the game or
-- the inventory, or decided here. A list that was never received is "not
-- known", an empty one "none", and one kept from before a failed panel
-- update says so. Opening, scrolling and closing it delete, assign, save,
-- send and spend nothing, and it works while Nexus is paused. It scrolls in
-- its own window, away from the panel's drag surfaces; Close, its X and
-- Escape (UISpecialFrames) close it. Built lazily, through M and frame
-- fields (EnsureFrame is at the upvalue ceiling).
------------------------------------------------------------------------
function M.ExtraListFacts()
    local model = type(M._lastModel) == "table" and M._lastModel or nil
    local pr = model and type(model.progress) == "table" and model.progress or nil
    local stale = renderState.committed ~= true
    if not (pr and type(pr.shed) == "table") then return {state = "unknown", names = {}, stale = stale} end
    local names = {}
    for index = 1, #pr.shed do names[index] = tostring(pr.shed[index]) end
    return {state = #names > 0 and "listed" or "empty", names = names, stale = stale}
end

-- The "+N more - Show all" row's button: shown exactly while that row is.
function M.SyncExtraListLink()
    local rows = shedText and shedText._nexusRows
    local row = rows and rows[3]
    local shown = row ~= nil and row:IsShown() and (row:GetText() or "") ~= ""
    local link = frame and frame._extraAllBtn
    if not shown then
        if link then link:Hide() end
        return false
    end
    if not link then
        link = CreateFrame("Button", nil, frame)
        link:SetFrameLevel(frame:GetFrameLevel() + 6)
        link:RegisterForClicks("LeftButtonUp")
        local hover = link:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetTexture(1, 1, 1, 0.12)
        link:SetScript("OnClick", function() M.ShowExtraList() end)
        link:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(LT("panel.tooltip.show_all_extra_title"), 1, 1, 1)
            GameTooltip:AddLine(LT("panel.tooltip.show_all_extra_body"),
                0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end)
        link:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        frame._extraAllBtn = link
    end
    link:ClearAllPoints()
    link:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    link:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
    link:Show()
    return true
end

-- The list window's geometry (M.LayoutExtraList): its preferred width and
-- the wider ones it may take, insets, the room kept for its X and scroll
-- bar, the gaps, the footer that holds Close, its preferred least height and
-- names viewport, and the screen margin it keeps (LayoutMetrics.FitToScreen's).
M.EXTRA_LIST = {width = 340, widths = {340, 440, 540, 640}, inset = 14, top = 12, gap = 6, closeXRoom = 32,
    scrollBarRoom = 32, footer = 42, closeBottom = 12, minHeight = 380, minView = 120, minRows = 3, margin = 24}

function M.EnsureExtraList()
    local list = M._extraList
    if list then return list end
    local L = M.EXTRA_LIST
    list = CreateFrame("Frame", "NexusExtraCopiesList", UIParent)
    list:SetFrameStrata("DIALOG")
    list:SetSize(L.width, L.minHeight)
    list:SetClampedToScreen(true)
    list:EnableMouse(true)
    list:SetBackdrop({bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4}})
    list:SetBackdropColor(0.04, 0.04, 0.07, 0.96)
    local function Text(owner, font, r, g, b)
        local text = owner:CreateFontString(nil, "OVERLAY", font)
        text:SetJustifyH("LEFT")
        text:SetJustifyV("TOP")
        text:SetWordWrap(true)
        if r then text:SetTextColor(r, g, b) end
        return text
    end
    -- Pinned at the top: the title and, for a list that is not current (kept
    -- from before a failed panel update), its warning. Never scrolled away.
    list.title = Text(list, "GameFontNormal")
    list.status = Text(list, "GameFontNormalSmall", 1, 0.45, 0.35)
    list.closeX = CreateFrame("Button", nil, list, "UIPanelCloseButton")
    list.closeX:SetPoint("TOPRIGHT", list, "TOPRIGHT", -2, -2)
    list.closeX:SetSize(32, 32)
    -- Scrolled together: the explanation, then every name.
    list.scroll = CreateFrame("ScrollFrame", "NexusExtraCopiesListScroll", list, "UIPanelScrollFrameTemplate")
    list.child = CreateFrame("Frame", nil, list.scroll)
    list.child:SetSize(L.width - L.inset - L.scrollBarRoom, 1)
    list.scroll:SetScrollChild(list.child)
    list.note = Text(list.child, "GameFontHighlightSmall")
    list.note:SetText(LT("panel.body.extra_list_note"))
    list.body = Text(list.child, "GameFontHighlightSmall")
    -- One line of the names' font, measured for the least viewport.
    list.probe = Text(list, "GameFontHighlightSmall")
    list.probe:SetText("Ag")
    list.probe:Hide()
    list.close = CreateFrame("Button", nil, list, "UIPanelButtonTemplate")
    list.close:SetText(LT("panel.button.close_extra_list"))
    list.close:SetSize(90, 22)
    list.close:SetPoint("BOTTOM", list, "BOTTOM", 0, L.closeBottom)
    list.close:SetScript("OnClick", function() list:Hide() end)
    if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, "NexusExtraCopiesList") end
    if Nexus.Theme and Nexus.Theme.StyleButton then pcall(Nexus.Theme.StyleButton, list.close) end
    list:Hide()
    M._extraList = list
    return list
end

-- A text's height at its width, measured as LayoutMetrics.WrapHeight and
-- M.DetailLineHeight do (height 0, then GetStringHeight); without a usable
-- measurement, a conservative estimate (7 units a character, 14 a row).
-- The text keeps the height it needs.
function M.FitListText(text, width)
    text:SetWidth(width)
    if (text:GetText() or "") == "" then text:SetHeight(1); return 0 end
    text:SetHeight(0)
    local ok, height = pcall(text.GetStringHeight, text)
    height = ok and tonumber(height) or nil
    if not height or height ~= height or height <= 0 or height == math.huge then
        local chars = #((text:GetText() or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
        height = 14 * math.max(1, math.ceil(chars * 7 / math.max(1, width)))
    end
    height = math.ceil(height)
    text:SetHeight(height)
    return height
end

-- The room the window may take: the UI less FitToScreen's margin. As there,
-- an implausibly small reported UI (under 640 x 480) is not acted on.
function M.ExtraListRoom()
    local L = M.EXTRA_LIST
    local function Read(method)
        local ok, value = pcall(UIParent[method], UIParent)
        value = ok and tonumber(value) or nil
        return (value and value == value and value < math.huge) and value or nil
    end
    local w, h = Read("GetWidth"), Read("GetHeight")
    if not (w and h and w >= 640 and h >= 480) then return math.huge, math.huge end
    return w - L.margin, h - L.margin
end

-- Pinned title and warning at the top, Close at the bottom, and between them
-- one scrolling region holding the explanation and every name. The window
-- is at most the room the screen has (M.ExtraListRoom), so clamping keeps
-- all of it on screen; its text keeps the player's size. When the pinned
-- part would leave fewer than M.EXTRA_LIST.minRows rows to scroll, the
-- window takes the next wider width the screen holds, so the pinned text
-- wraps into fewer rows. Returns the layout.
function M.LayoutExtraList(list)
    local L = M.EXTRA_LIST
    local roomW, roomH = M.ExtraListRoom()
    local lineH = math.max(1, M.FitListText(list.probe, 200))
    local chosen
    for index, width in ipairs(L.widths) do
        if width <= roomW or index == 1 then
            local inner = width - 2 * L.inset
            local y = L.top
            local titleH = M.FitListText(list.title, inner - L.closeXRoom)
            local titleY = y
            y = y + titleH + L.gap
            local statusH = M.FitListText(list.status, inner)
            local statusY = y
            if statusH > 0 then y = y + statusH + L.gap end
            local height = math.min(roomH, math.max(L.minHeight, y + L.minView + L.footer))
            local view = height - y - L.footer
            chosen = {width = width, height = height, view = view, scrollTop = y,
                titleY = titleY, statusY = statusY, statusH = statusH}
            if view >= L.minRows * lineH then break end
        end
    end
    local c = chosen
    list:SetSize(c.width, c.height)
    local inner = c.width - 2 * L.inset
    M.FitListText(list.title, inner - L.closeXRoom)
    list.title:ClearAllPoints()
    list.title:SetPoint("TOPLEFT", list, "TOPLEFT", L.inset, -c.titleY)
    list.title:Show()
    M.FitListText(list.status, inner)
    list.status:ClearAllPoints()
    list.status:SetPoint("TOPLEFT", list, "TOPLEFT", L.inset, -c.statusY)
    SetVisible(list.status, c.statusH > 0)
    list.scroll:ClearAllPoints()
    list.scroll:SetPoint("TOPLEFT", list, "TOPLEFT", L.inset, -c.scrollTop)
    list.scroll:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -L.scrollBarRoom, L.footer)
    local scrollW = c.width - L.inset - L.scrollBarRoom
    -- The size is stated too, for a reader that does not resolve the anchors.
    list.scroll:SetSize(scrollW, math.max(1, c.view))
    -- The scrolled text: the explanation, then the names under it.
    local textW = scrollW - 4
    local noteH = M.FitListText(list.note, textW)
    list.note:ClearAllPoints()
    list.note:SetPoint("TOPLEFT", list.child, "TOPLEFT", 0, 0)
    local bodyH = M.FitListText(list.body, textW)
    -- At least one 12-unit row per line: a short measurement never makes the
    -- names taller than the scroll child.
    local _, breaks = (list.body:GetText() or ""):gsub("\n", "\n")
    bodyH = math.max(bodyH, 12 * (breaks + 1))
    list.body:SetHeight(bodyH)
    list.body:ClearAllPoints()
    list.body:SetPoint("TOPLEFT", list.child, "TOPLEFT", 0, -(noteH + L.gap + 2))
    list.child:SetSize(scrollW, math.max(1, noteH + L.gap + 2 + bodyH))
    list._nexusLayout = c
    return c
end

-- The window's words from M.ExtraListFacts; returns those facts. A list kept
-- from before a failed panel update says so first, in its title and in the
-- pinned warning, and shows its names dimmed: they are the last completed
-- update's, not current.
function M.FillExtraList(list)
    local facts = M.ExtraListFacts()
    local lines = {}
    local mark = facts.stale and (" " .. LT("panel.label.extra_list_not_current")) or ""
    if facts.state == "unknown" then
        list.title:SetText(LT("panel.title.extra_list_not_known") .. mark)
        lines[#lines + 1] = "|cffd9d9d9" .. LT("panel.body.extra_list_not_known") .. "|r"
    elseif facts.state == "empty" then
        list.title:SetText(LT("panel.title.extra_list_none") .. mark)
        lines[#lines + 1] = "|cffd9d9d9" .. LT("panel.body.extra_list_none") .. "|r"
    else
        list.title:SetText(LF("panel.title.extra_list_count", {count = LC(#facts.names)}) .. mark)
        for index, name in ipairs(facts.names) do lines[#lines + 1] = index .. ". " .. name end
    end
    list.status:SetText(facts.stale and LT("panel.status.extra_list_stale") or "")
    if facts.stale then list.body:SetTextColor(0.62, 0.6, 0.66) else list.body:SetTextColor(0.78, 0.66, 1) end
    list.body:SetText(table.concat(lines, "\n"))
    M.LayoutExtraList(list)
    list._nexusFacts = facts
    return facts
end

-- Opens the list beside the panel, at its top.
function M.ShowExtraList()
    local list = M.EnsureExtraList()
    M.FillExtraList(list)
    list:ClearAllPoints()
    if frame then list:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
    else list:SetPoint("CENTER", UIParent, "CENTER", 0, 0) end
    list.scroll:SetVerticalScroll(0)
    list:Show()
    return list._nexusFacts
end

-- A committed render redraws an open list from that model; a closed one is
-- not built or filled.
function M.RefreshExtraList()
    local list = M._extraList
    if not (list and list:IsShown()) then return false end
    M.FillExtraList(list)
    return true
end

-- LayoutMetrics.Panel, with the open Details name columns reserved at the
-- client's measured height of their real lines when that is taller than the
-- modelled rows. Collapsed Details measures nothing and keeps the model.
function M.PanelLayout(spec, progress)
    local metrics = Nexus.LayoutMetrics
    local layout = metrics.Panel(spec)
    local boxes = type(layout) == "table" and layout.boxes or nil
    if not (spec.planDetails and boxes and boxes.needed and boxes.shed and needText and shedText) then
        return layout
    end
    local pr = type(progress) == "table" and progress or {}
    needText:SetWidth(boxes.needed.w)
    shedText:SetWidth(boxes.shed.w)
    local height = M.RenderDetailNames(type(pr.missing) == "table" and pr.missing or {},
        type(pr.shed) == "table" and pr.shed or {})
    if height > layout.small * 3 then
        spec.detailNamesH = height
        layout = metrics.Panel(spec)
    end
    return layout
end

local function ShowCoreProgress(show)
    SetVisible(progressLabel, show); SetVisible(progressValue, show)
    SetVisible(needLabel, show); SetVisible(needText, show); SetVisible(needHit, show)
    M.ShowDetailRows(needText)
    local showTomes = show and #unknownTomesCache > 0
    SetVisible(tomesLabel, showTomes); SetVisible(tomesValue, showTomes); SetVisible(tomesHit, showTomes)
    SetVisible(shedLabel, show); SetVisible(shedText, show); SetVisible(shedHit, show)
    M.ShowDetailRows(shedText)
    local showToLock = show and #toLockNamesCache > 0
    if frame then
        SetVisible(frame.toLockLabel, showToLock); SetVisible(frame.toLockText, showToLock); SetVisible(frame.toLockHit, showToLock)
        -- Issue #143: the mapped headings' full-text hovers follow their headings.
        SetVisible(frame._progressLabelHit, show); SetVisible(frame._needLabelHit, show); SetVisible(frame._shedLabelHit, show)
    end
end

------------------------------------------------------------------------
-- Play offer cards (Claude Design full UI, "Main panel (Play)": the current
-- offer first, as three cards side by side, the Wishlist pick set apart).
-- Each card shows the name, the quality and a tag from Readout.OfferCard,
-- with its complete CardLine on hover. The cards take exactly the space
-- LayoutMetrics.Panel already reserves for the three card rows, so the
-- panel's geometry contract is unchanged. Display only: a card has a hover
-- and no click, so it never takes, banishes, rerolls or freezes; choosing
-- stays in the game's Echo window. Built lazily and reached through M:
-- EnsureFrame is at the Lua 5.1 upvalue ceiling and ApplyModel close to it.
-- Without a responsive layout (no LayoutMetrics) the one-line rows stay.
------------------------------------------------------------------------
-- Fixed colours (status, never from the palette), the column gap and the
-- text inset. One table: the main chunk's locals are counted too.
local OFFER = {edge = {0.32, 0.32, 0.38}, mark = {1, 0.82, 0}, gap = 4, pad = 4}

function M.EnsureOfferCards()
    if not frame then return nil end
    if frame._offerCards then return frame._offerCards end
    local area = frame._rollArea
    local metrics = Nexus.LayoutMetrics
    local small = metrics and metrics.FontObject and metrics.FontObject("small") or "GameFontHighlightSmall"
    local cards = {}
    for index = 1, 3 do
        local card = CreateFrame("Frame", nil, area)
        -- Fixed status colours: no style or palette repaints a card.
        card._nexusThemeExempt = true
        card:EnableMouse(true)
        card.fill = card:CreateTexture(nil, "BACKGROUND")
        card.fill:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
        card.fill:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0)
        card.fill:SetTexture(0, 0, 0, 0.35)
        -- Top, bottom, left and right edges: a border the client draws as
        -- plain textures (no backdrop edge file at 1-2 px).
        card.edges = {}
        for edge = 1, 4 do card.edges[edge] = card:CreateTexture(nil, "BORDER") end
        for _, key in ipairs({"name", "quality", "tag"}) do
            local text = card:CreateFontString(nil, "OVERLAY", small)
            text:SetJustifyH("LEFT")
            text:SetJustifyV("TOP")
            text:SetWordWrap(false)
            card[key] = text
        end
        card:SetScript("OnEnter", function(self)
            if not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine(self._nexusFull or "", 1, 1, 1, true)
            if self._nexusTag and self._nexusTag ~= "" then
                GameTooltip:AddLine(self._nexusTag, OFFER.mark[1], OFFER.mark[2], OFFER.mark[3], true)
            end
            GameTooltip:AddLine(LT("panel.tooltip.offer_card_passive"), 0.8, 0.8, 0.8, true)
            GameTooltip:Show()
        end)
        card:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        -- It chooses nothing, so a drag from it moves the panel.
        M.PassiveDragSurface(card)
        card:Hide()
        cards[index] = card
    end
    frame._offerCards = cards
    return cards
end

local function PaintOfferEdges(card, marked)
    local c = marked and OFFER.mark or OFFER.edge
    local size = marked and 2 or 1
    local e = card.edges
    e[1]:ClearAllPoints(); e[1]:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    e[1]:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0); e[1]:SetHeight(size)
    e[2]:ClearAllPoints(); e[2]:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0)
    e[2]:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0); e[2]:SetHeight(size)
    e[3]:ClearAllPoints(); e[3]:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    e[3]:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 0); e[3]:SetWidth(size)
    e[4]:ClearAllPoints(); e[4]:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
    e[4]:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", 0, 0); e[4]:SetWidth(size)
    for edge = 1, 4 do e[edge]:SetTexture(c[1], c[2], c[3], marked and 1 or 0.9) end
end

-- Content of the three cards from the current model's card lines only:
-- `lines` the CardLine texts (as the one-line rows show them, without the
-- ">>" marker), `marked` Readout.MarkedCard's index or nil, `auto` the Auto
-- selection, `responsive` whether ApplyPanelLayout will place them, `facts`
-- (optional) the model cards' own Readout.CardFacts by index, so a card's
-- name and quality are its own and an unknown quality is never read from the
-- text. `frozen` (optional) Readout.FreezeCard's index, which the caller
-- passes only with Auto OFF: that card is tagged as a Freeze
-- (Readout.OfferCard). Returns whether the cards show; while they do, the
-- one-line rows are hidden and keep their text. No old card survives a new
-- board.
function M.RenderOfferCards(lines, marked, auto, responsive, facts, frozen)
    local readout = Nexus.Readout
    local any = false
    for index = 1, 3 do
        if type(lines) == "table" and SafeText(lines[index]) ~= "" then any = true end
    end
    local show = any and responsive == true and readout and type(readout.OfferCard) == "function"
    local cards = (show or (frame and frame._offerCards)) and M.EnsureOfferCards() or nil
    for index = 1, 3 do
        local card = cards and cards[index]
        local line = type(lines) == "table" and SafeText(lines[index]) or ""
        if card and show and line ~= "" then
            local own = type(facts) == "table" and type(facts[index]) == "table" and facts[index] or nil
            local shown = readout.OfferCard(line, marked == index, auto, own, frozen == index)
            card.name:SetText(shown.name)
            -- The name in its Echo quality colour (the design's quality on the
            -- name), only from the card's own quality fact and the addon's
            -- established Echo rarity colours (OrbHistory.QUALITY_COLORS, as
            -- the Wishlist overlay); an unknown quality stays white, never
            -- read from the text or a WoW item-quality offset.
            local history = Nexus.OrbHistory
            local q = own and tonumber(own.quality)
            local qc = q and history and type(history.QUALITY_COLORS) == "table" and history.QUALITY_COLORS[q] or nil
            card.name:SetTextColor(qc and qc[1] or 1, qc and qc[2] or 1, qc and qc[3] or 1)
            card._nexusQuality = qc and q or nil
            card.quality:SetText(shown.quality)
            card.tag:SetText(shown.shown or shown.tag)
            if shown.marked or shown.freeze then
                card.tag:SetTextColor(OFFER.mark[1], OFFER.mark[2], OFFER.mark[3])
            else
                card.tag:SetTextColor(0.75, 0.75, 0.75)
            end
            card._nexusFull, card._nexusTag, card._nexusMarked = shown.full, shown.tag, shown.marked
            PaintOfferEdges(card, shown.marked)
            card:Show()
        elseif card then
            card._nexusFull, card._nexusTag, card._nexusMarked = nil, nil, nil
            card:Hide()
        end
        SetVisible(cardTexts[index], not show)
    end
    return show and true or false
end

-- The measured one-line width of `line` in `text`'s font: the client's
-- measurement when it reports one, else the conservative text model at the
-- runtime font scale. Leaves `line` as the text's text.
function M.LineWidth(text, line)
    text:SetText(line)
    local ok, measured = pcall(text.GetStringWidth, text)
    measured = ok and tonumber(measured) or nil
    if measured and measured > 0 and measured < math.huge then return measured end
    local metrics = Nexus.LayoutMetrics
    local scale = metrics and metrics.RuntimeMetrics and metrics.RuntimeMetrics() or 1
    local char = metrics and metrics.ConservativeText and metrics.ConservativeText(scale) or 7
    local visible = tostring(line or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return #(visible:gsub("[\128-\191]", "")) * char
end

-- The offer heading (Readout.OfferHeadingForms: whose choice the offer is),
-- with the established state words and the destination, in the first of its
-- forms that fits the heading row on one line (its width less the charges,
-- as ApplyPanelLayout sets it): "Current offer - you choose", then "Offer -
-- you choose", then "You choose". Every form keeps who chooses, the Auto
-- state and the destination in the row itself; nothing moves to a hover.
-- Without a layout the full form stays. Text only.
function M.SetOfferHeading(text, model, activeSlot, layout)
    local readout = Nexus.Readout
    local forms = readout.OfferHeadingForms and readout.OfferHeadingForms(model.auto)
        or {readout.OfferHeading(model.auto)}
    local box = type(layout) == "table" and type(layout.boxes) == "table" and layout.boxes.roll or nil
    local width = box and (box.w - 4 - (SafeText(model._nexusChargeLine) ~= "" and 76 or 0)) or nil
    local chosen = ""
    for _, form in ipairs(forms) do
        -- The " · " separators and colours are code-owned; each word group is
        -- one reviewed meaning.
        if model.auto == false then
            chosen = "|cff7fd5ff" .. form .. "|r · " .. LT("panel.label.auto_state_off") .. " · "
                .. (activeSlot > 0 and LF("panel.label.slot_number", {slot = tostring(activeSlot)})
                    or LT("panel.label.preview_tag"))
        elseif activeSlot > 0 then
            chosen = "|cff4dff80" .. LT("panel.label.active_prefix") .. "|r " .. form .. " · "
                .. LF("panel.label.slot_number", {slot = tostring(activeSlot)})
        else
            chosen = "|cff888888" .. form .. "|r · " .. LT("panel.label.preview_tag")
        end
        if not width or M.LineWidth(text, chosen) <= width then break end
    end
    text:SetText(chosen)
    return chosen
end

-- Geometry of the cards inside the roll box (design/current "Nexus Main
-- Panel - Compact Redesign": compact offer rows, not tall cards): the band
-- the card rows hold (from below the heading, 3 x (small + row gap)), one
-- full-width row per offer: the name, then its quality and its tag at their
-- whole widths (only a tag wider than half the row, or a quality then left
-- without room, is shortened, complete on the card's hover), the name in the
-- rest (shortened there, complete on the hover and named in the
-- recommendation). The band, the roll box and the panel keep their size.
-- No Echo icon is drawn: no verified icon source exists in this source.
-- Returns "rows".
function M.PlaceOfferCards(layout, box, inset)
    local cards = frame and frame._offerCards
    if not (cards and layout and box) then return nil end
    local top = 1 + layout.small + math.max(3, math.floor(layout.gap / 2))
    local rowGap = math.max(2, math.floor(layout.gap / 3))
    local width = box.w - inset * 2
    for index = 1, 3 do
        local card = cards[index]
        card:ClearAllPoints()
        do
            card:SetPoint("TOPLEFT", frame._rollArea, "TOPLEFT", inset, -(top + (index - 1) * (layout.small + rowGap)))
            card:SetSize(width, layout.small)
            -- The status words first: the tag up to half the row, the quality
            -- up to what leaves the name a sixth of it; the name takes the rest.
            local inner = math.max(1, width - OFFER.pad * 2)
            local tag, quality = card.tag:GetText() or "", card.quality:GetText() or ""
            local tagW = tag ~= "" and math.min(math.floor(inner / 2), math.ceil(M.LineWidth(card.tag, tag))) or 0
            local room = inner - tagW - 2 * OFFER.gap - math.floor(inner / 6)
            local qualityW = quality ~= "" and math.max(1, math.min(room, math.ceil(M.LineWidth(card.quality, quality)))) or 0
            local nameW = math.max(1, inner - tagW - qualityW - (tagW > 0 and OFFER.gap or 0) - (qualityW > 0 and OFFER.gap or 0))
            local x = OFFER.pad
            for _, part in ipairs({{card.name, nameW}, {card.quality, qualityW}, {card.tag, tagW}}) do
                local text = part[1]
                text:ClearAllPoints()
                text:SetPoint("TOPLEFT", card, "TOPLEFT", x, 0)
                text:SetSize(math.max(1, part[2]), layout.small)
                if part[2] > 0 then x = x + part[2] + OFFER.gap end
            end
            card._nexusLayout = "rows"
        end
    end
    return "rows"
end

------------------------------------------------------------------------
-- The Play summary below the offer (Claude Design full UI, "Main panel
-- (Play)"): a compact plan progress (the run's count, a bar, four counts and
-- Details for the Echo names behind them), the Difficulty / Soul Ash line,
-- your DPS record beside the best known record for the same Echoes with what
-- best known means, and one line of Orb run status with Open. Every value is
-- read from the model this panel already shows (and, for the Orb line, the
-- Orb window's own compact read); an unknown is "?", never 0. Details only
-- changes what this panel shows (memory only, never saved); Open only opens
-- the Orb window. Built lazily and reached through M: EnsureFrame and
-- ApplyModel are at the Lua 5.1 upvalue ceiling. Without a responsive layout
-- (no LayoutMetrics) the former rows stay.
------------------------------------------------------------------------
-- Fixed colours (status, never from the palette). One table: the main
-- chunk's locals are counted too.
local PLAY = {bar = {1, 0.5, 0.2}, track = {0.12, 0.12, 0.15}, label = "|cffa8a8b0", value = "|cffffffff",
    wait = "|cff8fc8ff", muted = "|cff888888"}

local function PlayWhole(value)
    value = tonumber(value)
    if value == nil or value ~= value or value < 0 or value >= math.huge then return nil end
    return math.floor(value + 0.5)
end

-- "4,812": a whole DPS with thousands separators; nil when not a record.
local function PlayDps(record)
    local dps = type(record) == "table" and PlayWhole(record.dps) or nil
    if not dps or dps <= 0 then return nil end
    local text = tostring(dps)
    while true do
        local grouped, n = text:gsub("^(%d+)(%d%d%d)", "%1,%2")
        text = grouped
        if n == 0 then break end
    end
    return text
end

-- "<label>  <value>" in the two status colours.
local function PlayPair(label, value)
    return PLAY.label .. label .. "|r  " .. PLAY.value .. value .. "|r"
end

-- Anchor a hit frame over a text (two points, so offline geometry sees it).
local function PlayCover(hit, text)
    hit:ClearAllPoints()
    hit:SetPoint("TOPLEFT", text, "TOPLEFT", 0, 0)
    hit:SetPoint("BOTTOMRIGHT", text, "BOTTOMRIGHT", 0, 0)
end

function M.EnsurePlayWidgets()
    if not frame then return nil end
    if frame._play then return frame._play end
    local metrics = Nexus.LayoutMetrics
    local small = metrics and metrics.FontObject and metrics.FontObject("small") or "GameFontHighlightSmall"
    local p = {}
    local function Line(justify)
        local text = frame:CreateFontString(nil, "OVERLAY", small)
        text:SetJustifyH(justify or "LEFT")
        text:SetJustifyV("MIDDLE")
        text:SetWordWrap(false)
        text:Hide()
        return text
    end
    local function Hover(text, onEnter, onMouseUp)
        local hit = CreateFrame("Frame", nil, frame)
        hit:EnableMouse(true)
        PlayCover(hit, text)
        hit:SetScript("OnEnter", onEnter)
        hit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        if onMouseUp then hit:SetScript("OnMouseUp", onMouseUp) end
        hit:Hide()
        return hit
    end
    -- An existing hover of the former rows, shown over its count instead.
    local function Delegate(owner)
        return function(self)
            local enter = owner and owner:GetScript("OnEnter")
            if enter then enter(self) end
        end
    end
    local function OpenEditor() if Nexus.WishlistEditor then Nexus.WishlistEditor.Show() end end
    local theme = Nexus.Theme

    -- Show / Hide details: shows or collapses the detail section (the four
    -- counts and the Echo names behind them).
    p.details = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    p.details:SetScript("OnClick", function() M.TogglePlanDetails() end)
    p.details:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(LT(M._playDetails and "panel.button.details_hide" or "panel.button.details_show"), 1, 1, 1)
        GameTooltip:AddLine(LT("panel.tooltip.details_body"), 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    p.details:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    p.details:Hide()
    -- The bar: a track and the share of planned rolled copies this run has.
    p.track = frame:CreateTexture(nil, "ARTWORK")
    p.track:SetTexture(PLAY.track[1], PLAY.track[2], PLAY.track[3], 0.95)
    p.track:Hide()
    p.fill = frame:CreateTexture(nil, "OVERLAY")
    p.fill:SetTexture(PLAY.bar[1], PLAY.bar[2], PLAY.bar[3], 1)
    p.fill:Hide()
    -- The four counts; each keeps the hover (and click) of its former row.
    p.needed, p.tomes, p.extra, p.locked = Line(), Line(), Line(), Line()
    p.neededHit = Hover(p.needed, Delegate(needHit), OpenEditor)
    p.tomesHit = M.PassiveDragSurface(Hover(p.tomes, Delegate(tomesHit)))
    p.extraHit = M.PassiveDragSurface(Hover(p.extra, Delegate(shedHit)))
    p.lockedHit = Hover(p.locked, function(self)
        local hit = frame.toLockHit
        local enter = hit and hit:GetScript("OnEnter")
        if enter then enter(self) end
    end, OpenEditor)
    -- Difficulty and Soul Ash on one line, with the card's hover and click.
    p.server = Line()
    p.serverHit = CreateFrame("Button", nil, frame)
    p.serverHit:EnableMouse(true)
    PlayCover(p.serverHit, p.server)
    p.serverHit:SetScript("OnClick", function()
        if Nexus.ServerStatus and Nexus.ServerStatus.OpenHardcoreMenu then Nexus.ServerStatus.OpenHardcoreMenu() end
    end)
    p.serverHit:SetScript("OnEnter", Delegate(worldStatusHit))
    p.serverHit:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    p.serverHit:Hide()
    -- Your record (its label is the former best-DPS line, which keeps its
    -- hover) and the best known record for these Echoes, then the note.
    p.yoursValue = Line("RIGHT")
    p.bestLabel, p.bestValue = Line(), Line("RIGHT")
    p.note = Line()
    p.bestHit = Hover(p.bestLabel, function(self)
        if not GameTooltip then return end
        local model = type(M._lastModel) == "table" and M._lastModel or {}
        local pr = type(model.progress) == "table" and model.progress or {}
        local perf = type(pr.performance) == "table" and pr.performance or {}
        local text = Nexus.UserText
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(LF("panel.tooltip.best_known_same_echoes",
            {best_known = tostring(text and text.BEST_KNOWN or LT("panel.label.best_known"))}), 1, 1, 1)
        for _, category in ipairs({{"dummy", "panel.value.target_training_dummy"}, {"lk", "panel.value.target_lich_king"}}) do
            local row = type(perf[category[1]]) == "table" and perf[category[1]].global or nil
            local dps = PlayDps(row)
            local target = LT(category[2])
            GameTooltip:AddLine(dps and LF("panel.tooltip.best_known_target_dps", {target = target, dps = dps})
                or LF("panel.tooltip.best_known_target_none", {target = target}),
                0.85, 0.85, 0.85, true)
        end
        if text and text.RECORD_SCOPE then GameTooltip:AddLine(text.RECORD_SCOPE, 0.45, 0.75, 1, true) end
        GameTooltip:Show()
    end)
    M.PassiveDragSurface(p.bestHit)
    -- One line of Orb run status and Open (the Orb window).
    p.orb = Line()
    p.orbHit = Hover(p.orb, function(self)
        if not (GameTooltip and self._nexusFull) then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(self._nexusFull, 1, 1, 1, true)
        GameTooltip:AddLine(LT("panel.tooltip.orb_line_open"), 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    M.PassiveDragSurface(p.orbHit)
    p.orbOpen = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    p.orbOpen:SetText(LT("panel.button.orb_open"))
    p.orbOpen:SetScript("OnClick", function()
        if Nexus.OrbPanel and Nexus.OrbPanel.Show then Nexus.OrbPanel.Show() end
    end)
    p.orbOpen:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(LT("panel.tooltip.orbs_heading"), 1, 0.82, 0)
        GameTooltip:AddLine(LT("panel.tooltip.orbs_open_inspect"), 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    p.orbOpen:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    p.orbOpen:Hide()
    if theme and theme.StyleButton then
        pcall(theme.StyleButton, p.details)
        pcall(theme.StyleButton, p.orbOpen)
    end
    frame._play = p
    return p
end

-- Details is memory only: it is part of the layout key, and the panel is
-- rendered again with the model it shows. Nothing is saved or requested.
-- The panel's top (and so the Details button on it) stays where the player
-- sees it: the toggled layout grows or shrinks downward (M.HoldPanelTop).
function M.TogglePlanDetails()
    M._playDetails = not M._playDetails
    M._detailsHold = M.CapturePanelTop()
    if M.Refresh then M.Refresh() end
    return M._playDetails
end

-- The shown panel's top-left corner in screen units (any scale), and the
-- Details state the next layout must show; nil when it cannot be read.
function M.CapturePanelTop()
    if not (frame and frame:IsShown()) then return nil end
    local function Read(region, method)
        local ok, value = pcall(region[method], region)
        return ok and tonumber(value) or nil
    end
    local left, top, scale = Read(frame, "GetLeft"), Read(frame, "GetTop"), Read(frame, "GetEffectiveScale")
    if not (left and top and scale and scale > 0) then return nil end
    return {left = left * scale, top = top * scale, details = M._playDetails == true}
end

-- Run after every applied render, once its fit to the screen has set the
-- final scale (ApplyCandidate), so the screen-unit corner converts at that
-- scale. Only the first layout that shows the toggled Details state uses
-- the held corner: the panel is anchored by its
-- top-left there, so the Details row stays put and the section opens (or
-- closes) below it. If the taller panel would leave the bottom of the screen,
-- the panel moves up just enough to stay whole (the client clamps it there
-- too): the top then moves, and M._detailsGrowth says "clamped" instead of
-- "down". A layout that is not the Play view drops the hold, and so does a
-- move in progress. Nothing is saved: panelX / panelY change only by a drag.
function M.HoldPanelTop(layout)
    local hold = M._detailsHold
    if not (hold and frame and type(layout) == "table" and type(layout.boxes) == "table") then return nil end
    if not layout.play then M._detailsHold = nil; return nil end
    if (layout.boxes.planNeeded ~= nil) ~= hold.details then return nil end
    M._detailsHold = nil
    -- The player is moving the panel (issue #168): it stays under the
    -- pointer, and the corner held before the move no longer applies.
    if M._panelDrag then return nil end
    local okS, scale = pcall(frame.GetEffectiveScale, frame)
    scale = okS and tonumber(scale) or 1
    if not (scale and scale > 0) then return nil end
    local x, y = hold.left / scale, hold.top / scale
    local height = tonumber(layout.height) or tonumber(frame:GetHeight()) or 0
    local growth = "down"
    local okU, uiScale = pcall(UIParent.GetEffectiveScale, UIParent)
    uiScale = okU and tonumber(uiScale) or 1
    local uiH = tonumber(UIParent:GetHeight()) or 0
    if uiH >= 480 then
        local screenH = uiH * uiScale / scale
        if y > screenH then y = screenH; growth = "clamped" end
        if y - height < 0 then y = math.min(screenH, height); growth = "clamped" end
    end
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    M._detailsGrowth = {direction = growth, left = x * scale, top = y * scale}
    return growth
end

-- The Orb line's text for this render (UI.PanelRunLine), or nil.
function M.OrbLineText()
    local orb = Nexus.OrbPanel
    if not (orb and type(orb.PanelRunLine) == "function") then return nil end
    local ok, shown, full = pcall(orb.PanelRunLine)
    if not ok or type(shown) ~= "string" or shown == "" then return nil end
    return {shown = shown, full = type(full) == "string" and full or shown}
end

-- Your record and the best known record for the same Echoes (layout rows
-- bestDps, bestKnown, recordNote). Also run on a records-only render.
function M.RenderPlayRecords(model, layout)
    local records = layout ~= nil and layout.boxes ~= nil and layout.boxes.bestKnown ~= nil
    local p = (records or (frame and frame._play)) and M.EnsurePlayWidgets() or nil
    if not p then return end
    SetVisible(p.yoursValue, records); SetVisible(p.bestLabel, records); SetVisible(p.bestValue, records)
    SetVisible(p.bestHit, records); SetVisible(p.note, records)
    if not records then
        bestDpsText:SetJustifyH("CENTER")
        return
    end
    local text = Nexus.UserText
    local function Value(d, l)
        if d and l then return LF("panel.value.records_dummy_and_lk", {dummy = d, lk = l}) end
        if d then return LF("panel.value.records_dps", {dps = d}) end
        if l then return LF("panel.value.records_lk", {dps = l}) end
        return nil
    end
    local best = type(model.bestDps) == "table" and model.bestDps or {}
    local mineD, mineL = PlayDps(best.dummy), PlayDps(best.lk)
    local mine = Value(mineD, mineL)
    bestDpsText:SetJustifyH("LEFT")
    bestDpsText:SetText(PLAY.label .. LT((mineD and not mineL) and "panel.label.yours_training_dummy" or "panel.label.yours") .. "|r")
    p.yoursValue:SetText(mine and (PLAY.value .. mine .. "|r")
        or (PLAY.muted .. LT("panel.value.no_record_yet") .. "|r"))
    local pr = type(model.progress) == "table" and model.progress or {}
    local perf = type(pr.performance) == "table" and pr.performance or {}
    local knownD = PlayDps(type(perf.dummy) == "table" and perf.dummy.global or nil)
    local knownL = PlayDps(type(perf.lk) == "table" and perf.lk.global or nil)
    local known = Value(knownD, knownL)
    p.bestLabel:SetText(PLAY.label .. LF("panel.label.best_known_same_build",
        {best_known = tostring(text and text.BEST_KNOWN or LT("panel.label.best_known"))}) .. "|r")
    if known then
        p.bestValue:SetText(PLAY.value .. known .. "|r")
    else
        -- No record held: say why, from the start-up snapshot. Loading is a
        -- wait and unavailable is named; neither is "0" or "no records".
        local okStatus, status = false, nil
        if type(Nexus.StartupStatus) == "function" then okStatus, status = pcall(Nexus.StartupStatus) end
        local state = okStatus and type(status) == "table" and status.state or nil
        local readout = Nexus.Readout
        local function Kind(kind, fallback)
            return readout and readout.StatusText and readout.StatusText(kind, fallback) or fallback
        end
        if state == "ready" then
            p.bestValue:SetText(PLAY.muted .. LT("panel.value.none_received_yet") .. "|r")
        elseif state == "failed" then
            p.bestValue:SetText(PLAY.wait .. Kind("unavailable", LT("panel.status.shared_data_short")) .. "|r")
        else
            local loading = LT("panel.value.shared_data_loading")
            p.bestValue:SetText(PLAY.wait .. ((readout and readout.StatusParts)
                and (readout.StatusParts("loading").glyph .. " " .. loading) or loading) .. "|r")
        end
    end
    -- The design's note in the shared record-scope words (UserText.RECORD_SCOPE).
    p.note:SetText(PLAY.muted .. LT("panel.note.shared_records_scope") .. "|r")
end

-- The Play summary's content and visibility for this render. `layout` is the
-- responsive layout this pass places (nil without one).
function M.RenderPlaySummary(model, layout)
    local play = layout ~= nil and layout.play == true
    -- The DPS rows also show in the completed view.
    local records = layout ~= nil and type(layout.boxes) == "table" and layout.boxes.bestKnown ~= nil
    local p = (play or records or (frame and frame._play)) and M.EnsurePlayWidgets() or nil
    if not p then return end
    local pr = type(model.progress) == "table" and model.progress or {}
    local details = play and M._playDetails == true
    -- The detail section (native QA test.163008): the four counts and the
    -- names behind them show only while details are shown; Hide details
    -- collapses them and LayoutMetrics.Panel gives back their space. The
    -- counts are worded on every Play render either way, so Show details
    -- restores the same counts. The former tomes row is one of the counts.
    if play then
        SetVisible(needLabel, details); SetVisible(needText, details); SetVisible(needHit, details)
        SetVisible(shedLabel, details); SetVisible(shedText, details); SetVisible(shedHit, details)
        M.ShowDetailRows(needText); M.ShowDetailRows(shedText)
        SetVisible(frame._needLabelHit, details); SetVisible(frame._shedLabelHit, details)
        local toLock = details and #toLockNamesCache > 0
        SetVisible(frame.toLockLabel, toLock); SetVisible(frame.toLockText, toLock); SetVisible(frame.toLockHit, toLock)
        SetVisible(tomesLabel, false); SetVisible(tomesValue, false); SetVisible(tomesHit, false)
    end
    SetVisible(p.details, play); SetVisible(p.track, play)
    for _, widget in ipairs({p.needed, p.tomes, p.extra, p.locked,
        p.neededHit, p.tomesHit, p.extraHit, p.lockedHit}) do SetVisible(widget, details) end
    if play then
        local total, owned = PlayWhole(pr.total), PlayWhole(pr.owned)
        local text = Nexus.UserText
        -- The run's count with its whole unit (UX-13: "rolled copies this
        -- run"), on its own full-width row under the heading, so the unit is
        -- neither cut nor moved to a hover.
        progressValue:SetText(text and text.RunProgressText
            and text.RunProgressText(pr.owned, pr.total, #toLockNamesCache)
            or ((owned and total) and LF("panel.value.run_progress", {owned = LC(owned), total = LC(total)})
                or LT("panel.value.run_progress_unavailable")))
        p.details:SetText(LT(details and "panel.button.details_hide" or "panel.button.details_show"))
        -- The share of planned rolled copies this run has (none while
        -- either count is unknown).
        p.share = (owned and total and total > 0) and {math.min(owned, total), total} or nil
        SetVisible(p.fill, p.share ~= nil and p.share[1] > 0)
        -- English picks "copy"/"copies" (and "Echo"/"Echoes") by count: the
        -- same choice picks one of two reviewed keys (no plural grammar).
        local function Count(n, one, many)
            if n == nil then return "?" end
            return LF(n == 1 and one or many, {count = LC(n)})
        end
        local needed = (owned and total) and math.max(0, total - owned) or nil
        p.needed:SetText(PlayPair(LT("panel.label.play_still_needed"), Count(needed, "panel.value.count_copy", "panel.value.count_copies")))
        local tomes = #unknownTomesCache
        p.tomes:SetText(PlayPair(LT("panel.label.play_missing_tomes"), tomes > 0
            and Count(tomes, "panel.value.count_echo", "panel.value.count_echoes") or LT("panel.value.count_none")))
        local extra = #shedNamesCache
        p.extra:SetText(PlayPair(LT("panel.label.play_extra_copies"), extra > 0
            and LF("panel.value.count_listed", {count = LC(extra)}) or LT("panel.value.count_none")))
        local lock = #toLockNamesCache
        p.locked:SetText(PlayPair(LT("panel.label.play_locked_targets"), lock > 0
            and LF("panel.value.count_to_lock", {count = LC(lock)}) or LT("panel.value.none_to_lock")))
    else
        p.share = nil
        SetVisible(p.fill, false)
    end
    -- The Play panel shows the original difficulty card (design/current
    -- "Nexus Main Panel - Compact Redesign", from the pre-overhaul b0870929
    -- worldStatusBox): its own tier, Soul Ash, multiplier, red Intensity bar,
    -- hover and Hardcore-menu click, in the layout's status box. The former
    -- one-line row stays hidden.
    SetVisible(p.server, false); SetVisible(p.serverHit, false)
    M.RenderPlayRecords(model, layout)
    -- The Orb run line, while a run is known.
    M.RefreshOrbLine(model, layout)
end

-- The Orb line's text, on every render, settled ones included (the run
-- moves without a new model): shown while this render read a run and the
-- layout holds its row.
function M.RefreshOrbLine(model, layout)
    local p = frame and frame._play
    if not p then return end
    local line = type(model) == "table" and model._nexusOrbLine or nil
    local shown = type(line) == "table" and type(layout) == "table" and type(layout.boxes) == "table"
        and layout.boxes.orbLine ~= nil
    if shown then
        p.orb:SetText(line.shown)
        p.orbHit._nexusFull = line.full
    else
        p.orbHit._nexusFull = nil
    end
    SetVisible(p.orb, shown); SetVisible(p.orbHit, shown); SetVisible(p.orbOpen, shown)
end

-- Geometry of the Play summary inside the layout's boxes.
function M.PlacePlaySummary(layout)
    local p = frame and frame._play
    if not (p and layout and layout.boxes) then return end
    local boxes = layout.boxes
    local function Put(widget, box, dx, dw)
        if not (widget and box) then return end
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", frame, "TOPLEFT", box.x + (dx or 0), -box.y)
        widget:SetSize(math.max(1, box.w - (dw or 0)), box.h)
    end
    Put(p.details, boxes.planDetails)
    local bar = boxes.planBar
    if bar then
        Put(p.track, bar)
        p.fill:ClearAllPoints()
        p.fill:SetPoint("TOPLEFT", frame, "TOPLEFT", bar.x, -bar.y)
        local share = p.share
        p.fill:SetSize(math.max(1, share and math.floor(bar.w * share[1] / share[2]) or 0), bar.h)
    end
    Put(p.needed, boxes.planNeeded); Put(p.tomes, boxes.planTomes)
    Put(p.extra, boxes.planExtra); Put(p.locked, boxes.planLocked)
    -- Your value shares the label's row on the right; the label keeps the
    -- left part of it.
    local records = boxes.bestDps
    if records then
        local valueW = math.floor(records.w * 0.55)
        Put(bestDpsText, records, 0, valueW)
        Put(p.yoursValue, records, records.w - valueW, records.w - valueW)
        Put(p.bestLabel, boxes.bestKnown, 0, valueW)
        Put(p.bestValue, boxes.bestKnown, records.w - valueW, records.w - valueW)
        Put(p.note, boxes.recordNote)
    end
    Put(p.orb, boxes.orbLine)
    Put(p.orbOpen, boxes.orbLineOpen)
end

-- The Auto scope line (Claude Design full UI, "Main panel (Play)": with Auto
-- ON, "Auto may choose offers and may save a better finished run over this
-- build. It never loads a build or starts Orbs"), in Readout.AUTO_ON_NOTE's
-- permission-qualified words. Shown in full on its own rows whenever a
-- selected Auto has a roll block, beside a recommendation too, so the scope
-- never retreats into the Auto button's hover; a held or waiting Auto keeps
-- it as well (it states what Auto may do, not that it is acting), which keeps
-- the reserved roll footprint the same through a board cycle. A panel
-- region, not a roll-area row: the roll body and the card rows stay exactly
-- the runtime's. Text only; it reads and decides nothing.
-- Level 80, normal rolls finished, no offer (design/current "Nexus Main Panel
-- - Compact Redesign", Lv80 trigger): the Orb guidance says normal rolls are
-- finished (logic/OrbGuidance.lua "finished", "finished-no-orbs",
-- "finished-unknown"), no card is offered, no recommendation or inline Auto
-- line is shown, no earlier board's card rows are reserved, and a selected
-- Auto is not held (its paused heading stays). Layout only: the guidance,
-- its words and Open Orbs... are the runtime's own. A new offer or any other
-- guidance gives the full block back on the next render. Reads only.
function M.NoOfferState(model, guide, guideText, cardCount, recommendation, autoNote, roll)
    local state = type(guide) == "table" and guide.state or nil
    if state ~= "finished" and state ~= "finished-no-orbs" and state ~= "finished-unknown" then return false end
    if (tonumber(cardCount) or 0) > 0 or tostring(recommendation or "") ~= ""
        or tostring(autoNote or "") ~= "" or tostring(guideText or "") == "" then return false end
    if type(roll) == "table" and roll.cardRows then return false end
    if type(model) == "table" and model.auto and model.paused then return false end
    return true
end

-- Rows of the collapsed guidance in the conservative text model, at the 396
-- px content width less the inline Open Orbs... button and its gap (the
-- LayoutMetrics noOffer geometry). At least one.
function M.NoOfferRows(text, fontScale, button)
    local metrics = Nexus.LayoutMetrics
    if not (metrics and metrics.TextRows and metrics.ConservativeText) then return 1 end
    local char = metrics.ConservativeText(fontScale)
    local width = 396 - (button and (math.ceil(12 * char) + 20 + math.ceil(6 * (tonumber(fontScale) or 1))) or 0)
    return math.max(1, metrics.TextRows(text, math.max(1, width), fontScale))
end

function M.AutoScopeShown(model, rollBlock, noBuild)
    return type(model) == "table" and model.auto == true and rollBlock and not noBuild and true or false
end

-- The real fallback of that row. AutoNoteFor leaves the scope line out of the
-- roll body while LayoutMetrics is loaded, because the layout gives it its own
-- row. When this pass has no layout with that row (LayoutMetrics.Panel or
-- RuntimeMetrics failed and no earlier layout, or only an earlier layout
-- without the row, is at hand), the same words are added to the body on their
-- own line, so a selected Auto always shows what it may do. With the row they
-- are not repeated. Without LayoutMetrics, AutoNoteFor's own body line stays
-- as it was. Text only; it reads and decides nothing.
function M.AutoScopeFallback(body, model, rollBlock, noBuild, layout)
    local note = Nexus.Readout and Nexus.Readout.AUTO_ON_NOTE
    if not Nexus.LayoutMetrics or type(note) ~= "string"
        or not M.AutoScopeShown(model, rollBlock, noBuild) then return body end
    local boxes = type(layout) == "table" and type(layout.boxes) == "table" and layout.boxes or nil
    if boxes and boxes.autoScope then return body end
    body = tostring(body or "")
    if body:find(note, 1, true) then return body end
    return (body ~= "" and (body .. "\n") or "") .. note
end

-- Places and fills the line from the layout's autoScope box (none: hidden).
-- Built lazily and reached through M: EnsureFrame is at the upvalue ceiling.
function M.RenderAutoScope(layout)
    local box = type(layout) == "table" and type(layout.boxes) == "table" and layout.boxes.autoScope or nil
    local line = frame and frame._autoScopeText
    local note = Nexus.Readout and Nexus.Readout.AUTO_ON_NOTE
    if not (box and frame and type(note) == "string") then
        if line then line:Hide() end
        return false
    end
    if not line then
        local metrics = Nexus.LayoutMetrics
        line = frame:CreateFontString(nil, "OVERLAY", metrics and metrics.FontObject
            and metrics.FontObject("small") or "GameFontHighlightSmall")
        line:SetJustifyH("LEFT")
        line:SetJustifyV("TOP")
        line:SetWordWrap(true)
        -- A fixed status colour beside the words, never from the palette.
        line:SetTextColor(1, 0.68, 0.42)
        frame._autoScopeText = line
    end
    line:SetText(note)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", frame, "TOPLEFT", box.x, -box.y)
    line:SetSize(box.w, box.h)
    line:Show()
    return true
end

-- Built lazily: EnsureFrame is at the Lua 3.3.5 upvalue ceiling.
local function EnsureCallboardWidgets()
    if not frame or frame._callboardLabel then return end
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    label:SetText(LT("panel.heading.callboard"))
    label:SetJustifyH("LEFT")
    frame._callboardLabel = label
    local icon = CreateFrame("Button", nil, frame)
    icon:SetSize(22, 22)
    icon:EnableMouse(true)
    local tex = icon:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\Icons\\INV_Misc_Bag_10")
    icon.texture = tex
    icon:SetScript("OnEnter", function(self)
        if Nexus.CallboardStatus and Nexus.CallboardStatus.ShowRewardsTooltip then
            Nexus.CallboardStatus.ShowRewardsTooltip(self)
        end
    end)
    icon:SetScript("OnLeave", function()
        if Nexus.CallboardStatus and Nexus.CallboardStatus.HideTooltip then
            Nexus.CallboardStatus.HideTooltip()
        end
    end)
    M.PassiveDragSurface(icon)
    frame._callboardIcon = icon
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    title:SetJustifyH("LEFT")
    title:SetJustifyV("TOP")
    title:SetWordWrap(false)
    title:SetTextColor(1, 0.82, 0)
    frame._callboardTitle = title
    local titleHit = CreateFrame("Frame", nil, frame)
    titleHit:EnableMouse(true)
    frame._callboardTitleHit = titleHit
    local line = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    line:SetJustifyH("LEFT")
    line:SetJustifyV("TOP")
    line:SetWordWrap(false)
    line:SetTextColor(0.85, 0.85, 0.85)
    frame._callboardLine = line
    local lineHit = CreateFrame("Frame", nil, frame)
    lineHit:EnableMouse(true)
    frame._callboardLineHit = lineHit
    -- The detail row shows the first objective line and +N more. Its hover
    -- shows every complete line in order, from the lines the last render
    -- stored (FillCallboard); it reads no Callboard data itself.
    lineHit:SetScript("OnEnter", function(self)
        local full = self._nexusFullLines
        if not (GameTooltip and type(full) == "table" and #full > 0) then return end
        local layout = Nexus.LayoutMetrics
        local shortened = layout and layout.Shortened and layout.Shortened(line)
        if #full == 1 and not shortened then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for _, text in ipairs(full) do GameTooltip:AddLine(text, 1, 1, 1, true) end
        GameTooltip:Show()
        self._nexusFullTip = true
    end)
    lineHit:SetScript("OnLeave", function(self)
        if self._nexusFullTip and GameTooltip then GameTooltip:Hide() end
        self._nexusFullTip = nil
    end)
    if Nexus.LayoutMetrics and Nexus.LayoutMetrics.OneLineLabel then
        Nexus.LayoutMetrics.OneLineLabel(title, titleHit, 17)
        -- One 17px line. The row's own hover above replaces the label-text
        -- hover, so that hover is not added to this row.
        Nexus.LayoutMetrics.OneLineLabel(line, nil, 17)
    end
    -- Last, after every tooltip-producing OnEnter of the two rows (the
    -- title's complete-text hover from OneLineLabel included), so a move's
    -- tooltip suppression runs after them.
    M.PassiveDragSurface(titleHit)
    M.PassiveDragSurface(lineHit)
    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    pcall(function() divider:SetTexture(0.3, 0.3, 0.3, 0.65) end)
    frame._callboardDivider = divider
end

-- The title and detail hover areas follow their rows: shown and taking the
-- mouse only while an objective is observed. Without one, each area is
-- hidden and takes no mouse input, and its hover state is cleared, so no
-- earlier objective's text stays reachable. A complete-text tooltip it
-- opened itself is closed only while the tooltip reports this area as its
-- current owner. Another owner, no reported owner or an owner read that
-- fails does not show that the tooltip is still this area's: it stays open.
-- Geometry stays with PlaceCallboardBox and PlaceCallboardManual.
local function SetCallboardHit(hit, active)
    if not hit then return end
    if active then
        hit:EnableMouse(true)
        hit:Show()
        return
    end
    if (hit._nexusFullTip or hit._nexusOneLineTip) and GameTooltip then
        -- Positive identity only: a missing, failing or nil owner read, or
        -- another owner, leaves owned false. rawequal runs no metamethod.
        local ok, owned = pcall(function()
            return rawequal(GameTooltip:GetOwner(), hit)
        end)
        if ok and owned == true then GameTooltip:Hide() end
    end
    hit._nexusFullTip, hit._nexusOneLineTip = nil, nil
    hit:EnableMouse(false)
    hit:Hide()
end

local function FillCallboard(summary)
    EnsureCallboardWidgets()
    if not summary or summary.observed ~= true then
        SetVisible(frame._callboardLabel, false)
        SetVisible(frame._callboardTitle, false)
        SetVisible(frame._callboardLine, false)
        SetVisible(frame._callboardIcon, false)
        SetVisible(frame._callboardDivider, false)
        SetCallboardHit(frame._callboardTitleHit, false)
        SetCallboardHit(frame._callboardLineHit, false)
        -- No objective: the detail hover keeps no earlier complete lines.
        if frame._callboardLineHit then frame._callboardLineHit._nexusFullLines = nil end
        return false
    end
    local callboard = Nexus.CallboardStatus
    if callboard and callboard.IconTexture and frame._callboardIcon and frame._callboardIcon.texture then
        frame._callboardIcon.texture:SetTexture(callboard.IconTexture())
    end
    frame._callboardLabel:SetText(LT("panel.heading.callboard"))
    frame._callboardTitle:SetText(summary.title or LT("panel.label.callboard_objective"))
    local detail = ""
    -- Every complete detail line, in order, for the row's hover: a new table
    -- on each render, so an earlier objective's lines are never shown.
    local fullLines = {}
    if type(summary.lines) == "table" then
        for i = 1, #summary.lines do
            if summary.lines[i] ~= nil then fullLines[#fullLines + 1] = tostring(summary.lines[i]) end
        end
    end
    if frame._callboardLineHit then frame._callboardLineHit._nexusFullLines = fullLines end
    if type(summary.lines) == "table" and summary.lines[1] then
        detail = tostring(summary.lines[1])
        if #summary.lines > 1 then
            detail = detail .. "  |cff888888" .. LF("panel.label.more_count", {count = LC(#summary.lines - 1)}) .. "|r"
        end
    end
    frame._callboardLine:SetText(detail ~= "" and detail or ("|cff888888" .. LT("panel.label.callboard_no_details") .. "|r"))
    SetVisible(frame._callboardLabel, true)
    SetVisible(frame._callboardIcon, true)
    SetVisible(frame._callboardTitle, true)
    SetVisible(frame._callboardLine, true)
    SetVisible(frame._callboardDivider, true)
    SetCallboardHit(frame._callboardTitleHit, true)
    SetCallboardHit(frame._callboardLineHit, true)
    return true
end

-- Manual fallback when LayoutMetrics is unavailable (negative Y from TOPLEFT).
local function CallboardLineHeight(layout)
    local lineH = layout and tonumber(layout.callboardLine) or nil
    if not lineH and Nexus.LayoutMetrics and Nexus.LayoutMetrics.ConservativeText then
        local _, measured = Nexus.LayoutMetrics.ConservativeText(layout and layout.scale or 1)
        lineH = measured
    end
    if not lineH or lineH < 17 then lineH = 17 end
    return lineH
end

local function PlaceCallboardManual(top)
    if not frame or not frame._callboardLabel then return end
    local lineH = CallboardLineHeight(nil)
    SetPoint(frame._callboardLabel, "TOPLEFT", frame, "TOPLEFT", 12, top)
    SetPoint(frame._callboardIcon, "TOPLEFT", frame, "TOPLEFT", 12, top - 14)
    SetPoint(frame._callboardTitle, "TOPLEFT", frame, "TOPLEFT", 38, top - 14)
    frame._callboardTitle:SetSize(220, lineH)
    if frame._callboardTitleHit then
        SetPoint(frame._callboardTitleHit, "TOPLEFT", frame, "TOPLEFT", 38, top - 14)
        frame._callboardTitleHit:SetSize(220, lineH)
    end
    SetPoint(frame._callboardLine, "TOPLEFT", frame, "TOPLEFT", 38, top - (14 + lineH))
    frame._callboardLine:SetSize(220, lineH)
    if frame._callboardLineHit then
        SetPoint(frame._callboardLineHit, "TOPLEFT", frame, "TOPLEFT", 38, top - (14 + lineH))
        frame._callboardLineHit:SetSize(220, lineH)
    end
    if frame._callboardDivider then
        SetPoint(frame._callboardDivider, "TOPLEFT", frame, "TOPLEFT", 11, top - (14 + lineH + lineH + 3))
        frame._callboardDivider:SetSize(250, 1)
    end
end

local function PlaceCallboardBox(box, layout)
    if not box or not frame or not frame._callboardLabel then return end
    local small = layout and layout.small or 11
    local function place(widget, x, y, w, h)
        if not widget then return end
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", frame, "TOPLEFT", x, -y)
        widget:SetSize(w, h)
    end
    place(frame._callboardLabel, box.x, box.y, box.w, small)
    place(frame._callboardIcon, box.x, box.y + small + 2, 22, 22)
    local lineH = CallboardLineHeight(layout)
    local titleY = box.y + small + 2
    place(frame._callboardTitle, box.x + 26, titleY,
        math.max(1, box.w - 26), lineH)
    place(frame._callboardTitleHit, box.x + 26, titleY,
        math.max(1, box.w - 26), lineH)
    local lineY = titleY + lineH
    place(frame._callboardLine, box.x + 26, lineY,
        math.max(1, box.w - 26), lineH)
    place(frame._callboardLineHit, box.x + 26, lineY,
        math.max(1, box.w - 26), lineH)
    if frame._callboardDivider then
        place(frame._callboardDivider, box.x - 1, box.y + box.h - 1, box.w + 2, 1)
    end
end

local function RenderCallboard(summary, top)
    if FillCallboard(summary) then
        PlaceCallboardManual(top)
    end
end

local function ShowPerformance(show)
    SetVisible(performanceLabel, show); SetVisible(setLabelText, show)
    SetVisible(dummyLabel, show); SetVisible(dummyValue, show); SetVisible(dummyGlobal, show); SetVisible(dummyGlobalValue, show); SetVisible(dummyHit, show)
    SetVisible(lkLabel, show); SetVisible(lkPersonalLabel, show); SetVisible(lkValue, show); SetVisible(lkGlobal, show); SetVisible(lkGlobalValue, show); SetVisible(lkHit, show)
end

local function RenderPerformanceState(pr, completed, enabled)
    ShowPerformance(enabled)
    if enabled then RenderPerformance(pr, completed) end
end

function M.Init(cb)
    if cb ~= nil then callbacks = cb end
    pcall(EnsureMinimapButton)
end

function M.SetAuto(auto)
    -- Auto ON ends the line of an earlier refused click.
    if auto then M._autoRefusal = nil end
    if autoBtn then autoBtn:SetText(AutoLabel(auto and true or false)) end
    ReleaseRollOnAutoOff(auto and true or false)
end

-- /nexus panel and the minimap button: the player's own hide or show, saved
-- through M.Hide / M.Show.
function M.Toggle()
    local f = EnsureFrame()
    if f:IsShown() then M.Hide() else M.Show() end
end

local function LayoutServerStatus(completed)
    worldStatusBox:ClearAllPoints()
    worldStatusText:ClearAllPoints()
    worldStatusAsh:ClearAllPoints()
    worldStatusGain:ClearAllPoints()
    worldStatusBox.intensityBar:ClearAllPoints()

    if completed then
        worldStatusBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -33)
        worldStatusBox:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -33)
        worldStatusBox:SetHeight(66)

        worldStatusText:SetPoint("TOPLEFT", worldStatusBox, "TOPLEFT", 9, -5)
        worldStatusText:SetSize(156, 18)
        worldStatusText:SetJustifyH("LEFT")

        worldStatusAsh:SetPoint("BOTTOMLEFT", worldStatusBox, "BOTTOMLEFT", 9, 5)
        worldStatusAsh:SetSize(164, 17)
        worldStatusAsh:SetJustifyH("LEFT")

        worldStatusGain:SetPoint("TOPRIGHT", worldStatusBox, "TOPRIGHT", -9, -7)
        worldStatusGain:SetSize(66, 13)
        worldStatusGain:SetJustifyH("RIGHT")

        worldStatusAsh:ClearAllPoints()
        worldStatusAsh:SetPoint("TOPLEFT", worldStatusText, "BOTTOMLEFT", 0, -1)
        worldStatusAsh:SetSize(188, 17)

        worldStatusBox.intensityBar:ClearAllPoints()
        worldStatusBox.intensityBar:SetPoint("BOTTOMLEFT", worldStatusBox, "BOTTOMLEFT", 9, 5)
        worldStatusBox.intensityBar:SetPoint("BOTTOMRIGHT", worldStatusBox, "BOTTOMRIGHT", -9, 5)
        worldStatusBox.intensityBar:SetHeight(13)
        worldStatusBox.PositionIntensityTicks()
    else
        -- Give active builds the same readable status-card treatment as the
        -- completed HUD.  The old compressed strip made Soul Ash and Intensity
        -- feel secondary even though they are the player's live run state.
        worldStatusBox:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -33)
        worldStatusBox:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -33)
        worldStatusBox:SetHeight(56)

        worldStatusText:SetPoint("TOPLEFT", worldStatusBox, "TOPLEFT", 9, -5)
        worldStatusText:SetSize(104, 16)
        worldStatusText:SetJustifyH("LEFT")

        worldStatusAsh:SetPoint("TOPLEFT", worldStatusText, "BOTTOMLEFT", 0, -2)
        worldStatusAsh:SetSize(172, 17)
        worldStatusAsh:SetJustifyH("LEFT")

        worldStatusGain:SetPoint("TOPRIGHT", worldStatusBox, "TOPRIGHT", -9, -7)
        worldStatusGain:SetSize(70, 14)
        worldStatusGain:SetJustifyH("RIGHT")

        worldStatusBox.intensityBar:ClearAllPoints()
        worldStatusBox.intensityBar:SetPoint("BOTTOMLEFT", worldStatusBox, "BOTTOMLEFT", 9, 5)
        worldStatusBox.intensityBar:SetPoint("BOTTOMRIGHT", worldStatusBox, "BOTTOMRIGHT", -9, 5)
        worldStatusBox.intensityBar:SetHeight(10)
        worldStatusBox.PositionIntensityTicks()
    end
end

-- Auto keeps its existing consentful click handler, now in the header. The
-- footer contains navigation only; moving between hubs never toggles Auto.
local function LayoutFooter(showAuto)
    -- Header line 1 (M.HeaderSlots): Options beside Close, Auto beside Options.
    local slots = M.PlaceOptionsButton()

    local orbsHub = frame._orbsHubBtn
    autoBtn:ClearAllPoints()
    planBtn:ClearAllPoints()
    exploreBtn:ClearAllPoints()
    orbsHub:ClearAllPoints()

    if showAuto then
        autoBtn:Show()
        autoBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -slots.auto, -slots.top)
        autoBtn:SetSize(slots.autoWidth, slots.height)
        AUTO_LABEL.Fit()
    else autoBtn:Hide() end
    -- Three 116 px hubs and the 24 px FAQ shortcut (M.EnsureFaqButton) at
    -- their right: 10 + 3 x 116 + 2 x 10 + 8 + 24 = 410 of the 420 px row.
    planBtn:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 7)
    planBtn:SetSize(116, 22)
    exploreBtn:SetPoint("LEFT", planBtn, "RIGHT", 10, 0)
    exploreBtn:SetSize(116, 22)
    orbsHub:SetPoint("LEFT", exploreBtn, "RIGHT", 10, 0)
    orbsHub:SetSize(116, 22)

    planBtn:Show()
    exploreBtn:Show()
    orbsHub:Show()
    local faq = M.EnsureFaqButton()
    if faq then
        faq:ClearAllPoints()
        faq:SetPoint("LEFT", orbsHub, "RIGHT", 8, 0)
        faq:SetSize(24, 22)
        faq:Show()
    end
end

local function PlacePanelRect(widget, x, y, width, height, relative)
    if not widget then return end
    widget:ClearAllPoints()
    widget:SetPoint("TOPLEFT",relative or frame,"TOPLEFT",x,-y)
    widget:SetSize(width,height)
end

local function PlacePanelBox(widget, box, relative)
    if not box then return end
    PlacePanelRect(widget,box.x,box.y,box.w,box.h,relative)
end

-- Apply one cached geometry snapshot after the state renderer has populated
-- text and visibility. This final pass owns positions; model rendering remains
-- free to update content without rebuilding or measuring the frame tree.
local function ApplyPanelLayout(layout, completed)
    if not (layout and frame) then return end
    local boxes = layout.boxes
    frame._responsiveLayout = layout
    frame:SetSize(layout.width, layout.height)

    if boxes.status then PlacePanelBox(worldStatusBox, boxes.status) end
    if boxes.roll then
        PlacePanelBox(rollArea, boxes.roll)
        local inset = 2
        local y = 1
        statusText:ClearAllPoints()
        statusText:SetPoint("TOPLEFT", rollArea, "TOPLEFT", inset, -y)
        statusText:SetSize(boxes.roll.w-inset*2, layout.small)
        local charges = frame._chargesText
        if charges then
            charges:ClearAllPoints()
            charges:SetPoint("TOPRIGHT", rollArea, "TOPRIGHT", -inset, -y)
            charges:SetSize(72, layout.small)
            -- The heading keeps the rest of its row while charges are shown.
            if charges:IsShown() then statusText:SetWidth(boxes.roll.w-inset*2-76) end
        end
        y = y + layout.small + math.max(3,math.floor(layout.gap/2))
        for index = 1, 3 do
            local text = cardTexts[index]
            text:ClearAllPoints()
            text:SetPoint("TOPLEFT", rollArea, "TOPLEFT", inset, -y)
            text:SetSize(boxes.roll.w-inset*2, layout.small)
            y = y + layout.small + math.max(2,math.floor(layout.gap/3))
        end
        -- The offer cards take the same band as these rows (in three columns,
        -- or stacked rows when a status line does not fit a column).
        M.PlaceOfferCards(layout, boxes.roll, inset)
        -- Guidance alone (no cards) starts right below the heading, so it
        -- has the card rows' space; with cards it follows them as before.
        local noCards = true
        for index = 1, 3 do
            if (cardTexts[index]:GetText() or "") ~= "" then noCards = false end
        end
        local recY = y
        if noCards then
            recY = 1 + layout.small + math.max(3,math.floor(layout.gap/2))
        end
        local button = frame._orbsBtn
        local buttonRow = 0
        -- The ordinary bottom button row with the mini-panel access. The
        -- collapsed level-80 layout has no such row (no mini fields either);
        -- it places Open Orbs... inline below.
        if button and button:IsShown() and layout.orbButtonH and not layout.noOffer then
            buttonRow = layout.orbButtonH + math.ceil(layout.gap/2)
            button:ClearAllPoints()
            button:SetPoint("BOTTOMRIGHT", rollArea, "BOTTOMRIGHT", -inset, math.ceil(layout.gap/2))
            button:SetSize(layout.orbButtonW, layout.orbButtonH)
            local miniButton = frame._orbMiniBtn
            if miniButton then
                miniButton:ClearAllPoints()
                miniButton:SetPoint("RIGHT", button, "LEFT", -layout.orbMiniButtonGap, 0)
                miniButton:SetSize(layout.orbMiniButtonW, layout.orbButtonH)
                -- LayoutMetrics chooses the full or short label by room, in
                -- its own English; that choice is shown here as reviewed text.
                local miniLabel = layout.orbMiniButtonLabel
                miniButton:SetText(miniLabel == "Mini" and LT("panel.button.orb_mini_short")
                    or miniLabel == "Orb mini panel" and LT("panel.button.orb_mini") or miniLabel)
                M.FitOrbMiniButton(miniButton)
            end
        end
        recText:ClearAllPoints()
        recText:SetPoint("TOPLEFT", rollArea, "TOPLEFT", inset, -recY)
        recText:SetSize(boxes.roll.w-inset*2,
            math.max(layout.small*2,boxes.roll.h-recY-layout.gap-buttonRow))
        rollDivider:ClearAllPoints()
        rollDivider:SetPoint("BOTTOMLEFT", rollArea, "BOTTOMLEFT", 1, 0)
        rollDivider:SetSize(boxes.roll.w-2,1)
        -- The collapsed level-80 block (M.NoOfferState): no heading row, the
        -- guidance from the top, Open Orbs... inline at its right; the
        -- optional mini-panel access stays in the Orb window.
        if layout.noOffer then
            statusText:Hide()
            local inline = 0
            if button and button:IsShown() and layout.orbButtonW then
                inline = layout.orbButtonW + layout.gap
                button:ClearAllPoints()
                button:SetPoint("TOPRIGHT", rollArea, "TOPRIGHT", -inset, 0)
                button:SetSize(layout.orbButtonW, layout.orbButtonH)
            end
            if frame._orbMiniBtn then frame._orbMiniBtn:Hide() end
            -- From the block's top, the whole box: LayoutMetrics sizes it to
            -- the guidance (or the button) alone, with no padding.
            recText:ClearAllPoints()
            recText:SetPoint("TOPLEFT", rollArea, "TOPLEFT", inset, 0)
            recText:SetSize(math.max(1, boxes.roll.w-inset*2-inline), math.max(1, boxes.roll.h))
        else
            statusText:Show()
        end
    end

    PlacePanelBox(setupText, boxes.setupTitle)
    PlacePanelBox(setupHint, boxes.setupHint)
    PlacePanelBox(setupGetStartedBtn, boxes.setupAssign)
    PlacePanelBox(setupImportBtn, boxes.setupCreate)
    PlacePanelBox(completeBadge, boxes.completeTitle)
    PlacePanelBox(completeSubtext, boxes.completeText)
    if boxes.callboard then
        EnsureCallboardWidgets()
        PlaceCallboardBox(boxes.callboard, layout)
    end
    -- The heading keeps one small line (issue #143), centred in the Play
    -- heading row, which is as tall as its Details button.
    local header = boxes.progressHeader
    if header then
        PlacePanelRect(progressLabel, header.x,
            header.y + math.max(0, math.floor((header.h - layout.small) / 2)), header.w, layout.small)
    end
    PlacePanelBox(progressValue, boxes.progressValue)

    if boxes.tomes then
        tomesLabel:SetText(LT("panel.heading.missing_tomes"))
        PlacePanelRect(tomesLabel,boxes.tomes.x,boxes.tomes.y,
            boxes.tomes.w-28,boxes.tomes.h)
        tomesLabel:SetJustifyH("LEFT")
        PlacePanelRect(tomesValue,boxes.tomes.x+boxes.tomes.w-24,
            boxes.tomes.y,24,boxes.tomes.h)
    end

    local labelGap = math.max(3,math.floor(layout.gap/2))
    if boxes.needed then
        PlacePanelRect(needLabel,boxes.needed.x,boxes.needed.y,
            boxes.needed.w,layout.small)
        PlacePanelRect(needText,boxes.needed.x,
            boxes.needed.y+layout.small+labelGap,boxes.needed.w,
            boxes.needed.h-layout.small-labelGap)
        M.PlaceDetailRows(needText)
    end
    if boxes.shed then
        PlacePanelRect(shedLabel,boxes.shed.x,boxes.shed.y,
            boxes.shed.w,layout.small)
        PlacePanelRect(shedText,boxes.shed.x,
            boxes.shed.y+layout.small+labelGap,boxes.shed.w,
            boxes.shed.h-layout.small-labelGap)
        M.PlaceDetailRows(shedText)
    end
    if boxes.toLock and frame.toLockLabel then
        PlacePanelRect(frame.toLockLabel,boxes.toLock.x,boxes.toLock.y,
            boxes.toLock.w,layout.small)
        PlacePanelRect(frame.toLockText,boxes.toLock.x,
            boxes.toLock.y+layout.small+labelGap,boxes.toLock.w,
            boxes.toLock.h-layout.small-labelGap)
        frame.toLockHit:ClearAllPoints()
        frame.toLockHit:SetPoint("TOPLEFT",frame.toLockLabel,"TOPLEFT",-2,2)
        frame.toLockHit:SetPoint("BOTTOMRIGHT",frame.toLockText,"BOTTOMRIGHT",2,-2)
    end
    if boxes.performance then
        PositionPerformance(-boxes.performance.y,completed,layout)
    end
    PlacePanelBox(bestDpsText, boxes.bestDps)
    M.PlacePlaySummary(layout)
    -- Show / Hide details keeps the panel's top where it was: ApplyCandidate
    -- installs the held corner after the final fit (M.HoldPanelTop).
end

local function RenderBestDps(model, complete, noBuild, activeRoll, statusVisible)
    local best = type(model.bestDps) == "table" and model.bestDps or {}
    local dummyBest, lkBest = best.dummy, best.lk
    if dummyBest or lkBest then
        local dummyText = dummyBest and ("|cff4dff80" .. FmtDps(dummyBest.dps) .. "|r") or "|cff777777—|r"
        local lkText = lkBest and ("|cff4dff80" .. FmtDps(lkBest.dps) .. "|r") or "|cff777777—|r"
        -- M4 (UX-14): the character's own records, not a shared ranking.
        bestDpsText:SetText("|cffb8b8b8" .. LT("panel.label.your_best_dps") .. "|r  "
            .. LF("panel.label.best_dps_dummy", {dps = dummyText}) .. "  |cff666666•|r  "
            .. LF("panel.label.best_dps_lk", {dps = lkText}))
    else
        bestDpsText:SetText("|cff888888" .. LT("panel.label.best_dps_none") .. "|r")
    end
    if not noBuild then
        bestDpsText:Show()
        bestDpsHit:Show()
    else
        bestDpsText:Hide()
        bestDpsHit:Hide()
    end
end

local function ApplyModel(model, signatures, roll)
    local previousSignatures = renderState.signatures
    if previousSignatures and signatures.layout == previousSignatures.layout then
        local changed = false
        if signatures.notice ~= previousSignatures.notice then
            frame._menuBtn:SetText(M.OptionsText(model.updateNotice))
            renderStats.noticePasses = renderStats.noticePasses + 1
            changed = true
        end
        if signatures.performance ~= previousSignatures.performance then
            local pr = type(model.progress) == "table" and model.progress or {}
            local total, owned = tonumber(pr.total) or 0, tonumber(pr.owned) or 0
            local complete = total > 0 and owned >= total
                and #(type(pr.toLock) == "table" and pr.toLock or {}) == 0
            local cards = type(model.cards) == "table" and model.cards or {}
            local guide = type(model.orbGuidance) == "table" and model.orbGuidance or nil
            local activeRoll = #cards > 0 or SafeText(model.recommendation) ~= ""
                or (guide and SafeText(guide.text) ~= "") or SafeText(model.autoNote) ~= "" or false
            local noBuild = total <= 0 or not pr.wishlistName
            local ss = type(model.serverStatus) == "table" and model.serverStatus or nil
            local statusVisible = ss and (ss.tier or ss.mode or ss.ash
                or ss.gain or ss.intensity ~= nil) and true or false
            RenderPerformanceState(pr, complete, not noBuild and showPerformance)
            RenderBestDps(model, complete, noBuild, activeRoll, statusVisible)
            M.RenderPlayRecords(model, frame._responsiveLayout)
            renderStats.performancePasses = renderStats.performancePasses + 1
            changed = true
        end
        -- C-02: the difficulty card's values alone (Soul Ash, multiplier,
        -- Intensity) take no layout pass.
        if signatures.serverValues ~= previousSignatures.serverValues then
            M.RefreshServerStatusValues(model)
            changed = true
        end
        if signatures.auto ~= previousSignatures.auto
            and frame._autoBtn:IsShown() then
            frame._autoBtn:SetText(AutoLabel(model.auto))
            changed = true
        end
        if signatures.status ~= previousSignatures.status then
            renderStats.statusOnly = renderStats.statusOnly + 1
            changed = true
        end
        if not changed then renderStats.skipped = renderStats.skipped + 1 end
        -- Settled: no layout pass ran (ApplyCandidate, C-03).
        return true, true
    end
    renderStats.layouts = renderStats.layouts + 1
    if frame._menuBtn then
        frame._menuBtn:SetText(M.OptionsText(model.updateNotice))
    end

    local pr = type(model.progress) == "table" and model.progress or {}
    local name = pr.wishlistName
    local total = tonumber(pr.total) or 0
    local owned = tonumber(pr.owned) or 0
    -- A build is not complete while one of its designed permanent slots is
    -- still unresolved. This keeps the TO LOCK row visible at 79/79 until the
    -- server confirms the exact Echo in GetLockedPerks().
    local complete = total > 0 and owned >= total
        and #(type(pr.toLock) == "table" and pr.toLock or {}) == 0
    local cards = type(model.cards) == "table" and model.cards or {}
    local recommendation = SafeText(model.recommendation)
    local guide = type(model.orbGuidance) == "table" and model.orbGuidance or nil
    -- With no build, the setup view already names the missing Wishlist. The
    -- model keeps English; the guidance says it in the shown language.
    local guidance = Nexus.OrbGuidance
    local guideText = (guide and total > 0 and name) and SafeText(guidance and guidance.Shown
        and guidance.Shown(guide.text) or guide.text) or ""
    -- The inline Auto line (M.AutoNoteFor): why a selected Auto is not acting,
    -- or why the last Auto click left it OFF. It shows the roll block too.
    local autoNote = SafeText(model.autoNote)
    local activeRoll = #cards > 0 or recommendation ~= "" or guideText ~= "" or autoNote ~= ""
    -- The roll block's space: current content, or a reservation through an
    -- ordinary gap between choices (RollPresentation). Content and actions
    -- still come only from the current model.
    local rollBlock = activeRoll or (type(roll) == "table" and roll.reserved) or false
    -- Level 80 with normal rolls finished and no offer (design/current "Nexus
    -- Main Panel - Compact Redesign", Lv80): layout only, the block collapses
    -- to its guidance and inline Open Orbs... (M.NoOfferState).
    local noOffer = M.NoOfferState(model, guide, guideText, #cards, recommendation, autoNote, roll)
    -- The roll body: an unresolved Orb run's own reason first, else the
    -- recommendation (which carries an Orb pause reason), else the guidance.
    local bodyText = (guide and guide.state == "orb-run" and guideText ~= "") and guideText
        or (recommendation ~= "" and recommendation or guideText)
    local noBuild = total <= 0 or not name
    local ss = type(model.serverStatus) == "table" and model.serverStatus or nil
    local statusVisible = ss and (ss.tier or ss.mode or ss.ash or ss.gain or ss.intensity ~= nil) and true or false
    local playerLevel = tonumber(model.level) or 0
    -- Auto controls are useful only while actively progressing a build. At level
    -- 80 or once the destination is complete, the button is removed entirely
    -- instead of presenting an action that can no longer help the player.
    -- Keep the master Auto control visible for every active offering,
    -- including level 80 and completed-target boards. Toggling Auto off must
    -- never make the control used to turn it back on disappear.
    local showAutoControl = not noBuild and (rollBlock or (not complete and playerLevel < 80))
    local callboardSummary = Nexus.CallboardStatus and Nexus.CallboardStatus.GetSummary
        and Nexus.CallboardStatus.GetSummary() or nil
    -- Callboard belongs with the difficulty / Soul Ash HUD, not the wishlist
    -- progress block: keep it while an objective is observed, including the
    -- no-wishlist setup view.
    local callboardObserved = callboardSummary and callboardSummary.observed == true
    local responsiveLayout
    if Nexus.LayoutMetrics then
        local metricsOk, fontScale, uiScale, revision =
            pcall(Nexus.LayoutMetrics.RuntimeMetrics)
        if metricsOk then
            -- M.PanelLayout: LayoutMetrics.Panel, with open Details name
            -- columns at their measured height.
            local layoutOk, candidate = pcall(M.PanelLayout,{
                width=420,fontScale=fontScale,uiScale=uiScale,
                revision=revision,activeRoll=rollBlock,
                statusVisible=statusVisible,noBuild=noBuild,
                complete=complete,showPerformance=showPerformance,
                toLockCount=type(pr.toLock) == "table" and #pr.toLock or 0,
                unknownTomes=type(pr.unknownTomes) == "table"
                    and #pr.unknownTomes or 0,
                orbButton=(activeRoll and guide and guide.openOrbs
                    and total > 0 and name) and true or false,
                -- Rows for the body while it shows the Orb guidance or,
                -- with the Open Orbs button, the Orb pause reason; or, below
                -- the cards, the recommendation with the inline Auto line
                -- (without cards the body already has the card rows' space).
                noOffer=noOffer,
                guidanceRows=noOffer and M.NoOfferRows(guideText, fontScale, guide.openOrbs)
                    or (autoNote ~= "" and #cards > 0)
                    and Nexus.LayoutMetrics.TextRows((bodyText ~= "" and (bodyText .. "\n") or "")
                        .. autoNote, 248, fontScale)
                    or (guideText ~= "" and (bodyText == guideText
                    or guide.openOrbs))
                    and Nexus.LayoutMetrics.TextRows(bodyText, 248, fontScale)
                    or 0,
                cardRows=#cards > 0 or (type(roll) == "table" and roll.cardRows) or false,
                callboard=callboardObserved and true or false,
                planDetails=M._playDetails == true,
                orbLine=type(model._nexusOrbLine) == "table",
                -- The Auto scope line's rows (M.RenderAutoScope), at the
                -- 396 px content width of the 420 px panel.
                -- Not in the collapsed level-80 block: no offer, nothing to choose.
                autoScopeRows=M.AutoScopeShown(model, rollBlock and not noOffer, noBuild)
                    and Nexus.Readout and Nexus.Readout.AUTO_ON_NOTE
                    and Nexus.LayoutMetrics.TextRows(Nexus.Readout.AUTO_ON_NOTE, 396, fontScale)
                    or 0,
            }, pr)
            if layoutOk and type(candidate) == "table" then
                responsiveLayout = candidate
            end
        end
        if not responsiveLayout and frame then
            responsiveLayout = frame._responsiveLayout
        end
    end
    LayoutFooter(showAutoControl)

    -- The heading is the destination row's first cell: it is worded and
    -- fitted at the end of this pass (UpdateDestinationRow), not here.
    frame._switchBtn:SetText((Nexus.Localization.Text("panel.button.my_builds")))

    -- LayoutMetrics owns callboard geometry when present; the manual path
    -- only reserves height and places widgets when that layout is absent.
    local callboardTop = statusVisible and -98 or -39
    local callboardExtra = (not responsiveLayout and callboardObserved) and 50 or 0
    FillCallboard(callboardObserved and callboardSummary or nil)
    if not responsiveLayout and callboardObserved then
        PlaceCallboardManual(callboardTop)
    end

    SetVisible(frame._rollArea, rollBlock)
    frame._rollArea:ClearAllPoints()
    frame._rollArea:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, callboardTop - callboardExtra)
    if rollBlock then
        local activeSlot = tonumber(pr.activeSlot) or 0
        -- Auto stays ON while paused; the heading must not say it is acting.
        -- A hold that is a wait for a sent action's result (the runtime's
        -- effective state) is named as that wait; every other hold keeps the
        -- paused heading. The Auto button still shows the selection.
        local effective = type(model.effective) == "table" and model.effective.state
        if model._nexusSessionPaused then
            -- Issue #171: the whole session is paused (Options > Resume Nexus).
            statusText:SetText("|cffffd100" .. LT("panel.status.roll_nexus_paused") .. "|r")
        elseif model.auto and model.paused
            and (effective == "waiting" or effective == "rechecking") then
            statusText:SetText("|cffffd100" .. LT(effective == "waiting" and "panel.status.roll_auto_waiting"
                or "panel.status.roll_auto_rechecking") .. "|r")
        elseif model.auto and Nexus.Readout and Nexus.Readout.WaitingForOffer
            and Nexus.Readout.WaitingForOffer(model.paused) then
            -- The design's waiting state: named as a wait for the offer,
            -- never as "0 offers" or as an acting Auto.
            statusText:SetText("|cffffd100" .. Nexus.Readout.WAITING_OFFER_HEADING .. "|r")
        elseif model.auto and model.paused then
            statusText:SetText("|cffffd100" .. Nexus.Localization.Text("panel.status.auto_on_paused") .. "|r")
        elseif #cards == 0 and recommendation == "" then
            statusText:SetText("|cff7fd5ff" .. LT("panel.status.roll_status") .. "|r")
        elseif guide and guide.openOrbs and guideText ~= "" then
            -- With the Orb guidance and its button: the short form, which
            -- stays one line at every font scale. With Auto OFF the player
            -- chooses (Readout.OfferHeadingForms' shortest form), never
            -- "Active".
            if model.auto == false then
                statusText:SetText("|cff7fd5ff" .. LT("panel.status.roll_you_choose") .. "|r · "
                    .. (activeSlot > 0 and LF("panel.label.slot_number", {slot = tostring(activeSlot)})
                        or LT("panel.label.preview_tag")))
            else
                statusText:SetText(activeSlot > 0 and ("|cff4dff80" .. LT("panel.label.active_prefix") .. "|r "
                    .. LF("panel.label.slot_number", {slot = tostring(activeSlot)}))
                    or ("|cff888888" .. LT("panel.label.preview_tag") .. "|r"))
            end
        elseif #cards > 0 and Nexus.Readout and Nexus.Readout.OfferHeading then
            -- The design's offer heading (whose choice it is), with the
            -- destination it applies to: a Saved Build slot or a preview. It
            -- keeps the established state words: "Auto OFF" while the player
            -- chooses, and "Active:" only for a selected, unheld Auto on a
            -- Saved Build (every hold and wait took a branch above). It is
            -- fitted to the heading row (M.SetOfferHeading).
            M.SetOfferHeading(statusText, model, activeSlot, responsiveLayout)
        elseif model.auto == false then
            -- The Auto selection is OFF (not merely held): Nexus only
            -- recommends, and the player chooses in the game's window.
            statusText:SetText("|cff7fd5ff" .. LT("panel.status.roll_auto_off_you_choose") .. "|r · "
                .. (activeSlot > 0 and LF("panel.label.slot_number", {slot = tostring(activeSlot)})
                    or LT("panel.label.preview_tag")))
        else
            statusText:SetText(activeSlot > 0 and ("|cff4dff80" .. LT("panel.label.active_prefix") .. "|r "
                .. LF("panel.status.roll_recommendations_active", {slot = tostring(activeSlot)}))
                or ("|cff888888" .. LT("panel.status.roll_recommendation_preview") .. "|r"))
        end
        -- With Auto OFF, the one card the runtime marked as its Take target
        -- (Readout.MarkedCard: exactly one, else none) carries a marker, and
        -- an unstepped recommendation names it. Only the current model is
        -- read, so no older marker survives a new board.
        local marked = model.auto == false and Nexus.Readout and Nexus.Readout.MarkedCard
            and Nexus.Readout.MarkedCard(cards) or nil
        -- Likewise the one card the recommendation freezes
        -- (Readout.FreezeCard: exactly one, else none). It is shown as a
        -- Freeze, never with the Take marker or the Wishlist pick tag.
        local frozen = model.auto == false and not marked and Nexus.Readout and Nexus.Readout.FreezeCard
            and Nexus.Readout.FreezeCard(cards) or nil
        for i = 1, 3 do
            local c = cards[i]
            local line = type(c) == "table" and SafeText(c.text) or ""
            if marked == i and line ~= "" then line = "|cff4dff80>>|r " .. line end
            if frozen == i and line ~= "" then line = "|cff7fd5ff[" .. LT("panel.label.freeze_tag") .. "]|r " .. line end
            cardTexts[i]:SetText(line)
        end
        -- The design's offer cards over these rows (M.RenderOfferCards). The
        -- marked card is the runtime's own Take target in either Auto mode;
        -- the card's tag says what that means in each. The Freeze card is
        -- tagged only with Auto OFF.
        do
            local lines, facts = {}, {}
            for i = 1, 3 do
                lines[i] = type(cards[i]) == "table" and SafeText(cards[i].text) or ""
                facts[i] = type(cards[i]) == "table" and type(cards[i].facts) == "table" and cards[i].facts or false
            end
            M.RenderOfferCards(lines, Nexus.Readout and Nexus.Readout.MarkedCard
                and Nexus.Readout.MarkedCard(cards) or nil, model.auto, responsiveLayout ~= nil, facts, frozen)
        end
        -- An unresolved Orb action's own reason is more specific than the
        -- general pause text; otherwise the recommendation stays first. A
        -- reserved block has no current choice: it says so, and no more.
        -- An unstepped recommendation names its one Take or Freeze card; the
        -- Freeze reason's own words say the action.
        local body = activeRoll and bodyText
            or ("|cff888888" .. Nexus.Localization.Text("panel.body.no_echo_choice") .. "|r")
        local named = marked or (recommendation ~= "" and frozen)
        if named and activeRoll and bodyText == recommendation
            and not (guide and guide.openOrbs) and type(cards[named]) == "table" then
            body = Nexus.Readout.RecommendationWithTarget(recommendation, SafeText(cards[named].text),
                type(cards[named].facts) == "table" and cards[named].facts or nil)
        end
        -- The inline Auto line follows whatever the body shows, on its own line.
        if autoNote ~= "" then body = (body ~= "" and (body .. "\n") or "") .. autoNote end
        -- Without a built layout that holds the Auto scope row, the scope
        -- line stays visible in the body (M.AutoScopeFallback).
        body = M.AutoScopeFallback(body, model, rollBlock and not noOffer, noBuild, responsiveLayout)
        recText:SetText(body)
        -- Compact charges, only from charge facts the model itself carries
        -- (Readout.ChargesLine; unknown is "?", never 0).
        local chargesText = frame._chargesText
        if chargesText then
            local line = model._nexusChargeLine or ""
            chargesText:SetText(line)
            if line ~= "" then chargesText:Show() else chargesText:Hide() end
            if frame._chargesHover then
                if line ~= "" then frame._chargesHover:Show() else frame._chargesHover:Hide() end
            end
        end
    else
        -- No roll block: no offer card of an earlier board may stay shown
        -- (the block's own hide does not clear its children's state).
        M.RenderOfferCards(nil, nil, model.auto, false)
        if frame._chargesText then
            frame._chargesText:Hide()
            if frame._chargesHover then frame._chargesHover:Hide() end
        end
    end
    if frame._orbsBtn then
        frame._orbsBtn.blockers = guide and guide.blockers or nil
        if activeRoll and guide and guide.openOrbs and total > 0 and name then
            frame._orbsBtn:Show()
        else
            frame._orbsBtn:Hide()
        end
        -- Level 80 with no offer (design/current Lv80): Open Orbs... is the
        -- one next step, so it and the footer's Orbs hub are the filled
        -- primary (Theme.SetPrimary); otherwise both are ordinary buttons.
        -- Presentation only: both still only open the Orb window.
        if Nexus.Theme and type(Nexus.Theme.SetPrimary) == "function" then
            Nexus.Theme.SetPrimary(frame._orbsBtn, noOffer and frame._orbsBtn:IsShown())
            if frame._orbsHubBtn then
                Nexus.Theme.SetPrimary(frame._orbsHubBtn, noOffer and frame._orbsBtn:IsShown())
            end
        end
    end
    SetVisible(frame._orbMiniBtn, frame._orbsBtn and frame._orbsBtn:IsShown())

    missingNamesCache = type(pr.missing) == "table" and pr.missing or {}
    shedNamesCache = type(pr.shed) == "table" and pr.shed or {}
    unknownTomesCache = type(pr.unknownTomes) == "table" and pr.unknownTomes or {}
    toLockNamesCache = type(pr.toLock) == "table" and pr.toLock or {}

    SetVisible(setupText, noBuild); SetVisible(setupHint, noBuild)
    SetVisible(setupGetStartedBtn, noBuild); SetVisible(setupImportBtn, noBuild)
    SetVisible(completeBadge, complete and not noBuild); SetVisible(completeSubtext, complete and not noBuild)
    ShowCoreProgress(not noBuild and not complete)
    ShowPerformance(not noBuild and showPerformance)

    -- Collapse the space reserved for Nexus' Soul Ash card whenever the player
    -- uses the server HUD. Live-roll content still gets its own fixed block.
    local contentTop
    if rollBlock then
        contentTop = (statusVisible and -220 or -161) - callboardExtra
    else
        contentTop = (statusVisible and -103 or -44) - callboardExtra
    end
    local statusHeightReduction = statusVisible and 0 or 59

    if not complete then
        frame._switchBtn:ClearAllPoints()
        frame._switchBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -7)
        frame._switchBtn:SetSize(68, 19)
    end

    if noBuild then
        SetVisible(dummyGlobalValue, false)
        SetVisible(lkGlobalValue, false)
        -- Stacked, centered, and ordered by what actually needs to happen:
        -- Assign Wishlist is the one button that gets Nexus running at all
        -- (Create Wishlist is only needed first if no wishlist exists yet),
        -- so it sits right under the instructions instead of sharing a row
        -- with an equally-weighted second option.
        frame:SetHeight((rollBlock and 428 or 278) - statusHeightReduction + callboardExtra)
        SetPoint(setupText, "TOP", frame, "TOP", 0, contentTop - 18)
        local assignment=model.assignment or {}
        local restoring=assignment.state=="restoring" or assignment.state=="loading"
        setupText:SetText(LT(restoring and "panel.status.setup_restoring"
            or (assignment.state=="unavailable" and "panel.status.setup_unavailable" or "panel.status.setup_assign")))
        SetPoint(setupHint, "TOP", frame, "TOP", 0, contentTop - 48)
        setupHint:SetText((restoring or assignment.state=="unavailable") and (assignment.note or LT("panel.body.setup_waiting"))
            or (assignment.emptySlot and assignment.note)
            or LT("panel.body.setup_assign_or_create"))
        if restoring then setupGetStartedBtn:Hide();setupImportBtn:Hide()end
        setupGetStartedBtn:ClearAllPoints()
        setupGetStartedBtn:SetPoint("TOP", frame, "TOP", 0, contentTop - 96)
        setupImportBtn:ClearAllPoints()
        setupImportBtn:SetPoint("TOP", frame, "TOP", 0, contentTop - 128)
    elseif complete then
        -- Once a build is complete, progress text stops being the purpose of the
        -- HUD. The panel becomes a compact replacement for the stock difficulty /
        -- Soul Ash tracker, with Nexus navigation and the player's best DPS.
        frame:SetHeight((showPerformance and (rollBlock and 430 or 286) or (rollBlock and 292 or 168))
            - statusHeightReduction + callboardExtra)
        -- completeBadge/completeSubtext were created and toggled everywhere but
        -- never given text anywhere in this file -- when the server-status HUD
        -- has nothing to show (statusVisible false) and Performance is off, the
        -- panel had nothing left to render at all. Use them as the fallback so
        -- "complete" is never a blank frame.
        if statusVisible then
            SetVisible(completeBadge, false)
            SetVisible(completeSubtext, false)
        else
            SetPoint(completeBadge, "TOP", frame, "TOP", 0, contentTop - 8)
            completeBadge:SetText(LT("panel.status.wishlist_complete"))
            SetPoint(completeSubtext, "TOP", frame, "TOP", 0, contentTop - 30)
            completeSubtext:SetSize(252, 32)
            completeSubtext:SetJustifyV("TOP")
            completeSubtext:SetText(name
                and LF("panel.body.complete_named", {name = ShortName(name, 34)})
                or LT("panel.body.complete_unnamed"))
            SetVisible(completeBadge, true)
            SetVisible(completeSubtext, true)
        end
        frame._switchBtn:ClearAllPoints()
        frame._switchBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -7)
        frame._switchBtn:SetSize(68, 19)
        SetVisible(setLabelText, false)
        SetVisible(lkPersonalLabel, showPerformance)
        SetVisible(dummyGlobalValue, true)
        SetVisible(lkGlobalValue, true)
    else
        SetVisible(dummyGlobalValue, false)
        SetVisible(lkGlobalValue, false)
        SetVisible(setLabelText, true)
        -- The TO LOCK row only exists when there's something to report --
        -- most wishlists design zero locked-slot targets, so the extra
        -- height stays reserved only while it's actually needed.
        local toLockExtra = #toLockNamesCache > 0 and 34 or 0
        if not responsiveLayout then
            frame:SetHeight((showPerformance and (rollBlock and 448 or 325) or (rollBlock and 388 or 267))
                - statusHeightReduction + toLockExtra + callboardExtra)
        end
        local progressTop = contentTop
        SetPoint(progressLabel, "TOPLEFT", frame, "TOPLEFT", 12, progressTop)
        SetPoint(progressValue, "TOPLEFT", frame, "TOPLEFT", 12, progressTop - 17)
        -- M4 (UX-13): rolled copies this run, with the locked targets still to
        -- lock; never "complete" while a locked target is outstanding. The
        -- short form keeps clear of the MISSING TOMES box on the same row.
        local text = Nexus.UserText
        progressValue:SetText(text and text.RunProgressText
            and text.RunProgressText(owned, total, #toLockNamesCache, #unknownTomesCache > 0)
            or LF("panel.value.run_progress", {owned = string.format("%d", owned), total = string.format("%d", total)}))

        SetPoint(needLabel, "TOPLEFT", frame, "TOPLEFT", 12, progressTop - 42)
        needLabel:SetText((Nexus.Localization.Text("panel.heading.still_needed")))

        if #unknownTomesCache > 0 then
            -- Tomes are metadata for the run, not a third content column.
            -- Keep them on the progress line and preserve two clean Echo columns.
            tomesLabel:SetText(LT("panel.heading.missing_tomes_stacked"))
            SetPoint(tomesLabel, "TOPRIGHT", frame, "TOPRIGHT", -26, progressTop - 18)
            tomesLabel:SetSize(58, 24)
            tomesLabel:SetJustifyH("RIGHT")
            tomesLabel:SetJustifyV("TOP")
            SetPoint(tomesValue, "TOPRIGHT", frame, "TOPRIGHT", -10, progressTop - 18)
            tomesValue:SetSize(18, 14)
            tomesValue:SetJustifyH("RIGHT")
            tomesValue:SetText(tostring(#unknownTomesCache))
            tomesLabel:SetTextColor(0.85, 0.7, 0.55)
            tomesValue:SetTextColor(1, 0.4, 0.4)
            tomesLabel:Show()
            tomesValue:Show()
            tomesHit:ClearAllPoints()
            tomesHit:SetPoint("TOPLEFT", tomesLabel, "TOPLEFT", -2, 2)
            tomesHit:SetPoint("BOTTOMRIGHT", tomesValue, "BOTTOMRIGHT", 2, -2)
            tomesHit:Show()
        else
            tomesLabel:Hide()
            tomesValue:Hide()
            tomesHit:Hide()
        end
        needText:SetWidth(112)

        SetPoint(needText, "TOPLEFT", frame, "TOPLEFT", 12, progressTop - 58)
        SetPoint(shedLabel, "TOPLEFT", frame, "TOPLEFT", 142, progressTop - 42)
        SetPoint(shedText, "TOPLEFT", frame, "TOPLEFT", 142, progressTop - 58)
        shedText:SetWidth(108)
        -- Two names, then "+N more", one line each (M.DetailNameLines). The
        -- STILL NEEDED face drops " (Poor:×N Common:×N ...)": the quality
        -- breakdown is in the tooltip on mouseover instead.
        M.RenderDetailNames(missingNamesCache, shedNamesCache)

        if #toLockNamesCache > 0 then
            SetPoint(frame.toLockLabel, "TOPLEFT", frame, "TOPLEFT", 12, progressTop - 90)
            SetPoint(frame.toLockText, "TOPLEFT", frame, "TOPLEFT", 12, progressTop - 106)
            frame.toLockText:SetWidth(238)
            local toLockLines = {}
            local toLockShown = math.min(#toLockNamesCache, 2)
            for i = 1, toLockShown do toLockLines[#toLockLines + 1] = toLockNamesCache[i] end
            if #toLockNamesCache > toLockShown then
                toLockLines[#toLockLines + 1] = LF("panel.label.more_count", {count = LC(#toLockNamesCache - toLockShown)})
            end
            frame.toLockText:SetText(table.concat(toLockLines, ", "))
            frame.toLockLabel:Show()
            frame.toLockText:Show()
            frame.toLockHit:ClearAllPoints()
            frame.toLockHit:SetPoint("TOPLEFT", frame.toLockLabel, "TOPLEFT", -2, 2)
            frame.toLockHit:SetPoint("BOTTOMRIGHT", frame.toLockText, "BOTTOMRIGHT", 2, -2)
            frame.toLockHit:Show()
        else
            frame.toLockLabel:Hide()
            frame.toLockText:Hide()
            frame.toLockHit:Hide()
        end

        SetVisible(lkPersonalLabel, false)
    end

    if not noBuild then RenderPerformanceState(pr, complete, showPerformance) end

    LayoutServerStatus(complete and not noBuild)
    -- The words and hover facts (M.RenderServerStatusValues, shared with a
    -- settled render's value pass); the hover keeps the full unformatted ash.
    if M.RenderServerStatusValues(ss, complete) then
        -- The bar is scaled to the game's validated maximum. Without valid
        -- constants, or without a reading, it has no truthful scale and stays
        -- hidden; the tooltip still states the raw value.
        local maximum = tonumber(ss.intensityMax)
        local thresholds = type(ss.intensityThresholds) == "table"
            and ss.intensityThresholds or nil
        worldStatusBox.intensityText:SetText("")
        if ss.intensity ~= nil and maximum and maximum > 0 and thresholds then
            worldStatusBox._intensityScale = {max=maximum, thresholds=thresholds}
            worldStatusBox.intensityBar:SetMinMaxValues(0, maximum)
            worldStatusBox.intensityBar:SetValue(
                math.max(0, math.min(maximum, tonumber(ss.intensity) or 0)))
            worldStatusBox.PositionIntensityTicks()
            worldStatusBox.intensityBar:Show()
        else
            worldStatusBox._intensityScale = nil
            worldStatusBox.intensityBar:Hide()
        end
        worldStatusBox:Show()
    else
        worldStatusText:SetText("")
        worldStatusAsh:SetText("")
        worldStatusGain:SetText("")
        worldStatusBox.intensityText:SetText("")
        worldStatusBox.intensityBar:Hide()
        worldStatusBox:Hide()
    end

    RenderBestDps(model, complete, noBuild, activeRoll, statusVisible)
    -- The Play summary over the rows above (counts, Details, the Difficulty
    -- / Soul Ash line, the DPS rows and the Orb line).
    M.RenderPlaySummary(model, responsiveLayout)
    ApplyPanelLayout(responsiveLayout,complete)
    M.RenderAutoScope(responsiveLayout)
    -- Issue #143: the labels of the three mapped buttons keep one line inside
    -- their final boxes: My Builds at the 68x19 set above, Assign Wishlist and
    -- Create Wishlist at the setup boxes ApplyPanelLayout placed (their
    -- creation size without a layout). As with the Wishlist editor's candidate
    -- buttons (115 px wide, 103 px labels), each label is the button's own
    -- FontString at the button's width less 12 px for the end caps and at its
    -- height, one line (LayoutMetrics.OneLineLabel, with no owner). The client
    -- shortens the rest and the button's own hover adds the complete label
    -- (EnsureFrame). Each full layout refits them, so font and UI scale
    -- revisions follow; nothing is created or hooked, and the buttons keep
    -- their size, anchors, font and text.
    local metrics = Nexus.LayoutMetrics
    if metrics and type(metrics.OneLineLabel) == "function" then
        for index = 1, 3 do
            local button = setupImportBtn
            if index == 1 then
                button = frame._switchBtn
            elseif index == 2 then
                button = setupGetStartedBtn
            end
            local label = button and button:GetFontString()
            if label then
                label:SetWidth(math.max(1, (tonumber(button:GetWidth()) or 0) - 12))
                metrics.OneLineLabel(label, nil, tonumber(button:GetHeight()) or 1)
            end
        end
    end
    -- Re-assert after ApplyPanelLayout: geometry owns positions; this owns
    -- visibility so complete/setup boards never leave a stale CALLBOARD row.
    FillCallboard(callboardObserved and callboardSummary or nil)
    if callboardObserved and responsiveLayout and responsiveLayout.boxes
        and responsiveLayout.boxes.callboard then
        PlaceCallboardBox(responsiveLayout.boxes.callboard, responsiveLayout)
    end
    if frame._autoBtn:IsShown() then
        frame._autoBtn:SetText(AutoLabel(model.auto))
    end
    if frame and Nexus.Theme and Nexus.Theme.StyleTree
        and not frame._nexusHudTreeStyled then
        Nexus.Theme.StyleTree(frame)
        frame._nexusHudTreeStyled = true
        renderStats.themeTreeWalks = renderStats.themeTreeWalks + 1
    end
    -- The destination row, last: after every competing header and layout
    -- operation and the one-time theme pass, so its cells' fonts are final.
    -- The header's space on the 272 px HUD is 151 px in every mode: from
    -- x 40 to the 5 px gap before My Builds (TOPRIGHT -8, 68 px) at x 191.
    -- A changed layout re-applies the first cell's text for real.
    M.UpdateDestinationRow(frame._destinationRow,
        signatures.destination or M.DestinationFacts(model), 151, 17, true)
    -- The settled layout key records the fonts the cells now have, so the
    -- next identical render is settled; it is committed only on success.
    signatures.layout = (signatures.modelLayout or signatures.layout)
        .. "|fonts:" .. M.DestinationRowFonts()
    return true
end

local function ApplyCandidate(model, signatures, roll)
    if not frame.toLockLabel then CreateToLockWidgets(frame) end
    M.ApplyOwnedFonts()
    -- settled: no layout pass ran. The header and the passive hovers then
    -- apply only what changed (C-03); a layout pass applies them whole.
    local applied, settled = ApplyModel(model, signatures, roll)
    if applied then
        M.UpdateContextHeader(model, settled)
        -- The Orb line's words follow the run on settled renders too.
        M.RefreshOrbLine(model, frame._responsiveLayout)
        M.FitPassiveHovers(settled)
    end
    if applied then
        -- The HUD can grow taller than the viewport with large fonts, an
        -- observed Callboard and optional sections. Refit on settled renders
        -- too: a viewport resize need not change the model's layout key.
        -- The player's chosen size is the ceiling (issue #170).
        M.ApplyPanelScale()
    end
    if applied then
        -- Show / Hide details keeps the panel's top where it was. The held
        -- corner is in screen units, so it is installed only now, at the
        -- scale the fit above left: a toggle that crosses the fit threshold
        -- (an expanded panel scaled down, a collapsed one back at 1) keeps
        -- the same physical top.
        M.HoldPanelTop(frame._responsiveLayout)
    end
    return applied
end

-- Panel is the one owner of the user-text presentation of a model's status
-- and recommendation (issue #142). Render and SetStatus take RAW text (planner
-- reasons, runtime status lines) and present it once with UserText.Message.
-- That conversion maps raw to presented and is not idempotent: presented text,
-- for example a translation, may hold bytes that a legacy rewrite matches
-- (ARMED, TARGET:), so presented text is never converted again. A committed
-- model (M._lastModel) keeps the presented text under its usual field names,
-- as before, and an owned _nexusPanelPresentation = {version=1, raw={...},
-- text={...}} record of the raw source of each presented field. A copy of a committed
-- model may be rendered again: a field that still holds the bytes its own
-- record presented is presented again from its recorded raw source; any other
-- value is a raw input. Equality with this field's own valid record takes
-- precedence over an identical-byte raw override. A raw caller copying a
-- committed model removes _nexusPanelPresentation to declare raw intent.
-- No language guess, cache, or string-content heuristic supplies provenance.
local function Present(raw)
    local userText = Nexus.UserText
    if userText and type(userText.Message) == "function" then
        return userText.Message(raw)
    end
    return raw
end

local function RawSource(model, field)
    local value = model[field]
    local record = rawget(model, "_nexusPanelPresentation")
    if type(record) ~= "table" or getmetatable(record) ~= nil
        or rawget(record, "version") ~= 1 then return value end
    local raw, text = rawget(record, "raw"), rawget(record, "text")
    if type(raw) ~= "table" or getmetatable(raw) ~= nil
        or type(text) ~= "table" or getmetatable(text) ~= nil then return value end
    for _, key in ipairs({"status", "recommendation"}) do
        local input, output = rawget(raw, key), rawget(text, key)
        if (input ~= nil and type(input) ~= "string") or type(output) ~= "string"
            or (input == nil and output ~= "") then return value end
    end
    if type(value) == "string" and rawget(text, field) == value then
        return rawget(raw, field)
    end
    return value
end

function M.Render(model)
    if type(model) ~= "table" then return false end
    local candidate = DefensiveCopy(model)
    -- Read the original record: DefensiveCopy removes its metatables.
    local raw = {status=RawSource(model, "status"),
        recommendation=RawSource(model, "recommendation")}
    candidate.recommendation = Present(raw.recommendation)
    local status, localized = Present(raw.status)
    candidate.status = status
    candidate._nexusPanelPresentation = {version=1, raw=raw,
        text={status=candidate.status, recommendation=candidate.recommendation}}
    local rawText = {status=raw.status,recommendation=raw.recommendation}
    -- The inline Auto line, from this model and the last refused Auto click
    -- (memory only); recomputed on every render, so an old one never stays.
    candidate.autoNote = M.AutoNoteFor(candidate)
    -- Issue #171: the confirmed session pause, read (Status only) per render.
    candidate._nexusSessionPaused = M.PauseStatus().paused == true or nil
    -- Format once per render; the visible output is part of the signature,
    -- so a changed presentation with identical raw counts cannot stay stale.
    candidate._nexusChargeLine = type(candidate.charges) == "table" and Nexus.Readout
        and Nexus.Readout.ChargesLine and Nexus.Readout.ChargesLine(candidate.charges) or ""
    -- The Orb run line, read once per render (the Orb window's compact read).
    candidate._nexusOrbLine = M.OrbLineText()
    local signatures = ModelSignatures(candidate)
    -- The reservation changes the layout, so it is part of its signature.
    local roll = RollPresentation(candidate)
    signatures.layout = signatures.layout .. "|roll:"
        .. (roll.reserved and "reserved" or "content") .. ":"
        .. (roll.cardRows and "cards" or "none")
    renderStats.calls = renderStats.calls + 1
    EnsureFrame()
    -- The destination cells' effective fonts are part of the layout key. A
    -- full pass replaces this with the fonts it leaves (ApplyModel); a failed
    -- one commits nothing.
    signatures.modelLayout = signatures.layout
    signatures.layout = signatures.modelLayout .. "|fonts:" .. M.DestinationRowFonts()

    if Nexus.OrbPanel then Nexus.OrbPanel.AttachMainPanel(frame)end

    -- A widget tree is a mutable object, so the render is a transaction:
    -- publish commit/model/signature state only after every required step
    -- succeeds.  On failure the prior immutable model remains the sole
    -- last-good owner and the frame is hidden, so no partial tree is exposed.
    -- Main retains the current input for the next ordinary retry.  A shown
    -- panel is not hidden while it applies (native test.163012, issues #165
    -- and #168): no frame is drawn inside this call, and that hide only
    -- reached the root and every shown descendant while the player's pointer
    -- could be pressing Options or moving the panel.  A hidden one stays
    -- hidden until ApplyWantedVisibility shows it after the commit.
    local previousModel = M._lastModel
    renderState.applying = true
    local ok, result = pcall(ApplyCandidate, candidate, signatures, roll)
    renderState.applying = false
    if not ok or result == false then
        M._lastModel = previousModel
        -- A mutating widget can fail after changing itself, so the old
        -- signature cannot certify the tree anymore.  Retain only the prior
        -- immutable model, keep the frame hidden, and force a complete apply
        -- on the next ordinary refresh.
        renderState.signatures = nil
        renderState.committed = false
        renderState.hadFailure = true
        renderStats.failures = renderStats.failures + 1
        frame:Hide()
        M.SettlePanelDrag()
        -- An open extra-copies list (a separate window) says at once that it
        -- is not current: it keeps the last committed names, never this
        -- failed candidate's (M.FillExtraList).
        pcall(M.RefreshExtraList)
        if not ok then error(result, 0) end
        return false
    end

    M._lastModel = candidate
    renderState.signatures = signatures
    -- Only a successful render decides the next reservation; a failed one
    -- leaves the last committed state as it was.
    renderState.roll = roll.nextRoll
    renderState.rawText = rawText
    renderState.statusPresentation = {text=candidate.status, localized=localized==true}
    renderState.committed = true
    renderStats.commits = renderStats.commits + 1
    if renderState.hadFailure then
        renderStats.recoveries = renderStats.recoveries + 1
        renderState.hadFailure = false
    end
    ApplyWantedVisibility()
    M.SettlePanelDrag()
    -- After the commit: presentation only. The paused banner (session pause
    -- Status) and an open extra-copies list (this committed model) follow it;
    -- neither can undo the commit.
    pcall(M.UpdatePauseBanner)
    pcall(M.RefreshExtraList)
    return true
end

-- Issue #171 (UI slice): the session pause is owned by Nexus.SessionPause
-- (frozen API: IsPaused, Status, Pause, Resume). The panel only reads Status
-- and calls Pause / Resume on the player's click; it keeps no paused flag of
-- its own. Without a usable API the control says so and nothing is labelled
-- paused. Status must answer {paused=boolean, epoch=whole number >= 0}.
-- The pause and resume notes, each two reviewed sentences (the Session
-- menu shows them as two rows), resolved when shown.
local function PauseExplain()
    return LT("panel.note.pause_scope") .. " " .. LT("panel.note.pause_sent_may_finish")
end
local function ResumeNote()
    return LT("panel.note.resume_auto_continues") .. " " .. LT("panel.note.resume_orb_stays_paused")
end
local function PauseAPI()
    local api = Nexus.SessionPause
    if type(api) == "table" and type(api.Status) == "function" and type(api.Pause) == "function"
        and type(api.Resume) == "function" then return api end
    return nil
end
local function ValidPause(status)
    local epoch = type(status) == "table" and status.epoch
    return type(status) == "table" and type(status.paused) == "boolean" and type(epoch) == "number"
        and epoch >= 0 and epoch < math.huge and math.floor(epoch) == epoch
end
-- unknown: the API is there but its Status failed or was malformed, so
-- whether Nexus is paused cannot be said either way (never "not paused").
function M.PauseStatus()
    local api = PauseAPI()
    if not api then return {available = false, paused = false} end
    local ok, status = pcall(api.Status)
    if not (ok and ValidPause(status)) then return {available = false, paused = false, unknown = true} end
    return {available = true, paused = status.paused}
end
local function PauseUnknown() return LT("panel.status.pause_unknown") end

-- After a transition the committed model is drawn again (Render only: no
-- refresh step, no action is prepared).
local function RepaintPause()
    if M._lastModel then pcall(M.Render, M._lastModel) end
    -- The banner follows the session pause even without a committed model.
    pcall(M.UpdatePauseBanner)
end
local function Transition(method, want, verb)
    local api = PauseAPI()
    local ok, status = false, nil
    if api then ok, status = pcall(api[method]) end
    RepaintPause()
    if ok and ValidPause(status) and status.paused == want then return true end
    print("|cffffd200Nexus:|r " .. LF(verb == "pause" and "panel.chat.pause_failed" or "panel.chat.resume_failed",
        {reason = LT(not api and "panel.chat.pause_reason_unavailable"
            or not ok and "panel.chat.pause_reason_error"
            or "panel.chat.pause_reason_unconfirmed")}))
    return false
end
function M.PauseNexus() return Transition("Pause", true, "pause") end
function M.ResumeNexus() return Transition("Resume", false, "resume") end

-- Owner-approved item 1 (issue #171): the paused banner. A strip outside the
-- panel's own box (above it, or below it when the screen has no room above),
-- so no panel layout, header slot or difficulty card moves. It is drawn from
-- the session pause's own Status after every committed render and after each
-- banner click, never from a flag of the panel's own:
--   "paused"  confirmed paused: the banner and its Resume button, which calls
--             M.ResumeNexus (the same owner route as Options > Resume Nexus)
--             once per click, and only while Status still confirms a pause;
--   "unknown" Status failed or was malformed: the banner says so and offers
--             no Resume, since nothing confirms a pause to resume;
--   nil       not paused, or a build without the control: no banner.
-- Resuming removes only the session pause: Auto keeps its selection, an Orb
-- run stays paused and nothing held is replayed (SessionPause.Resume). The
-- banner is a child of the panel, so it hides and shows with it; windows
-- opened from the panel keep working while paused. Built lazily (EnsureFrame
-- is at the upvalue ceiling).
local BANNER_H = 36
function M.PauseBannerState()
    local status = M.PauseStatus()
    if status.unknown then return "unknown" end
    if status.available and status.paused == true then return "paused" end
    return nil
end
function M.EnsurePauseBanner()
    if not frame then return nil end
    local banner = frame._pauseBanner
    if banner then return banner end
    banner = CreateFrame("Frame", nil, frame)
    banner._nexusThemeExempt = true
    banner:SetFrameLevel(frame:GetFrameLevel() + 10)
    banner:EnableMouse(true)
    banner.fill = banner:CreateTexture(nil, "BACKGROUND")
    banner.fill:SetAllPoints()
    banner.fill:SetTexture(0.36, 0.22, 0.02, 0.96)
    banner.edge = banner:CreateTexture(nil, "BORDER")
    banner.edge:SetPoint("BOTTOMLEFT", banner, "BOTTOMLEFT", 0, 0)
    banner.edge:SetPoint("BOTTOMRIGHT", banner, "BOTTOMRIGHT", 0, 0)
    banner.edge:SetHeight(2)
    banner.edge:SetTexture(1, 0.72, 0.1, 1)
    banner.title = banner:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    banner.title:SetPoint("TOPLEFT", banner, "TOPLEFT", 8, -4)
    banner.title:SetJustifyH("LEFT")
    banner.title:SetWordWrap(false)
    banner.title:SetTextColor(1, 0.82, 0)
    banner.note = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    banner.note:SetPoint("TOPLEFT", banner.title, "BOTTOMLEFT", 0, -2)
    banner.note:SetJustifyH("LEFT")
    banner.note:SetWordWrap(false)
    banner:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        if self._nexusState == "paused" then
            GameTooltip:AddLine(LT("panel.tooltip.paused_title"), 1, 0.82, 0)
            GameTooltip:AddLine(PauseExplain(), 0.9, 0.9, 0.9, true)
            GameTooltip:AddLine(LF("panel.tooltip.paused_resume_how", {note = ResumeNote()}), 0.9, 0.9, 0.9, true)
            GameTooltip:AddLine(LT("panel.tooltip.paused_reload_ends"), 0.75, 0.75, 0.75, true)
        else
            GameTooltip:AddLine(LT("panel.tooltip.session_pause_title"), 1, 0.82, 0)
            GameTooltip:AddLine(PauseUnknown(), 0.9, 0.9, 0.9, true)
        end
        GameTooltip:Show()
    end)
    banner:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    local resume = CreateFrame("Button", nil, banner, "UIPanelButtonTemplate")
    resume:SetText(LT("panel.button.resume"))
    resume:SetSize(76, 22)
    resume:SetPoint("RIGHT", banner, "RIGHT", -6, 0)
    resume:SetScript("OnClick", function() M.ResumeFromBanner() end)
    resume:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(LT("panel.tooltip.resume_nexus_title"), 1, 1, 1)
        GameTooltip:AddLine(ResumeNote(), 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    resume:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    resume:Disable()
    resume:Hide()
    -- The banner's own colours are exempt from the theme walk; its button
    -- keeps the panel's button style.
    if Nexus.Theme and Nexus.Theme.StyleButton then pcall(Nexus.Theme.StyleButton, resume) end
    banner.resume = resume
    -- No action of its own: a plain left drag on it moves the panel.
    M.PassiveDragSurface(banner)
    banner:Hide()
    frame._pauseBanner = banner
    return banner
end
-- Above the panel when the screen holds the strip there, else below it.
function M.PlacePauseBanner()
    local banner = frame and frame._pauseBanner
    if not banner then return nil end
    local function Read(region, method)
        local ok, value = pcall(region[method], region)
        return ok and tonumber(value) or nil
    end
    banner:SetSize(math.max(240, Read(frame, "GetWidth") or 420), BANNER_H)
    local top, uiTop = Read(frame, "GetTop"), Read(UIParent, "GetTop")
    local fs, us = Read(frame, "GetEffectiveScale") or 1, Read(UIParent, "GetEffectiveScale") or 1
    local above = not (top and uiTop) or (top + BANNER_H + 2) * fs <= uiTop * us
    banner:ClearAllPoints()
    if above then banner:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
    else banner:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -2) end
    banner._nexusSide = above and "above" or "below"
    return banner._nexusSide
end
function M.UpdatePauseBanner()
    if not frame then return nil end
    local state = M.PauseBannerState()
    local banner = frame._pauseBanner
    if not state then
        if banner then
            banner._nexusState = nil
            banner.resume:Disable(); banner.resume:Hide()
            banner:Hide()
        end
        return nil
    end
    banner = M.EnsurePauseBanner()
    banner._nexusState = state
    if state == "paused" then
        banner.title:SetText(LT("panel.status.paused_banner"))
        banner.note:SetText(LT("panel.status.paused_banner_note"))
        banner.resume:Enable(); banner.resume:Show()
    else
        banner.title:SetText(LT("panel.status.pause_unreadable_banner"))
        banner.note:SetText(LT("panel.status.pause_unreadable_note"))
        banner.resume:Disable(); banner.resume:Hide()
    end
    M.PlacePauseBanner()
    local textWidth = math.max(100, (tonumber(banner:GetWidth()) or 420) - 16 - (state == "paused" and 82 or 0))
    local metrics = Nexus.LayoutMetrics
    for _, label in ipairs({banner.title, banner.note}) do
        label:SetWidth(textWidth)
        if metrics and type(metrics.OneLineLabel) == "function" then metrics.OneLineLabel(label, nil, 16) end
    end
    banner:Show()
    return state
end
-- The banner's Resume: once per click, and only while the session pause
-- confirms a pause now (a stale click on a banner whose pause already ended
-- elsewhere calls nothing). Its failure is reported by Transition; the
-- banner then shows whatever the session pause reports.
function M.ResumeFromBanner()
    if M.PauseBannerState() ~= "paused" then
        M.UpdatePauseBanner()
        return false
    end
    local ok = M.ResumeNexus()
    M.UpdatePauseBanner()
    return ok
end

-- Options > Session: Pause or Resume with its note beside it, or the
-- unavailable control. Building it reads Status only.
function M.SessionMenuItems()
    local status = M.PauseStatus()
    if status.unknown then
        return {{ text = LT("panel.menu.session_pause_unreadable"), notCheckable = true, disabled = true,
            tooltipTitle = LT("panel.tooltip.session_pause_title"), tooltipText = PauseUnknown() }}
    end
    if not status.available then
        return {{ text = LT("panel.menu.pause_not_available"), notCheckable = true, disabled = true,
            tooltipTitle = LT("panel.tooltip.pause_session_title"),
            tooltipText = LT("panel.tooltip.pause_no_control") }}
    end
    if status.paused then
        return {{ text = LT("panel.menu.resume_nexus"), notCheckable = true, tooltipTitle = LT("panel.tooltip.resume_nexus_title"),
            tooltipText = ResumeNote(), func = MenuAction(function() M.ResumeNexus() end) },
            MenuNote(LT("panel.note.resume_auto_continues")), MenuNote(LT("panel.note.resume_orb_stays_paused"))}
    end
    -- The note is two short rows, so the menu stays narrow.
    return {{ text = LT("panel.menu.pause_session"), notCheckable = true,
        tooltipTitle = LT("panel.tooltip.pause_session_title"), tooltipText = PauseExplain(),
        func = MenuAction(function() M.PauseNexus() end) },
        MenuNote(LT("panel.note.pause_scope")),
        MenuNote(LT("panel.note.pause_sent_may_finish"))}
end

-- Issue #169: the Auto facts of the last committed model (memory only; no
-- gate, request or write) and its effective-state line.
local function AutoFacts()
    local model = type(M._lastModel) == "table" and M._lastModel or {}
    local held = model.auto and (type(model.paused) == "string" and model.paused
        or (type(model.effective) == "table" and model.effective.hold and model.effective.reason)) or nil
    return model, held
end
local function Bounded(text, limit)
    text = tostring(text or "")
    return Nexus.Identity and Nexus.Identity.Utf8Prefix and Nexus.Identity.Utf8Prefix(text, limit) or text:sub(1, limit)
end
-- The button is the selection; this is what it is doing now (waiting,
-- rechecking, paused or ready, with the reason in the player's wording).
local AUTO_NOW_STATES = {off = "panel.value.auto_now_off", paused = "panel.value.auto_now_paused",
    ready = "panel.value.auto_now_ready", waiting = "panel.value.auto_now_waiting",
    rechecking = "panel.value.auto_now_rechecking"}
local function AutoNowLine(model, limit)
    local effective = type(model) == "table" and model.effective
    if not (type(effective) == "table" and type(effective.state) == "string") then return nil end
    local reason = type(effective.reason) == "string" and effective.reason or nil
    if reason and Nexus.UserText then reason = Nexus.UserText.Message(reason) end
    if reason then reason = Bounded(reason, limit) end
    -- The runtime's state code is said in words when it is a known one; any
    -- other code is shown as it is (as before).
    local words = AUTO_NOW_STATES[effective.state]
    local state = words and LT(words) or effective.state
    if reason and reason ~= "" then
        return LF("panel.tooltip.auto_now_reason", {state = state, reason = reason})
    end
    return LF("panel.tooltip.auto_now", {state = state})
end
local function HoldWords(held)
    local readout = Nexus.Readout
    return Bounded(readout and readout.AutoHoldText and readout.AutoHoldText(held) or held, 160)
end

-- The complete explanation (Options > Auto explained, the Help Auto page):
-- every disclosure the Auto hover carried before issue #169, each
-- permission the runtime gates on with its current value
-- (Readout.AutomationScopeLines), why a selected Auto is held and its
-- effective state. Read from the last committed model and Store.Settings.
function M.AutoDetailLines()
    local model, held = AutoFacts()
    local lines = {
        LT("panel.body.auto_detail_heading"),
        LT("panel.body.auto_detail_when_on"),
        LT("panel.body.auto_detail_separate"),
        LT("panel.body.auto_detail_off"),
        LT("panel.body.auto_detail_off_wishlist"),
    }
    local readout = Nexus.Readout
    if readout and type(readout.AutomationScopeLines) == "function" then
        local store = Nexus.Store
        local okSettings, settings = false, nil
        if store and type(store.Settings) == "function" then okSettings, settings = pcall(store.Settings) end
        local internals = Nexus.MainInternals
        local okRead, readOnly = false, nil
        if internals and type(internals.SavedRootReadOnlyV1) == "function" then
            okRead, readOnly = pcall(internals.SavedRootReadOnlyV1)
        end
        for _, line in ipairs(readout.AutomationScopeLines({selected = model.auto == true,
            held = held, settings = okSettings and settings or nil,
            readOnly = okRead and readOnly ~= nil and readOnly ~= false})) do
            lines[#lines + 1] = line
        end
    end
    local pause = M.PauseStatus()
    if pause.paused then
        -- The confirmed session pause is the current hold, over the
        -- committed model's own state words.
        lines[#lines + 1] = LT("panel.body.auto_detail_paused_because")
        lines[#lines + 1] = LT("panel.tooltip.auto_now_session_paused")
        return lines
    end
    if pause.unknown then
        -- An established pause may still hold: the last committed model's
        -- state words are not the current state.
        lines[#lines + 1] = PauseUnknown()
        lines[#lines + 1] = LT("panel.tooltip.auto_now_pause_unknown")
        return lines
    end
    local now = AutoNowLine(model, 600)
    if now then lines[#lines + 1] = now end
    return lines
end

-- The first hover: the current state, what to click next and the essential
-- consequence, then where the complete explanation is.
function M.AutoSummaryLines()
    local model, held = AutoFacts()
    local lines = {}
    local pause = M.PauseStatus()
    if pause.unknown then lines[1] = PauseUnknown() end
    if pause.paused then
        lines[1] = LT("panel.tooltip.auto_paused_session")
        lines[2] = LT("panel.tooltip.auto_paused_continue") .. " " .. ResumeNote()
    else
        local refusal = model.auto ~= true and type(M._autoRefusal) == "table" and M._autoRefusal.text or nil
        local state, action
        if refusal then
            state = LF("panel.tooltip.auto_refused_last_click", {reason = Bounded(refusal, 160)})
            action = LT("panel.tooltip.auto_refused_action")
        elseif model.auto == true and held then
            state = LF("panel.tooltip.auto_on_held", {reason = HoldWords(held)})
            action = LT("panel.tooltip.auto_on_held_action")
        elseif model.auto == true then
            state = LT("panel.tooltip.auto_on_state")
            action = LT("panel.tooltip.auto_on_action")
        elseif model.auto == false then
            state = LT("panel.tooltip.auto_off_state")
            action = LT("panel.tooltip.auto_off_action")
        else
            state = LT("panel.tooltip.auto_unknown_state")
            action = LT("panel.tooltip.auto_unknown_action")
        end
        lines[#lines + 1] = state
        lines[#lines + 1] = action
        lines[#lines + 1] = LT("panel.tooltip.auto_consequence")
    end
    lines[#lines + 1] = LT("panel.tooltip.auto_full_details")
    return lines
end

function M.ShowAutoTooltip(owner)
    if not GameTooltip then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:AddLine(LT("panel.tooltip.auto_title"), 1, 1, 1)
    local lines = M.AutoSummaryLines()
    for i = 1, #lines do
        if i == #lines then GameTooltip:AddLine(lines[i], 1, 0.82, 0, true)
        else GameTooltip:AddLine(lines[i], 0.9, 0.9, 0.9, true) end
    end
    -- A confirmed session pause is what holds Auto now, whatever the last
    -- committed model's state words were.
    -- An unreadable status leaves the current state unknown as well.
    local pause = M.PauseStatus()
    local now = pause.paused and LT("panel.tooltip.auto_now_session_paused")
        or pause.unknown and LT("panel.tooltip.auto_now_pause_unknown")
        or AutoNowLine(M._lastModel, 120)
    if now then GameTooltip:AddLine(now, 1, 0.82, 0, true) end
    GameTooltip:Show()
end

function M.Refresh()
    if callbacks and type(callbacks.RefreshDisplay) == "function" then
        return callbacks.RefreshDisplay()
    end
    if M._lastModel then return M.Render(M._lastModel) end
    return false
end
-- The inline Auto line of the roll block (UX-09), from the model and the last
-- refused Auto click only: why a selected Auto is not acting, in plain words
-- with what helps (not for a wait for a sent action, whose heading and line
-- already say it, and not when the Orb guidance is itself the pause reason:
-- an Orb run or the Orb-state gate, shown with Open Orbs); or why the last
-- Auto click left Auto OFF. Other guidance (for example "An Echo choice is
-- open", which every board carries and the body does not show beside a
-- recommendation) does not explain a pause and does not hide it. Passive:
-- memory only, no gate, request or action; nil when there is nothing to say.
function M.AutoNoteFor(model)
    if type(model) ~= "table" or not Nexus.Readout then return nil end
    local pr = type(model.progress) == "table" and model.progress or {}
    local total, owned = tonumber(pr.total) or 0, tonumber(pr.owned) or 0
    -- Without a build the setup view stands in this space (M.NoteAutoClick prints).
    if total <= 0 or not pr.wishlistName then return nil end
    local refusal = M._autoRefusal
    if model.auto == false and type(refusal) == "table" and type(refusal.text) == "string"
        and (tonumber(GetTime()) or 0) - (tonumber(refusal.at) or 0) <= 60 then
        return refusal.text
    end
    -- Auto ON and acting: what Auto may do (the design's Auto ON line,
    -- Readout.AUTO_ON_NOTE) is the panel's own Auto scope row
    -- (M.RenderAutoScope), shown beside a recommendation too, so the roll
    -- body stays exactly the runtime's recommendation (hud_roll_footprint).
    -- While LayoutMetrics is loaded the row is expected; if this pass then
    -- builds no layout with that row, ApplyModel adds the line to the body
    -- itself (M.AutoScopeFallback). Without LayoutMetrics the former body line
    -- remains, beside an offer with no recommendation.
    if model.auto == true and not (type(model.paused) == "string" and model.paused ~= "") then
        if Nexus.LayoutMetrics then return nil end
        local cards = type(model.cards) == "table" and model.cards or {}
        return (#cards > 0 and SafeText(model.recommendation) == "") and Nexus.Readout.AUTO_ON_NOTE or nil
    end
    if not (model.auto and type(model.paused) == "string" and model.paused ~= "") then return nil end
    local complete = owned >= total and #(type(pr.toLock) == "table" and pr.toLock or {}) == 0
    local effective = type(model.effective) == "table" and model.effective.state or nil
    local guide = type(model.orbGuidance) == "table" and model.orbGuidance or nil
    local orbPause = guide and (guide.state == "orb-run" or guide.state == "orb-state")
        and SafeText(guide.text) ~= ""
    if complete or effective == "waiting" or effective == "rechecking" or orbPause then
        return nil
    end
    return Nexus.Readout.AutoHoldNote and Nexus.Readout.AutoHoldNote(model.paused) or nil
end

-- The "Automation settings" submenu of the Options menu (UX-10): every permission
-- Auto gates on, with its current value (Readout.AutomationSettingsRows), read
-- from Store.Settings and the runtime's counters when the menu opens. Opening,
-- hovering or closing it changes nothing. Only the Reroll and Freeze rows act,
-- through their existing setter (/nexus reroll|freeze on|off: MainCommands to
-- Main's rollingOption); Lock Wishlist Echoes opens the Wishlist Editor, whose
-- own control is its setter; the last row opens the Reference page on Auto.
-- `action` wraps a click
-- (the menu's MenuAction: it closes the menu first).
function M.AutomationMenuItems(action)
    local readout = Nexus.Readout
    if not (readout and type(readout.AutomationSettingsRows) == "function") then
        return {{text = LT("panel.menu.automation_unavailable"), notCheckable = true, disabled = true}}
    end
    local store = Nexus.Store
    local okSettings, settings = false, nil
    if store and type(store.Settings) == "function" then okSettings, settings = pcall(store.Settings) end
    local internals = Nexus.MainInternals
    local okRead, readOnly = false, nil
    if internals and type(internals.SavedRootReadOnlyV1) == "function" then
        okRead, readOnly = pcall(internals.SavedRootReadOnlyV1)
    end
    local rows = readout.AutomationSettingsRows({selected = M.AutoSelectedNow() == true,
        settings = okSettings and settings or nil,
        readOnly = okRead and readOnly ~= nil and readOnly ~= false})
    local items = {}
    for _, row in ipairs(rows) do
        local item = {text = row.text}
        if row.kind == "title" then
            item.isTitle, item.notCheckable = true, true
        elseif row.kind == "toggle" then
            local command = row.command
            item.checked = row.checked == true
            item.func = action(function()
                local slash = SlashCmdList and SlashCmdList.NEXUS
                if type(slash) == "function" then slash(command) end
            end)
        elseif row.kind == "editor" then
            item.notCheckable = true
            item.func = action(function()
                local help = Nexus.Help
                if help and type(help.OpenEditor) == "function" then help.OpenEditor() end
            end)
        elseif row.kind == "help" then
            item.notCheckable = true
            item.func = action(function() if Nexus.Help then Nexus.Help.Show("rolling") end end)
        else
            item.notCheckable, item.disabled = true, true
        end
        items[#items + 1] = item
    end
    return items
end

-- Issue #123: the Nexus-only language chooser of the Options menu. Its facts come
-- from the lifecycle's read-only LanguageStatus callback (Panel.Init); until
-- that exists every choice is shown disabled. Opening, hovering and closing
-- the menu only read. A choice is submitted only by a row click, through the
-- lifecycle's ChooseLanguage callback, which checks the saved-data authority
-- again at that moment and alone holds the Store writer: this file never
-- writes a setting. The result is said once in chat. Nothing is reloaded or
-- refreshed: a saved choice applies after the next reload or login.
-- The refusal codes' words (localization keys); the codes stay codes.
local LANGUAGE_REASONS = {
    startup = "panel.status.language_reason_startup",
    capacity = "panel.status.language_reason_capacity",
    ["read-only"] = "panel.status.language_reason_read_only",
    authority = "panel.status.language_reason_authority",
    drift = "panel.status.language_reason_drift",
    invalid = "panel.status.language_reason_invalid",
    failed = "panel.status.language_reason_failed",
}
local function LanguageReason(code)
    return LT(LANGUAGE_REASONS[code] or "panel.status.language_reason_refused")
end
-- The scope statement is a block of short lines (one sentence each): the
-- Language menu shows each line as its own row (a menu row does not wrap);
-- a chat line joins them with spaces.
local function LanguageScopeLines()
    local lines = {}
    for line in (LT("panel.note.language_scope") .. "\n"):gmatch("([^\n]*)\n") do
        if line ~= "" then lines[#lines + 1] = line end
    end
    return lines
end
local function LanguageScope() return table.concat(LanguageScopeLines(), " ") end
local function LanguageReload() return LT("panel.note.language_reload") end
-- Issue #141: Automatic is a preference shown beside the installed packs,
-- never one of them. This build reads no game language and has no evidenced
-- client code for any pack, so Automatic shows English; the menu says so and
-- never claims that a client locale is known.
local function LanguageAutomatic() return LT("panel.note.language_automatic") end

local function LanguageName(status, id)
    for _, row in ipairs(type(status) == "table" and type(status.languages) == "table"
        and status.languages or {}) do
        if type(row) == "table" and row.id == id and type(row.name) == "string" then
            return row.name
        end
    end
    return "English"
end

-- Issue #141: "Automatic (<the language it shows>)". Never a client locale.
local function AutomaticName(status, id)
    return LF("panel.menu.language_automatic", {language = LanguageName(status, id)})
end

-- The chooser's facts (see above). Reads only.
function M.LanguageStatus()
    if callbacks and type(callbacks.LanguageStatus) == "function" then
        local ok, status = pcall(callbacks.LanguageStatus)
        if ok and type(status) == "table" then return status end
    end
    -- No reliable lifecycle status: before Panel.Init, or the callback
    -- failed or gave no table. The active language and the startup refusal
    -- are known; the saved preference is not. Issue #141: saved, preference
    -- and automatic stay unset, so no Automatic or manual row is checked and
    -- the active language is never reported as a saved choice.
    local status = {active = "enUS", pending = false,
        refusal = "startup", languages = {}}
    local localization = Nexus.Localization
    if localization and type(localization.Languages) == "function" then
        local ok, list = pcall(localization.Languages)
        if ok and type(list) == "table" then status.languages = list end
    end
    if localization and type(localization.ActiveLanguage) == "function" then
        local ok, id = pcall(localization.ActiveLanguage)
        if ok and type(id) == "string" then status.active = id end
    end
    -- Issue #141: the Automatic value and what it shows; the saved
    -- preference itself is not known here.
    local automatic = localization and localization.AUTOMATIC_PREFERENCE
    if type(automatic) == "string" then
        status.automaticPreference, status.automaticLanguage = automatic, "enUS"
        if type(localization.EffectiveLanguage) == "function" then
            local ok, id = pcall(localization.EffectiveLanguage, automatic)
            if ok and type(id) == "string" then status.automaticLanguage = id end
        end
    end
    return status
end

-- The Options menu row: the active language, and a pending choice when there is one.
function M.LanguageMenuLabel()
    local ok, status = pcall(M.LanguageStatus)
    if not ok or type(status) ~= "table" then return LT("panel.menu.language") end
    local name = status.activeAutomatic and AutomaticName(status, status.active)
        or LanguageName(status, status.active)
    return LF((status.pending or status.preferencePending) and "panel.menu.language_row_pending"
        or "panel.menu.language_row", {language = name})
end

-- The submenu rows. `action` wraps a click (the menu's MenuAction).
function M.LanguageMenuItems(action)
    local status = M.LanguageStatus()
    local refusal = status.refusal
    local items = {{text = LT("panel.menu.language_title"), isTitle = true, notCheckable = true}}
    -- Issue #141: Automatic first, as a preference beside the packs (never
    -- one of them). Checked marks the saved preference; "- active" the
    -- language this session shows; "- in use" an Automatic session start.
    -- A refused Automatic row carries no click.
    local automatic = type(status.automaticPreference) == "string"
        and status.automaticPreference or nil
    local pending = status.preferencePending or status.pending
    if automatic then
        local label = AutomaticName(status, status.automaticLanguage)
        if status.activeAutomatic then label = LF("panel.menu.language_in_use", {language = label}) end
        if pending and status.automatic then
            label = LF("panel.menu.language_saved_after_reload", {language = label})
        end
        items[#items + 1] = {text = label, checked = status.automatic == true,
            disabled = refusal ~= nil,
            func = refusal == nil and action(function() M.ChooseLanguage(automatic) end) or nil}
    end
    for _, row in ipairs(type(status.languages) == "table" and status.languages or {}) do
        if type(row) == "table" and type(row.id) == "string" and type(row.name) == "string" then
            local id, label = row.id, row.name
            if id == status.active then label = LF("panel.menu.language_active", {language = label}) end
            if pending and status.automatic ~= true and not status.savedUnsupported
                and id == status.saved then
                label = LF("panel.menu.language_saved_after_reload", {language = label})
            end
            items[#items + 1] = {text = label, checked = status.automatic ~= true and id == status.saved,
                disabled = refusal ~= nil,
                func = action(function() M.ChooseLanguage(id) end)}
        end
    end
    items[#items + 1] = {text = LanguageReload(), notCheckable = true, disabled = true}
    for _, line in ipairs(LanguageScopeLines()) do
        items[#items + 1] = {text = line, notCheckable = true, disabled = true}
    end
    if automatic then
        items[#items + 1] = {text = LanguageAutomatic(), notCheckable = true, disabled = true}
    end
    if status.savedUnsupported then
        items[#items + 1] = {text = LT("panel.note.language_saved_unsupported"),
            notCheckable = true, disabled = true}
    end
    if status.sessionOnly then
        items[#items + 1] = {text = LT("panel.note.language_session_only"),
            notCheckable = true, disabled = true}
    end
    if refusal ~= nil then
        items[#items + 1] = {text = LF("panel.note.language_changes_unavailable", {reason = LanguageReason(refusal)}),
            notCheckable = true, disabled = true}
    end
    return items
end

-- What a choice did, in words. Reads only.
function M.LanguageResultText(result, id)
    local state = type(result) == "table" and result.state or nil
    local status = M.LanguageStatus()
    local automatic = type(result) == "table" and result.automatic == true
    local name = automatic and AutomaticName(status, result.resolved)
        or LanguageName(status, type(result) == "table" and result.id or id)
    local note = automatic and (" " .. LanguageAutomatic()) or ""
    if state == "saved" then
        if result.pending then
            return LF("panel.chat.language_saved", {language = name}) .. " " .. LanguageReload() .. " "
                .. LanguageScope() .. note
        elseif result.preferencePending then
            return LF("panel.chat.language_saved_next_reload", {language = name}) .. note
        end
        return LF("panel.chat.language_saved", {language = name}) .. " "
            .. LT(automatic and "panel.chat.language_already_session" or "panel.chat.language_already_active") .. note
    elseif state == "unchanged" then
        return LF("panel.chat.language_unchanged", {language = name})
            .. (result.pending and (" " .. LanguageReload()) or "") .. note
    elseif state == "session" then
        return LT("panel.chat.language_session_only")
    elseif state == "unconfirmed" then
        return LT("panel.chat.language_unconfirmed")
    end
    local reason = type(result) == "table" and result.reason or nil
    return LF("panel.chat.language_refused", {reason = LanguageReason(reason)})
end

-- A row click: submits the choice through the lifecycle and says the result.
function M.ChooseLanguage(id)
    local result
    if callbacks and type(callbacks.ChooseLanguage) == "function" then
        local ok, value = pcall(callbacks.ChooseLanguage, id)
        result = ok and type(value) == "table" and value or {state = "refused", reason = "authority"}
    else
        result = {state = "refused", reason = "startup"}
    end
    print("|cffffd200Nexus:|r " .. M.LanguageResultText(result, id))
    return result
end

-- Whether Auto is selected now, from the runtime's counters (memory only).
function M.AutoSelectedNow()
    if type(Nexus.RecomputeStats) ~= "function" then return nil end
    local ok, stats = pcall(Nexus.RecomputeStats)
    if not ok or type(stats) ~= "table" then return nil end
    return stats.autoEnabled == true
end

-- After an Auto button click: when Auto was OFF, stayed OFF and no warning
-- opened (the warning is its own next step), remember why for the roll block
-- and render the last model again. Any other outcome forgets an earlier one.
-- Reads only; it never toggles, retries or requests.
function M.NoteAutoClick(before, ok, state)
    local warning = Nexus.OverwriteWarning
    local open = warning and type(warning.IsOpen) == "function" and warning.IsOpen()
    if before ~= false or not ok or state ~= false or open then
        M._autoRefusal = nil
        return false
    end
    local orb = Nexus.OrbRuntime
    local blocked = false
    if orb and type(orb.BlocksOrdinary) == "function" then
        local okOrb, value = pcall(orb.BlocksOrdinary)
        blocked = okOrb and value == true
    end
    local model = type(M._lastModel) == "table" and M._lastModel or nil
    local status = model and SafeText(model.status) or ""
    local kind = blocked and "orb"
        or ((not warning or type(warning.RequestAuto) ~= "function") and "warning") or nil
    local text = Nexus.Readout and Nexus.Readout.AutoRefusalText
        and Nexus.Readout.AutoRefusalText(kind, status) or LF("panel.status.auto_stayed_off", {status = status})
    M._autoRefusal = {text = text, at = tonumber(GetTime()) or 0}
    local pr = model and type(model.progress) == "table" and model.progress or {}
    if not model or (tonumber(pr.total) or 0) <= 0 or not pr.wishlistName then
        -- No roll block to show it in: said once in chat instead.
        print("|cffffd200Nexus:|r " .. text)
        return true
    end
    -- The ordinary render transaction of the last committed model with its
    -- own raw text (as ReleaseRollOnAutoOff); nothing else changes.
    local copy = DefensiveCopy(model)
    local rawText = renderState.rawText or {}
    copy.status, copy.recommendation = rawText.status, rawText.recommendation
    local rendered, why = pcall(M.Render, copy)
    if not rendered and Nexus.Errors and type(Nexus.Errors.Record) == "function" then
        pcall(Nexus.Errors.Record, "Panel.NoteAutoClick", why)
    end
    return true
end

-- `status` is a raw status line (Main's onStatus passes the runtime's own),
-- presented here once, as Render presents it.
function M.SetStatus(status)
    if not M._lastModel then return false end
    local text, localized = Present(status)
    local nextStatus = SafeText(text)
    -- Refresh raw provenance even when the visible bytes do not change.
    local record = M._lastModel._nexusPanelPresentation
    if type(record) == "table" and type(record.raw) == "table"
        and type(record.text) == "table" then
        record.raw.status, record.text.status = status, nextStatus
    end
    if renderState.rawText then renderState.rawText.status = status end
    renderState.statusPresentation = {text=nextStatus, localized=localized==true}
    if SafeText(M._lastModel.status) == nextStatus then return false end
    M._lastModel.status = nextStatus
    if renderState.signatures then
        renderState.signatures.status = Signature(nextStatus)
    end
    renderStats.statusOnly = renderStats.statusOnly + 1
    return true
end
-- Actual menu status boundary. The provenance is owned by the committed
-- render/SetStatus, not supplied by a model's metadata. Revalidate the bytes
-- against Localization's bounds; unrelated raw status retains Identity rules.
function M.StatusTooltipText()
    local status = M._lastModel and M._lastModel.status
    local presented, localization = renderState.statusPresentation, Nexus.Localization
    if presented and presented.localized and presented.text == status
        and type(localization) == "table" and type(localization.IsText) == "function"
        and localization.IsText(status) == true then return status end
    local displayText = Nexus.Identity and Nexus.Identity.DisplaySafeText
    return displayText and displayText(tostring(status or ""), 2048, false, true)
        or LT("panel.value.status_unavailable")
end
function M.RenderStats() return DefensiveCopy(renderStats) end

-- What this owner knows about its own visibility, as facts another owner can
-- act on. Read-only: it creates no frame, requests no render and writes
-- nothing. `ready` says whether this panel can display at all, which is
-- deliberately NOT the same as `shown`: a player who hid it and a dialog that
-- suppresses it both leave a panel that is perfectly able to display.
-- `wanted` is the player's saved choice (issue #164). The stock HUD stands
-- aside only for a panel that is ready AND wanted: one the player hid is not
-- replacing anything, while one an open dialog suppresses still is.
function M.VisibilityFacts()
    LoadWantedVisibility()
    return {
        exists = frame ~= nil,
        shown = frame ~= nil and frame:IsShown() and true or false,
        wanted = panelWantedVisible and true or false,
        menuSuppressed = menuSuppressed and true or false,
        ready = frame ~= nil and renderState.committed == true
            and renderState.applying ~= true,
        committed = renderState.committed == true,
        hadFailure = renderState.hadFailure == true,
        hiddenUncommitted = renderStats.hiddenUncommitted,
        commits = renderStats.commits,
        failures = renderStats.failures,
    }
end
-- The player's own show and hide (the header X, Hide Nexus Panel, /nexus
-- panel, the minimap button). Both save the choice (SetWantedVisibility) and
-- tell the stock HUD owner; neither touches Auto or any gameplay setting.
function M.Show()
    SetWantedVisibility(true)
    if M._restoreCue then M.CueMinimapRestore(false) end
    EnsureFrame()
    ReleaseStaleMenuSuppression()
    RequestDisplayRecovery()
    ApplyWantedVisibility()
    NotifyStockHud()
end
function M.Hide()
    SetWantedVisibility(false)
    if frame then frame:Hide() end
    NotifyStockHud()
end
function M.IsShown() return frame and frame:IsShown() or false end

return M
