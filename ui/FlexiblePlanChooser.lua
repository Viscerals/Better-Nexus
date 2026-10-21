-- Session-only ordinary planning. Membership never supplies a choice.
Nexus = Nexus or {}
local Factory = {}
Nexus.FlexiblePlanChooser = Factory

local ROWS, HEIGHT = 12, 32
local function Plain(value) return type(value) == "table" and getmetatable(value) == nil end
local function Display(value)
    local identity = Nexus.Identity
    return identity and identity.DisplaySafeText
        and identity.DisplaySafeText(value or "", 256, true) or ""
end
local REASONS = {
    INVALID_SELECTION="Choose exact Echo counts before opening a draft.",
    INVALID_ALTERNATIVES="The pool can hold at most 256 distinct Echo alternatives.",
    STACK_LIMIT="That count exceeds this Echo's maximum stack.",
    ORDINARY_LIMIT="Choose at most 79 ordinary Echo copies.",
    CATALOG_UNAVAILABLE="The Echo catalog is not available yet. Reopen when it has loaded.",
    INVALID_CATALOG="This Echo's required catalog details are unavailable. Review the pool when they are available.",
    UNSUPPORTED_ROLE="This pool accepts ordinary Echo alternatives only.",
    CATALOG_CHANGED="A chosen Echo's catalog details changed. Reset the pool and choose again.",
    EDITOR_CHANGED="The editor changed. Open the draft again to review its replacement.",
    PLAN_CHANGED="The pool or choice changed. Open the draft again to review your choice.",
}
function Factory.Reason(code)
    return REASONS[code] or "This choice cannot be opened. Review the pool and exact counts."
end

