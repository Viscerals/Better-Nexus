-- Nexus: ui/CallboardStatus.lua
-- Read-only mirror of the accepted Callboard objective and its difficulty
-- rewards. Sources: EbonAPI.Ebonhold.Objectives and EbonholdQuestTracker (the
-- PE tracker shown in fstack). Never falls back to generic WatchFrame/quest-
-- watch entries (that grabbed unrelated quests like "One More Door") and
-- never calls SelectQuestLogEntry. Stock trackers stay until the Nexus row
-- for the same objective is visible, and only the state Nexus changed is
-- restored. Passive reward reads do not drive foreign enter/leave handlers.

Nexus = Nexus or {}
local M = {}
Nexus.CallboardStatus = M

local scanner
local elapsed = 0
local cachedSummary = { observed = false }
local cachedSignature = ""
local remembered
local scrapedRewards
local scrapedForTitle
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
            return active
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
        return bagData
    end
    return nil
end

local function ReadCurrentObjectives()
    local list = CallService(ObjectivesService(), "GetCurrentObjectives")
    return type(list) == "table" and list or nil
end

local function QuestLogMatch(objective)
    local ok, match = pcall(function()
        local title = QuestTitle(objective)
        local questId = tonumber(objective and (objective.questId or objective.id)) or 0
        if (not title or title == "") and questId <= 0 then return nil end
        if type(GetNumQuestLogEntries) ~= "function" or type(GetQuestLogTitle) ~= "function" then
            return nil
        end
        local want = title and NormalizeTitle(title) or nil
        local count = GetNumQuestLogEntries() or 0
        local idOnly = nil
        for i = 1, count do
            -- 3.3.5 + Ebonhold: title, level, tag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily, questID
            local logTitle, _, _, _, isHeader, _, isComplete, _, logQuestId = GetQuestLogTitle(i)
            if not isHeader then
                local row = {
                    title = Strip(logTitle or title or ""),
                    index = i,
                    questId = tonumber(logQuestId) or questId,
                    isComplete = tonumber(isComplete) or 0,
                }
                -- A stored id can name a different log row than the objective
                -- title. Progress from that row is not this objective's.
                if want and want ~= "" and logTitle and NormalizeTitle(logTitle) == want then
                    return row
                end
                if not idOnly and questId > 0 and tonumber(logQuestId) == questId then
                    idOnly = row
                end
            end
        end
        if want and want ~= "" then return nil end
        return idOnly
    end)
    if not ok then return nil end
    return match
end

