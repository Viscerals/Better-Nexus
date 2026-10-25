-- #151 Stage A2: the private Store pool seam and FlexiblePlanStore.New
-- Read/Save/Clear through actual F.Boot/F.Reload. Synthetic data only;
-- offline, not native SavedVariables or a client reload. The remaining Stage A
-- retention acceptance is tests/prototype/flexible_plan_persistence_retention.lua:
-- measured startup work of a maximal pool against the actual PumpCaps and
-- SourceBounds (edge division alone omits row, cursor, sort and comparison
-- work, so no fixed pump number is promised here), a maximal pool plus a
-- 28,672-byte sibling reaching READY/durable, and the released-peer round trip.
local F = dofile('tests/prototype/format5_support.lua')
local checks = 0
local function check(v, m) assert(v, m); checks = checks + 1 end
local KEY, A, B, C, MAX_ID = 'flexiblePlanPoolV1', 310001, 310002, 310003, 2147483647
local BYTES = 'v1|310003,3,5,900,2;310001,1,5,-1,0;310002,0,1,0,0;'
local BYTES2 = 'v1|310001,1,5,-1,4;'
local function dump(v)
    if type(v) ~= 'table' then return type(v)..':'..tostring(v) end
    local keys, out = {}, {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(x, y) return type(x)..tostring(x) < type(y)..tostring(y) end)
    for _, k in ipairs(keys) do out[#out + 1] = dump(k)..'='..dump(v[k]) end
    return '{'..table.concat(out, ',')..'}'
end
local function Record()
    return {version=1, ids={C, A, B}, quality={3, 1, 0}, maxStack={5, 5, 1},
        groupId={900, -1, 0}, counts={2, 0, 0}}
end
local RECORD = dump(Record())
local SESSION = dump({ids={C, A, B}, chosen={[C]=2}, rows={
    [C]={spellId=C, quality=3, maxStack=5, groupId=900},
    [A]={spellId=A, quality=1, maxStack=5}, [B]={spellId=B, quality=0, maxStack=1, groupId=0}}})
local function Session()
    return {ids={C, A, B}, chosen={[C]=2, [A]=0}, rows={
        [C]={spellId=C, quality=3, maxStack=5, groupId=900, name='Synthetic C'},
        [A]={spellId=A, quality=1, maxStack=5, name='Synthetic A'},
        [B]={spellId=B, quality=0, maxStack=1, groupId=0}}}
end
local function Session2() return {ids={A}, rows={[A]={spellId=A, quality=1, maxStack=5}}, chosen={[A]=4}} end
-- The serialized saved root with exactly the current owned row's pool key left
-- out. The owned row is one physical table that the saved root reaches through
-- more than one path (NexusDB.chars[owner] and the durable bundle's
-- authorityBundle.storeData.chars[owner]), so the exclusion is by row IDENTITY,
-- wherever that row appears. Everything else is copied and compared: other
-- characters' rows including their pool keys, the same name nested in any
-- table, and every other part of the bundle. Test-owned, bounded, memoized
-- plain copy; serializable synthetic data only.
local function Without(db)
    local chars = rawget(db, 'chars')
    local owned = type(chars) == 'table' and rawget(chars, F.OWNER) or nil
    local memo, tables = {}, 0
    local function Copy(v, depth)
        if type(v) ~= 'table' then return v end
        if memo[v] then return memo[v] end
        tables = tables + 1
        assert(tables <= 100000 and depth <= 64, 'Without: saved graph past the test copy bound')
        assert(getmetatable(v) == nil, 'Without: plain saved data only')
        local out = {}
        memo[v] = out
        local skip = owned ~= nil and rawequal(v, owned)
        for k, x in next, v do
            if not (skip and k == KEY) then out[k] = Copy(x, depth + 1) end
        end
        return out
    end
    return F.Serialize(Copy(db, 1))
end
-- Unrelated saved parts compared across a reboot (ledger without the
-- registration timestamp, which normal start-up rewrites).
local function Parts(db)
    local r, ledger = db.chars[F.OWNER], {}
    for k, v in pairs(db.accountCharacters[F.OWNER]) do if k ~= 'lastSeen' then ledger[k] = v end end
    return F.Serialize({r.unknownGenField, r.nestedHolder, db.settings.customGenSetting,
        db.genUnknownTopLevel, db.nexusNativeRecoveryArchiveF5, ledger})
end
-- Counts calls into owners the pool must never drive, plus harness actions
-- and messages. Restores every wrapped function.
local function Spy(N, H)
    local calls, undo = 0, {}
    local function wrap(t, k, f)
        undo[#undo + 1] = {t, k, f}
        t[k] = function(...) calls = calls + 1; return f(...) end
    end
    for _, name in ipairs({'WishlistController', 'Sync', 'SyncTransport', 'OrbRuntime', 'OrbAdapter',
            'GameAdapter', 'DataRetention', 'DataCompaction', 'CommunityController'}) do
        local t = N[name]
        if type(t) == 'table' then
            for k, f in pairs(t) do if type(f) == 'function' then wrap(t, k, f) end end
        end
    end
    wrap(N.Store, 'RegisterCurrentCharacter', N.Store.RegisterCurrentCharacter)
    local acts, sent = #H.actions, #H.sent
    return function()
        for i = #undo, 1, -1 do undo[i][1][undo[i][2]] = undo[i][3] end
        return calls, #H.actions - acts, #H.sent - sent
    end
end

local H = F.Boot(F.Database({version=2, mutate=function(db)
    db.chars = {[F.OWNER]=F.Row({nestedHolder={[KEY]={keep='nested'}}})} end}))
local N = Nexus
local O = type(N.MainInternals) == 'table' and N.MainInternals.StoreAuthorityOwner or nil
local codec = N.FlexiblePlanStore
if type(codec) ~= 'table' or type(codec.New) ~= 'function' or type(O) ~= 'table'
    or type(O.PlanPoolReadV1) ~= 'function' or type(O.IsDurableStateRowV1) ~= 'function'
    or O.PLAN_POOL_KEY ~= KEY then
    print('FEATURE_UNAVAILABLE FlexiblePlanStore.New / StoreAuthorityOwner.PlanPoolReadV1')
    error('EXPECT #151 local pool persistence owner capability is absent', 0)
end
local P = codec.New({store=N.Store})
local row = NexusDB.chars[F.OWNER]
local held, snap

do -- 0. the byte oracle itself: exclusion by owned-row identity through every alias, negative controls
    local bundle = rawget(NexusDB, 'authorityBundle')
    local storeData = type(bundle) == 'table' and rawget(bundle, 'storeData') or nil
    local bundleChars = type(storeData) == 'table' and rawget(storeData, 'chars') or nil
    local aliased = type(bundleChars) == 'table' and rawequal(rawget(bundleChars, F.OWNER), row)
    print('ORACLE owned row also reached as authorityBundle.storeData.chars[owner]='..tostring(aliased))
    check(aliased, 'oracle control: the owned row is aliased through the durable bundle, the case the helper must cover')
    local peer = 'oraclepeer@ebonhold'
    check(rawget(NexusDB.chars, peer) == nil and rawget(row, KEY) == nil and rawget(row, 'oracleProbe151') == nil
        and rawget(bundle, 'oracleProbe151') == nil, 'oracle control: clean start')
    local clean = Without(NexusDB)
    NexusDB.chars[peer] = {[KEY]=Record(), nested={[KEY]={keep='peer'}}}
    local other, base = NexusDB.chars[peer], Without(NexusDB)
    check(base ~= clean, 'oracle negative control: a row of another character, pool key included, is compared')
    rawset(row, KEY, Record())
    check(Without(NexusDB) == base, 'oracle control: the owned pool key is excluded wherever the owned row appears')
    rawset(row, KEY, nil)
    local function changes(label, apply, undo)
        apply()
        local text = Without(NexusDB)
        undo()
        check(text ~= base and Without(NexusDB) == base, 'oracle negative control: '..label..' is compared')
    end
    changes('a same-named pool field of another character', function() other[KEY].counts[1] = 3 end,
        function() other[KEY].counts[1] = 2 end)
    changes('a nested same-named field of another character', function() other.nested[KEY].keep = 'changed' end,
        function() other.nested[KEY].keep = 'peer' end)
    changes('a nested same-named field of the owned row', function() row.nestedHolder[KEY].keep = 'changed' end,
        function() row.nestedHolder[KEY].keep = 'nested' end)
    changes('another field of the owned row', function() rawset(row, 'oracleProbe151', 1) end,
        function() rawset(row, 'oracleProbe151', nil) end)
    changes('an unrelated durable bundle field', function() rawset(bundle, 'oracleProbe151', 1) end,
        function() rawset(bundle, 'oracleProbe151', nil) end)
    NexusDB.chars[peer] = nil
    check(Without(NexusDB) == clean, 'oracle controls restored every value')
end

do -- 1. ABSENT -> saved, exact record, snapshot identity, receipts, no actions
    local r0 = P.Read()
    check(r0.mode == 'durable' and r0.class == 'ABSENT' and r0.ownerKey == F.OWNER and type(r0.root) == 'number'
        and r0.saveable and not r0.loadable and r0.visited == 0, 'durable ABSENT read: '..tostring(r0.mode)..'/'..tostring(r0.reason))
    check(codec.New({}) == nil and select(2, codec.New({})) == 'INVALID_STORE', 'New refuses a missing store')
    local s1 = N.Store.State()
    check(s1[KEY] == nil and s1.nestedHolder[KEY].keep == 'nested' and s1.unknownGenField.keep == 'row',
        'snapshot keeps the nested same-named field and unknown fields')
    local before, startup, sess, done = Without(NexusDB), N.StartupStatus().state, Session(), Spy(N, H)
    local sv = P.Save(sess, r0)
    local calls, acts, sent = done()
    check(sv.state == 'saved' and sv.bytes == BYTES and sv.receipt.class == 'CURRENT',
        'ABSENT -> saved: '..tostring(sv.reason)..'/'..tostring(sv.detail))
    check(calls == 0 and acts == 0 and sent == 0 and N.StartupStatus().state == startup,
        'Save: no owner call, action or message ('..calls..'/'..acts..'/'..sent..')')
    check(Without(NexusDB) == before, 'Save changed nothing but the pool key')
    check(N.Store.State() == s1 and s1[KEY] == nil, 'snapshot identity stable and pool-free after Save')
    sess.ids[1], sess.chosen[C] = A, 5
    check(dump(rawget(row, KEY)) == RECORD, 'exact stored v1 record in fresh tables; names are not stored')
    local r1 = P.Read()
    check(r1.class == 'CURRENT' and r1.bytes == BYTES and dump(r1.pool) == SESSION and r1.loadable and r1.visited == 21,
        'CURRENT read back exactly')
    for _ = 1, 3 do P.Read() end
    check(N.Store.State() == s1, 'repeated pool reads keep the snapshot identity')
    local stored = rawget(row, KEY)
    check(P.Save(Session2(), r0).reason == 'SAVED_CHANGED', 'a stale receipt (old saved bytes) refuses')
    local forged = {}; for k, v in pairs(r1) do forged[k] = v end
    check(P.Save(Session2(), forged).reason == 'RECEIPT_UNKNOWN' and P.Save(Session2(), nil).reason == 'RECEIPT_UNKNOWN'
        and codec.New({store=N.Store}).Save(Session2(), r1).reason == 'RECEIPT_UNKNOWN',
        'forged, missing and another facade receipts refuse')
    check(P.Save({ids={A}, rows={}, chosen={}}, r1).detail == 'ROW_MISMATCH', 'an inexact session refuses before any write')
    local same = P.Save(Session(), r1)
    check(same.state == 'saved' and same.unchanged and rawequal(rawget(row, KEY), stored), 'same bytes: saved unchanged, no write')
    local other = 'othertester@ebonhold'
    NexusDB.chars[other] = {[KEY]=Record()}
    local unit = UnitName; UnitName = function() return 'OtherTester', 'Ebonhold' end
    local ro = P.Read(); UnitName = unit
    check(ro.ownerKey == other and ro.class == 'CURRENT' and ro.bytes == BYTES, 'another character reads identical bytes')
    check(P.Save(Session2(), ro).reason == 'OWNER_CHANGED' and rawequal(rawget(row, KEY), stored),
        'identical bytes of another owner do not authorize')
    NexusDB.chars[other] = nil
    local s2 = P.Save(Session2(), r1)
    check(s2.state == 'saved' and s2.bytes == BYTES2 and N.Store.State() == s1, 'CURRENT replaced, snapshot stable')
    local cl = P.Clear(s2.receipt)
    check(cl.state == 'saved' and rawget(row, KEY) == nil and P.Read().class == 'ABSENT' and N.Store.State() == s1,
        'Clear removes only the key')
    O.UpdateStateV1(function(r) r.nestedHolder[KEY].keep = 'changed' end)
    local s3 = N.Store.State()
    check(s3 ~= s1 and s3.nestedHolder[KEY].keep == 'changed', 'a nested same-named field is still compared and copied')
    O.UpdateStateV1(function(r) r.nestedHolder[KEY].keep = 'nested' end)
    local s4 = N.Store.State(); O.UpdateStateV1(function() end)
    check(N.Store.State() == s4, 'a no-op write keeps the snapshot identity')
    local base = P.Save(Session(), P.Read())
    check(base.state == 'saved' and base.bytes == BYTES, 'saved again for fault injection')
end
held, snap = rawget(row, KEY), N.Store.State()

do -- 2. fault injection at the actual owner seam: restore, no overwrite, no trusted transient
    local text = Without(NexusDB)
    local function Fault(at, effect)
        local real, n = O.PlanPoolReadV1, 0
        O.PlanPoolReadV1 = function()
            n = n + 1
            local r = real()
            if n == at then return effect(r) end
            return r
        end
        return function() O.PlanPoolReadV1 = real end
    end
    local function blank(r) r.present, r.copy = false, nil; return r end
    local newer = Record(); newer.counts[1] = 1
    for _, case in ipairs({
        {'in-mutator verify mismatch', 3, blank, true},
        {'in-mutator verify error', 3, function() error('synthetic fault', 0) end, true},
        {'post-read mismatch', 4, blank, true},
        {'newer write before post-read', 4, function(r)
            O.UpdateStateV1(function(x) rawset(x, KEY, newer) end); return blank(r) end, false},
    }) do
        local receipt = P.Read()
        local undo = Fault(case[2], case[3])
        local ok, res = pcall(P.Save, Session2(), receipt)
        undo()
        check(ok and res.state == 'unverified' and res.reason == 'SAVE_UNVERIFIED' and res.restored == case[4],
            case[1]..': '..tostring(ok and (tostring(res.state)..'/'..tostring(res.detail)) or res))
        check(rawequal(rawget(row, KEY), case[4] and held or newer), case[1]..': exact record identity afterwards')
        check(N.Store.State() == snap, case[1]..': snapshot identity unchanged')
        rawset(row, KEY, held)
    end
    local resolve, fake = O.ResolveStateRowV1, {}
    O.ResolveStateRowV1 = function() return fake, false end
    local tr = P.Save(Session2(), P.Read())
    O.ResolveStateRowV1 = resolve
    check(tr.state == 'refused' and tr.reason == 'NOT_DURABLE' and next(fake) == nil and rawequal(rawget(row, KEY), held),
        'UpdateStateV1 true on a transient row is not trusted; nothing written: '..tostring(tr.reason))
    local update = O.UpdateStateV1
    O.UpdateStateV1 = function() error('synthetic update fault', 0) end
    local ue = P.Save(Session2(), P.Read())
    O.UpdateStateV1 = update
    check(ue.state == 'refused' and ue.reason == 'WRITE_ERROR' and rawequal(rawget(row, KEY), held), 'a failing write entry is reported')
    check(Without(NexusDB) == text and N.Store.State() == snap, 'fault paths left every unrelated key intact')
end

do -- 3. refused records stay exactly as found; legacy State and generic writes keep working
    local traps = 0
    local function trap() traps = traps + 1; error('metamethod', 0) end
    local function tagged(t) return setmetatable(t, {__index=trap, __newindex=trap, __len=trap,
        __eq=trap, __lt=trap, __le=trap, __concat=trap, __call=trap, __tostring=trap}) end
    local function with(f) local r = Record(); f(r); return r end
    local cyclic = Record(); cyclic.counts = cyclic
    local huge = {}; for k = 1, 100000 do huge[k] = k end
    for _, case in ipairs({
        {'future', 'FUTURE', {version=2, ids=tagged({}), extra='kept'}},
        {'unknown field', 'UNSUPPORTED', with(function(r) r.note = 'kept' end), true},
        {'sparse', 'MALFORMED', with(function(r) r.ids[2] = nil end), true},
        {'cyclic', 'MALFORMED', cyclic},
        {'metatable', 'MALFORMED', tagged(Record())},
        {'string', 'MALFORMED', 'v1|'},
        {'oversized 100k', 'OVERSIZED', with(function(r) r.ids = huge end)},
    }) do
        local name, class, value = case[1], case[2], case[3]
        rawset(row, KEY, value)
        local shape = case[4] and dump(value)
        local r = P.Read()
        check(r.mode == 'durable' and r.class == class and r.pool == nil and not r.loadable and not r.saveable
            and r.visited <= 3872, name..' read refused as '..class..' (got '..tostring(r.class)..' '
            ..tostring(r.detail)..' visited '..tostring(r.visited)..')')
        local s = P.Save(Session(), r)
        check(s.state == 'refused' and s.reason == 'SAVED_'..class, name..' Save refused: '..tostring(s.reason))
        check(rawequal(rawget(row, KEY), value) and (not shape or dump(value) == shape), name..' kept exactly as found')
        local ok, state = pcall(N.Store.State)
        check(ok and state[KEY] == nil, name..': Store.State still works')
        check(O.UpdateStateV1(function(x) x.genericProbe151 = 1 end) == true and row.genericProbe151 == 1,
            name..': a generic write still works')
        O.UpdateStateV1(function(x) x.genericProbe151 = nil end)
    end
    rawset(row, KEY, held)
    check(traps == 0 and P.Read().bytes == BYTES, 'no metamethod ran; the valid record is back')
end

do -- 4. measured bounds: maximal pool, repeated reads, unrelated and oversized 100k fields
    if jit and jit.off then jit.off(); if jit.flush then jit.flush() end end
    local function cost(fn, a, b)
        local ticks = 0
        debug.sethook(function() ticks = ticks + 1 end, '', 100)
        local r = fn(a, b)
        debug.sethook()
        return ticks * 100, r
    end
    local function settle() collectgarbage('collect'); collectgarbage('collect'); return collectgarbage('count') end
    local big = {ids={}, rows={}, chosen={}}
    for k = 1, 256 do
        local id = MAX_ID - 256 + k
        big.ids[k], big.rows[id] = id, {spellId=id, quality=255, maxStack=MAX_ID, groupId=MAX_ID}
    end
    big.chosen[big.ids[1]] = 79
    local saveCost, sb = cost(P.Save, big, P.Read())
    check(sb.state == 'saved' and #sb.bytes == 9988, 'maximal 256/79 pool saved: '..tostring(sb.reason))
    local readCost, rb = cost(P.Read)
    check(rb.class == 'CURRENT' and rb.visited == 1286 and rb.bytes == sb.bytes and #rb.pool.ids == 256,
        'maximal pool reads back; 1,286 entries visited')
    local start = settle()
    local keep = P.Read()
    local readHeap = math.floor((settle() - start) * 1024)
    keep = nil
    start = settle()
    for _ = 1, 200 do P.Read() end
    local residue = math.floor((settle() - start) * 1024)
    local hugeRow = {}; for k = 1, 100000 do hugeRow[k] = k end
    rawset(row, 'hugeUnrelated151', hugeRow)
    local unrelatedCost, ru = cost(P.Read)
    rawset(row, 'hugeUnrelated151', nil)
    local maximal, oversized = rawget(row, KEY), Record()
    oversized.counts = hugeRow
    rawset(row, KEY, oversized)
    local overCost, rv = cost(P.Read)
    rawset(row, KEY, maximal)
    if jit and jit.on then jit.on() end
    print(string.format('MEASURE store maximal pool visited=%d instructions read=%d save=%d'
        ..' unrelated100k=%d oversized100k=%d; heap readHeld=%d repeat200Residue=%d bytes'
        ..' (offline synthetic host, JIT off; not native)', rb.visited, readCost, saveCost,
        unrelatedCost, overCost, readHeap, residue))
    check(ru.class == 'CURRENT' and unrelatedCost <= readCost + 1000, 'a 100k unrelated row field adds no read work')
    check(rv.class == 'OVERSIZED' and rv.detail == 'ENTRIES' and rv.visited <= 3872 and overCost < readCost,
        'a 100k pool array stops at the copy bound')
    check(readHeap <= 131072 and residue <= 32768, 'held maximal read <= 128 KB; 200 reads leave <= 32 KB')
    check(P.Save(Session(), P.Read()).bytes == BYTES, 'normal pool saved again for the reload')
end

do -- 5. a reloaded Store module (stale owner) refuses and pollutes nothing
    local MI, keep, oldStore = N.MainInternals, {}, N.Store
    for k, v in pairs(MI) do keep[k] = v end
    local receipt, text, pool = P.Read(), F.Serialize(NexusDB), rawget(row, KEY)
    dofile('core/Store.lua')
    local stale = P.Save(Session2(), receipt)
    local fresh = codec.New({store=N.Store})
    local fr = fresh.Read()
    local fs = fresh.Save(Session2(), fr)
    local newState = N.Store.State()
    for k in pairs(MI) do MI[k] = nil end
    for k, v in pairs(keep) do MI[k] = v end
    N.Store = oldStore
    check(stale.state == 'refused' and stale.reason == 'STORE_OWNER_MISMATCH', 'stale owner refuses: '..tostring(stale.reason))
    check(fr.mode == 'loading' and fs.reason == 'LOADING', 'a Store module without its lifecycle refuses: '
        ..tostring(fr.mode)..'/'..tostring(fs.reason))
    check(newState[KEY] == nil and F.Serialize(NexusDB) == text and rawequal(rawget(row, KEY), pool), 'nothing written')
    check(P.Read().class == 'CURRENT' and MI.StoreAuthorityOwner == O, 'probe restored')
end

do -- 6. offline module reload with round-tripped literal data
    local oldDb, oldReceipt, parts = NexusDB, P.Read(), Parts(NexusDB)
    local H2 = F.Reload()
    local N2, startup = Nexus, #H2.actions
    local done = Spy(N2, H2)
    local P2 = N2.FlexiblePlanStore.New({store=N2.Store})
    local rr = P2.Read()
    local cross = P2.Save(Session2(), oldReceipt)
    local calls, acts, sent = done()
    print('STARTUP actions during the reboot (normal initialization, counted separately)='..startup)
    check(N2 ~= N and N2.FlexiblePlanStore ~= codec and NexusDB ~= oldDb, 'fresh module generation and deserialized root')
    check(rr.mode == 'durable' and rr.class == 'CURRENT' and rr.bytes == BYTES and dump(rr.pool) == SESSION,
        'reload retention: exact IDs, qualities, max stacks, groups and counts; no names')
    check(cross.reason == 'RECEIPT_UNKNOWN' and dump(rawget(NexusDB.chars[F.OWNER], KEY)) == RECORD,
        'a previous-generation receipt with identical bytes refuses')
    check(calls == 0 and acts == 0 and sent == 0, 'reboot Read/Save stage: no owner call, action or message')
    check(Parts(NexusDB) == parts, 'unknown row, settings, top-level, archive and ledger fields survive byte-identically')
end

do -- 7. format 5: pre-init creates nothing; the carried record loads; the first Save carries
    local plainPool, pre = Record(), {}
    F.fileHooks = {['core\\FlexiblePlanStore.lua']=function()
        local text, Q = F.Serialize(NexusDB), Nexus.FlexiblePlanStore.New({store=Nexus.Store})
        local r = Q.Read()
        pre.mode, pre.reason = r.mode, Q.Save(Session2(), r).reason
        pre.same = F.Serialize(NexusDB) == text and NexusDB.chars[F.OWNER] == nil
    end}
    F.Boot(F.Database({mutate=function(db) db.chars[F.NAME][KEY] = plainPool end}))
    F.fileHooks = nil
    check(pre.mode == 'loading' and pre.reason == 'LOADING' and pre.same, 'pre-init: loading, Save refused, nothing created')
    local P5, plain = Nexus.FlexiblePlanStore.New({store=Nexus.Store}), NexusDB.chars[F.NAME]
    local plainText, absent = F.Serialize(plain), NexusDB.chars[F.OWNER] == nil
    local r5 = P5.Read()
    print('CARRY canonical row absent before the first Save='..tostring(absent))
    check(r5.mode == 'durable' and r5.class == 'CURRENT' and r5.bytes == BYTES and r5.carried == absent
        and (NexusDB.chars[F.OWNER] == nil) == absent, 'format 5 reads the owned record without creating a row')
    local s5 = P5.Save(Session2(), r5)
    local canon = NexusDB.chars[F.OWNER]
    check(s5.state == 'saved' and type(canon) == 'table' and dump(rawget(canon, KEY))
        == dump({version=1, ids={A}, quality={1}, maxStack={5}, groupId={-1}, counts={4}})
        and type(canon.savedFormatCarry) == 'table' and canon.savedFormatCarry.from == F.NAME,
        'first Save writes the carried canonical row: '..tostring(s5.reason)..'/'..tostring(s5.detail))
    check(rawequal(rawget(plain, KEY), plainPool) and F.Serialize(plain) == plainText and NexusDB.settingsVersion == 5,
        'plain-name row and format marker unchanged')
    F.Reload()
    local r6 = Nexus.FlexiblePlanStore.New({store=Nexus.Store}).Read()
    check(r6.mode == 'durable' and r6.class == 'CURRENT' and r6.bytes == BYTES2 and r6.rowPresent and not r6.carried,
        'format 5 retention after reload')
end

do -- 8. read-only format 6: Load allowed, Save and Clear refused, everything kept
    F.Boot(F.Database({version=6, mutate=function(db) db.chars[F.OWNER] = F.Row({[KEY]=Record()}) end}))
    local P6 = Nexus.FlexiblePlanStore.New({store=Nexus.Store})
    local text, pool = F.Serialize(NexusDB), NexusDB.chars[F.OWNER][KEY]
    local r = P6.Read()
    local s, c = P6.Save(Session2(), r), P6.Clear(r)
    check(r.mode == 'readOnly' and r.class == 'CURRENT' and r.bytes == BYTES and r.loadable and not r.saveable,
        'read-only root loads a detached pool: '..tostring(r.mode)..'/'..tostring(r.reason))
    check(s.reason == 'READ_ONLY' and c.reason == 'READ_ONLY', 'read-only Save and Clear refuse')
    check(F.Serialize(NexusDB) == text and rawequal(NexusDB.chars[F.OWNER][KEY], pool), 'read-only root unchanged')
end

print('REMAINING Stage A retention is measured in flexible_plan_persistence_retention (no fixed'
    ..' pump number is claimed here); chooser UI, full CI/package and final reviews are later')
print('PASS flexible_plan_persistence_store checks='..checks)