function Factory.New(options)
    local M = {}
    local ids, captured, chosen = {}, {rows={}}, {}
    local pool, frame, status, budget, search, catalogArea, poolArea
    local catalogRows, poolRows = {}, {}
    local catalogOffset, poolOffset, revision = 0, 0, 0
    local note = ""

    local function Selection()
        local out = {}
        for _, id in ipairs(ids) do
            if chosen[id] then out[#out+1] = {spellId=id, stacks=chosen[id]} end
        end
        return out
    end
    local function Say(code)
        note = Factory.Reason(code)
        if status then status:SetText(note) end
        return false, code
    end
    local function Refresh()
        if not frame then return end
        local catalog = options.catalog()
        local available = Plain(catalog) and Plain(catalog.rows)
        local matches = {}
        if available then
            local query = string.lower(search:GetText() or "")
            for id, row in pairs(catalog.rows) do
                if type(id) == "number" and id > 0 and id == math.floor(id) and Plain(row)
                    and (query == "" or tostring(id):find(query,1,true)
                        or string.lower(type(row.name)=="string" and row.name or ""):find(query,1,true)) then
                    matches[#matches+1] = id
                end
            end
            table.sort(matches)
        end
        local left = Nexus.VirtualList.Window(#matches, HEIGHT, ROWS*HEIGHT, catalogOffset, 0)
        local right = Nexus.VirtualList.Window(#ids, HEIGHT, ROWS*HEIGHT, poolOffset, 0)
        catalogOffset, poolOffset = left.offset, right.offset
        for i=1,ROWS do
            local row, id = catalogRows[i], matches[left.first+i-1]
            row.spellId = id
            if id then
                local value = catalog.rows[id]
                row.label:SetText("#"..id.."  Q"..tostring(value.quality).."  "..Display(value.name))
                row.action:SetText(captured.rows[id] and "Added" or "Add")
                if captured.rows[id] then row.action:Disable() else row.action:Enable() end
                row:Show()
            else row:Hide() end
            row, id = poolRows[i], ids[right.first+i-1]
            row.spellId = id
            if id then
                local value = captured.rows[id]
                row.label:SetText("#"..id.."  Q"..value.quality.." / max "..value.maxStack.."  "..Display(value.name))
                row.count:SetText(chosen[id] and tostring(chosen[id]) or "0")
                row:Show()
            else row:Hide() end
        end
        local total = 0
        for _, count in pairs(chosen) do total = total + count end
        budget:SetText(#ids.." / 256 alternatives     Chosen: "..total.." / 79 ordinary copies")
        status:SetText(available and note or Factory.Reason("CATALOG_UNAVAILABLE"))
    end
    local function Add(id)
        if captured.rows[id] then return Say("INVALID_ALTERNATIVES") end
        local nextIds = {}
        for i,value in ipairs(ids) do nextIds[i]=value end
        nextIds[#nextIds+1]=id
        local catalog = options.catalog()
        if not Plain(catalog) or not Plain(catalog.rows) then return Say("CATALOG_UNAVAILABLE") end
        local nextCatalog = {rows={}}
        for key,value in pairs(captured.rows) do nextCatalog.rows[key]=value end
        nextCatalog.rows[id]=catalog.rows[id]
        local nextPool, why = Nexus.FlexiblePlanModel.New({alternativeSpellIds=nextIds,catalog=nextCatalog})
        if not nextPool then return Say(why) end
        local detached = {rows={}}
        for _,row in ipairs(nextPool.Alternatives()) do detached.rows[row.spellId]=row end
        ids, captured, pool = nextIds, detached, nextPool
        revision, note = revision+1, ""
        Refresh()
        return true
    end
    local function SetCount(id, text)
        local count = tonumber(text)
        if not count or count ~= math.floor(count) or count < 0 or count > 79 then
            return Say("INVALID_SELECTION")
        end
        local selection = {}
        for _, member in ipairs(ids) do
            local copies = member == id and count or chosen[member]
            if copies and copies > 0 then selection[#selection+1]={spellId=member,stacks=copies} end
        end
        if #selection > 0 then
            local result, why = pool.Choose(selection)
            if not result then return Say(why) end
        end
        chosen[id] = count > 0 and count or nil
        revision, note = revision+1, ""
        Refresh()
        return true
    end
    local function Remove(id)
        local nextIds = {}
        for _,member in ipairs(ids) do if member ~= id then nextIds[#nextIds+1]=member end end
        ids, chosen[id], captured.rows[id] = nextIds, nil, nil
        pool = #ids>0 and Nexus.FlexiblePlanModel.New({alternativeSpellIds=ids,catalog=captured}) or nil
        revision, note = revision+1, ""
        Refresh()
    end
    local function Open()
        if not pool then return Say("INVALID_SELECTION") end
        local draft, why = pool.Choose(Selection())
        if not draft then return Say(why) end
        local capturedRevision = revision
        return options.openDraft(draft, pool.Alternatives(), function()
            return capturedRevision == revision
        end, function() frame:Hide() end, Say)
    end
    local function Button(parent, name, text, width, callback)
        local button=CreateFrame("Button",name,parent,"UIPanelButtonTemplate")
        button:SetSize(width,22);button:SetText(text);button:SetScript("OnClick",callback)
        return button
    end
    local function Label(parent, text, width, height, x, y)
        local label=parent:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        label:SetPoint("TOPLEFT",x,y);label:SetSize(width,height);label:SetJustifyH("LEFT");label:SetText(text)
        return label
    end
    local function EnsureFrame()
        if frame then return end
        frame=CreateFrame("Frame","NexusFlexiblePlanChooser",UIParent)
        frame:SetSize(1020,650);frame:SetPoint("CENTER");frame:SetFrameStrata("HIGH");frame:SetFrameLevel(60)
        frame:SetClampedToScreen(true);frame:EnableMouse(true)
        if type(UISpecialFrames)=="table" then table.insert(UISpecialFrames,"NexusFlexiblePlanChooser") end
        Label(frame,"Plan alternatives — session only",900,24,22,-16)
        Label(frame,"Add exact Echo IDs to your pool, then set each chosen count. 0 leaves an alternative unchosen.",970,20,22,-44)
        Label(frame,"Hide keeps this pool and choice until reload. Reset clears only this planning session.",970,20,22,-66)
        Label(frame,"Catalog",430,20,22,-94);Label(frame,"Your pool / exact counts",480,20,505,-94)
        search=CreateFrame("EditBox","NexusFlexiblePlanSearch",frame,"InputBoxTemplate")
        search:SetSize(430,22);search:SetPoint("TOPLEFT",22,-120);search:SetAutoFocus(false);search:SetMaxLetters(96)
        search:SetScript("OnTextChanged",function() catalogOffset=0;Refresh() end)
        search:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
        catalogArea=CreateFrame("Frame","NexusFlexiblePlanCatalog",frame)
        catalogArea:SetPoint("TOPLEFT",22,-152);catalogArea:SetSize(460,ROWS*HEIGHT)
        poolArea=CreateFrame("Frame","NexusFlexiblePlanPool",frame)
        poolArea:SetPoint("TOPLEFT",505,-152);poolArea:SetSize(495,ROWS*HEIGHT)
        catalogArea:EnableMouseWheel(true);poolArea:EnableMouseWheel(true)
        catalogArea:SetScript("OnMouseWheel",function(_,delta) catalogOffset=catalogOffset-delta*HEIGHT;Refresh() end)
        poolArea:SetScript("OnMouseWheel",function(_,delta) poolOffset=poolOffset-delta*HEIGHT;Refresh() end)
        for i=1,ROWS do
            local row=CreateFrame("Frame",nil,catalogArea)
            row:SetSize(460,HEIGHT);row:SetPoint("TOPLEFT",0,-(i-1)*HEIGHT)
            row.label=Label(row,"",375,30,0,0)
            local catalogRow = row
            row.action=Button(row,nil,"Add",62,function() return Add(catalogRow.spellId) end)
            row.action:SetPoint("TOPRIGHT",0,-3)
            catalogRows[i]=row
            row=CreateFrame("Frame",nil,poolArea)
            row:SetSize(495,HEIGHT);row:SetPoint("TOPLEFT",0,-(i-1)*HEIGHT)
            row.label=Label(row,"",280,30,0,0)
            row.count=CreateFrame("EditBox",nil,row,"InputBoxTemplate")
            row.count:SetSize(32,22);row.count:SetPoint("TOPLEFT",290,-3);row.count:SetAutoFocus(false);row.count:SetMaxLetters(3)
            row.count:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
            row.action=Button(row,nil,"Set",52,function() row.count:ClearFocus();return SetCount(row.spellId,row.count:GetText()) end)
            row.action:SetPoint("LEFT",row.count,"RIGHT",4,0)
            row.remove=Button(row,nil,"Remove",84,function() return Remove(row.spellId) end)
            row.remove:SetPoint("LEFT",row.action,"RIGHT",4,0)
            poolRows[i]=row
        end
        budget=Label(frame,"",970,20,22,-546)
        status=Label(frame,"",970,36,22,-570)
        local open=Button(frame,"NexusFlexiblePlanOpen","Open as new Wishlist draft",224,Open)
        open:SetPoint("BOTTOMRIGHT",-22,18)
        local reset=Button(frame,"NexusFlexiblePlanReset","Reset pool",100,function()
            ids,captured,chosen,pool={},{rows={}},{},nil
            catalogOffset,poolOffset,revision,note=0,0,revision+1,""
            Refresh()
        end)
        reset:SetPoint("RIGHT",open,"LEFT",-8,0)
        local hide=Button(frame,"NexusFlexiblePlanHide","Hide",70,function() frame:Hide() end)
        hide:SetPoint("TOPRIGHT",-20,-16)
        frame:SetScript("OnShow",function(self)
            if Nexus.LayoutMetrics then Nexus.LayoutMetrics.FitToScreen(self) end
        end)
        if Nexus.Theme then Nexus.Theme.StyleTree(frame) end
        frame:Hide()
    end
    function M.Show() EnsureFrame();Refresh();frame:Show() end
    function M.Hide() if frame then frame:Hide() end end
    return M
end
