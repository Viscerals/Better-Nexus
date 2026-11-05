-- #47: explicit player choice through the production-loaded pure model.
-- Synthetic catalog only; no private/native input, live I/O or game actions.
local H = dofile('tests/prototype/harness.lua')
H.Boot()
local checks = 0
local function check(value, message)
    assert(value, message)
    checks = checks + 1
end
local function sameRows(left, right)
    if #left ~= #right then return false end
    for i, row in ipairs(left) do
        local other = right[i]
        if row.spellId ~= other.spellId or row.quality ~= other.quality
            or row.stacks ~= other.stacks or row.locked ~= other.locked then
            return false
        end
    end
    return true
end

local catalog, ids = {rows={}}, {}
for i = 1, 257 do
    local id = 310000 + i
    ids[i] = id
    catalog.rows[id] = {spellId=id, name='Synthetic alternative '..i,
        quality=i % 4, maxStack=5, groupId=0}
end
local hundred, selection = {}, {}
for i = 1, 100 do hundred[i] = ids[i] end
for i = 1, 79 do selection[i] = {spellId=ids[101-i], stacks=1} end

-- Existing exact-draft control must succeed even before the new capability.
local exact = Nexus.WishlistModel.New()
local pending = {}
for _, row in ipairs(selection) do
    pending = exact.AddPending(pending, catalog.rows[row.spellId], {catalog=catalog})
end
local expected = exact.CanonicalEchoes(pending)
check(exact.PendingTotal(pending) == 79 and #expected == 79,
    'SETUP existing exact model constructs the explicit 79-row control')
print('CONTROL existing exact Wishlist 79 rows PASS')

local factory = Nexus.FlexiblePlanModel
if type(factory) ~= 'table' or type(factory.New) ~= 'function' then
    print('FEATURE_UNAVAILABLE explicit choice from >79 alternatives')
    error('EXPECT #47 player-choice capability is absent', 0)
