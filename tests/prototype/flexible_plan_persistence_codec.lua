-- #151 Stage A1: the pure local-pool codec, loaded through the actual TOC.
-- Synthetic public data only: no Store, UI, private/native input, live I/O
-- or game action. Persistence operations (New/Read/Save) are a later slice.
local H = dofile('tests/prototype/harness.lua')
H.Boot()
local checks = 0
local function check(value, message) assert(value, message); checks = checks + 1 end
check(type(Nexus.FlexiblePlanModel) == 'table', 'SETUP actual TOC boot loads the session pool model')
local codec = Nexus.FlexiblePlanStore
if type(codec) ~= 'table' or type(codec.Encode) ~= 'function'
    or type(codec.Decode) ~= 'function' then
    print('FEATURE_UNAVAILABLE Nexus.FlexiblePlanStore.Encode/Decode')
    error('EXPECT #151 local pool codec capability is absent', 0)
end
local Encode, Decode = codec.Encode, codec.Decode
local MAX_ID, A, B, C = 2147483647, 310001, 310002, 310003
local ARR = {'ids', 'quality', 'maxStack', 'groupId', 'counts'}
local metaCalls = 0
local function trap() metaCalls = metaCalls + 1; error('caller metamethod invoked') end
local function tagged(t)
    return setmetatable(t, {__index=trap, __newindex=trap, __len=trap, __pairs=trap,
        __ipairs=trap, __eq=trap, __lt=trap, __le=trap, __concat=trap,
        __call=trap, __tostring=trap})
