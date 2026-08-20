-- Nexus: ui/JournalTab.lua
-- An "Optimizer" tab inside ProjectEbonhold's Echo Journal, rendering
-- plain text sections supplied by an injected dataProvider callback.
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
local rowButtons, rowFrames = {}, {}
local associationPanel
local scanFrame, associationVisible = nil, false
local wishlistPicker, wishlistPickerRows = nil, {}
local HideWishlistPicker
local pendingOpenLoadoutsUntil = 0
local theirTabCount = 0
local stockTabs = {}
local linePool, linesUsed = {}, 0

local function SafeGetScript(frame, scriptName)
    if not frame or type(frame.GetScript) ~= "function" then return nil end
    if type(frame.HasScript) == "function" then
        local ok, has = pcall(frame.HasScript, frame, scriptName)
        if ok and not has then return nil end
    end
    local ok, fn = pcall(frame.GetScript, frame, scriptName)
    if ok and type(fn) == "function" then return fn end
    return nil
end

local ASSET = "Interface\\AddOns\\ProjectEbonhold\\assets\\"
local NOTE1 = "Targets the wishlist associated with the ACTIVE saved loadout."
local NOTE2 = "|cff8a8a8aSet associations on the game's My Builds screen; loadout activation remains server-controlled and level-1-only.|r"

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

local function DoRefresh()
    local data
    if type(provider) == "function" then
        local okP, res = pcall(provider)
        if okP and type(res) == "table" then data = res end
    end

    linesUsed = 0
    local width = math.floor((scroll and scroll:GetWidth()) or 0)
    if width < 100 then width = 292 end
    width = width - 12
    local cy = -6

    local function AddLine(text, font, indent)
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
    end

    AddLine(NOTE1, "GameFontNormalSmall")
    AddLine(NOTE2)
    cy = cy - 6

    local sections = data and data.sections
    if type(sections) ~= "table" or #sections == 0 then
        AddLine("|cff8a8a8ano data yet|r")
    else
        for i = 1, #sections do
            local sec = sections[i]
            if type(sec) == "table" then
                AddLine(tostring(sec.title or ""), "GameFontNormalSmall")
                local lines = sec.lines
                if type(lines) == "table" then
                    for j = 1, #lines do
                        AddLine(tostring(lines[j] or ""), nil, 8)
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

    for i = linesUsed + 1, #linePool do linePool[i]:Hide() end
    child:SetWidth(width + 12)
    child:SetHeight(-cy + 8)
end

function M.Refresh()
    if not (installed and panel and panel:IsShown()) then return end
    pcall(DoRefresh)
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

local function FindButtonByText(root, wanted)
    local match
    local function Walk(f, depth)
        if match or not f or depth > 10 then return end
        local objectType = f.GetObjectType and f:GetObjectType() or ""
        if objectType == "Button" then
            local txt = NormalizedText(f)
            for line in txt:gmatch("[^\n]+") do
                line = line:gsub("^%s+", ""):gsub("%s+$", "")
                if line == wanted then match = f; return end
            end
        end
        if f.GetChildren then
            local kids = { f:GetChildren() }
            for i = 1, #kids do Walk(kids[i], depth + 1) end
        end
    end
    Walk(root, 0)
    return match
end

local function IsLoadoutCard(frame)
    if not frame or not frame.GetWidth or not frame.GetHeight then return false end
    local w, h = tonumber(frame:GetWidth()) or 0, tonumber(frame:GetHeight()) or 0
    if w < 420 or w > 700 or h < 82 or h > 180 then return false end
    local txt = NormalizedText(frame)
    if txt:find("Empty slot %d+") then return true end
    if txt:find("Save Build", 1, true) then return true end
    -- A populated card normally has LOADOUT plus its echo icons / overflow menu.
    if txt:find("LOADOUT", 1, true) and (txt:find("...", 1, true) or h >= 95) then return true end
    return false
end

