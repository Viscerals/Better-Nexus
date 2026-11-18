-- Nexus: ui/CallboardStatus.lua
-- Read-only mirror of the accepted Callboard objective and its difficulty
-- rewards. Sources: EbonAPI.Ebonhold.Objectives and the objectiveData of the
-- tracker reward bag. EbonholdQuestTracker text (the PE tracker shown in
-- fstack) never names an objective: it only selects or adds progress to one
-- those sources established. Two different known positive quest IDs are two
-- objectives even under one title, and neither lends the other quest-log
-- progress or reward rows. Never falls back to generic WatchFrame/quest-watch
-- entries (that grabbed unrelated quests like "One More Door") and never
-- calls SelectQuestLogEntry. Stock trackers stay until the Nexus row
-- for the same objective is visible, and only the state Nexus changed is
-- restored. Passive reward reads do not drive foreign enter/leave handlers.

Nexus = Nexus or {}
local M = {}
Nexus.CallboardStatus = M

-- Full-UI localization (issues #143-#148): Nexus's own words in the reward
-- tooltip and the two quest-log state lines resolve through
-- Nexus.Localization when shown (never cached at load); while the seam is
-- absent or a key answers "unavailable" the exact English is shown. The
-- reward rows keep their canonical English difficulty label (row.label is
-- compared, signed and matched against the game's tooltip); only the shown
-- name is translated. Objective titles and progress text are game data.
local function Say(key, english)
    local localization = Nexus.Localization
    if type(localization) == "table" and type(localization.Text) == "function" then
        local text, source = localization.Text(key)
        if type(text) == "string" and source ~= "unavailable" then return text end
    end
    return english
end
local function SayF(key, args, english)
    local localization = Nexus.Localization
    if type(localization) == "table" and type(localization.Format) == "function" then
        local text, source = localization.Format(key, args)
        if type(text) == "string" and source ~= "unavailable" then return text end
    end
    return english
end

-- The shown name of a canonical difficulty label (display only).
local DIFFICULTY_SHOWN = {
    ["Normal"] = "callboard.label.difficulty_normal",
    ["Hardcore I"] = "callboard.label.difficulty_hc1",
    ["Hardcore II"] = "callboard.label.difficulty_hc2",
    ["Hardcore III"] = "callboard.label.difficulty_hc3",
    ["Hardcore IV"] = "callboard.label.difficulty_hc4",
    ["Hardcore V"] = "callboard.label.difficulty_hc5",
}
local function DifficultyShown(label)
    local key = type(label) == "string" and DIFFICULTY_SHOWN[label] or nil
    return key and Say(key, label) or label
end

local scanner
local elapsed = 0
local cachedSummary = { observed = false }
local cachedSignature = ""
local remembered
-- Reward rows read from a tooltip the game showed, kept with the identity of
-- the objective its owner named: { rows, title, questId }.
local scraped
-- Identity of the last observed objective; it keeps a known positive ID.
local lastIdentity
local showingOwnTooltip = false
local hookedObjectivesUI = false
local hookedQuestTracker = false
local fastPollRemaining = 0
local refreshQueued = false

local REWARD_ROWS = {
    { label = "Normal", ash = "normalSoulAshes", xp = "normalXp",
        gold = "normalGold", copper = "normalMoney", color = { 1.00, 1.00, 1.00 } },
    { label = "Hardcore I", ash = "hc1SoulAshes", xp = "hc1Xp",
        gold = "hc1Gold", copper = "hc1Money", color = { 1.00, 0.73, 0.73 } },
    { label = "Hardcore II", ash = "hc2SoulAshes", xp = "hc2Xp",
        gold = "hc2Gold", copper = "hc2Money", color = { 1.00, 0.47, 0.47 } },
    { label = "Hardcore III", ash = "hc3SoulAshes", xp = "hc3Xp",
        gold = "hc3Gold", copper = "hc3Money", color = { 1.00, 0.20, 0.20 } },
    { label = "Hardcore IV", ash = "hc4SoulAshes", xp = "hc4Xp",
        gold = "hc4Gold", copper = "hc4Money", color = { 0.80, 0.00, 0.00 } },
    { label = "Hardcore V", ash = "hc5SoulAshes", xp = "hc5Xp",
        gold = "hc5Gold", copper = "hc5Money", color = { 0.60, 0.00, 0.00 } },
}

local function Strip(s)
    s = tostring(s or "")
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function NormalizeTitle(title)
    title = Strip(title):lower()
    title = title:gsub("^!", ""):gsub("^%s+", "")
    title = title:gsub("^%(!%)%s*", "")
    return title
end

local function ObjectivesService()
    local ok, service = pcall(function()
        local pe = _G.ProjectEbonhold
        if type(pe) == "table" and type(pe.ObjectivesService) == "table" then
            return pe.ObjectivesService
        end
        local api = _G.EbonAPI
        local ebon = type(api) == "table" and api.Ebonhold or nil
        if type(ebon) == "table" and type(ebon.Objectives) == "function" then
            return ebon.Objectives()
        end
        return nil
    end)
    if not ok or type(service) ~= "table" then return nil end
    return service
end

-- Project Ebonhold's ObjectiveTrackerFrame (parented to WatchFrame) and its
-- child rewardBagFrame (LOW strata, holds .objectiveData = activeObjective).
local function ObjectiveTrackerRoot()
    local ok, root = pcall(function()
        if type(_G.ObjectiveTrackerFrame) == "table" then
            return _G.ObjectiveTrackerFrame
        end
        local pe = _G.ProjectEbonhold
        local ui = type(pe) == "table" and pe.ObjectivesUI or nil
        if type(ui) == "table" and type(ui.GetTrackerFrame) == "function" then
            return ui.GetTrackerFrame()
        end
        return nil
    end)
    if not ok or type(root) ~= "table" then return nil end
    return root
end

local function ObjectiveBagFrame()
    local ok, bag = pcall(function()
        local root = ObjectiveTrackerRoot()
        if root and type(root.rewardBagFrame) == "table" then
            return root.rewardBagFrame
        end
        return nil
    end)
    if not ok or type(bag) ~= "table" then return nil end
    return bag
end

local function QuestTitle(objective)
    if type(objective) ~= "table" then return nil end
    local title = Strip(objective.title or objective.name or objective.questTitle or "")
    return title ~= "" and title or nil
end

local function ObjectiveBlurb(objective)
    if type(objective) ~= "table" then return nil end
    local text = Strip(objective.objectiveText or objective.objective or "")
    return text ~= "" and text or nil
end

local function PositiveId(value)
    local id = tonumber(value) or 0
    if id > 0 then return id end
    return 0
end

-- An objective identity: its normalized title and its positive quest ID, or
-- 0 when none is known.
local function ObjectiveIdentity(objective)
    local title = QuestTitle(objective)
    if not title then return nil end
    return {
        title = NormalizeTitle(title),
        questId = PositiveId(objective.questId or objective.id),
    }
end

-- Two different known positive quest IDs name two objectives, whatever their
-- titles. A missing ID is no conflict.
local function IdsConflict(a, b)
    a, b = PositiveId(a), PositiveId(b)
    return a > 0 and b > 0 and a ~= b
end

-- The same objective: one nonempty normalized title and no ID conflict.
local function SameIdentity(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    if type(a.title) ~= "string" or a.title == "" or a.title ~= b.title then
        return false
    end
    return not IdsConflict(a.questId, b.questId)
end

local function SnapshotObjective(objective)
    if type(objective) ~= "table" then return nil end
    local title = QuestTitle(objective)
    if not title then return nil end
    local out = {
        title = title,
        questId = tonumber(objective.questId or objective.id) or 0,
        questType = tonumber(objective.questType) or 1,
        objectiveText = ObjectiveBlurb(objective),
    }
    for i = 1, #REWARD_ROWS do
        local spec = REWARD_ROWS[i]
        out[spec.ash] = tonumber(objective[spec.ash]) or 0
        out[spec.xp] = tonumber(objective[spec.xp]) or 0
        out[spec.gold] = tonumber(objective[spec.gold]) or 0
        out[spec.copper] = tonumber(objective[spec.copper]) or 0
    end
    return out
end

local function Remember(objective)
    local snap = SnapshotObjective(objective)
    if snap then remembered = snap end
    return snap
end

local function CallService(service, name)
    if type(service) ~= "table" or type(service[name]) ~= "function" then
        return nil
    end
    local ok, result = pcall(service[name])
    if not ok then return nil end
    return result
end

local function ReadActiveObjective()
    local service = ObjectivesService()
    if service and type(service.GetActiveObjective) == "function" then
        local active = CallService(service, "GetActiveObjective")
        if type(active) == "table" and QuestTitle(active) then
            return active, "active"
        end
    end
    local ok, bagData = pcall(function()
        local root = ObjectiveTrackerRoot()
        if not root or type(root.IsShown) ~= "function" or not root:IsShown() then
            return nil
        end
        local bag = root.rewardBagFrame
        return type(bag) == "table" and bag.objectiveData or nil
    end)
    if ok and type(bagData) == "table" and QuestTitle(bagData) then
        return bagData, "bag"
    end
    return nil
end

local function ReadCurrentObjectives()
    local list = CallService(ObjectivesService(), "GetCurrentObjectives")
    return type(list) == "table" and list or nil
end

-- Updated client (wow.export 0.2.19 capture, callboard_service.lua 51-65,
-- 180-302): the ObjectivesService is gone; the board the server sent is
-- ProjectEbonhold.Callboard.board, with quests {questId, title, objectives,
-- state, done, max, ...} (state 1 = accepted, 2 = complete) and
-- Callboard.enabled false while the realm has no board. Used only when no
-- ObjectivesService exists (an older provider keeps its own path). Read
-- passively under protection; nothing is requested, accepted or claimed.
-- Smallest truthful choice, never an arbitrary one:
--   * an unreadable or disabled board, a malformed quest row, an accepted or
--     complete quest without a positive ID or a title, or two of them with
--     the same ID: no objective;
--   * with the tracker's title: the one accepted or complete quest of that
--     normalized title (two of the same title: none);
--   * without it: the only accepted or complete quest, if there is exactly one.
-- The board's rewards are for the player's own tier and are not mapped onto
-- the per-difficulty reward rows; so no reward row is invented, and the
-- stock reward bag keeps its alpha and mouse (JustifiedStock, RewardsUsable).
-- The identity of the board the provider publishes now: its table and its
-- enabled flag. The provider replaces the board table on every push and sets
-- board = nil, enabled = false when the realm has none, so a cached summary
-- made from another board identity is rebuilt before it is returned (second
-- Spec review: a board refusal is never answered from an earlier board).
local cachedBoardKey = nil
local function BoardKey()
    local ok, key = pcall(function()
        local pe = _G.ProjectEbonhold
        local callboard = type(pe) == "table" and pe.Callboard or nil
        if type(callboard) ~= "table" then return "none" end
        return tostring(callboard.board) .. "|" .. tostring(callboard.enabled)
    end)
    return ok and key or "unreadable"
end

-- Second value: whether the board decides (the provider publishes a
-- Callboard table, or reading it raised). A deciding board that names no
-- objective is a refusal: the caller keeps no earlier objective for it.
local BOARD_STATES = {[1] = true, [2] = true}
local function BoardObjective(trackerTitle)
    local present = false
    local ok, chosen = pcall(function()
        local pe = _G.ProjectEbonhold
        local callboard = type(pe) == "table" and pe.Callboard or nil
        present = type(callboard) == "table"
        if not present or callboard.enabled == false then return nil end
        local board = callboard.board
        local quests = type(board) == "table" and board.quests or nil
        if type(quests) ~= "table" then return nil end
        local candidates, ids = {}, {}
        for i = 1, #quests do
            local quest = quests[i]
            if type(quest) ~= "table" then return nil end
            if BOARD_STATES[quest.state] then
                local id = PositiveId(quest.questId)
                local title = type(quest.title) == "string" and Strip(quest.title) or ""
                if id <= 0 or title == "" or ids[id] then return nil end
                ids[id] = true
                local blurb = type(quest.objectives) == "string" and Strip(quest.objectives) or ""
                candidates[#candidates + 1] = {title = title, questId = id,
                    objectiveText = blurb ~= "" and blurb or nil}
            end
        end
        if trackerTitle then
            local match = nil
            for _, candidate in ipairs(candidates) do
                if NormalizeTitle(candidate.title) == trackerTitle then
                    if match then return nil end
                    match = candidate
                end
            end
            return match
        end
        return #candidates == 1 and candidates[1] or nil
    end)
    if not ok then return nil, true end
    if type(chosen) ~= "table" then return nil, present end
    return chosen, true
end

-- The quest-log row of this objective, and whether the log holds its title
-- under another known positive quest ID. Such a row is another quest: its
-- progress and ID are never this objective's, and while it is there a
-- same-title row without an ID does not stand in for the objective either.
local function QuestLogMatch(objective)
    local ok, match, conflict = pcall(function()
        local title = QuestTitle(objective)
        local questId = PositiveId(objective and (objective.questId or objective.id))
        if (not title or title == "") and questId <= 0 then return nil, false end
        if type(GetNumQuestLogEntries) ~= "function" or type(GetQuestLogTitle) ~= "function" then
            return nil, false
        end
        local want = title and NormalizeTitle(title) or nil
        local count = GetNumQuestLogEntries() or 0
        local idOnly, exact, untagged, conflicting = nil, nil, nil, false
        for i = 1, count do
            -- 3.3.5 + Ebonhold: title, level, tag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily, questID
            local logTitle, _, _, _, isHeader, _, isComplete, _, logQuestId = GetQuestLogTitle(i)
            if not isHeader then
                local logId = PositiveId(logQuestId)
                local row = {
                    title = Strip(logTitle or title or ""),
                    index = i,
                    questId = logId > 0 and logId or questId,
                    isComplete = tonumber(isComplete) or 0,
                }
                -- A stored id can name a different log row than the objective
                -- title. Progress from that row is not this objective's.
                if want and want ~= "" and logTitle and NormalizeTitle(logTitle) == want then
                    if questId > 0 and logId == questId then
                        exact = exact or row
                    elseif IdsConflict(questId, logId) then
                        conflicting = true
                    else
                        untagged = untagged or row
                    end
                end
                if not idOnly and questId > 0 and logId == questId then
                    idOnly = row
                end
            end
        end
        if want and want ~= "" then
            if exact then return exact, conflicting end
            if conflicting then return nil, true end
            return untagged, false
        end
        return idOnly, false
    end)
    if not ok then return nil, false end
    return match, conflict == true
end

local function QuestLogLinesForIndex(index, isComplete)
    local ok, lines = pcall(function()
        if not index then return nil end
        if isComplete and isComplete > 0 then
            return { "|cff66d966" .. Say("callboard.status.ready_turn_in", "Ready for turn-in") .. "|r" }
        elseif isComplete and isComplete < 0 then
            return { "|cffff4d4d" .. Say("callboard.status.failed", "Failed") .. "|r" }
        end
        if type(GetNumQuestLeaderBoards) ~= "function"
            or type(GetQuestLogLeaderBoard) ~= "function" then
            return nil
        end
        local boards = GetNumQuestLeaderBoards(index) or 0
        if boards <= 0 then return nil end
        local found = {}
        for i = 1, boards do
            local text = Strip(GetQuestLogLeaderBoard(i, index))
            if text ~= "" then
                found[#found + 1] = text:gsub("^%-+%s*", "")
            end
        end
        return #found > 0 and found or nil
    end)
    if not ok then return nil end
    return lines
end

local function CollectFontStrings(frame, out, seen, depth)
    out = out or {}
    seen = seen or {}
    depth = depth or 0
    if not frame or seen[frame] or depth > 8 then return out end
    seen[frame] = true
    if type(frame.GetText) == "function" and type(frame.GetObjectType) == "function" then
        local okType, kind = pcall(frame.GetObjectType, frame)
        if okType and kind == "FontString" then
            local ok, text = pcall(frame.GetText, frame)
            text = ok and Strip(text) or ""
            if text ~= "" then out[#out + 1] = text end
        end
    end
    if type(frame.GetRegions) == "function" then
        local ok, regions = pcall(function() return { frame:GetRegions() } end)
        if ok then
            for i = 1, #regions do
                CollectFontStrings(regions[i], out, seen, depth + 1)
            end
        end
    end
    if type(frame.GetChildren) == "function" then
        local ok, children = pcall(function() return { frame:GetChildren() } end)
        if ok then
            for i = 1, #children do
                CollectFontStrings(children[i], out, seen, depth + 1)
            end
        end
    end
    return out
end

local function CollectFieldTexts(frame, out, seen, depth)
    out = out or {}
    seen = seen or {}
    depth = depth or 0
    if not frame or type(frame) ~= "table" or seen[frame] or depth > 6 then
        return out
    end
    seen[frame] = true
    local keys = {
        "text", "Text", "title", "Title", "label", "Label", "name", "Name",
        "objective", "Objective", "objectiveText", "questTitle", "QuestTitle",
        "headerText", "HeaderText",
    }
    for i = 1, #keys do
        local value = frame[keys[i]]
        if type(value) == "string" and Strip(value) ~= "" then
            out[#out + 1] = Strip(value)
        elseif type(value) == "table" and type(value.GetText) == "function" then
            local ok, text = pcall(value.GetText, value)
            text = ok and Strip(text) or ""
            if text ~= "" then out[#out + 1] = text end
        end
    end
    if type(frame.GetChildren) == "function" then
        local ok, children = pcall(function() return { frame:GetChildren() } end)
        if ok then
            for i = 1, #children do
                CollectFieldTexts(children[i], out, seen, depth + 1)
            end
        end
    end
    return out
end

-- The PE callboard tracker frame (confirmed by fstack: <1> EbonholdQuestTracker).
local function TrackerFrame()
    if _G.EbonholdQuestTracker then return _G.EbonholdQuestTracker end
    local ok, f = pcall(function()
        local pe = _G.ProjectEbonhold
        local qt = type(pe) == "table" and pe.QuestTracker or nil
        if type(qt) == "table" and type(qt.GetFrame) == "function" then
            return qt.GetFrame()
        end
        return nil
    end)
    return (ok and type(f) == "table") and f or _G.ProjectEbonholdQuestTracker
end

-- Stock state Nexus changed, one record per exact object and property:
-- { frame, prop = "alpha" or "mouse", original, written }. A record goes
-- only once a getter confirms the original again, or shows that another
-- owner has since set a different usable value (RestoreStock), so a restore
-- that raised or changed nothing is retried by a later publish, with or
-- without a replacement.
-- Alpha and mouse are separate records. The bound only stops new holds (the
-- stock state then stays as it is); no record is dropped to make room.
local heldStock = {}
local MAX_HELD_STOCK = 32

-- The mouse is a client widget boolean: IsMouseEnabled answers 1 or nil on
-- the 3.3.5a client where the offline harness answers true or false.
local STOCK_PROPS = {
    alpha = { get = "GetAlpha", set = "SetAlpha", kind = "number", suppressed = 0 },
    mouse = { get = "IsMouseEnabled", set = "EnableMouse", kind = "clientBoolean",
        suppressed = false },
}

-- Theme.ClientBool, the shared reading of a client widget boolean: true for
-- true or 1, false for false, nil or 0, nil for any other answer. This
-- module is also loaded without Theme (its own fixtures); the same reading
-- stands in then.
local function ClientBool(value)
    local theme = Nexus.Theme
    if type(theme) == "table" and type(theme.ClientBool) == "function" then
        return theme.ClientBool(value)
    end
    if value == true or value == 1 then return true end
    if value == false or value == nil or value == 0 then return false end
    return nil
end

local function IndexStock(frame, key)
    return frame[key]
end

local function StockMethod(frame, name)
    local ok, method = pcall(IndexStock, frame, name)
    if ok and type(method) == "function" then return method end
    return nil
end

-- The current value, or nil when the getter is missing, raises or answers
-- something that is not a usable value of that property. Nothing is guessed
-- in its place. A mouse answer is read as a Lua boolean (1 is on, nil or 0
-- is off); a string, a table or another number is no answer.
local function ReadStock(frame, prop)
    local spec = STOCK_PROPS[prop]
    local getter = StockMethod(frame, spec.get)
    if not getter then return nil end
    local ok, value = pcall(getter, frame)
    if not ok then return nil end
    if spec.kind == "clientBoolean" then return ClientBool(value) end
    if type(value) ~= spec.kind or value ~= value then return nil end
    return value
end

local function FindHeldStock(frame, prop)
    for i = 1, #heldStock do
        local item = heldStock[i]
        if item.frame == frame and item.prop == prop then return item end
    end
    return nil
end

-- Takes one property only from a usable original that is not already the
-- suppressed value (a game-owned alpha 0 or mouse off stays the game's), and
-- only through a supported setter. The original is kept whenever the readback
-- no longer shows it: a setter can change the value and then raise. A
-- readback still at the original means nothing changed and nothing is owned.
local function HoldStock(frame, prop)
    if FindHeldStock(frame, prop) or #heldStock >= MAX_HELD_STOCK then return end
    local spec = STOCK_PROPS[prop]
    local original = ReadStock(frame, prop)
    if original == nil or original == spec.suppressed then return end
    local setter = StockMethod(frame, spec.set)
    if not setter then return end
    pcall(setter, frame, spec.suppressed)
    local after = ReadStock(frame, prop)
    if after ~= original then
        -- What Nexus's write reads back as; the value written when the
        -- readback fails.
        local written = after
        if written == nil then written = spec.suppressed end
        heldStock[#heldStock + 1] = { frame = frame, prop = prop, original = original,
            written = written }
    end
end

-- True once the property is no longer Nexus's: a getter confirms the exact
-- original, or reads a usable value that is neither the original nor what
-- Nexus wrote (another owner changed it since; that value is kept, not
-- overwritten). Only a property that still reads as Nexus's own write, or
-- that cannot be read now, is restored or retried. A property that already
-- reads as its original is not written again. A foreign write of the very
-- value Nexus wrote cannot be told apart and is restored.
local function RestoreStock(item)
    local current = ReadStock(item.frame, item.prop)
    if current == item.original then return true end
    if current ~= nil and current ~= item.written then return true end
    local setter = StockMethod(item.frame, STOCK_PROPS[item.prop].set)
    if setter then pcall(setter, item.frame, item.original) end
    return ReadStock(item.frame, item.prop) == item.original
end

-- Gives back every held property this pass does not justify, each on its
-- own; a record that no getter confirms yet stays for the next pass.
local function ReleaseStock(justified)
    local kept = {}
    for i = 1, #heldStock do
        local item = heldStock[i]
        local props = justified[item.frame]
        local released = false
        if not (props and props[item.prop]) then
            local ok, restored = pcall(RestoreStock, item)
            released = ok and restored == true
        end
        if not released then kept[#kept + 1] = item end
    end
    heldStock = kept
end

-- True when EbonholdQuestTracker / WatchFrame has no other tracked quest or
-- incomplete achievement besides the callboard objective Nexus is mirroring.
local function TrackerOnlyHasCallboard(summary)
    local wantTitle = NormalizeTitle(summary and summary.title or "")
    local wantId = tonumber(summary and summary.questId) or 0
    if wantTitle == "" and wantId <= 0 then return false end

    if type(GetTrackedAchievements) == "function" then
        for _, achID in ipairs({ GetTrackedAchievements() }) do
            if type(GetAchievementInfo) == "function" then
                local ok, _, name, _, completed = pcall(GetAchievementInfo, achID)
                if ok and name and not completed then
                    return false
                end
            else
                return false
            end
        end
    elseif type(GetNumTrackedAchievements) == "function" then
        if (GetNumTrackedAchievements() or 0) > 0 then return false end
    end

    local watched = _G.ProjectEbonholdDB
        and type(_G.ProjectEbonholdDB.questTracker) == "table"
        and type(_G.ProjectEbonholdDB.questTracker.watchedQuests) == "table"
        and _G.ProjectEbonholdDB.questTracker.watchedQuests
        or nil

    local clientWatched = {}
    if type(GetNumQuestWatches) == "function" and type(GetQuestIndexForWatch) == "function" then
        for i = 1, (GetNumQuestWatches() or 0) do
            local idx = GetQuestIndexForWatch(i)
            if idx then clientWatched[idx] = true end
        end
    end

    if type(GetNumQuestLogEntries) == "function" and type(GetQuestLogTitle) == "function" then
        local count = GetNumQuestLogEntries() or 0
        for questIndex = 1, count do
            local logTitle, _, _, _, isHeader, _, _, _, logQuestId = GetQuestLogTitle(questIndex)
            if not isHeader and logTitle then
                local qid = tonumber(logQuestId) or 0
                local isWatched = clientWatched[questIndex] == true
                    or (watched ~= nil and qid > 0 and watched[qid] == true)
                if isWatched then
                    -- A watched quest of the same title under another known
                    -- positive quest ID is another quest, not this objective.
                    local isCallboard = (wantId > 0 and qid == wantId)
                        or SameIdentity({ title = wantTitle, questId = wantId },
                            { title = NormalizeTitle(logTitle), questId = qid })
                    if not isCallboard then
                        return false
                    end
                end
            end
        end
    end
    return true
end

-- Suppress stock frames only while Nexus is showing this same objective.
-- Remember the objects and the alpha/mouse values actually changed.
local function ReplacementCovered(summary)
    if not summary or summary.observed ~= true then return false end
    local panelApi = Nexus.Panel
    if not panelApi or type(panelApi.VisibilityFacts) ~= "function" then
        return false
    end
    local okFacts, facts = pcall(panelApi.VisibilityFacts)
    if not okFacts or type(facts) ~= "table" then return false end
    if facts.shown ~= true or facts.committed ~= true or facts.hadFailure == true then
        return false
    end
    local root = _G.NexusPanel
    local title = root and root._callboardTitle
    local line = root and root._callboardLine
    if not title or not line then return false end
    if type(title.IsShown) ~= "function" or not title:IsShown() then return false end
    if type(line.IsShown) ~= "function" or not line:IsShown() then return false end
    local titleHeight = type(title.GetHeight) == "function" and tonumber(title:GetHeight()) or 0
    local lineHeight = type(line.GetHeight) == "function" and tonumber(line:GetHeight()) or 0
    if not titleHeight or titleHeight < 17 or not lineHeight or lineHeight < 17 then
        return false
    end
    local shown = Strip(type(title.GetText) == "function" and title:GetText() or "")
    if shown == "" or NormalizeTitle(shown) ~= NormalizeTitle(summary.title or "") then
        return false
    end
    return true
end

-- Usable replacement reward rows: at least one row the Nexus tooltip can
-- state. Without one that tooltip says the rewards are not available.
local function RewardsUsable(summary)
    local rows = type(summary) == "table" and summary.rewards or nil
    if type(rows) ~= "table" then return false end
    for i = 1, #rows do
        local row = rows[i]
        if type(row) == "table" and ((tonumber(row.ash) or 0) > 0
            or (tonumber(row.copper) or 0) > 0 or (tonumber(row.xp) or 0) > 0) then
            return true
        end
    end
    return false
end

-- Marks a frame and every parent above it. Bounded; a parent that cannot be
-- read ends the walk.
local function MarkWithAncestors(set, frame)
    local depth = 0
    while type(frame) == "table" and not set[frame] and depth < 16 do
        set[frame] = true
        depth = depth + 1
        local getParent = StockMethod(frame, "GetParent")
        local ok, parent = false, nil
        if getParent then ok, parent = pcall(getParent, frame) end
        frame = ok and parent or nil
    end
end

-- The exact object/property pairs this pass justifies, in order, and the
-- same pairs by object. Nothing is justified unless the matching Nexus row
-- is covered. Without usable reward rows the Nexus tooltip cannot replace
-- the stock rewards, so the reward bag, the objective root that holds it
-- and every parent above either keep their alpha and mouse: a bag at alpha 1
-- is not usable inside a parent at alpha 0. A progress-only tracker outside
-- that chain may still be replaced. The tracker roles need that no other
-- quest or achievement is tracked.
local function JustifiedStock(summary)
    local order, justified, kept = {}, {}, {}
    local okCovered, covered = pcall(ReplacementCovered, summary)
    if not okCovered or covered ~= true then return order, justified end
    local otf = ObjectiveTrackerRoot()
    local bag = ObjectiveBagFrame()
    if not RewardsUsable(summary) then
        MarkWithAncestors(kept, bag)
        MarkWithAncestors(kept, otf)
    end
    local function Want(frame, prop)
        if type(frame) ~= "table" or kept[frame] then return end
        local props = justified[frame]
        if not props then
            props = {}
            justified[frame] = props
        end
        if not props[prop] then
            props[prop] = true
            order[#order + 1] = { frame = frame, prop = prop }
        end
    end
    local function Role(frame, mouseFrame)
        if type(frame) ~= "table" or kept[frame] then return end
        Want(frame, "alpha")
        Want(mouseFrame, "mouse")
    end
    Role(otf, otf)
    Role(bag, bag)
    local okOnly, onlyCallboard = pcall(TrackerOnlyHasCallboard, summary)
    if okOnly and onlyCallboard == true then
        local tracker = TrackerFrame()
        if type(tracker) == "table" then
            local okCollapse, collapse = pcall(IndexStock, tracker, "collapse")
            Role(tracker, okCollapse and collapse or nil)
        end
        Role(_G.WatchFrame, nil)
    end
    return order, justified
end

-- Each pass gives back first what is no longer justified (an old object
-- before its successor is taken) and then holds what is. A shared object
-- stays held while any of its roles still justifies the property.
local function PublishStock(summary)
    local okJustified, order, justified = pcall(JustifiedStock, summary)
    if not okJustified then order, justified = {}, {} end
    ReleaseStock(justified)
    for i = 1, #order do
        pcall(HoldStock, order[i].frame, order[i].prop)
    end
end

function M.PublishCoverage()
    pcall(PublishStock, cachedSummary)
end

local function CollectTrackerTexts()
    local tracker = TrackerFrame()
    if not tracker then return nil, nil end
    local texts = CollectFontStrings(tracker, {}, {}, 0)
    CollectFieldTexts(tracker, texts, {}, 0)
    return tracker, texts
end

local function IsObjectivesHeader(normalized)
    if not normalized or normalized == "" then return false end
    return normalized == "objectives"
        or normalized == "quests"
        or normalized:match("^objectives%s*%b()$") ~= nil
        or normalized:match("^quests%s*%b()$") ~= nil
end

local function ParseTrackerQuest(texts)
    if not texts or #texts == 0 then return nil, nil end
    local afterQuests, title, lines = false, nil, nil
    for i = 1, #texts do
        local text = texts[i]
        local normalized = NormalizeTitle(text)
        if normalized == "quests" or normalized:match("^quests%s*%b()$") then
            afterQuests = true
        elseif afterQuests and not title then
            if not IsObjectivesHeader(normalized) and not text:match("^%-")
                and not text:match("^%d+%s*m") and not text:match("^%d+%s*s")
                and not text:match("^%d+%s*/%s*%d+") then
                title = Strip(text):gsub("^%(!%)%s*", ""):gsub("^!+%s*", "")
            end
        elseif title then
            if text:match("^%-") or text:match("%d+%s*/%s*%d+") then
                lines = lines or {}
                lines[#lines + 1] = text:gsub("^%-+%s*", "")
            elseif IsObjectivesHeader(normalized) then
                break
            elseif lines and #lines > 0 then
                break
            end
        end
    end
    if not title or title == "" then
        -- Fallback within EbonholdQuestTracker only (still never WatchFrame):
        -- pick the first non-header line inside the PE tracker. Skip collapsed
        -- "Objectives (1)" / "Quests (1)" headers so they are never taken as a
        -- quest title.
        for i = 1, #texts do
            local text = texts[i]
            local n = NormalizeTitle(text)
            if not IsObjectivesHeader(n) and not text:match("^%-")
                and not text:match("^%d+%s*/%s*%d+") and #n > 3
                and not n:find("waypoint", 1, true)
                and not n:find("location data", 1, true) then
                title = Strip(text):gsub("^%(!%)%s*", ""):gsub("^!+%s*", "")
                lines = {}
                for j = i + 1, #texts do
                    local line = texts[j]
                    if line:match("^%-") or line:match("%d+%s*/%s*%d+") then
                        lines[#lines + 1] = line:gsub("^%-+%s*", "")
                    elseif #lines > 0 then
                        break
                    end
                end
                break
            end
        end
    end
    if not title or title == "" then return nil, nil end
    return {
        title = title,
        questId = 0,
        objectiveText = lines and lines[1] or nil,
    }, lines
end

local DIFFICULTY_LABELS = {
    normal = "Normal",
    ["hardcore i"] = "Hardcore I",
    ["hardcore ii"] = "Hardcore II",
    ["hardcore iii"] = "Hardcore III",
    ["hardcore iv"] = "Hardcore IV",
    ["hardcore v"] = "Hardcore V",
    ["hardcore 1"] = "Hardcore I",
    ["hardcore 2"] = "Hardcore II",
    ["hardcore 3"] = "Hardcore III",
    ["hardcore 4"] = "Hardcore IV",
    ["hardcore 5"] = "Hardcore V",
    hc1 = "Hardcore I",
    hc2 = "Hardcore II",
    hc3 = "Hardcore III",
    hc4 = "Hardcore IV",
    hc5 = "Hardcore V",
}

local function MatchDifficultyLabel(text)
    text = NormalizeTitle(text)
    if text == "" then return nil end
    if DIFFICULTY_LABELS[text] then return DIFFICULTY_LABELS[text] end
    local hc = text:match("^hardcore%s*([ivx]+)$") or text:match("^hardcore%s*([1-5])$")
    if hc then
        return DIFFICULTY_LABELS["hardcore " .. hc]
            or DIFFICULTY_LABELS["hardcore " .. tostring(hc)]
    end
    return nil
end

-- The longest difficulty label that begins this normalized text. Labels
-- are prefixes of one another ("hardcore i" of "hardcore ii" and
-- "hardcore iii"), so the choice is by length and never by pairs order:
-- Hardcore I cannot claim a Hardcore II or III line.
local function LongestDifficultyPrefix(normalized)
    local bestKey, bestLabel = nil, nil
    for k, canonical in pairs(DIFFICULTY_LABELS) do
        if normalized:sub(1, #k) == k and (not bestKey or #k > #bestKey) then
            bestKey, bestLabel = k, canonical
        end
    end
    return bestKey, bestLabel
end

-- In the PE tooltip: "451 [gold icon] 11 [silver icon] 60 [copper icon] 59169500 [ash icon]".
-- Strip "|T...|t" texture tags first so icon dimensions/paths cannot pollute
-- the numbers. Also understands formatted "59.2M Ash" / "103K Ash" so a re-parse
-- of formatted text never turns "59.2M" into "59" and "2".
local function ParseRewardRight(text)
    text = tostring(text or "")
    text = text:gsub("|T.-|t", " "):gsub("|A.-|a", " ")
    text = Strip(text)

    local scaledAsh, unit = text:match("(%d+%.?%d*)%s*([MmKk])%s*[Aa]sh")
    if not scaledAsh then
        scaledAsh, unit = text:match("(%d+%.?%d*)([MmKk])")
    end
    local ash = 0
    if scaledAsh then
        local mult = (unit == "M" or unit == "m") and 1000000 or 1000
        ash = math.floor((tonumber(scaledAsh) or 0) * mult + 0.5)
        -- Remove the scaled ash token before extracting coin integers.
        text = text:gsub("%d+%.?%d*%s*[MmKk]%s*[Aa]sh", " ")
        text = text:gsub("%d+%.?%d*[MmKk]", " ")
    end

    local nums = {}
    for token in text:gmatch("%d+") do
        nums[#nums + 1] = tonumber(token)
    end
    local g, s, c = 0, 0, 0
    if ash > 0 then
        g = nums[1] or 0
        s = nums[2] or 0
        c = nums[3] or 0
    elseif #nums >= 4 then
        g, s, c, ash = nums[1], nums[2], nums[3], nums[#nums]
    elseif #nums == 3 then
        if nums[3] >= 1000 then
            g, s, ash = nums[1], nums[2], nums[3]
        else
            g, s, c = nums[1], nums[2], nums[3]
        end
    elseif #nums == 2 then
        if nums[2] >= 1000 then
            g, ash = nums[1], nums[2]
        else
            g, s = nums[1], nums[2]
        end
    elseif #nums == 1 then
        if nums[1] >= 1000 then ash = nums[1] else g = nums[1] end
    end
    local copper = (tonumber(g) or 0) * 10000 + (tonumber(s) or 0) * 100 + (tonumber(c) or 0)
    return copper, tonumber(ash) or 0
end

local function ReadTooltipRewardRows()
    if not GameTooltip or not GameTooltip.NumLines then return nil end
    local n = GameTooltip:NumLines() or 0
    if n <= 0 then return nil end
    local hasHeader = false
    for i = 1, math.min(n, 3) do
        local left = _G["GameTooltipTextLeft" .. i]
        local t = left and Strip(left:GetText() or "") or ""
        if NormalizeTitle(t):find("rewards by difficulty", 1, true) then
            hasHeader = true
            break
        end
    end
    if not hasHeader then return nil end
    local rows = {}
    for i = 1, n do
        local left = _G["GameTooltipTextLeft" .. i]
        local right = _G["GameTooltipTextRight" .. i]
        local leftRaw = left and left:GetText() or ""
        local rightRaw = right and right:GetText() or ""
        local label = MatchDifficultyLabel(leftRaw)
        if not label then
            -- Single-line fallback when difficulty and numbers share LeftN.
            local stripped = Strip(leftRaw:gsub("|T.-|t", " "))
            local key, canonical = LongestDifficultyPrefix(NormalizeTitle(stripped))
            if key then
                label = canonical
                if rightRaw == "" then
                    rightRaw = stripped:sub(#key + 1)
                end
            end
        end
        if label then
            local copper, ash = ParseRewardRight(rightRaw ~= "" and rightRaw or leftRaw)
            rows[#rows + 1] = {
                label = label,
                copper = copper,
                ash = ash,
                xp = 0,
            }
        end
    end
    return #rows > 0 and rows or nil
end


local function FormatAsh(n)
    n = tonumber(n) or 0
    if n <= 0 then return nil end
    if n >= 1000000 then
        local m = n / 1000000
        if m >= 100 then return string.format("%.0fM", m) end
        if m >= 10 then return string.format("%.1fM", m) end
        return string.format("%.2fM", m):gsub("(%..-)0+$", "%1"):gsub("%.$", "")
    end
    if n >= 1000 then
        return string.format("%.0fK", n / 1000)
    end
    return tostring(math.floor(n + 0.5))
end

local COIN_GOLD = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
local COIN_SILVER = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t"
local COIN_COPPER = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t"
local ASH_ICON = "|TInterface\\Icons\\Spell_Frost_Stun:12:12:2:0|t"

local function FormatCopper(copper)
    copper = tonumber(copper) or 0
    if copper <= 0 then return nil end
    local g = math.floor(copper / 10000)
    local s = math.floor((copper % 10000) / 100)
    local c = copper % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = "|cffffffff" .. g .. "|r" .. COIN_GOLD end
    if s > 0 then parts[#parts + 1] = "|cffffffff" .. s .. "|r" .. COIN_SILVER end
    if c > 0 or #parts == 0 then parts[#parts + 1] = "|cffffffff" .. c .. "|r" .. COIN_COPPER end
    return table.concat(parts, " ")
end

local function CollectRewardRows(objective)
    local rows = {}
    local isProfession = (tonumber(objective and objective.questType) or 1) == 4
    local maxIdx = isProfession and 1 or #REWARD_ROWS
    for i = 1, maxIdx do
        local spec = REWARD_ROWS[i]
        local ash = tonumber(objective and objective[spec.ash]) or 0
        local xp = tonumber(objective and objective[spec.xp]) or 0
        local gold = tonumber(objective and objective[spec.gold]) or 0
        local copper = tonumber(objective and objective[spec.copper]) or 0
        if gold > 0 and copper <= 0 then
            copper = math.floor(gold) * 10000
        end
        -- XP stays XP: no money is derived from it. Money is only the
        -- copper or gold the source states.
        if ash > 0 or xp > 0 or copper > 0 then
            rows[#rows + 1] = {
                label = spec.label,
                ash = ash,
                xp = xp,
                copper = copper,
                color = spec.color,
            }
        end
    end
    return rows
end

-- Legitimate sources for the callboard quest:
--   1. ProjectEbonhold.ObjectivesService.GetActiveObjective() / ObjectiveTrackerFrame.rewardBagFrame.objectiveData
--   2. ProjectEbonhold.ObjectivesService.GetCurrentObjectives() matched against the quest log
--   3. an objective remembered from those sources that still matches
-- EbonholdQuestTracker text names no objective: a shown ObjectiveTrackerFrame
-- does not make its first ordinary quest a Callboard one. A tracker title only
-- selects, or adds progress lines to, an objective of that title from a source
-- above, and not while the quest log holds that title under another known
-- quest ID.
local function ResolveObjective()
    local _, trackerTexts = CollectTrackerTexts()
    local trackerObj, trackerLines = ParseTrackerQuest(trackerTexts)
    local trackerTitle = trackerObj and NormalizeTitle(trackerObj.title) or nil
    if trackerTitle == "" then trackerTitle = nil end

    -- Updated client: the Callboard board stands in only where no
    -- ObjectivesService exists at all, and a deciding board is applied before
    -- the stock reward bag's retained objective (third Spec review): a bag
    -- the old tracker still shows never overrides a disabled, empty,
    -- malformed or ambiguous current board. Without a Callboard table the
    -- earlier order (active objective, bag, list, remembered) is unchanged.
    if not ObjectivesService() then
        local fromBoard, decides = BoardObjective(trackerTitle)
        if fromBoard then
            local snap = Remember(fromBoard)
            if snap then
                local useLines = nil
                if trackerTitle and NormalizeTitle(snap.title) == trackerTitle then
                    useLines = trackerLines
                end
                return snap, useLines, "board"
            end
        end
        -- Second Spec review: a deciding board that names none (disabled,
        -- empty, ambiguous, malformed or unreadable) stays a refusal. The
        -- objective remembered from an earlier board is dropped, never
        -- revived from the tracker text or the quest log.
        if decides then
            remembered = nil
            return nil, nil, nil
        end
    end

    local active, activeSource = ReadActiveObjective()
    if type(active) == "table" and QuestTitle(active) then
        local snap = Remember(active)
        if snap then
            local useLines = nil
            if trackerTitle and NormalizeTitle(snap.title) == trackerTitle then
                useLines = trackerLines
            end
            return snap, useLines, activeSource
        end
    end

    local list = ReadCurrentObjectives()
    if type(list) == "table" then
        for i = 1, #list do
            local snap = SnapshotObjective(list[i])
            if snap then
                local tracked = trackerTitle ~= nil and NormalizeTitle(snap.title) == trackerTitle
                local logMatch, conflict = QuestLogMatch(snap)
                if logMatch or (tracked and not conflict) then
                    Remember(list[i])
                    return snap, tracked and trackerLines or nil, "list"
                end
            end
        end
    end

    if remembered and trackerTitle and NormalizeTitle(remembered.title) == trackerTitle then
        local logMatch, conflict = QuestLogMatch(remembered)
        if logMatch or not conflict then
            return remembered, trackerLines, "remembered"
        end
    end

    if remembered and QuestLogMatch(remembered) then
        return remembered, nil, "remembered"
    end

    return nil, nil, nil
end

-- Tooltip reward rows follow one objective. Its removal ends them, and so
-- does a change to another objective identity, unless the capture names the
-- new objective by its own positive quest ID. The identity kept for that
-- comparison holds on to a known ID, so the same objective read later without
-- one does not hide a conflict with the next objective.
local function TrackRewardIdentity(identity)
    if not identity then
        if lastIdentity then scraped = nil end
        lastIdentity = nil
        return
    end
    if lastIdentity and SameIdentity(lastIdentity, identity) then
        if identity.questId <= 0 then identity.questId = lastIdentity.questId end
    elseif lastIdentity then
        local own = scraped ~= nil and scraped.questId > 0
            and scraped.questId == identity.questId and scraped.title == identity.title
        if not own then scraped = nil end
    end
    lastIdentity = identity
end

local function BuildSummary()
    local ok, summary = pcall(function()
        local objective, trackerLines, source = ResolveObjective()
        local title = QuestTitle(objective)
        if not title then
            TrackRewardIdentity(nil)
            return { observed = false }
        end
        local identity = ObjectiveIdentity(objective)
        local logMatch, logConflict = QuestLogMatch(objective)
        if logMatch and NormalizeTitle(logMatch.title or "") ~= identity.title then
            logMatch = nil
        end
        -- Tracker text carries no quest ID. While the log holds this title
        -- under another known ID, that text can be the other quest's.
        local lines, progressSource = nil, nil
        if not logConflict and type(trackerLines) == "table" and #trackerLines > 0 then
            lines = trackerLines
            progressSource = "tracker"
        end
        if not lines and logMatch then
            lines = QuestLogLinesForIndex(logMatch.index, logMatch.isComplete)
            if lines and #lines > 0 then progressSource = "questlog" else lines = nil end
        end
        local blurb = ObjectiveBlurb(objective)
        if not lines and blurb then
            lines = { blurb }
            progressSource = "objective"
        end
        -- The objective's own positive ID stays authoritative. A matched log
        -- row lends its ID only to an objective without one.
        local questId = identity.questId
        if questId <= 0 and logMatch then questId = PositiveId(logMatch.questId) end
        identity.questId = questId
        TrackRewardIdentity(identity)
        local rewards = CollectRewardRows(objective)
        local rewardSource = nil
        if type(rewards) == "table" and #rewards > 0 then
            rewardSource = "api"
            for i = 1, #rewards do rewards[i].source = "api" end
        elseif scraped and SameIdentity(scraped, identity) then
            rewards = scraped.rows
            rewardSource = "tooltip"
        else
            rewards = {}
        end
        return {
            observed = true,
            title = (logMatch and logMatch.title) or title,
            lines = lines or {},
            questId = questId,
            rewards = rewards,
            source = source,
            progressSource = progressSource,
            rewardSource = rewardSource,
        }
    end)
    if not ok or type(summary) ~= "table" then
        return cachedSummary or { observed = false }
    end
    return summary
end

local function Signature(summary)
    if not summary or not summary.observed then return "none" end
    local parts = {
        tostring(summary.questId or 0),
        tostring(summary.title or ""),
    }
    for i = 1, #(summary.lines or {}) do
        parts[#parts + 1] = tostring(summary.lines[i])
    end
    for i = 1, #(summary.rewards or {}) do
        local row = summary.rewards[i]
        parts[#parts + 1] = tostring(row.label) .. ":" .. tostring(row.ash)
            .. ":" .. tostring(row.copper)
    end
    return table.concat(parts, "|")
end

-- No Ebonhold tracker or objectives API: there is nothing to mirror. The
-- scanner must not walk the UI or rebuild the HUD on that path. A full panel
-- refresh from this frame changes how many startup slices fit in one
-- profiler tick, and that moves later sync request IDs.
local function CallboardSourcePresent()
    if type(_G.EbonholdQuestTracker) == "table" then return true end
    if type(_G.ProjectEbonholdQuestTracker) == "table" then return true end
    if type(_G.ObjectiveTrackerFrame) == "table" then return true end
    if type(_G.ProjectEbonhold) == "table" then return true end
    local api = _G.EbonAPI
    return type(api) == "table" and type(api.Ebonhold) == "table"
end

local function RefreshNow()
    cachedBoardKey = BoardKey()
    local summary = BuildSummary()
    if type(summary) ~= "table" then
        pcall(PublishStock, nil)
        return
    end
    local sig = Signature(summary)
    local previous = cachedSummary
    local changed = sig ~= cachedSignature
    cachedSignature = sig
    cachedSummary = summary
    -- Filling the empty cache is not a panel change. Rebuilding the HUD here
    -- is what shifts a profiler-budgeted sync send by one frame. An unchanged
    -- observation does not refresh it again.
    local wasObserved = type(previous) == "table" and previous.observed == true
    if changed and (summary.observed or wasObserved) then
        if Nexus.Panel and Nexus.Panel.Refresh then
            pcall(Nexus.Panel.Refresh)
        end
    end
    pcall(PublishStock, cachedSummary)
end

local function EnsureEbonholdHooks()
    if type(hooksecurefunc) ~= "function" then return end
    local pe = _G.ProjectEbonhold
    if type(pe) ~= "table" then return end
    if not hookedObjectivesUI and type(pe.ObjectivesUI) == "table" then
        hookedObjectivesUI = true
        if type(pe.ObjectivesUI.UpdateTracker) == "function" then
            pcall(hooksecurefunc, pe.ObjectivesUI, "UpdateTracker", function(objective)
                if type(objective) == "table" then Remember(objective) end
                refreshQueued = true
                fastPollRemaining = math.max(fastPollRemaining, 2)
            end)
        end
        if type(pe.ObjectivesUI.DisplayObjectives) == "function" then
            pcall(hooksecurefunc, pe.ObjectivesUI, "DisplayObjectives", function()
                refreshQueued = true
            end)
        end
    end
    if not hookedQuestTracker and type(pe.QuestTracker) == "table" then
        hookedQuestTracker = true
        if type(pe.QuestTracker.MarkDirty) == "function" then
            pcall(hooksecurefunc, pe.QuestTracker, "MarkDirty", function()
                fastPollRemaining = math.max(fastPollRemaining, 2)
                refreshQueued = true
            end)
        end
    end
end

-- Identity of the objective a shown tooltip belongs to, from the objectiveData
-- of its owner or of the owner's parent. A parent of the same title supplies a
-- positive ID the owner lacks; one of the same title under another known ID
-- leaves the source ambiguous, and it names no objective. Reads only: no
-- handler of the owner runs and the tooltip is left as the game drew it.
local function TooltipSourceIdentity()
    if not GameTooltip or type(GameTooltip.GetOwner) ~= "function" then
        return nil
    end
    local ok, identity = pcall(function()
        local owner = GameTooltip.GetOwner(GameTooltip)
        if type(owner) ~= "table" then return nil end
        local parentData = nil
        if type(owner.GetParent) == "function" then
            local okParent, parent = pcall(owner.GetParent, owner)
            if okParent and type(parent) == "table" then
                parentData = parent.objectiveData
            end
        end
        local data = owner.objectiveData
        if type(data) ~= "table" then
            data, parentData = parentData, nil
        end
        local found = ObjectiveIdentity(data)
        if not found or found.title == "" then return nil end
        local above = ObjectiveIdentity(parentData)
        if above and above.title == found.title then
            if IdsConflict(found.questId, above.questId) then return nil end
            if found.questId <= 0 then found.questId = above.questId end
        end
        return found
    end)
    if not ok then return nil end
    return identity
end

function M.Init()
    if scanner then return end
    EnsureEbonholdHooks()
    scanner = CreateFrame("Frame", "NexusCallboardStatusScanner", UIParent)
    scanner:RegisterEvent("PLAYER_ENTERING_WORLD")
    scanner:RegisterEvent("QUEST_LOG_UPDATE")
    scanner:RegisterEvent("UNIT_QUEST_LOG_CHANGED")
    scanner:SetScript("OnEvent", function(_, event)
        if not CallboardSourcePresent() and not remembered then return end
        EnsureEbonholdHooks()
        refreshQueued = true
        fastPollRemaining = math.max(fastPollRemaining, 10)
        if event == "PLAYER_ENTERING_WORLD" then
            -- A new world inherits no reward rows read before it.
            scraped = nil
            local service = ObjectivesService()
            if service and type(service.RequestObjectives) == "function" then
                pcall(service.RequestObjectives)
            end
        end
    end)
    scanner:SetScript("OnUpdate", function(_, dt)
        if not CallboardSourcePresent() and not remembered then return end
        elapsed = elapsed + (tonumber(dt) or 0)
        local interval = fastPollRemaining > 0 and 0.2 or 1.0
        if not refreshQueued and elapsed < interval then return end
        elapsed = 0
        refreshQueued = false
        if fastPollRemaining > 0 then
            fastPollRemaining = fastPollRemaining - 1
        end
        EnsureEbonholdHooks()
        RefreshNow()
    end)
    -- Passive capture of a tooltip the game already showed. The owner of that
    -- tooltip names the objective. Nexus does not call foreign enter/leave
    -- handlers and does not hide a tooltip it did not open.
    if GameTooltip and type(GameTooltip.HookScript) == "function" then
        pcall(GameTooltip.HookScript, GameTooltip, "OnShow", function()
            if showingOwnTooltip then return end
            local rows = ReadTooltipRewardRows()
            local source = TooltipSourceIdentity()
            if not rows or not source then return end
            for i = 1, #rows do rows[i].source = "tooltip" end
            scraped = { rows = rows, title = source.title, questId = source.questId }
            if cachedSummary and cachedSummary.observed and lastIdentity
                and SameIdentity(lastIdentity, scraped) then
                refreshQueued = true
            end
        end)
    end
end

function M.GetSummary()
    local boardKey = BoardKey()
    if cachedSignature == "" or boardKey ~= cachedBoardKey then
        cachedBoardKey = boardKey
        local summary = BuildSummary()
        if type(summary) == "table" then
            cachedSummary = summary
            cachedSignature = Signature(summary)
        end
    end
    return cachedSummary
end

function M.IsObserved()
    local summary = M.GetSummary()
    return summary and summary.observed == true
end

function M.IconTexture()
    return "Interface\\Icons\\INV_Misc_Bag_10"
end

local function AnchorRewardsTooltipLeft(owner)
    if not GameTooltip or not owner then return end
    GameTooltip:ClearAllPoints()
    -- `owner` is positioned at x=12 inside the Nexus panel; -16 places the
    -- tooltip's right edge 4px to the left of the panel's outer border.
    GameTooltip:SetPoint("TOPRIGHT", owner, "TOPLEFT", -16, 4)
end

local function ShowRewardsRows(owner, rows)
    showingOwnTooltip = true
    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    AnchorRewardsTooltipLeft(owner)
    GameTooltip:ClearLines()
    GameTooltip:AddLine(Say("callboard.heading.rewards_by_difficulty", "Rewards by Difficulty"), 1, 0.82, 0)
    GameTooltip:AddLine(Say("callboard.tooltip.higher_difficulty_rewards",
        "Completing the objective on higher difficulties grants better rewards."), 0.85, 0.85, 0.85, true)
    GameTooltip:AddLine(" ")
    for i = 1, #rows do
        local row = rows[i]
        local right = {}
        local money = FormatCopper(row.copper)
        if money then
            right[#right + 1] = money
        elseif row.xp and row.xp > 0 then
            local xp = tostring(math.floor(row.xp))
            right[#right + 1] = SayF("callboard.value.reward_xp", {xp = xp}, xp .. " XP")
        end
        local ash = FormatAsh(row.ash)
        if ash then
            right[#right + 1] = "|cffa380ff" .. SayF("callboard.value.reward_ash", {ash = ash}, ash .. " Ash") .. "|r"
        end
        local labelColor = row.color or (row.label == "Normal" and { 1, 1, 1 } or { 1, 0.35, 0.35 })
        GameTooltip:AddDoubleLine(
            DifficultyShown(row.label),
            #right > 0 and table.concat(right, "  ") or "—",
            labelColor[1], labelColor[2], labelColor[3],
            1, 1, 1)
    end
    GameTooltip:Show()
    AnchorRewardsTooltipLeft(owner)
    showingOwnTooltip = false
end

function M.ShowRewardsTooltip(owner)
    if not GameTooltip or not owner then return end
    local summary = M.GetSummary()
    local rows = summary and summary.rewards or nil
    if type(rows) == "table" and #rows > 0 then
        ShowRewardsRows(owner, rows)
        return
    end

    GameTooltip:SetOwner(owner, "ANCHOR_NONE")
    AnchorRewardsTooltipLeft(owner)
    GameTooltip:ClearLines()
    GameTooltip:AddLine(Say("callboard.heading.rewards_by_difficulty", "Rewards by Difficulty"), 1, 0.82, 0)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(Say("callboard.tooltip.rewards_unavailable",
        "Reward details are not available for this objective yet."), 0.7, 0.7, 0.7, true)
    GameTooltip:Show()
    AnchorRewardsTooltipLeft(owner)
end

function M.HideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

return M
