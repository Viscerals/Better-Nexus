-- Echo display text comes from the installed Ebonhold Russian dictionary.
-- Catalog identities, saved names and raw server formulas are never rewritten.
Nexus = Nexus or {}
local E = {}
Nexus.EchoText = E

local cache, cacheSize, translator = {}, 0, nil

local function Values(text)
    local values = {}
    local function Keep(value)
        values[value] = (values[value] or 0) + 1
        return " "
    end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        :gsub("|H.-|h", ""):gsub("|T.-|t", "")
    text = text:gsub("@[^@]*@", Keep):gsub("%${[^}]*}", Keep):gsub("%$[/;%w]+", Keep)
    for value in text:gmatch("%d+%.?%d*") do Keep(value) end
    return values
end

local function PreservesValues(original, translated)
    local before, after = Values(original), Values(translated)
    for value, count in pairs(before) do
        if (after[value] or 0) < count then return false end
    end
    return true
end

function E.Text(text)
    if type(text) ~= "string" or Nexus.Localization.ActiveLanguage() ~= "ruRU" then return text end
    local translate = _G.EbonholdRU_TranslateEchoText
    if type(translate) ~= "function" then return text end
    if translator ~= translate then
        translator, cache, cacheSize = translate, {}, 0
    end
    if cache[text] ~= nil then return cache[text] end
    -- Use the text dictionary, never the preview/scaling evaluator: @ppm...@,
    -- @base...+sp...+ap...@ and $spell fields stay exactly as the server sent them.
    local ok, translated = pcall(translate, text)
    if not ok or type(translated) ~= "string" or not PreservesValues(text, translated) then
        translated = text
    end
    if cacheSize >= 2048 then cache, cacheSize = {}, 0 end
    cache[text], cacheSize = translated, cacheSize + 1
    return translated
end

-- Lua 5.1's string.lower only folds ASCII. Include the Russian alphabet so
-- both English names and their Russian display names can be searched.
function E.Fold(text)
    text = tostring(text or ""):lower()
    text = text:gsub("\208([\144-\175])", function(letter)
        local code = letter:byte()
        if code < 160 then return "\208" .. string.char(code + 32) end
        return "\209" .. string.char(code - 32)
    end)
    return (text:gsub("\208\129", "\209\145"))
end

function E.Matches(name, search)
    if search == "" then return true end
    return E.Fold(name):find(search, 1, true) ~= nil
        or E.Fold(E.Text(name)):find(search, 1, true) ~= nil
end

-- Rebuild only the tooltip explicitly opened by a Nexus Echo row. Preserve
-- the native lines, colors and double columns; allow the longer text to wrap.
function E.Tooltip(tooltip)
    if Nexus.Localization.ActiveLanguage() ~= "ruRU" or not tooltip then return end
    local name = tooltip:GetName()
    if not name then return end
    local lines, changed = {}, false
    for index = 1, tooltip:NumLines() do
        local left, right = _G[name .. "TextLeft" .. index], _G[name .. "TextRight" .. index]
        if right and not right:IsShown() then right = nil end
        local originalLeft, originalRight = left and left:GetText(), right and right:GetText()
        local shownLeft, shownRight = E.Text(originalLeft), E.Text(originalRight)
        changed = changed or shownLeft ~= originalLeft or shownRight ~= originalRight
        local lr, lg, lb, rr, rg, rb = 1, 1, 1, 1, 1, 1
        if left then lr, lg, lb = left:GetTextColor() end
        if right then rr, rg, rb = right:GetTextColor() end
        lines[#lines + 1] = {shownLeft or "", shownRight, lr, lg, lb, rr, rg, rb}
    end
    if not changed then return end
    tooltip:ClearLines()
    for _, line in ipairs(lines) do
        if line[2] and line[2] ~= "" then
            tooltip:AddDoubleLine(line[1], line[2], line[3], line[4], line[5], line[6], line[7], line[8])
        else
            tooltip:AddLine(line[1], line[3], line[4], line[5], true)
        end
    end
end