local function CollectCards(root)
    local found, seen = {}, {}

    local function AddCandidate(frame)
        local f = frame
        for _ = 1, 7 do
            if not f then break end
            if f.GetWidth and f.GetHeight then
                local w, h = tonumber(f:GetWidth()) or 0, tonumber(f:GetHeight()) or 0
                -- Stock loadout cards on this client are wide, shallow panels.
                -- Find the first ancestor with card-like dimensions instead of
                -- relying on the card parent itself exposing all child text.
                if w >= 430 and w <= 680 and h >= 80 and h <= 190 then
                    if not seen[f] then
                        seen[f] = true
                        found[#found + 1] = f
                    end
                    return
                end
            end
            f = f.GetParent and f:GetParent() or nil
        end
    end

    local function Walk(f, depth)
        if not f or depth > 14 then return end

        if f.GetRegions then
            local regs = { f:GetRegions() }
            for i = 1, #regs do
                local r = regs[i]
                if r and r.GetText then
                    local ok, text = pcall(r.GetText, r)
                    if ok and type(text) == "string" then
                        text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                        text = text:gsub("^%s+", ""):gsub("%s+$", "")
                        if text == "LOADOUT" or text:match("^Empty slot %d+$") then
                            AddCandidate(r.GetParent and r:GetParent() or f)
                        end
                    end
                end
            end
        end

        if f.GetObjectType and f:GetObjectType() == "Button" and f.GetText then
            local ok, text = pcall(f.GetText, f)
            if ok and type(text) == "string" then
                text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
                text = text:gsub("^%s+", ""):gsub("%s+$", "")
                if text == "LOADOUT" or text:match("^Empty slot %d+$") then
                    AddCandidate(f)
                end
            end
        end

        if f.GetChildren then
            local kids = { f:GetChildren() }
            for i = 1, #kids do Walk(kids[i], depth + 1) end
        end
    end

    Walk(root, 0)

    -- Fallback for alternate client revisions where card text is only
    -- discoverable through recursive frame text.
    if #found == 0 then
        local fallbackSeen = {}
        local function Fallback(f, depth)
            if not f or depth > 12 then return end
            if IsLoadoutCard(f) and not fallbackSeen[f] then
                fallbackSeen[f] = true
                found[#found + 1] = f
                return
            end
            if f.GetChildren then
                local kids = { f:GetChildren() }
                for i = 1, #kids do Fallback(kids[i], depth + 1) end
            end
        end
        Fallback(root, 0)
    end

    table.sort(found, function(a, b)
        local at, bt = (a.GetTop and a:GetTop()) or 0, (b.GetTop and b:GetTop()) or 0
        if at == bt then
            local al, bl = (a.GetLeft and a:GetLeft()) or 0, (b.GetLeft and b:GetLeft()) or 0
            return al < bl
        end
        return at > bt
    end)
    return found
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

local function ClickLoadoutsTab(journal)
    if IsLoadoutsVisible(journal) then return true end
    local tab = FindLoadoutsTab(journal)
    if not tab then return false end
    if tab.Click then
        local ok = pcall(tab.Click, tab)
        if ok then return true end
    end
    local click = SafeGetScript(tab, "OnClick")
    if type(click) == "function" then
        return pcall(click, tab, "LeftButton")
    end
    return false
end

local function FindButtonByText(root, wanted)
    local found
    local function Walk(frame, depth)
        if found or not frame or depth > 18 then return end
        if frame.GetText then
            local ok, text = pcall(frame.GetText, frame)
            if ok and type(text) == "string" and text:lower() == wanted:lower() then
                found = frame
                return
            end
        end
        if frame.GetChildren then
            local kids = { frame:GetChildren() }
            for i = 1, #kids do Walk(kids[i], depth + 1) end
        end
    end
    Walk(root, 0)
    return found
end

local function ClickFrame(frame)
    if not frame then return false end
    if frame.Click then
        local ok = pcall(frame.Click, frame)
        if ok then return true end
    end
    local click = SafeGetScript(frame, "OnClick")
    if type(click) == "function" then
        return pcall(click, frame, "LeftButton")
    end
    return false
end

local function OpenNexusWishlistEditor(journal)
    -- The stock New Wishlist button is not consistently addressable across
    -- Project Ebonhold UI revisions. Nexus owns a reliable editor, so use it
    -- directly and close the journal to avoid overlapping full-size panels.
    if associationPanel then associationPanel:Hide() end
    if journal and journal.Hide then pcall(journal.Hide, journal) end
    local editor = Nexus and Nexus.WishlistEditor
    if editor and type(editor.NewWishlist) == "function" then
        pcall(editor.NewWishlist)
    elseif editor and type(editor.Show) == "function" then
        pcall(editor.Show)
    else
        print("|cffff6060Nexus:|r Wishlist Editor is unavailable.")
    end
end

local function ShortName(name, maxLen)
    name = tostring(name or "")
    maxLen = tonumber(maxLen) or 28
    if #name <= maxLen then return name end
    return name:sub(1, maxLen - 3) .. "..."
end



local function PlainText(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    return text
end

local function IsDescendantOf(frame, ancestor)
    local cur = frame
    for _ = 1, 20 do
        if not cur then return false end
        if cur == ancestor then return true end
        cur = cur.GetParent and cur:GetParent() or nil
    end
    return false
end

local function FrameText(frame)
    if not frame then return "" end
    if frame.GetText then
        local ok, text = pcall(frame.GetText, frame)
        if ok and text and text ~= "" then return PlainText(text) end
    end
    if frame.GetRegions then
        local regions = { frame:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            if r and r.GetText then
                local ok, text = pcall(r.GetText, r)
                if ok and text and text ~= "" then return PlainText(text) end
            end
        end
    end
    return ""
end

local function FindVisibleWishlistMenuButton(wishlistName)
    wishlistName = PlainText(wishlistName)
    if wishlistName == "" then return nil end

    local headerY
    local candidates = {}
    local seen = {}

    local function CenterY(obj)
        if not obj or not obj.GetCenter then return nil end
        local ok, _, y = pcall(obj.GetCenter, obj)
        if ok then return y end
        return nil
    end

    local function AddCandidate(button, y, score)
        if not button or seen[button] then return end
        if IsDescendantOf(button, associationPanel) then return end
        if button.IsShown and not button:IsShown() then return end
        seen[button] = true
        candidates[#candidates + 1] = { frame = button, y = y or CenterY(button), score = score or 0 }
    end

    -- Blizzard-style dropdown entries are normally named DropDownListNButtonN.
    -- Prefer those concrete buttons over climbing from a FontString, which can
    -- accidentally resolve to the entire dropdown container.
    for list = 1, 4 do
        for index = 1, 64 do
            local button = _G["DropDownList" .. list .. "Button" .. index]
            if button and (not button.IsShown or button:IsShown()) then
                local text = FrameText(button)
                local y = CenterY(button)
                if text == "Wishlists" and y then
                    if not headerY or y > headerY then headerY = y end
                elseif text == wishlistName then
                    AddCandidate(button, y, 100)
                end
            end
        end
    end

    -- Custom server menus may not use Blizzard dropdown names. Scan visible
    -- BUTTON frames directly and require the button itself to own the label.
    local frame = EnumerateFrames and EnumerateFrames() or nil
    while frame do
        local shown = not frame.IsShown or frame:IsShown()
        if shown and not IsDescendantOf(frame, associationPanel) then
            local objectType = frame.GetObjectType and frame:GetObjectType() or ""
            local text = FrameText(frame)
            local y = CenterY(frame)
            if text == "Wishlists" and y then
                if not headerY or y > headerY then headerY = y end
            elseif objectType == "Button" and text == wishlistName then
                local name = frame.GetName and frame:GetName() or ""
                local score = 50
                if type(name) == "string" and string.find(name, "DropDown", 1, true) then score = score + 20 end
                if SafeGetScript(frame, "OnClick") then score = score + 10 end
                AddCandidate(frame, y, score)
            end
        end
        frame = EnumerateFrames and EnumerateFrames(frame) or nil
    end

    local best
    for i = 1, #candidates do
        local c = candidates[i]
        -- Wishlist entries are below the Wishlists header. Reject the
        -- same-named Saved Build above that header whenever the header exists.
        local belowWishlistHeader = not headerY or (c.y and c.y < headerY)
        if belowWishlistHeader then
            if not best
                or c.score > best.score
                or (c.score == best.score and c.y and best.y and c.y > best.y) then
                best = c
            end
        end
    end
    return best and best.frame or nil
end

local function ButtonBounds(frame)
    if not frame then return nil end
    local ok1, left = pcall(frame.GetLeft, frame)
    local ok2, right = pcall(frame.GetRight, frame)
    local ok3, bottom = pcall(frame.GetBottom, frame)
    local ok4, top = pcall(frame.GetTop, frame)
    if ok1 and ok2 and ok3 and ok4 and left and right and bottom and top then
        return left, right, bottom, top
    end
    return nil
end

local function IsLikelyEditControl(frame, row)
    if not frame or frame == row or IsDescendantOf(frame, associationPanel) then return false end
    if frame.IsShown and not frame:IsShown() then return false end
    local objectType = frame.GetObjectType and frame:GetObjectType() or ""
    if objectType ~= "Button" then return false end

    local rl, rr, rb, rt = ButtonBounds(row)
    local fl, fr, fb, ft = ButtonBounds(frame)
    if not (rl and fl) then return false end

    local rowY = (rb + rt) * 0.5
    local frameY = (fb + ft) * 0.5
    if math.abs(frameY - rowY) > 15 then return false end
    if fr < rl - 6 or fl > rr + 46 then return false end

    local w = frame.GetWidth and frame:GetWidth() or 0
    local h = frame.GetHeight and frame:GetHeight() or 0
    if w > 48 or h > 38 then return false end

    local text = string.lower(PlainText(FrameText(frame)))
    if text == "edit" or text == "design" or text == "modify" then return true end

    local name = frame.GetName and string.lower(tostring(frame:GetName() or "")) or ""
    if name:find("edit", 1, true) or name:find("design", 1, true) then return true end

    -- Icon-only controls beside a wishlist row are the server's row actions.
    -- Require an actual click handler so decorative textures are ignored.
    local click = SafeGetScript(frame, "OnClick")
    return type(click) == "function"
end

local function FindWishlistEditControl(row)
    if not row then return nil end

    -- First prefer explicit children/siblings named Edit or Design.
    local explicit, fallback
    local frame = EnumerateFrames and EnumerateFrames() or nil
    while frame do
        if IsLikelyEditControl(frame, row) then
            local text = string.lower(PlainText(FrameText(frame)))
            local name = frame.GetName and string.lower(tostring(frame:GetName() or "")) or ""
            if text == "edit" or text == "design"
                or name:find("edit", 1, true) or name:find("design", 1, true) then
                explicit = frame
                break
            end
            if not fallback then fallback = frame end
        end
        frame = EnumerateFrames and EnumerateFrames(frame) or nil
    end
    return explicit or fallback
end

local function ProbeAdd(event, detail)
    if Nexus and type(Nexus.UIProbeAdd) == "function" then
        Nexus.UIProbeAdd(event, detail)
    end
end

local function ScriptFlags(frame)
    local names = { "OnClick", "OnMouseUp", "OnMouseDown", "OnEnter", "OnLeave", "OnShow", "OnHide", "OnUpdate" }
    local out = {}
    for i = 1, #names do
        local n = names[i]
        local fn = SafeGetScript(frame, n)
        if type(fn) == "function" then out[#out + 1] = n end
    end
    return table.concat(out, ",")
end

local function RegionSummary(frame)
    local out = {}
    if not frame or not frame.GetRegions then return "" end
    local regions = { frame:GetRegions() }
    for i = 1, #regions do
        local r = regions[i]
        local typ = r and r.GetObjectType and r:GetObjectType() or "?"
        local text = r and r.GetText and PlainText(r:GetText() or "") or ""
        local tex = r and r.GetTexture and tostring(r:GetTexture() or "") or ""
        out[#out + 1] = typ .. "{text=" .. text .. ",tex=" .. tex .. "}"
    end
    return table.concat(out, ";")
end

local function FrameDebugSummary(frame, tag)
    if not frame then return tostring(tag) .. "=nil" end
    local name = frame.GetName and tostring(frame:GetName() or "") or ""
    local typ = frame.GetObjectType and tostring(frame:GetObjectType() or "") or ""
    local parent = frame.GetParent and frame:GetParent() or nil
    local pname = parent and parent.GetName and tostring(parent:GetName() or "") or tostring(parent or "")
    local left, right, bottom, top = ButtonBounds(frame)
    local text = PlainText(FrameText(frame))
    return table.concat({
        tostring(tag or "frame"),
        "name=" .. name,
        "type=" .. typ,
        "parent=" .. pname,
        "text=" .. tostring(text or ""),
        "shown=" .. tostring(frame.IsShown and frame:IsShown()),
        "enabled=" .. tostring(frame.IsEnabled and frame:IsEnabled()),
        "bounds=" .. table.concat({ tostring(left), tostring(right), tostring(bottom), tostring(top) }, ","),
        "scripts=" .. ScriptFlags(frame),
        "regions=" .. RegionSummary(frame),
    }, "|")
end

local function CaptureWishlistDesignEnvironment(row, phase)
    ProbeAdd("DESIGN_DEBUG_ROW", FrameDebugSummary(row, phase))

    if row and row.GetChildren then
        local children = { row:GetChildren() }
        for i = 1, #children do
            ProbeAdd("DESIGN_DEBUG_CHILD", FrameDebugSummary(children[i], phase .. ".child" .. i))
        end
    end

    local rl, rr, rb, rt = ButtonBounds(row)
    local frame = EnumerateFrames and EnumerateFrames() or nil
    local count = 0
    while frame and count < 80 do
        local fl, fr, fb, ft = ButtonBounds(frame)
        if rl and fl and frame ~= row and not IsDescendantOf(frame, associationPanel) then
            local cy = (fb + ft) * 0.5
            local ry = (rb + rt) * 0.5
            if math.abs(cy - ry) <= 24 and fr >= rl - 20 and fl <= rr + 100 then
                count = count + 1
                ProbeAdd("DESIGN_DEBUG_NEARBY", FrameDebugSummary(frame, phase .. ".near" .. count))
            end
        end
        frame = EnumerateFrames and EnumerateFrames(frame) or nil
    end

    local globals = {}
    for key, value in pairs(_G) do
        if type(key) == "string" then
            local low = string.lower(key)
            if (low:find("wishlist", 1, true) or low:find("echo", 1, true))
                and (low:find("edit", 1, true) or low:find("design", 1, true) or low:find("loadout", 1, true)) then
                local vt = type(value)
                if vt == "function" or vt == "table" then
                    globals[#globals + 1] = key .. "=" .. vt
                end
            end
        end
    end
    table.sort(globals)
    ProbeAdd("DESIGN_DEBUG_GLOBALS", table.concat(globals, ";"))
end

local function TooltipLinesFor(frame)
    if not frame then return "" end
    local enter = SafeGetScript(frame, "OnEnter")
    if type(enter) ~= "function" then return "" end
    local oldOwner = GameTooltip and GameTooltip:GetOwner() or nil
    pcall(enter, frame)
    local lines = {}
    for i = 1, 12 do
        local fs = _G["GameTooltipTextLeft" .. i]
        local text = fs and fs.GetText and fs:GetText() or nil
        if text and text ~= "" then lines[#lines + 1] = PlainText(text) end
    end
    local leave = SafeGetScript(frame, "OnLeave")
    if type(leave) == "function" then pcall(leave, frame) end
    if GameTooltip and GameTooltip:GetOwner() == frame then GameTooltip:Hide() end
    return table.concat(lines, " | ")
end

local designActionBusy = false

local function VisibleFrameText(frame)
    if not frame or (frame.IsShown and not frame:IsShown()) then return "" end
    local text = PlainText(FrameText(frame))
    if text ~= "" then return text end
    if frame.GetRegions then
        local regions = { frame:GetRegions() }
        for i = 1, #regions do
            local r = regions[i]
            if r and r.GetText then
                local ok, value = pcall(r.GetText, r)
                value = ok and PlainText(value) or ""
                if value ~= "" then return value end
            end
        end
    end
    return ""
end

local function FindMoreActionsControl(row)
    if not row then return nil end
    local rl, rr, rb, rt = ButtonBounds(row)
    if not rl then return nil end
    local ry = (rb + rt) * 0.5
    local best
    local frame = EnumerateFrames and EnumerateFrames() or nil
    while frame do
        if frame ~= row and not IsDescendantOf(frame, associationPanel)
            and (not frame.IsShown or frame:IsShown())
            and frame.GetObjectType and frame:GetObjectType() == "Button" then
            local fl, fr, fb, ft = ButtonBounds(frame)
            if fl and math.abs(((fb + ft) * 0.5) - ry) <= 14
                and fl >= rr - 20 and fl <= rr + 80 then
                local w = frame.GetWidth and frame:GetWidth() or 0
                local h = frame.GetHeight and frame:GetHeight() or 0
                if w <= 54 and h <= 42 and SafeGetScript(frame, "OnClick") then
                    local text = string.lower(VisibleFrameText(frame))
                    local name = string.lower(tostring(frame.GetName and frame:GetName() or ""))
                    local score = 10
                    if text == "..." or text == "..." then score = score + 100 end
                    if name:find("more", 1, true) or name:find("action", 1, true)
                        or name:find("option", 1, true) or name:find("menu", 1, true) then
                        score = score + 60
                    end
                    if not best or score > best.score then best = { frame = frame, score = score } end
                end
            end
        end
        frame = EnumerateFrames and EnumerateFrames(frame) or nil
    end
    return best and best.frame or nil
end

local function FindVisibleEditMenuItem()
    local best
    local function scoreText(text)
        text = string.lower(PlainText(text))
        if text == "edit wishlist" then return 300 end
        if text == "edit" then return 280 end
        if text == "design wishlist" then return 260 end
        if text == "design" or text == "modify" then return 240 end
        if text:find("edit", 1, true) and text:find("wishlist", 1, true) then return 220 end
        return nil
    end
    local function consider(frame, bonus)
        if not frame or IsDescendantOf(frame, associationPanel) then return end
        if frame.IsShown and not frame:IsShown() then return end
        local points = scoreText(VisibleFrameText(frame))
        if not points then return end
        local owner = frame
        for _ = 1, 5 do
            if not owner then return end
            if owner.GetObjectType and owner:GetObjectType() == "Button" and SafeGetScript(owner, "OnClick") then break end
            owner = owner.GetParent and owner:GetParent() or nil
        end
        if not owner or not SafeGetScript(owner, "OnClick") then return end
        local score = points + (bonus or 0)
        if not best or score > best.score then best = { frame = owner, score = score } end
    end
    -- The server uses dropdown-style buttons for the secondary actions menu.
    for list = 1, 8 do
        for index = 1, 96 do consider(_G["DropDownList" .. list .. "Button" .. index], 100) end
    end
    -- One bounded pass for custom menu buttons. Never call their OnEnter scripts.
    local frame = EnumerateFrames and EnumerateFrames() or nil
    local seen = 0
    while frame and seen < 2500 do
        if frame.GetObjectType and frame:GetObjectType() == "Button" then consider(frame, 0) end
        frame = EnumerateFrames and EnumerateFrames(frame) or nil
        seen = seen + 1
    end
    return best and best.frame or nil
end

local function FinishDesignAction(ok, reason)
    designActionBusy = false
    if ok then
        print("|cff66ff66Nexus:|r Opened wishlist editor.")
    else
        print("|cffff6060Nexus:|r Could not open wishlist editor (" .. tostring(reason or "unknown") .. ").")
    end
end

local function OpenWishlistRowDesigner(row)
    if not row then FinishDesignAction(false, "missing_row") return end

    local enter = SafeGetScript(row, "OnEnter")
    if type(enter) == "function" then pcall(enter, row) end

    -- One bounded lookup after hover. No fast OnUpdate scanner and no global tooltip probing.
    C_Timer.After(0.12, function()
        local more = FindMoreActionsControl(row)
        if not more then FinishDesignAction(false, "more_actions_missing") return end
        ProbeAdd("DESIGN_MORE_ACTIONS", FrameDebugSummary(more, "found"))
        if not ClickFrame(more) then FinishDesignAction(false, "more_actions_click_failed") return end

        C_Timer.After(0.15, function()
            local edit = FindVisibleEditMenuItem()
            if not edit then
                ProbeAdd("DESIGN_EDIT_MISSING", "More actions opened, but no visible Edit menu item was found")
                FinishDesignAction(false, "edit_item_missing")
                return
            end
            ProbeAdd("DESIGN_EDIT_ITEM", FrameDebugSummary(edit, "found"))
            local ok = ClickFrame(edit)
            FinishDesignAction(ok, ok and "opened" or "edit_click_failed")
        end)
    end)
end

local function OpenServerWishlistDesigner(linked)
    if designActionBusy then
        print("|cffffcc66Nexus:|r Wishlist editor action is already running.")
        return
    end
    if not linked or not linked.name or linked.name == "" then
        print("|cffff6060Nexus:|r Associate a wishlist first.")
        return
    end
    designActionBusy = true
    local dd = _G["ProjectEbonholdEchoJournalLoadoutDDButton"]
        or _G["ProjectEbonholdEchoJournalLoadoutDD"]
    if not ClickFrame(dd) then FinishDesignAction(false, "loadout_menu_failed") return end

    -- Give the server menu time to populate, then perform exactly one row lookup.
    C_Timer.After(0.18, function()
        local button = FindVisibleWishlistMenuButton(linked.name)
        if not button then FinishDesignAction(false, "wishlist_row_missing") return end
        OpenWishlistRowDesigner(button)
    end)

    -- Hard safety release in case the server UI disappears during the action.
    C_Timer.After(2.5, function()
        if designActionBusy then FinishDesignAction(false, "timed_out") end
    end)
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
            GameTooltip:AddLine("Design associated wishlist", 0.35, 0.8, 1)
            GameTooltip:AddLine("Open this associated wishlist in the Nexus editor.", 0.82, 0.82, 0.82, true)
            GameTooltip:Show()
        end)
        associationPanel.design:SetScript("OnLeave", function() GameTooltip:Hide() end)
        associationPanel.selector:SetScript("OnEnter", function(self)
            if self.SetBackdropBorderColor then self:SetBackdropBorderColor(0.42, 0.72, 0.95, 1) end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:AddLine("Automation Wishlist", 0.35, 0.8, 1)
            GameTooltip:AddLine("Assigns a wishlist reference to the Saved Build currently selected in the server dropdown.", 0.82, 0.82, 0.82, true)
            GameTooltip:Show()
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
    for _, row in pairs(rowButtons) do row:Hide() end
end

HideWishlistPicker = function()
    if wishlistPicker then wishlistPicker:Hide() end
end

local function ShowWishlistPicker(anchor, wishes, linked, active, loadoutName, A)
    if not wishlistPicker then
        wishlistPicker = CreateFrame("Frame", "NexusWishlistOnlyPicker", UIParent)
        wishlistPicker:SetFrameStrata("TOOLTIP")
        wishlistPicker:SetFrameLevel(500)
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
    for i=1,#wishlistPickerRows do wishlistPickerRows[i]:Hide() end
    if wishlistPicker.emptyRow then wishlistPicker.emptyRow:Hide() end
    if wishlistPicker.clearRow then wishlistPicker.clearRow:Hide() end
    wishlistPicker:ClearAllPoints()
    wishlistPicker:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    local width, rowH = 245, 24
    wishlistPicker:SetWidth(width)
    local count = math.max(1, #wishes)
    wishlistPicker:SetHeight(26 + count * rowH + (linked and 24 or 0) + 6)

    if #wishes == 0 then
        local row = wishlistPicker.emptyRow
        if not row then
            row = wishlistPicker:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            wishlistPicker.emptyRow = row
        end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 10, -28); row:SetText("No server wishlists found"); row:Show()
    else
        for i=1,#wishes do
            local c = wishes[i]
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
            local selected = linked and linked.key and cKey and linked.key == cKey
            local evidenceSuffix = c.lockEvidenceStatus == "unavailable"
                and "  |cffff9040(awaiting lock evidence)|r" or ""
            row.nameButton.text:SetText((selected and "|cff55ff55[Selected] |r" or "")
                .. ((cName ~= "" and cName) or "Unnamed Wishlist")
                .. evidenceSuffix)
            local cEchoes = c.echoes
            local cSnapshot = {
                slot=cSlot, name=cName, key=cKey,
                lockEvidenceVersion=c.lockEvidenceVersion,
                lockEvidenceStatus=c.lockEvidenceStatus,
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
                local ok, err
                if tonumber(active) and tonumber(active) > 0 then
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
                        loadoutName = loadoutName,
                    }, (tonumber(active) and tonumber(active) > 0) and active or nil)
                else
                    print("|cffff6060Nexus:|r Nexus Wishlist Editor is unavailable.")
                end
            end
            row.nameButton:SetScript("OnClick", AssociateWishlistOnly)
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
            row.text:SetPoint("LEFT",6,0); row.text:SetText("Clear association")
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            wishlistPicker.clearRow = row
        end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT",6,-24-#wishes*rowH); row:SetPoint("RIGHT",-6,0)
        row:SetScript("OnClick", function()
            if tonumber(active) and tonumber(active) > 0 then A.ClearLoadoutWishlist(active)
            elseif A.ClearFirstRunWishlist then A.ClearFirstRunWishlist() end
            HideWishlistPicker(); M.RefreshAssociations()
        end)
        row:Show()
    end
    wishlistPicker:Show()
end

local function RefreshAssociationRows()
    local journal = _G["ProjectEbonholdEchoJournal"]
    if not journal or not journal.IsShown or not journal:IsShown() then HideRowButtons(); return end
    if installed and panel and panel:IsShown() then HideRowButtons(); return end

    local A = Nexus and Nexus.GameAdapter
    local slots = A and A.Slots and A.Slots()
    if not slots then HideRowButtons(); return end

    local active = tonumber(slots.activeSlot) or 0
    local maxSlots = tonumber(slots.maxSlots) or 5
    local activeRow = slots.bySlot and slots.bySlot[active]
    local populated = activeRow and type(activeRow.echoes) == "table" and #activeRow.echoes > 0
    local firstRun = active < 1 or active > maxSlots or not populated

    local host = EnsureAssociationPanel(journal)
    local wishes = A.GetWishlistCandidates and A.GetWishlistCandidates() or {}
    local linked = firstRun and (A.GetFirstRunWishlist and A.GetFirstRunWishlist())
        or (A.GetLoadoutWishlist and A.GetLoadoutWishlist(active))
    local loadoutName = firstRun and "First Run" or tostring(activeRow.name or "")
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
            editor.OpenForWishlist({
                slot = linked.slot,
                name = linked.name,
                key = linked.key,
                echoes = linked.echoes,
                loadoutName = loadoutName,
            }, firstRun and nil or active)
        else
            print("|cffff6060Nexus:|r Nexus Wishlist Editor is unavailable.")
        end
    end)

    host.selector:SetScript("OnClick", function(self)
        if wishlistPicker and wishlistPicker:IsShown() then HideWishlistPicker(); return end
        ShowWishlistPicker(self, wishes, linked, active, loadoutName, A)
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

local function DeselectOurTab(showAssociation)
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
    local lastTab = _G["ProjectEbonholdEchoJournalTab" .. n]

    ourTab = CreateFrame("Button", "NexusJournalTab",
        journal, "CharacterFrameTabButtonTemplate")
    ourTab:SetText("Optimizer")
    -- Same row as their tabs, standard -16 overlap after the last one.
    ourTab:ClearAllPoints()
    ourTab:SetPoint("TOPLEFT", lastTab, "TOPRIGHT", -16, 0)
    ourTab:SetFrameLevel(lastTab:GetFrameLevel())
    -- A fresh template tab shows BOTH texture sets until its state is
    -- set; without this it renders as a mangled sliver.
    pcall(function() PanelTemplates_TabResize(ourTab, 0) end)
    pcall(function() PanelTemplates_DeselectTab(ourTab) end)
    ourTab:Show()
    ourTab:SetScript("OnClick", function() pcall(SelectOurTab) end)

    -- Their tab numbering differs between client revisions. Never assume
    -- Tab1 is Loadouts: inspect the clicked tab after the stock handler runs.
    stockTabs = {}
    for i = 1, theirTabCount do
        local t = _G["ProjectEbonholdEchoJournalTab" .. i]
        if t then
            stockTabs[#stockTabs + 1] = t
            if t.HookScript then
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
    if journal.HookScript then
        journal:HookScript("OnShow", function()
            pcall(function()
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
    panel = CreateFrame("Frame", "NexusJournalPanel", journal)
    panel:SetPoint("TOPLEFT", journal, "TOPLEFT", 10, -32)
    panel:SetPoint("BOTTOMRIGHT", journal, "BOTTOMRIGHT", -8, 8)
    panel:SetFrameLevel(journal:GetFrameLevel() + 10)
    panel:EnableMouse(true)
    local bg = panel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(ASSET .. "UI-Background-Rock")

    scroll = CreateFrame("ScrollFrame", "NexusJournalScroll",
        panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, -6)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -26, 4)
    child = CreateFrame("Frame", nil, scroll)
    child:SetSize(292, 100)
    scroll:SetScrollChild(child)

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
        if installed then DeselectOurTab(true) end
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

function M.OpenBuilds()
    EnsureAssociationScanner()

    local opened = ClickCurrentEchoesMicroButton()
    if not opened then
        print("|cffff6060Nexus:|r Could not find the server Character Progression button. Open Character Progression → Echoes manually.")
        return
    end

    -- Let the server finish constructing/selecting its new Echoes page before
    -- attaching Nexus beside the live loadout dropdown.
    local function finish()
        pcall(function()
            if not installed and pcall(Install) then installed = true end
            if installed then DeselectOurTab(false) end
            RefreshAssociationRows()
        end)
    end
    finish()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.10, finish)
        C_Timer.After(0.35, finish)
    end
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
