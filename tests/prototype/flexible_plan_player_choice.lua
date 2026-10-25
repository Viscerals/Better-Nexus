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
print('PASS flexible_plan_player_choice checks='..checks)