local function QuestLogLinesForIndex(index, isComplete)
    local ok, lines = pcall(function()
        if not index then return nil end
        if isComplete and isComplete > 0 then
            return { "|cff66d966Ready for turn-in|r" }
        elseif isComplete and isComplete < 0 then
            return { "|cffff4d4dFailed|r" }
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

local heldStock = {}

local function StockAlpha(frame)
    if not frame or type(frame.GetAlpha) ~= "function" then return nil end
    local ok, value = pcall(frame.GetAlpha, frame)
    if ok and type(value) == "number" then return value end
    return nil
end

local function StockMouse(frame)
    if not frame or type(frame.IsMouseEnabled) ~= "function" then return nil end
    local ok, value = pcall(frame.IsMouseEnabled, frame)
    if ok and type(value) == "boolean" then return value end
    return nil
end

local function HoldFrame(frame, mouseFrame)
    if not frame then return end
    for i = 1, #heldStock do
        if heldStock[i].frame == frame then return end
    end
    heldStock[#heldStock + 1] = {
        frame = frame,
        alpha = StockAlpha(frame),
        mouseFrame = mouseFrame,
        mouse = StockMouse(mouseFrame),
    }
    if type(frame.SetAlpha) == "function" then
        pcall(frame.SetAlpha, frame, 0)
    end
    if mouseFrame and type(mouseFrame.EnableMouse) == "function" then
        pcall(mouseFrame.EnableMouse, mouseFrame, false)
    end
end

local function RestoreHeldStock()
    for i = 1, #heldStock do
        local item = heldStock[i]
        if item.frame and item.alpha and type(item.frame.SetAlpha) == "function" then
            pcall(item.frame.SetAlpha, item.frame, item.alpha)
        end
        if item.mouseFrame and item.mouse ~= nil
            and type(item.mouseFrame.EnableMouse) == "function" then
            pcall(item.mouseFrame.EnableMouse, item.mouseFrame, item.mouse)
        end
    end
    heldStock = {}
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
                    local isCallboard = (wantId > 0 and qid == wantId)
                        or (wantTitle ~= "" and NormalizeTitle(logTitle) == wantTitle)
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

local function PublishStock(summary)
    if not ReplacementCovered(summary) then
        RestoreHeldStock()
        return
    end
    local otf = ObjectiveTrackerRoot()
    if otf then HoldFrame(otf, otf) end
    local bag = ObjectiveBagFrame()
    if bag and bag ~= otf then HoldFrame(bag, bag) end
    local okOnly, onlyCallboard = pcall(TrackerOnlyHasCallboard, summary)
    if not okOnly then onlyCallboard = false end
    local tracker = TrackerFrame()
    if onlyCallboard and tracker then
        local collapse = type(tracker.collapse) == "table" and tracker.collapse or nil
        HoldFrame(tracker, collapse)
    end
    local wf = _G.WatchFrame
    if onlyCallboard and wf and wf ~= tracker and wf ~= otf then
        HoldFrame(wf, nil)
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
            for k, canonical in pairs(DIFFICULTY_LABELS) do
                if NormalizeTitle(stripped):sub(1, #k) == k then
                    label = canonical
                    if rightRaw == "" then
                        rightRaw = stripped:sub(#k + 1)
                    end
                    break
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
    local playerLevel = (type(UnitLevel) == "function" and tonumber(UnitLevel("player"))) or 80
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
        if copper <= 0 and xp > 0 and playerLevel >= 80 then
            copper = math.floor(xp * 6 / 10)
        end
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
--   3. EbonholdQuestTracker when ObjectiveTrackerFrame is active
local function ResolveObjective()
    local _, trackerTexts = CollectTrackerTexts()
    local trackerObj, trackerLines = ParseTrackerQuest(trackerTexts)

    local active = ReadActiveObjective()
    if type(active) == "table" and QuestTitle(active) then
        local snap = Remember(active)
        if snap then
            local useLines = nil
            if trackerObj and NormalizeTitle(snap.title) == NormalizeTitle(trackerObj.title) then
                useLines = trackerLines
            end
            return snap, useLines
        end
    end

    local list = ReadCurrentObjectives()
    if type(list) == "table" then
        for i = 1, #list do
            local snap = SnapshotObjective(list[i])
            if snap then
                if trackerObj and NormalizeTitle(snap.title) == NormalizeTitle(trackerObj.title) then
                    Remember(list[i])
                    return snap, trackerLines
                end
                if QuestLogMatch(snap) then
                    Remember(list[i])
                    local useLines = nil
                    if trackerObj and NormalizeTitle(snap.title) == NormalizeTitle(trackerObj.title) then
                        useLines = trackerLines
                    end
                    return snap, useLines
                end
            end
        end
    end

    if trackerObj then
        if remembered and NormalizeTitle(remembered.title) == NormalizeTitle(trackerObj.title) then
            return remembered, trackerLines
        end
        local root = ObjectiveTrackerRoot()
        local bagShown = root and type(root.IsShown) == "function" and root:IsShown()
        if bagShown then
            return trackerObj, trackerLines
        end
    end

    if remembered and QuestLogMatch(remembered) then
        return remembered, nil
    end

    return nil, nil
end

local function BuildSummary()
    local ok, summary = pcall(function()
        local objective, trackerLines = ResolveObjective()
        local title = QuestTitle(objective)
        if not title then
            return { observed = false }
        end
        local logMatch = QuestLogMatch(objective)
        if logMatch and NormalizeTitle(logMatch.title or "") ~= NormalizeTitle(title) then
            logMatch = nil
        end
        local lines = trackerLines
        if (not lines or #lines == 0) and logMatch
            and NormalizeTitle(logMatch.title or "") == NormalizeTitle(title) then
            lines = QuestLogLinesForIndex(logMatch.index, logMatch.isComplete)
        end
        local blurb = ObjectiveBlurb(objective)
        if (not lines or #lines == 0) and blurb then
            lines = { blurb }
        end
        local apiRewards = CollectRewardRows(objective)
        local normTitle = NormalizeTitle((logMatch and logMatch.title) or title)
        local rewards = (type(apiRewards) == "table" and #apiRewards > 0) and apiRewards
            or (scrapedForTitle == normTitle and scrapedRewards)
            or {}
        return {
            observed = true,
            title = (logMatch and logMatch.title) or title,
            lines = lines or {},
            questId = (logMatch and logMatch.questId and logMatch.questId > 0 and logMatch.questId)
                or tonumber(objective.questId or objective.id) or 0,
            rewards = rewards,
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

local function TooltipSourceTitle()
    if not GameTooltip or type(GameTooltip.GetOwner) ~= "function" then
        return nil
    end
    local ok, owner = pcall(GameTooltip.GetOwner, GameTooltip)
    if not ok or type(owner) ~= "table" then return nil end
    local data = owner.objectiveData
    if type(data) ~= "table" and type(owner.GetParent) == "function" then
        local okParent, parent = pcall(owner.GetParent, owner)
        if okParent and type(parent) == "table" then
            data = parent.objectiveData
        end
    end
    return QuestTitle(data)
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
            scrapedRewards = nil
            scrapedForTitle = nil
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
            local sourceTitle = TooltipSourceTitle()
            if not rows or not sourceTitle then return end
            scrapedRewards = rows
            scrapedForTitle = NormalizeTitle(sourceTitle)
            if cachedSummary and cachedSummary.observed
                and NormalizeTitle(cachedSummary.title or "") == scrapedForTitle then
                refreshQueued = true
            end
        end)
    end
end

function M.GetSummary()
    if cachedSignature == "" then
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
    GameTooltip:AddLine("Rewards by Difficulty", 1, 0.82, 0)
    GameTooltip:AddLine("Completing the objective on higher difficulties grants better rewards.",
        0.85, 0.85, 0.85, true)
    GameTooltip:AddLine(" ")
    for i = 1, #rows do
        local row = rows[i]
        local right = {}
        local money = FormatCopper(row.copper)
        if money then
            right[#right + 1] = money
        elseif row.xp and row.xp > 0 then
            right[#right + 1] = tostring(math.floor(row.xp)) .. " XP"
        end
        local ash = FormatAsh(row.ash)
        if ash then right[#right + 1] = "|cffa380ff" .. ash .. " Ash|r" end
        local labelColor = row.color or (row.label == "Normal" and { 1, 1, 1 } or { 1, 0.35, 0.35 })
        GameTooltip:AddDoubleLine(
            row.label,
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
    GameTooltip:AddLine("Rewards by Difficulty", 1, 0.82, 0)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Reward details are not available for this objective yet.",
        0.7, 0.7, 0.7, true)
    GameTooltip:Show()
    AnchorRewardsTooltipLeft(owner)
end

function M.HideTooltip()
    if GameTooltip then GameTooltip:Hide() end
end

return M