end
local pool, why = factory.New({alternativeSpellIds=hundred, catalog=catalog})
check(pool ~= nil and why == nil, '100 ordinary alternatives are admitted')
local alternatives = pool.Alternatives()
check(#alternatives == 100, 'all 100 alternatives remain available; none chosen implicitly')
local draft = assert(pool.Choose(selection))
check(sameRows(draft.echoes, expected), 'player selects exact last79; no implicit first79 winner')
check(exact.PendingTotal(draft.pending) == 79, 'returned existing-model pending map contains79')
check(next(draft.pendingLock) == nil and next(draft.fulfilledTargets) == nil,
    'ordinary draft adds no locked or fulfilled ownership claims')

local function refused(value, code, expectedCode, label)
    check(value == nil and code == expectedCode, label..' ('..tostring(code)..')')
end
local lockedCatalog = {rows={[ids[1]]={spellId=ids[1], name='Synthetic lock',
    quality=1, maxStack=5, locked=true}}}
local rejected, reason = factory.New({alternativeSpellIds={ids[1]}, catalog=lockedCatalog})
refused(rejected, reason, 'UNSUPPORTED_ROLE', 'locked-tagged catalog input is not coerced to an ordinary alternative')

local function clone(value)
    if type(value) ~= 'table' then return value end
    local out = {}
    for key, field in pairs(value) do out[key] = clone(field) end
    return out
end
local function newRefusal(opts, code, label)
    local value, why = factory.New(opts)
    refused(value, why, code, label)
end
local function choiceRefusal(rows, code, label)
    local value, why = pool.Choose(rows)
    refused(value, why, code, label)
end

-- Strict bounded admission, with no inferred/defaulted copies or roles.
local many = {}
for i = 1, 256 do many[i] = ids[i] end
local maxPool = assert(factory.New({alternativeSpellIds=many, catalog=catalog}))
check(#maxPool.Alternatives() == 256, '256 alternatives accepted as the technical memory bound')
newRefusal({alternativeSpellIds=ids, catalog=catalog}, 'INVALID_ALTERNATIVES', '257 alternatives refuse')
newRefusal({}, 'INVALID_ALTERNATIVES', 'missing alternative collection refuses')
newRefusal({alternativeSpellIds={}, catalog=catalog}, 'INVALID_ALTERNATIVES', 'empty pool refuses')
newRefusal({alternativeSpellIds={[2]=ids[1]}, catalog=catalog}, 'INVALID_ALTERNATIVES', 'sparse pool refuses')
newRefusal({alternativeSpellIds={[1000000000]=ids[1]}, catalog=catalog}, 'INVALID_ALTERNATIVES', 'huge sparse index refuses')
newRefusal({alternativeSpellIds={ids[1],ids[1]}, catalog=catalog}, 'DUPLICATE_ALTERNATIVE', 'duplicate pool identity refuses')
for _, id in ipairs({0,-1,1.5,math.huge,'310001'}) do
    newRefusal({alternativeSpellIds={id}, catalog=catalog}, 'INVALID_ALTERNATIVE', 'invalid alternative ID refuses')
end
newRefusal({alternativeSpellIds={0/0}, catalog=catalog}, 'INVALID_ALTERNATIVE', 'NaN ID refuses')
newRefusal({alternativeSpellIds={999999}, catalog=catalog}, 'INVALID_CATALOG', 'missing catalog identity refuses')
newRefusal({alternativeSpellIds={ids[1]}, catalog={}}, 'INVALID_CATALOG', 'missing catalog rows refuse')
for _, field in ipairs({'spellId','quality','maxStack'}) do
    local bad = clone(catalog); bad.rows[ids[1]][field] = nil
    newRefusal({alternativeSpellIds={ids[1]}, catalog=bad}, 'INVALID_CATALOG', 'missing '..field..' refuses')
end
for _, value in ipairs({-1,256,1.5,math.huge,'1'}) do
    local bad = clone(catalog); bad.rows[ids[1]].quality = value
    newRefusal({alternativeSpellIds={ids[1]}, catalog=bad}, 'INVALID_CATALOG', 'invalid catalog quality refuses')
end
for _, field in ipairs({'locked','sourceRole','lockIntent'}) do
    local bad = clone(catalog); bad.rows[ids[1]][field] = field == 'sourceRole' and 'locked' or true
    newRefusal({alternativeSpellIds={ids[1]}, catalog=bad}, 'UNSUPPORTED_ROLE', 'catalog role '..field..' refuses')
end
local eighty = {}
for i = 1, 80 do eighty[i] = {spellId=ids[i],stacks=1} end
choiceRefusal(eighty, 'INVALID_SELECTION', '80-row selection refuses without trimming/reclassifying')
local overCopies = clone(selection); overCopies[1].stacks = 2
choiceRefusal(overCopies, 'ORDINARY_LIMIT', '80 explicit copies refuse')
choiceRefusal({}, 'INVALID_SELECTION', 'empty choice does not recall a previous selection')
choiceRefusal({[2]={spellId=ids[1],stacks=1}}, 'INVALID_SELECTION', 'sparse selection refuses')
choiceRefusal({{spellId=ids[101],stacks=1}}, 'NOT_IN_POOL', 'catalog member outside this pool refuses')
choiceRefusal({{spellId=ids[1],stacks=1},{spellId=ids[1],stacks=1}}, 'DUPLICATE_SELECTION', 'duplicate chosen identity refuses')
for _, value in ipairs({0,-1,1.5,math.huge,'1'}) do
    choiceRefusal({{spellId=ids[1],stacks=value}}, 'INVALID_SELECTION', 'invalid chosen count refuses')
end
choiceRefusal({{spellId=ids[1]}}, 'INVALID_SELECTION', 'omitted count is not implicitly one')
choiceRefusal({{spellId=ids[1],stacks=6}}, 'STACK_LIMIT', 'count above catalog bound refuses rather than clamps')
choiceRefusal({{spellId=ids[1],stacks=1,quality=0}}, 'INVALID_SELECTION', 'caller cannot replace captured catalog quality')
for _, field in ipairs({'locked','sourceRole','lockIntent'}) do
    local row = {spellId=ids[1],stacks=1}; row[field] = field == 'sourceRole' and 'locked' or true
    choiceRefusal({row}, 'UNSUPPORTED_ROLE', 'selection role '..field..' refuses')
end

-- Same family is not permission to substitute or merge exact quality IDs.
local tiers = {rows={
    [ids[1]]={spellId=ids[1],name='Synthetic tiers',groupId=900,quality=1,maxStack=5},
    [ids[2]]={spellId=ids[2],name='Synthetic tiers',groupId=900,quality=3,maxStack=5}}}
local tierPool = assert(factory.New({alternativeSpellIds={ids[1],ids[2]},catalog=tiers}))
local tierDraft = assert(tierPool.Choose({{spellId=ids[2],stacks=3},{spellId=ids[1],stacks=2}}))
check(sameRows(tierDraft.echoes,{{spellId=ids[1],quality=1,stacks=2},{spellId=ids[2],quality=3,stacks=3}}),
    'same-family exact IDs/quality quotas survive the existing model bridge')

-- Admission must not invoke caller metamethods, even on rejected keys/rows.
local metaCalls = 0
local function trap() metaCalls=metaCalls+1; error('caller metamethod invoked') end
local function tagged(value)
    return setmetatable(value,{__index=trap,__newindex=trap,__len=trap,__pairs=trap,__tostring=trap})
end
newRefusal(tagged({}), 'INVALID_OPTIONS', 'metatable options refuse')
newRefusal({alternativeSpellIds=tagged({ids[1]}),catalog=catalog}, 'INVALID_ALTERNATIVES', 'metatable alternative list refuses')
newRefusal({alternativeSpellIds={ids[1]},catalog=tagged({})}, 'INVALID_CATALOG', 'metatable catalog refuses')
newRefusal({alternativeSpellIds={ids[1]},catalog={rows=tagged({})}}, 'INVALID_CATALOG', 'metatable catalog rows refuse')
newRefusal({alternativeSpellIds={ids[1]},catalog={rows={[ids[1]]=tagged({})}}}, 'INVALID_CATALOG', 'metatable catalog row refuses')
choiceRefusal(tagged({}), 'INVALID_SELECTION', 'metatable selection refuses')
choiceRefusal({tagged({})}, 'INVALID_SELECTION', 'metatable selection row refuses')
local key = tagged({})
newRefusal({alternativeSpellIds={[key]=ids[1]},catalog=catalog}, 'INVALID_ALTERNATIVES', 'non-numeric key refuses without stringification')
check(metaCalls == 0, 'all caller metamethods remain uncalled')

-- Detached snapshots and complete explicit choices, not cumulative selections.
local sourceIds, sourceCatalog = {ids[1],ids[2]}, clone(tiers)
local isolated = assert(factory.New({alternativeSpellIds=sourceIds,catalog=sourceCatalog}))
sourceIds[1] = ids[3];sourceCatalog.rows[ids[1]].quality = 99;sourceCatalog.rows[ids[1]].maxStack = 99
local view = isolated.Alternatives()
check(view[1].spellId == ids[1] and view[1].quality == 1 and view[1].maxStack == 5,
    'later caller mutation cannot alter the captured catalog/membership')
view[1].quality = 88;view[1].maxStack = 88;view[1].spellId = ids[3]
check(isolated.Alternatives()[1].quality == 1, 'alternative output has no internal references')
local one = {{spellId=ids[1],stacks=2}}
local first = assert(isolated.Choose(one));one[1].stacks = 5
check(first.echoes[1].stacks == 2, 'chosen output does not retain selection input references')
first.echoes[1].stacks = 55;first.pending['exact:'..ids[1]].stacks = 55
local repeated = assert(isolated.Choose({{spellId=ids[1],stacks=2}}))
check(repeated.echoes[1].stacks == 2, 'mutated previous draft does not affect repeated complete choice')
local other = assert(isolated.Choose({{spellId=ids[2],stacks=1}}))
check(#other.echoes == 1 and other.echoes[1].spellId == ids[2], 'next choice replaces no implicit remembered winner')
check(other.verified == nil and other.fingerprint == nil and other.assigned == nil,
    'result carries draft data, not verification/fingerprint/assignment authority')
local loss, lossCode = isolated.Choose({{spellId=ids[1],stacks=6}})
refused(loss, lossCode, 'STACK_LIMIT', 'refused choice still uses frozen stack bound')
check(isolated.Alternatives()[1].quality == 1 and repeated.echoes[1].stacks == 2,
    'refusal preserves previous results and the pool')

-- Fault control at the existing public dependency: a changed/clipping draft
-- projection must be refused, rather than accepted because counts look plausible.
local realNew = Nexus.WishlistModel.New
Nexus.WishlistModel.New = function()
    local model = realNew();local canonical = model.CanonicalEchoes
    model.CanonicalEchoes = function(rows)
        local out = canonical(rows);out[1].stacks = out[1].stacks + 1;return out
    end
    return model
end
local mismatchPool = assert(factory.New({alternativeSpellIds={ids[1]},catalog=catalog}))
Nexus.WishlistModel.New = realNew
local mismatch, mismatchCode = mismatchPool.Choose({{spellId=ids[1],stacks=1}})
refused(mismatch, mismatchCode, 'DRAFT_MISMATCH', 'actual-model projection fault refuses atomically')

-- The production-loaded model has no Store, adapter, service or frame calls.
local oldStore, oldAdapter, oldService, oldFrame = Nexus.Store,Nexus.GameAdapter,ProjectEbonhold,CreateFrame
local actions, sent = #H.actions,#H.sent
Nexus.Store,Nexus.GameAdapter,ProjectEbonhold = tagged({}),tagged({}),tagged({})
CreateFrame = trap
local passivePool = assert(factory.New({alternativeSpellIds={ids[1]},catalog=catalog}))
local passive = assert(passivePool.Choose({{spellId=ids[1],stacks=1}}))
passivePool.Alternatives()
Nexus.Store,Nexus.GameAdapter,ProjectEbonhold,CreateFrame = oldStore,oldAdapter,oldService,oldFrame
check(metaCalls == 0 and #H.actions == actions and #H.sent == sent,
    'no caller metamethod, service/store/adapter/frame call, game action or send')
check(passive.echoes[1].spellId == ids[1], 'no-I/O control still produces the explicit draft')

-- PR136 catalog picker (docs/UI_TEXT_LAYOUT.md fixed row labels): the reused
-- 32 px catalog rows keep one line and recover the complete current exact ID,
-- quality and name on hover, also after a refresh rebinds a row under the
-- pointer. Self-contained synthetic widgets with the offline 7 px per
-- character model; not native font, pixel, wheel or tooltip evidence.
do
    local saved = {CreateFrame=CreateFrame, UIParent=UIParent, GameTooltip=GameTooltip,
        UISpecialFrames=UISpecialFrames, theme=Nexus.Theme}
    local named, Widget = {}, {}
    local function noop() end
    Widget.__index = function(_, key)
        if Widget[key] then return Widget[key] end
        if type(key) == 'string' and key:find('^%u') then return noop end
        return nil
    end
    local function New(kind, parent, name)
        local w = setmetatable({kind=kind, parent=parent, shown=true, width=0, height=0,
            scripts={}, hooks={}, children={}, regions={}, mouse=false, enabled=true,
            scale=1}, Widget)
        if parent then
            local list = kind == 'FontString' and parent.regions or parent.children
            list[#list+1] = w
        end
        if name then named[name] = w end
        return w
    end
    local function Fire(w, event, ...)
        if w.scripts[event] then w.scripts[event](w, ...) end
        for _, fn in ipairs(w.hooks[event] or {}) do fn(w, ...) end
    end
    local function Chars(text) return #(tostring(text or ''):gsub('[\128-\191]', '')) end
    function Widget:SetSize(width, height) self.width, self.height = width, height end
    function Widget:SetWidth(width) self.width = width end
    function Widget:SetHeight(height) self.height = height end
    function Widget:GetWidth() return self.width end
    function Widget:GetHeight() return self.height end
    function Widget:GetScale() return self.scale end
    function Widget:SetScale(scale) self.scale = scale end
    function Widget:IsShown() return self.shown end
    function Widget:Show() if not self.shown then self.shown = true; Fire(self, 'OnShow') end end
    function Widget:Hide() if self.shown then self.shown = false; Fire(self, 'OnHide') end end
    function Widget:EnableMouse(on) self.mouse = on and true or false end
    function Widget:IsMouseEnabled() return self.mouse end
    function Widget:SetScript(event, fn) self.scripts[event] = fn end
    function Widget:HookScript(event, fn)
        local list = self.hooks[event] or {}
        list[#list+1] = fn;self.hooks[event] = list
    end
    function Widget:SetText(text)
        local old = self.text
        self.text = text ~= nil and tostring(text) or nil
        if self.kind == 'EditBox' and old ~= self.text then Fire(self, 'OnTextChanged', false) end
    end
    function Widget:GetText() return self.text end
    function Widget:GetStringWidth() return Chars(self.text) * 7 end
    function Widget:GetTextWidth() return Chars(self.text) * 7 end
    function Widget:SetWordWrap(on) self.wordWrap = on and true or false end
    function Widget:Enable() self.enabled = true end
    function Widget:Disable() self.enabled = false end
    function Widget:IsEnabled() return self.enabled end
    function Widget:CreateFontString() return New('FontString', self) end
    function Widget:GetParent() return self.parent end
    local tip = {shown=false, lines={}}
    function tip:SetOwner(owner, anchor) self.owner, self.anchor, self.lines = owner, anchor, {} end
    function tip:AddLine(text) self.lines[#self.lines+1] = tostring(text) end
    function tip:Show() self.shown = true end
    function tip:Hide() self.shown, self.owner, self.lines = false, nil, {} end
    function tip:IsShown() return self.shown end
    function tip:IsOwned(frame) return self.owner == frame end
    function tip:GetOwner() return self.owner end
    local function Visible(owner)
        if not (tip.shown and tip.owner == owner) then return nil end
        return table.concat(tip.lines, '\n')
    end
    CreateFrame = function(kind, name, parent)
        local w = New(kind, parent, name)
        if kind == 'EditBox' then w.text = '' end
        return w
    end
    UIParent = New('Frame');UIParent:SetSize(1280, 800)
    GameTooltip, UISpecialFrames, Nexus.Theme = tip, {}, nil

    local longA = 'Synthetic alternative A with an exceptionally long exact catalog name that cannot fit one picker row'
    local longB = 'Synthetic alternative B, a different long exact catalog name that also needs complete-text recovery'
    local pickerNames = {longA, longB, 'Short C'}
    local picker = {rows={}}
    for i = 1, 20 do
        local id = 320000 + i
        picker.rows[id] = {spellId=id, name=pickerNames[i] or ('Synthetic picker '..i),
            quality=i % 4, maxStack=5, groupId=0}
    end
    local A, B, C = 320001, 320002, 320003
    local function Full(id)
        local value = picker.rows[id]
        return '#'..id..'  Q'..value.quality..'  '..value.name
    end
    local drafts = 0
    check(type(Nexus.FlexiblePlanChooser) == 'table' and type(Nexus.FlexiblePlanChooser.New) == 'function',
        'SETUP production chooser is loaded')
    local chooser = Nexus.FlexiblePlanChooser.New({
        catalog=function() return picker end,
        openDraft=function() drafts = drafts + 1;return false end,
    })
    chooser.Show()
    local catalogArea, poolArea = named.NexusFlexiblePlanCatalog, named.NexusFlexiblePlanPool
    local search = named.NexusFlexiblePlanSearch
    check(catalogArea and poolArea and search and #catalogArea.children == 12 and #poolArea.children == 12,
        'chooser keeps two fixed sets of 12 reused row frames')
    local row1, row2 = catalogArea.children[1], catalogArea.children[2]
    check(row1.spellId == A and row1.label:GetText() == Full(A),
        'catalog row shows the exact ID, quality and complete safe name')
    check(row1.label:GetHeight() <= 32 and row1.label.wordWrap == false,
        'catalog label keeps one line at the 32 px row height')
    check(row1.label:GetStringWidth() > row1.label:GetWidth(),
        'SETUP the long exact name is shortened in the fixed catalog label')
    check(row1:IsMouseEnabled(), 'catalog row takes mouse input for complete-text recovery')
    Fire(row1, 'OnEnter')
    check(Visible(row1) == Full(A), 'hover recovers the complete current exact ID, quality and name')

    -- Rebinding under a resting pointer: the open tooltip follows the row's
    -- current item and never keeps another item's complete text.
    Fire(catalogArea, 'OnMouseWheel', -1)
    check(row1.spellId == B and row1.label:GetText() == Full(B), 'wheel refresh rebinds the reused row to B')
    check(Visible(row1) == Full(B), 'open tooltip shows rebound B, not the previous A text')
    Fire(catalogArea, 'OnMouseWheel', -1)
    check(row1.spellId == C and row1.label:GetText() == Full(C)
        and row1.label:GetStringWidth() <= row1.label:GetWidth(), 'row rebinds to fitting short C')
    check(not tip.shown, 'no stale long text remains over a fitting rebound item')
    Fire(catalogArea, 'OnMouseWheel', 2)
    check(row1.spellId == A and Visible(row1) == Full(A), 'rebinding back to long A recovers A again')
    Fire(row1, 'OnLeave')
    check(not tip.shown, 'leaving the row closes its complete-text tooltip')

    -- A search refresh that hides a hovered row closes its tooltip.
    Fire(row2, 'OnEnter')
    check(row2.spellId == B and Visible(row2) == Full(B), 'second reused row recovers B on hover')
    search:SetText(tostring(A))
    check(row1.spellId == A and not row2:IsShown() and row2.spellId == nil, 'search refresh leaves only A')
    check(not tip.shown, 'a hidden row keeps no complete text of its previous item')
    search:SetText('')
    check(row2:IsShown() and row2.spellId == B and not tip.shown, 'clearing search rebinds B without a stale tooltip')
    Fire(row2, 'OnEnter')
    check(Visible(row2) == Full(B), 're-entering the rebound row recovers B')
    Fire(row2, 'OnLeave')

    -- Add on a rebound row acts on its current exact identity; hover never chooses.
    Fire(row1, 'OnEnter')
    Fire(catalogArea, 'OnMouseWheel', -1)
    check(row1.spellId == B and Visible(row1) == Full(B), 'pointer rests on rebound B before Add')
    Fire(row1, 'OnLeave')
    Fire(row1.action, 'OnClick')
    local poolRow = poolArea.children[1]
    check(poolRow.spellId == B and row1.spellId == B and row1.action:GetText() == 'Added'
        and not row1.action:IsEnabled(), 'Add adds rebound B exactly and marks it Added')
    check(poolRow.label.wordWrap == false and poolRow:IsMouseEnabled(), 'pool row keeps its one-line policy')
    Fire(poolRow, 'OnEnter')
    check(Visible(poolRow) == 'Set: 0  #'..B..'  Q'..picker.rows[B].quality..' / max 5  '..longB,
        'pool row still recovers its complete one-line text')
    Fire(poolRow, 'OnLeave')
    local budgetText
    for _, region in ipairs(named.NexusFlexiblePlanChooser.regions) do
        local text = region:GetText()
        if text and text:find('/ 256 alternatives', 1, true) then budgetText = text end
    end
    check(budgetText == '1 / 256 alternatives     Chosen: 0 / 79 ordinary copies' and drafts == 0,
        'hover, refresh and rebinding choose and open nothing')
    chooser.Hide()

    CreateFrame, UIParent, GameTooltip = saved.CreateFrame, saved.UIParent, saved.GameTooltip
    UISpecialFrames, Nexus.Theme = saved.UISpecialFrames, saved.theme
end

-- PR136 tooltip ownership (docs/UI_TEXT_LAYOUT.md: other tooltips are
-- unchanged): after a real catalog or pool row hover, another frame takes
-- GameTooltip. Leaving, hiding or rebinding the row must not hide, replace or
-- reclaim that tooltip, while a tooltip the row still owns is cleaned up and
-- current long text still recovers. Same synthetic widget model as above.
do
    local saved = {CreateFrame=CreateFrame, UIParent=UIParent, GameTooltip=GameTooltip,
        UISpecialFrames=UISpecialFrames, theme=Nexus.Theme}
    local named, Widget = {}, {}
    local function noop() end
    Widget.__index = function(_, key)
        if Widget[key] then return Widget[key] end
        if type(key) == 'string' and key:find('^%u') then return noop end
        return nil
    end
    local function New(kind, parent, name)
        local w = setmetatable({kind=kind, parent=parent, shown=true, width=0, height=0,
            scripts={}, hooks={}, children={}, regions={}, mouse=false, enabled=true,
            scale=1}, Widget)
        if parent then
            local list = kind == 'FontString' and parent.regions or parent.children
            list[#list+1] = w
        end
        if name then named[name] = w end
        return w
    end
    local function Fire(w, event, ...)
        if w.scripts[event] then w.scripts[event](w, ...) end
        for _, fn in ipairs(w.hooks[event] or {}) do fn(w, ...) end
    end
    local function Chars(text) return #(tostring(text or ''):gsub('[\128-\191]', '')) end
    function Widget:SetSize(width, height) self.width, self.height = width, height end
    function Widget:SetWidth(width) self.width = width end
    function Widget:SetHeight(height) self.height = height end
    function Widget:GetWidth() return self.width end
    function Widget:GetHeight() return self.height end
    function Widget:GetScale() return self.scale end
    function Widget:SetScale(scale) self.scale = scale end
    function Widget:IsShown() return self.shown end
    function Widget:Show() if not self.shown then self.shown = true; Fire(self, 'OnShow') end end
    function Widget:Hide() if self.shown then self.shown = false; Fire(self, 'OnHide') end end
    function Widget:EnableMouse(on) self.mouse = on and true or false end
    function Widget:IsMouseEnabled() return self.mouse end
    function Widget:SetScript(event, fn) self.scripts[event] = fn end
    function Widget:HookScript(event, fn)
        local list = self.hooks[event] or {}
        list[#list+1] = fn;self.hooks[event] = list
    end
    function Widget:SetText(text)
        local old = self.text
        self.text = text ~= nil and tostring(text) or nil
        if self.kind == 'EditBox' and old ~= self.text then Fire(self, 'OnTextChanged', false) end
    end
    function Widget:GetText() return self.text end
    function Widget:GetStringWidth() return Chars(self.text) * 7 end
    function Widget:GetTextWidth() return Chars(self.text) * 7 end
    function Widget:SetWordWrap(on) self.wordWrap = on and true or false end
    function Widget:Enable() self.enabled = true end
    function Widget:Disable() self.enabled = false end
    function Widget:IsEnabled() return self.enabled end
    function Widget:CreateFontString() return New('FontString', self) end
    function Widget:GetParent() return self.parent end
    local tip = {shown=false, lines={}}
    function tip:SetOwner(owner, anchor) self.owner, self.anchor, self.lines = owner, anchor, {} end
    function tip:AddLine(text) self.lines[#self.lines+1] = tostring(text) end
    function tip:Show() self.shown = true end
    function tip:Hide() self.shown, self.owner, self.lines = false, nil, {} end
    function tip:IsShown() return self.shown end
    function tip:IsOwned(frame) return self.owner == frame end
    function tip:GetOwner() return self.owner end
    local function Visible(owner)
        if not (tip.shown and tip.owner == owner) then return nil end
        return table.concat(tip.lines, '\n')
    end
    CreateFrame = function(kind, name, parent)
        local w = New(kind, parent, name)
        if kind == 'EditBox' then w.text = '' end
        return w
    end
    UIParent = New('Frame');UIParent:SetSize(1280, 800)
    GameTooltip, UISpecialFrames, Nexus.Theme = tip, {}, nil

    -- A separate frame (for example a spell or identity tooltip owner) that
    -- takes GameTooltip after the row hover, as the client allows.
    local outside = New('Frame', UIParent)
    local EXTERNAL = 'External spell tooltip'
    local function TakeTooltip()
        tip:SetOwner(outside, 'ANCHOR_LEFT');tip:AddLine(EXTERNAL);tip:Show()
    end
    local function KeepsExternal()
        return Visible(outside) == EXTERNAL and tip.anchor == 'ANCHOR_LEFT' and #tip.lines == 1
    end

    local longA = 'Synthetic owner A with an exceptionally long exact catalog name that cannot fit one picker row'
    local longB = 'Synthetic owner B, a different long exact catalog name that also needs complete-text recovery'
    local ownerNames = {longA, longB, 'Short C'}
    local picker = {rows={}}
    for i = 1, 20 do
        local id = 330000 + i
        picker.rows[id] = {spellId=id, name=ownerNames[i] or ('Synthetic owner picker '..i),
            quality=i % 4, maxStack=5, groupId=0}
    end
    local A, B, C = 330001, 330002, 330003
    local function Full(id)
        local value = picker.rows[id]
        return '#'..id..'  Q'..value.quality..'  '..value.name
    end
    local drafts = 0
    local chooser = Nexus.FlexiblePlanChooser.New({
        catalog=function() return picker end,
        openDraft=function() drafts = drafts + 1;return false end,
    })
    chooser.Show()
    local catalogArea, poolArea = named.NexusFlexiblePlanCatalog, named.NexusFlexiblePlanPool
    local search = named.NexusFlexiblePlanSearch
    check(catalogArea and poolArea and search and #catalogArea.children == 12,
        'SETUP ownership chooser has its fixed catalog rows')
    local row1, row2 = catalogArea.children[1], catalogArea.children[2]
    check(row1.spellId == A and row2.spellId == B and row1.label:GetStringWidth() > row1.label:GetWidth(),
        'SETUP rows bind long A and B')

    -- Leave after ownership transfer.
    Fire(row1, 'OnEnter')
    check(Visible(row1) == Full(A), 'real catalog hover shows the row-owned complete text')
    TakeTooltip()
    Fire(row1, 'OnLeave')
    check(KeepsExternal(), 'catalog leave after transfer keeps the external owner, anchor and text')
    tip:Hide()

    -- Rebind under the pointer after ownership transfer.
    Fire(row1, 'OnEnter')
    check(Visible(row1) == Full(A), 'row owns the tooltip again on a fresh hover')
    TakeTooltip()
    Fire(catalogArea, 'OnMouseWheel', -1)
    check(row1.spellId == B and row1.label:GetText() == Full(B) and KeepsExternal(),
        'rebinding to long B neither hides, replaces nor reclaims the external tooltip')
    Fire(catalogArea, 'OnMouseWheel', -1)
    check(row1.spellId == C and KeepsExternal(), 'rebinding to fitting C keeps the external tooltip')
    -- The external owner releases the tooltip; the pointer still rests on the row.
    tip:Hide()
    Fire(catalogArea, 'OnMouseWheel', 1)
    check(row1.spellId == B and Visible(row1) == Full(B),
        'after release, rebinding recovers the current long text for the row')
    Fire(catalogArea, 'OnMouseWheel', 1)
    check(row1.spellId == A and Visible(row1) == Full(A), 'row-owned tooltip follows its rebinding to A')
    Fire(row1, 'OnLeave')
    check(not tip.shown, 'catalog leave still closes a tooltip the row owns')

    -- Hide a hovered row after ownership transfer, then a late leave.
    Fire(row2, 'OnEnter')
    check(Visible(row2) == Full(B), 'second row owns its complete-text tooltip')
    TakeTooltip()
    search:SetText(tostring(A))
    check(not row2:IsShown() and KeepsExternal(), 'hiding the hovered row keeps the external tooltip')
    Fire(row2, 'OnLeave')
    check(KeepsExternal(), 'a late leave from the hidden row keeps the external tooltip')
    search:SetText('')
    check(row2:IsShown() and row2.spellId == B and KeepsExternal(), 'reshowing the row keeps the external tooltip')
    tip:Hide()
    Fire(row2, 'OnEnter')
    check(Visible(row2) == Full(B), 'reshown row recovers B on hover')
    search:SetText(tostring(A))
    check(not tip.shown, 'hiding the hovered row closes the tooltip it owns')
    Fire(row2, 'OnLeave')
    search:SetText('')

    -- Pool rows share the helper: the same ownership rule and cleanup apply.
    check(row1.spellId == A, 'SETUP catalog row is bound to A before Add')
    Fire(row1.action, 'OnClick')
    local poolRow = poolArea.children[1]
    check(poolRow.spellId == A and row1.action:GetText() == 'Added', 'Add still adds A exactly')
    local poolText = 'Set: 0  #'..A..'  Q'..picker.rows[A].quality..' / max 5  '..longA
    Fire(poolRow, 'OnEnter')
    check(Visible(poolRow) == poolText, 'real pool hover shows its complete one-line text')
    TakeTooltip()
    Fire(poolRow, 'OnLeave')
    check(KeepsExternal(), 'pool leave after transfer keeps the external tooltip')
    tip:Hide()
    Fire(poolRow, 'OnEnter')
    Fire(poolRow, 'OnLeave')
    check(not tip.shown, 'pool leave still closes a tooltip the row owns')

    local budgetText
    for _, region in ipairs(named.NexusFlexiblePlanChooser.regions) do
        local text = region:GetText()
        if text and text:find('/ 256 alternatives', 1, true) then budgetText = text end
    end
    check(budgetText == '1 / 256 alternatives     Chosen: 0 / 79 ordinary copies' and drafts == 0,
        'tooltip ownership changes choose and open nothing')
    chooser.Hide()

    CreateFrame, UIParent, GameTooltip = saved.CreateFrame, saved.UIParent, saved.GameTooltip
    UISpecialFrames, Nexus.Theme = saved.UISpecialFrames, saved.theme
end
print('PASS flexible_plan_player_choice checks='..checks)