end
local function dump(v)
    if type(v) ~= 'table' then return type(v)..':'..tostring(v) end
    local keys, out = {}, {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(x, y) return type(x)..tostring(x) < type(y)..tostring(y) end)
    for _, k in ipairs(keys) do out[#out + 1] = dump(k)..'='..dump(v[k]) end
    return '{'..table.concat(out, ',')..'}'
end
local function sample()
    return {C, A, B}, {
        [C]={spellId=C, quality=3, maxStack=5, groupId=900, name='Synthetic C'},
        [A]={spellId=A, quality=1, maxStack=5, name='Synthetic A'},
        [B]={spellId=B, quality=0, maxStack=1, groupId=0}}, {[C]=2, [A]=0}
end
local function fresh() return (Encode(sample())) end
local BYTES = 'v1|310003,3,5,900,2;310001,1,5,-1,0;310002,0,1,0,0;'
local RECORD = dump({version=1, ids={C, A, B}, quality={3, 1, 0}, maxStack={5, 5, 1},
    groupId={900, -1, 0}, counts={2, 0, 0}})
local SESSION = dump({ids={C, A, B}, chosen={[C]=2}, rows={
    [C]={spellId=C, quality=3, maxStack=5, groupId=900},
    [A]={spellId=A, quality=1, maxStack=5},
    [B]={spellId=B, quality=0, maxStack=1, groupId=0}}})

-- Positive controls: literal bytes, record and decoded session; detachment.
local ids, rows, chosen = sample()
local inputs = dump({ids, rows, chosen})
local record, bytes = Encode(ids, rows, chosen)
check(bytes == BYTES, 'literal canonical bytes in insertion order: '..tostring(bytes))
check(dump(record) == RECORD, 'exact six-key v1 record; no names; zero and absent counts are 0')
check(dump({ids, rows, chosen}) == inputs, 'Encode leaves every input unchanged')
for _, field in ipairs(ARR) do
    for _, t in ipairs({ids, rows, chosen, rows[A], rows[B], rows[C]}) do
        check(record[field] ~= t, 'record '..field..' is not a caller table')
    end
end
ids[1], rows[C].quality, chosen[C], rows[A].groupId = A, 0, 5, 7
check(dump(record) == RECORD, 'later caller edits cannot reach the encoded record')
local frozen = dump(record)
check(select('#', Decode(record)) == 3, 'CURRENT returns pool, bytes, class')
local pool, decoded, class = Decode(record)
check(class == 'CURRENT' and decoded == BYTES, 'record decodes CURRENT with identical bytes')
check(dump(pool) == SESSION, 'literal session: captured facts, committed counts, no names')
check(dump(record) == frozen, 'Decode leaves the record unchanged')
for _, field in ipairs(ARR) do check(pool.ids ~= record[field], 'decoded ids detached from '..field) end
pool.ids[1], pool.rows[C].quality, pool.chosen[C], pool.rows[A].name = A, 0, 9, 'x'
local again = Decode(record)
check(dump(again) == SESSION and dump(record) == frozen,
    'mutating a decoded session reaches neither the record nor a later decode')
again.rows[A].name, again.rows[C].name = 'Changed name', 'Other name'
local reRecord, reBytes = Encode(again.ids, again.rows, again.chosen)
check(reBytes == BYTES and dump(reRecord) == RECORD,
    'decoded session re-encodes byte-identically; changed names are ignored')
check(select('#', Encode({}, {}, {})) == 2 and Encode({}, {}, {}) == nil
    and select(2, Encode({}, {}, {})) == nil, 'only a truly empty session encodes nil,nil (clear)')

local function refuse(label, code, a, b, c)
    local value, why = Encode(a, b, c)
    check(value == nil and why == code, label..' refuses '..code..' (got '..tostring(why)..')')
end
local function classOf(rec)
    local p, second, third = Decode(rec)
    if p ~= nil then return third end
    return second
end
local shared = {}
refuse('aliased empty inputs', 'ALIASED_INPUT', shared, shared, shared)
refuse('missing ids', 'INVALID_INPUT', nil, {}, {})
refuse('missing rows', 'INVALID_INPUT', {}, nil, {})
refuse('missing chosen', 'INVALID_INPUT', {}, {}, nil)
refuse('metatable empty ids', 'INVALID_INPUT', tagged({}), {}, {})
refuse('empty ids with a row', 'ROW_MISMATCH', {}, {[A]={spellId=A, quality=1, maxStack=5}}, {})
refuse('empty ids with a chosen count', 'NOT_IN_POOL', {}, {}, {[A]=1})
refuse('sparse empty-looking ids', 'INVALID_IDS', {[2]=A}, {}, {})

-- One defect per case on a fresh copy of the positive control.
local function row(id, field, value) return function(_, r) r[id][field] = value end end
local function pick(id, value) return function(_, _, c) c[id] = value end end
local cases = {
    {'duplicate ID', 'DUPLICATE_ID', function(i) i[3] = C end},
    {'sparse IDs', 'INVALID_IDS', function(i) i[2] = nil end},
    {'NaN ID', 'INVALID_ID', function(i) i[1] = 0/0 end},
    {'infinite ID', 'INVALID_ID', function(i) i[1] = math.huge end},
    {'string-number ID', 'INVALID_ID', function(i) i[1] = '310003' end},
    {'fractional ID', 'INVALID_ID', function(i) i[1] = 1.5 end},
    {'missing row', 'ROW_MISMATCH', function(_, r) r[B] = nil end},
    {'extra row', 'ROW_MISMATCH', function(_, r) r[999] = {spellId=999, quality=0, maxStack=1} end},
    {'mismatched spellId', 'ROW_MISMATCH', row(C, 'spellId', A)},
    {'string spellId', 'ROW_MISMATCH', row(C, 'spellId', '310003')},
    {'string quality', 'INVALID_ROW', row(C, 'quality', '3')},
    {'quality 256', 'INVALID_ROW', row(C, 'quality', 256)},
    {'NaN maxStack', 'INVALID_ROW', row(C, 'maxStack', 0/0)},
    {'infinite maxStack', 'INVALID_ROW', row(C, 'maxStack', math.huge)},
    {'zero maxStack', 'INVALID_ROW', row(C, 'maxStack', 0)},
    {'source group -1', 'INVALID_ROW', row(C, 'groupId', -1)},
    {'string group', 'INVALID_ROW', row(C, 'groupId', '900')},
    {'non-string name', 'INVALID_ROW', row(C, 'name', 5)},
    {'locked role', 'UNSUPPORTED_ROLE', row(A, 'locked', true)},
    {'sourceRole', 'UNSUPPORTED_ROLE', row(A, 'sourceRole', 'ordinary')},
    {'false lockIntent', 'UNSUPPORTED_ROLE', row(A, 'lockIntent', false)},
    {'unknown row field', 'UNKNOWN_FIELD', row(A, 'note', 'x')},
    {'shared row table', 'ALIASED_ROW', function(_, r) r[A] = r[C] end},
    {'row cycle', 'ALIASED_ROW', function(_, r) r[A] = r end},
    {'metatable row', 'INVALID_ROW', function(_, r) tagged(r[A]) end},
    {'out-of-pool choice', 'NOT_IN_POOL', pick(999, 1)},
    {'string-key choice', 'NOT_IN_POOL', pick('310003', 1)},
    {'metatable-key choice', 'NOT_IN_POOL', function(_, _, c) c[tagged({})] = 1 end},
    {'string count', 'INVALID_COUNT', pick(C, '2')},
    {'boolean count', 'INVALID_COUNT', pick(C, true)},
    {'negative count', 'INVALID_COUNT', pick(C, -1)},
    {'fractional count', 'INVALID_COUNT', pick(C, 1.5)},
    {'NaN count', 'INVALID_COUNT', pick(C, 0/0)},
    {'count 80', 'INVALID_COUNT', function(_, r, c) r[A].maxStack = 100; c[A] = 80 end},
    {'count above maxStack', 'STACK_LIMIT', pick(A, 6)},
    {'count above single maxStack', 'STACK_LIMIT', pick(B, 2)},
}
for _, case in ipairs(cases) do
    local i, r, c = sample(); case[3](i, r, c); refuse(case[1], case[2], i, r, c)
end

-- Boundaries: 256 alternatives and 79 copies admitted; 257/80/over-stack refused.
local function bigPool(n)
    local i, r = {}, {}
    for k = 1, n do
        local id = MAX_ID - n + k
        i[k], r[id] = id, {spellId=id, quality=255, maxStack=MAX_ID, groupId=MAX_ID}
    end
    return i, r
end
local function rawRecord(n, first)
    local r = {version=1, ids={}, quality={}, maxStack={}, groupId={}, counts={}}
    for k = 1, n do
        r.ids[k], r.quality[k], r.maxStack[k] = MAX_ID - n + k, 255, MAX_ID
        r.groupId[k], r.counts[k] = MAX_ID, 0
    end
    r.counts[1] = first
    return r
end
local maxIds, maxRows = bigPool(256)
local maxChosen = {[maxIds[1]]=79}
local maxRecord, maxBytes = Encode(maxIds, maxRows, maxChosen)
check(maxRecord ~= nil and dump(maxRecord) == dump(rawRecord(256, 79)),
    '256 alternatives with 79 copies of one ID encode exactly')
check(#maxBytes == 9988 and maxBytes:sub(1, 43) == 'v1|2147483392,255,2147483647,2147483647,79;'
    and maxBytes:sub(-39) == '2147483647,255,2147483647,2147483647,0;',
    'maximal canonical bytes have literal ends and length 9988 (got '..#maxBytes..')')
local maxPool, maxDecoded, maxClass = Decode(maxRecord)
check(maxClass == 'CURRENT' and maxDecoded == maxBytes and #maxPool.ids == 256
    and dump(maxPool.chosen) == dump({[maxIds[1]]=79}), 'maximal record decodes CURRENT')
local spread = {}
for k = 1, 79 do spread[maxIds[k]] = 1 end
check(Encode(maxIds, maxRows, spread) ~= nil, '79 single copies across 79 IDs are admitted')
spread[maxIds[80]] = 1
refuse('80 copies', 'ORDINARY_LIMIT', maxIds, maxRows, spread)
local ids257, rows257 = bigPool(257)
refuse('257 alternatives', 'TOO_MANY_ALTERNATIVES', ids257, rows257, {})
check(classOf(rawRecord(257, 0)) == 'OVERSIZED', '257-row record is OVERSIZED')
local over = rawRecord(256, 79); over.counts[2] = 1
check(classOf(over) == 'MALFORMED', '80 total stored copies are MALFORMED')
check(classOf(rawRecord(256, 80)) == 'MALFORMED', 'a stored count of 80 is MALFORMED')

-- Decode classification; each case is a single defect on a fresh record.
check(classOf(nil) == 'ABSENT', 'missing record is ABSENT')
local function set(field, value) return function(r) r[field] = value; return r end end
local function at(field, i, value) return function(r) r[field][i] = value; return r end end
local decodeCases = {
    {'string record', 'MALFORMED', function() return 'v1' end},
    {'metatable root', 'MALFORMED', tagged},
    {'version 0', 'MALFORMED', set('version', 0)},
    {'string version', 'MALFORMED', set('version', '1')},
    {'missing version', 'MALFORMED', set('version', nil)},
    {'fractional version', 'MALFORMED', set('version', 1.5)},
    {'infinite version', 'MALFORMED', set('version', math.huge)},
    {'NaN version', 'MALFORMED', set('version', 0/0)},
    {'string future version', 'MALFORMED', set('version', '2')},
    {'version 3', 'FUTURE', set('version', 3)},
    {'unknown root field', 'UNSUPPORTED', set('note', 'kept')},
    {'missing counts', 'UNSUPPORTED', set('counts', nil)},
    {'string array', 'MALFORMED', set('counts', 'x')},
    {'metatable array', 'MALFORMED', function(r) tagged(r.ids); return r end},
    {'shared array alias', 'MALFORMED', function(r) r.groupId = r.quality; return r end},
    {'root cycle', 'MALFORMED', function(r) r.counts = r; return r end},
    {'value cycle', 'MALFORMED', function(r) r.ids[1] = r; return r end},
    {'sparse array', 'MALFORMED', at('ids', 2, nil)},
    {'unequal lengths', 'MALFORMED', at('counts', 4, 0)},
    {'duplicate IDs', 'MALFORMED', at('ids', 2, C)},
    {'NaN quality', 'MALFORMED', at('quality', 1, 0/0)},
    {'infinite maxStack', 'MALFORMED', at('maxStack', 1, math.huge)},
    {'string-number count', 'MALFORMED', at('counts', 1, '2')},
    {'string-number ID', 'MALFORMED', at('ids', 1, '310003')},
    {'group -2', 'MALFORMED', at('groupId', 1, -2)},
    {'quality 256', 'MALFORMED', at('quality', 1, 256)},
    {'count above maxStack', 'MALFORMED', at('counts', 3, 2)},
    {'empty arrays', 'MALFORMED', function(r) for _, f in ipairs(ARR) do r[f] = {} end; return r end},
}
for _, case in ipairs(decodeCases) do
    local p, cls = Decode(case[3](fresh()))
    check(p == nil and cls == case[2], 'Decode '..case[1]..' is '..case[2]..' (got '..tostring(cls)..')')
end
local kept = fresh(); kept.note = 'kept'; local keptDump = dump(kept)
check(classOf(kept) == 'UNSUPPORTED' and dump(kept) == keptDump, 'unknown-field record is refused and left as found')

-- Huge maps: deterministic instruction ceilings (count hook, JIT off) prove
-- early exit; metatables are refused without traversal or metamethod calls.
if jit and jit.off then jit.off(); if jit.flush then jit.flush() end end
local function cost(fn, a, b, c)
    local ticks = 0
    debug.sethook(function() ticks = ticks + 1 end, '', 100)
    local x, y, z = fn(a, b, c)
    debug.sethook()
    return ticks * 100, x, y, z
end
local decodeBudget = cost(Decode, maxRecord)
local encodeBudget = cost(Encode, maxIds, maxRows, maxChosen)
check(decodeBudget > 0 and encodeBudget > 0, 'instruction meter observes the maximal valid controls')
local huge, trappedHuge, hugeRows = {}, {}, {}
for k = 1, 100000 do huge[k], trappedHuge[k], hugeRows[k] = k, k, true end
tagged(trappedHuge)
local worst = 0
for _, field in ipairs(ARR) do
    local hugeRecord = fresh(); hugeRecord[field] = huge
    local spent, p, cls = cost(Decode, hugeRecord)
    worst = math.max(worst, spent)
    check(p == nil and cls == 'OVERSIZED' and spent <= decodeBudget,
        '100k-entry '..field..' is OVERSIZED within the maximal decode cost')
end
local si, sr, sc = sample()
hugeRows[A], hugeRows[B], hugeRows[C] = sr[A], sr[B], sr[C]
for _, case in ipairs({{'ids', 'TOO_MANY_ALTERNATIVES', huge, sr, sc},
    {'rows', 'ROW_MISMATCH', si, hugeRows, sc}, {'chosen', 'NOT_IN_POOL', si, sr, huge}}) do
    local spent, value, why = cost(Encode, case[3], case[4], case[5])
    worst = math.max(worst, spent)
    check(value == nil and why == case[2] and spent <= encodeBudget,
        '100k-entry '..case[1]..' refuses '..case[2]..' within the maximal encode cost')
end
local trappedRecord = fresh(); trappedRecord.ids = trappedHuge
local spent, p, cls = cost(Decode, trappedRecord)
check(p == nil and cls == 'MALFORMED' and spent <= 1000, 'metatable 100k array refused before traversal')
spent, p, cls = cost(Decode, trappedHuge)
check(p == nil and cls == 'MALFORMED' and spent <= 1000, 'metatable root refused before traversal')
spent, p, cls = cost(Encode, trappedHuge, {}, {})
check(p == nil and cls == 'INVALID_INPUT' and spent <= 1000, 'metatable source ids refused before traversal')
local future = {version=2, ids=trappedHuge, quality='junk', unknown=tagged({}), [tagged({})]=true}
spent, p, cls = cost(Decode, future)
check(p == nil and cls == 'FUTURE' and spent <= 1000 and future.quality == 'junk',
    'version 2 is FUTURE before any traversal; nothing rewritten')

-- Heap: warm code, collected GC. The decoded session holds 256 row tables, so
-- the five-array record graph alone does not bound it.
local function retained(fn)
    collectgarbage('collect'); collectgarbage('collect')
    local start = collectgarbage('count')
    local held = {fn()}
    collectgarbage('collect'); collectgarbage('collect')
    return math.floor((collectgarbage('count') - start) * 1024), held
end
local recordHeap = retained(function() return Encode(maxIds, maxRows, maxChosen) end)
local sessionHeap = retained(function() return Decode(maxRecord) end)
collectgarbage('collect'); collectgarbage('collect')
local base = collectgarbage('count')
for _ = 1, 200 do Decode(maxRecord) end
collectgarbage('collect'); collectgarbage('collect')
local residue = math.floor((collectgarbage('count') - base) * 1024)

-- Independent graph count of the maximal record (test-owned charging model).
local function measure(root)
    local tables, edges, charged, depth = 0, 0, 0, 0
    local function walk(t, d)
        tables, depth = tables + 1, math.max(depth, d)
        for k, v in pairs(t) do
            edges = edges + 1
            charged = charged + (type(k) == 'string' and #k or #string.format('%d', k))
            if type(v) == 'table' then walk(v, d + 1) else charged = charged + 8 end
        end
    end
    walk(root, 1)
    return tables, edges, charged, depth
end
local tables, edges, charged, depth = measure(maxRecord)
print(string.format('MEASURE maximal record tables=%d edges=%d chargedBytes=%d depth=%d canonicalBytes=%d'
    ..' (test model: key text or decimal digits plus 8 per scalar; synthetic, not native SavedVariables bytes)',
    tables, edges, charged, depth, #maxBytes))
print(string.format('MEASURE heap recordHeld=%d sessionHeld=%d repeat200Residue=%d bytes;'
    ..' instructions decodeMax=%d encodeMax=%d hugeWorst=%d', recordHeap, sessionHeap, residue,
    decodeBudget, encodeBudget, worst))
check(tables == 6 and edges == 1286 and charged == 13586 and depth == 2,
    'independent count matches contract hypothesis: 6 tables, 1,286 edges, 13,586 bytes, arrays one level down')
check(recordHeap <= 65536, 'held maximal record plus bytes stays within 64 KB')
check(sessionHeap <= 131072, 'held decoded maximal session (256 row tables) stays within the proposed 128 KB')
check(residue <= 16384, '200 repeated maximal decodes leave no residual heap growth')
check(metaCalls == 0, 'no caller metamethod was invoked')
print('PASS flexible_plan_persistence_codec checks='..checks)
