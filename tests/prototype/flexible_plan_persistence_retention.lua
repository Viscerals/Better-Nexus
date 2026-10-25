-- #151 retention acceptance (docs/flexible-plans/LOCAL_PERSISTENCE_CONTRACT.md,
-- "Measured bounds" and "Validation"). Synthetic data and host only; offline.
-- F.Boot/F.Reload is an
-- offline module reload with round-tripped literal data, not a client reload and not
-- native SavedVariables bytes. Instruction counts are Lua VM counts (count hook, JIT
-- off) of the actual coordinator pumps on a synthetic host, not native time.
--  A A maximal v1 pool across a serialized reboot: the exact record is retained,
--    and the startup work it adds is measured on the actual bootstrap coordinator,
--    observed by wrapping AuthorityBootstrap.New from the existing test file hook
--    (no product method is added). Every charge pump is compared with the actual
--    PumpCaps and the totals with the actual SourceBounds. Edge division alone
--    (ceil(1,286 / 64) = 21) omits row, cursor, sort and comparison work, so no
--    fixed pump number is claimed: the asserted bound is derived from the measured
--    edge delta and the actual edge cap, and the measured numbers are printed.
--  B The maximal pool plus a 28,672-charged-byte sibling of small edges reaches
--    READY and durable with no other field lost. The aggregate source bounds are
--    enforced; the notional per-row 32,768 bytes is not, and this row exceeds it
--    (recorded, not claimed as a cap or a server/storage contract).
--  C Canonical bytes of a supported v2 and a known format-5 root survive a
--    serialized reboot.
--  D The released test.9049 peer (sync_pair_support MANIFEST-verified files) and
--    the current peer keep the key across load, an existing Orb preference write,
--    logout and a serialized reload; a FUTURE v2 record with unknown fields is kept
--    unchanged by both. Builds between 9049 and current are not run.
-- Startup effects of a boot (actions, messages) are counted apart from pool
-- operations, which must have none; no message may carry the pool.
local F = dofile('tests/prototype/format5_support.lua')
local checks = 0
local function check(v, m) assert(v, m); checks = checks + 1 end
local KEY, SIBLING, MAX_ID = 'flexiblePlanPoolV1', 'retentionSibling151', 2147483647
local IA, IB, IC = 310001, 310002, 310003
local BYTES = 'v1|310003,3,5,900,2;310001,1,5,-1,0;310002,0,1,0,0;'
local CHARGE = {STORE_CHAR_MIGRATION_PENDING=true, STORE_DURABLE_BUNDLE_ADMISSION_PENDING=true}
local NEEDLES = {KEY, string.format('v1|%d', MAX_ID - 255), 'v1|310003'}

local function dump(v)
    if type(v) ~= 'table' then return type(v)..':'..tostring(v) end
    local keys, out = {}, {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(x, y) return type(x)..tostring(x) < type(y)..tostring(y) end)
    for _, k in ipairs(keys) do out[#out + 1] = dump(k)..'='..dump(v[k]) end
    return '{'..table.concat(out, ',')..'}'
end
local function Load(text) return assert(loadstring('return '..text))() end
local function Record()
    return {version=1, ids={IC, IA, IB}, quality={3, 1, 0}, maxStack={5, 5, 1},
        groupId={900, -1, 0}, counts={2, 0, 0}}
end
local function Session()
    return {ids={IC, IA, IB}, chosen={[IC]=2, [IA]=0}, rows={
        [IC]={spellId=IC, quality=3, maxStack=5, groupId=900, name='Synthetic C'},
        [IA]={spellId=IA, quality=1, maxStack=5, name='Synthetic A'},
        [IB]={spellId=IB, quality=0, maxStack=1, groupId=0}}}
end
local function MaxSession()
    local s = {ids={}, rows={}, chosen={}}
    for k = 1, 256 do
        local id = MAX_ID - 256 + k
        s.ids[k], s.rows[id] = id, {spellId=id, quality=255, maxStack=MAX_ID, groupId=MAX_ID}
    end
    s.chosen[s.ids[1]] = 79
    return s
end
local function MaxRecord()
    local r = {version=1, ids={}, quality={}, maxStack={}, groupId={}, counts={}}
    for k = 1, 256 do
        r.ids[k], r.quality[k], r.maxStack[k], r.groupId[k], r.counts[k] = MAX_ID - 256 + k, 255, MAX_ID, MAX_ID, 0
    end
    r.counts[1] = 79
    return r
end
local MAXRECORD = dump(MaxRecord())
local function Future()
    return {version=2, ids={IA, IB}, counts={1, 0}, note='kept', extra={nested={keep='future'}}}
end
local FUTURE = dump(Future())

-- Independent charge by the CharMigration rule: an edge costs its key text plus
-- 8 for a number or boolean, the length of a string, 0 for a table (whose own
-- edges are charged). depth 1 is the measured table itself.
local function Measure(v, depth, out)
    depth = depth or 1
    out = out or {edges=0, bytes=0, tables=1, depth=depth, maxEdge=0}
    for k, x in next, v do
        local kind, charge = type(x), #tostring(k)
        if kind == 'string' then charge = charge + #x
        elseif kind == 'number' or kind == 'boolean' then charge = charge + 8 end
        out.edges, out.bytes = out.edges + 1, out.bytes + charge
        if charge > out.maxEdge then out.maxEdge = charge end
        if kind == 'table' then
            out.tables = out.tables + 1
            if depth + 1 > out.depth then out.depth = depth + 1 end
            Measure(x, depth + 1, out)
        end
    end
    return out
end
-- 32 groups of 90 small numeric edges plus one 64-byte pad edge: exactly 28,672
-- charged bytes in 2,913 edges, none above 64 bytes (no single huge value).
local function Sibling()
    local s = {pad=string.rep('s', 61)}
    for g = 1, 32 do
        local group = {}
        for i = 1, 90 do group[i] = i end
        s[string.format('g%02d', g)] = group
    end
    return s
end
local function BundleRow(db)
    local bundle = rawget(db, 'authorityBundle')
    local data = type(bundle) == 'table' and rawget(bundle, 'storeData') or nil
    local chars = type(data) == 'table' and rawget(data, 'chars') or nil
    return type(chars) == 'table' and rawget(chars, F.OWNER) or nil
end
local function MaxEdge(db)
    local m = 0
    for _, part in ipairs({rawget(db, 'settings'), rawget(db, 'chars')}) do
        if type(part) == 'table' then m = math.max(m, Measure(part).maxEdge) end
    end
    return m
end
local function Leaks(H)
    local n = 0
    for i = 1, #H.sent do
        local text = tostring(H.sent[i].text or '')
        for _, needle in ipairs(NEEDLES) do
            if text:find(needle, 1, true) then n = n + 1 end
        end
    end
    return n
end
local function Parts(db)
    local r, ledger = db.chars[F.OWNER], {}
    local entry = type(db.accountCharacters) == 'table' and db.accountCharacters[F.OWNER] or nil
    for k, v in pairs(type(entry) == 'table' and entry or {}) do if k ~= 'lastSeen' then ledger[k] = v end end
    return F.Serialize({r.unknownGenField, r.nestedHolder, r.recordedPicks, db.settings.customGenSetting,
        db.genUnknownTopLevel, db.nexusNativeRecoveryArchiveF5, ledger})
end
-- Counts calls into owners the pool must never drive, plus harness actions and
-- messages. Restores every wrapped function.
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
local function JitOff() if jit and jit.off then jit.off(); if jit.flush then jit.flush() end end end
local function JitOn() if jit and jit.on then jit.on() end end

-- Boots with the actual coordinator observed. Each PumpAuthorityBootstrap call
-- records its state before the slice and, for a charge slice, the per-pump
-- ledger CharMigration left on the actual work item.
local function Observe(boot, instructions)
    local seen = {}
    F.fileHooks = {['core\\Store.lua']=function()
        local AB = Nexus.MainInternals.AuthorityBootstrap
        local new = AB.New
        AB.New = function(...)
            local coordinator = new(...)
            local rec = {C=coordinator, pumps={}}
            seen[#seen + 1] = rec
            local pump = coordinator.PumpAuthorityBootstrap
            coordinator.PumpAuthorityBootstrap = function(self, ...)
                local before, ticks = self.state, 0
                if instructions then debug.sethook(function() ticks = ticks + 1 end, '', 100) end
                local ok, result = pcall(pump, self, ...)
                if instructions then debug.sethook() end
                if not ok then error(result, 0) end
                local p, work = {state=before, instructions=ticks * 100}, self.charWork
                if CHARGE[before] and type(work) == 'table' then
                    p.charge, p.edges, p.nodes, p.bytes, p.rows =
                        true, work.pumpEdges, work.pumpNodes, work.pumpBytes, work.pumpRows
                end
                rec.pumps[#rec.pumps + 1] = p
                return result
            end
            return coordinator
        end
    end}
    local ok, H = pcall(boot)
    F.fileHooks = nil
    if not ok then error(H, 0) end
    local rec
    for _, r in ipairs(seen) do
        local st = tostring(r.C.state)
        if (st == 'STORE_READY' or st:find('^STORE_MUTATION')) and rawequal(r.C.database, NexusDB) then rec = r end
    end
    check(rec ~= nil, 'the actual bootstrap coordinator was observed and is serving this root')
    local s = {pumps=0, chargePumps=0, instructions=0, chargeInstructions=0, maxInstructions=0,
        maxEdges=0, maxNodes=0, maxBytes=0, maxRows=0, phases={}, list={}, work=rec.C.charWork}
    for _, p in ipairs(rec.pumps) do
        local st = tostring(p.state)
        if st ~= 'STORE_READY' and not st:find('^STORE_MUTATION') then
            s.pumps = s.pumps + 1
            s.instructions = s.instructions + p.instructions
            if p.instructions > s.maxInstructions then s.maxInstructions = p.instructions end
            s.phases[st] = (s.phases[st] or 0) + 1
            if p.charge then
                s.chargePumps = s.chargePumps + 1
                s.chargeInstructions = s.chargeInstructions + p.instructions
                s.maxEdges, s.maxNodes = math.max(s.maxEdges, p.edges), math.max(s.maxNodes, p.nodes)
                s.maxBytes, s.maxRows = math.max(s.maxBytes, p.bytes), math.max(s.maxRows, p.rows)
                s.list[#s.list + 1] = p
            end
        end
    end
    local AB = Nexus.MainInternals.AuthorityBootstrap
    s.caps, s.bounds, s.edge = AB.PumpCaps(), AB.SourceBounds(), MaxEdge(NexusDB)
    check(type(s.caps) == 'table' and type(s.bounds) == 'table', 'actual PumpCaps and SourceBounds published')
    return s, H
end
local function Phases(s)
    local names, out = {}, {}
    for name in pairs(s.phases) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do out[#out + 1] = (name:gsub('^STORE_', ''))..'='..s.phases[name] end
    return table.concat(out, ' ')
end
local function CheckPumps(s, label)
    local caps, bounds, bad, over = s.caps, s.bounds, 0, 0
    for _, p in ipairs(s.list) do
        -- A pump stops at the first cap reached, after the edge that reached it,
        -- so its byte ledger can end above the cap by at most one source edge.
        if p.edges > caps.edges or p.nodes > caps.nodes or p.rows > caps.rows
            or p.bytes > caps.graphBytes + s.edge then bad = bad + 1 end
        if p.bytes > caps.graphBytes then over = over + 1 end
    end
    local w = s.work
    print(string.format('MEASURE %s: coordinator pumps %d (charge %d); max per charge pump edges %d/%d'
        ..' nodes %d/%d bytes %d/%d (largest source edge %d, pumps ending above the byte cap %d) rows %d/%d;'
        ..' totals edges %d nodes %d graphBytes %d rows %d cursorEntries %d comparisons %d comparedBytes %d',
        label, s.pumps, s.chargePumps, s.maxEdges, caps.edges, s.maxNodes, caps.nodes, s.maxBytes,
        caps.graphBytes, s.edge, over, s.maxRows, caps.rows, w.edges, w.nodes, w.graphBytes, w.rows,
        w.cursorEntries, w.comparisons, w.comparedBytes))
    check(#s.list == s.chargePumps and s.chargePumps > 0 and bad == 0,
        label..': every charge pump within the actual PumpCaps ('..bad..' outside)')
    check(w.done == true and w.failure == nil and w.rows <= bounds.mapEntries and w.edges <= bounds.SGE
        and w.nodes <= bounds.SGN and w.graphBytes <= bounds.SGB and w.cursorEntries <= bounds.SM
        and w.comparisons <= bounds.SSC and w.comparedBytes <= bounds.SSB,
        label..': the complete charge finished within the actual SourceBounds')
end

local MAXBYTES, POOLM

do -- A. maximal pool: serialized reboot, exact retention, measured startup work
    F.Boot(F.Database({version=2, mutate=function(db)
        db.chars = {[F.OWNER]=F.Row({nestedHolder={[KEY]={keep='nested'}}})} end}))
    local P = Nexus.FlexiblePlanStore.New({store=Nexus.Store})
    local sv = P.Save(MaxSession(), P.Read())
    check(sv.state == 'saved' and type(sv.bytes) == 'string' and #sv.bytes == 9988,
        'maximal 256/79 pool saved through the actual Store: '..tostring(sv.reason)..'/'..tostring(sv.detail))
    MAXBYTES = sv.bytes
    local record = rawget(NexusDB.chars[F.OWNER], KEY)
    check(dump(record) == MAXRECORD, 'the stored maximal record is exactly the expected v1 record')
    POOLM = Measure(record)
    check(POOLM.tables == 6 and POOLM.edges == 1286 and POOLM.bytes == 13586 and POOLM.depth == 2,
        'independent charge of the maximal record: 6 tables, 1,286 edges, 13,586 bytes, two levels')
    local text, firstNexus = F.Serialize(NexusDB), Nexus
    local without, with = Load(text), Load(text)
    local bundleRow = BundleRow(without)
    local bundleHad = type(bundleRow) == 'table' and rawget(bundleRow, KEY) ~= nil
    rawset(without.chars[F.OWNER], KEY, nil)
    if type(bundleRow) == 'table' then rawset(bundleRow, KEY, nil) end
    print('ALIAS serialized root: a separate durable-bundle copy of the owned row carries the pool key='
        ..tostring(bundleHad)..' (serialization does not keep table aliases; reported, not asserted)')
    JitOff()
    local okW, sw, Hwo = pcall(Observe, function() return F.Boot(without) end, true)
    local okP, sp, Hp = false, 'baseline boot failed', nil
    if okW then okP, sp, Hp = pcall(Observe, function() return F.Boot(with) end, true) end
    JitOn()
    if not okW then error(sw, 0) end
    if not okP then error(sp, 0) end
    CheckPumps(sw, 'baseline reboot without the pool')
    CheckPumps(sp, 'reboot with the maximal pool')
    local row = NexusDB.chars[F.OWNER]
    print('ALIAS after the reboot: bundle row is the live row='..tostring(rawequal(BundleRow(NexusDB), row)))
    check(Nexus ~= firstNexus and rawequal(NexusDB, with), 'fresh module generation on the deserialized root')
    check(dump(rawget(row, KEY)) == MAXRECORD, 'exact full maximal record retained across the serialized reboot')
    local done = Spy(Nexus, Hp)
    local rr = Nexus.FlexiblePlanStore.New({store=Nexus.Store}).Read()
    local calls, acts, sent = done()
    check(rr.mode == 'durable' and rr.class == 'CURRENT' and rr.bytes == MAXBYTES and rr.visited == 1286
        and #rr.pool.ids == 256 and rr.pool.chosen[MAX_ID - 255] == 79, 'the maximal pool reads back exactly after the reboot')
    check(calls == 0 and acts == 0 and sent == 0, 'the pool Read: no owner call, action or message')
    local ew, eo = sp.work, sw.work
    local edgeDelta = ew.edges - eo.edges
    check(edgeDelta == POOLM.edges + 1 and ew.graphBytes - eo.graphBytes == POOLM.bytes + #KEY
        and ew.nodes - eo.nodes == POOLM.tables and ew.rows == eo.rows and ew.cursorEntries == eo.cursorEntries,
        'the measured charge delta is exactly the record plus its one row edge (edges '..edgeDelta..')')
    local pumpDelta = sp.chargePumps - sw.chargePumps
    local bound = math.ceil(edgeDelta / sp.caps.edges) + 1
    print(string.format('MEASURE pool startup work: charge pumps %d -> %d (delta %d; derived bound'
        ..' ceil(%d edges / %d edge cap) + 1 = %d); coordinator pumps %d -> %d; VM instructions all pumps'
        ..' %d -> %d (delta %d), charge pumps %d -> %d, largest single pump %d -> %d'
        ..' (count hook x100, JIT off, synthetic host; not native time)',
        sw.chargePumps, sp.chargePumps, pumpDelta, edgeDelta, sp.caps.edges, bound, sw.pumps, sp.pumps,
        sw.instructions, sp.instructions, sp.instructions - sw.instructions, sw.chargeInstructions,
        sp.chargeInstructions, sw.maxInstructions, sp.maxInstructions))
    print('MEASURE phases without: '..Phases(sw)..' | with: '..Phases(sp))
    print('NOTE the charge frontier counts no comparisons and does no sorting; such work by other'
        ..' startup owners appears only in the instruction counts above')
    check(pumpDelta > 0 and pumpDelta <= bound, 'measured charge-pump delta '..pumpDelta
        ..' is within the bound derived from the measured edges and the actual edge cap ('..bound..')')
    check(sw.instructions > 0 and sp.instructions > 0, 'instruction metering was active on the actual pumps')
    print(string.format('STARTUP effects counted apart from pool operations: baseline boot actions=%d'
        ..' messages=%d; pool boot actions=%d messages=%d', #Hwo.actions, #Hwo.sent, #Hp.actions, #Hp.sent))
    check(Leaks(Hwo) == 0 and Leaks(Hp) == 0, 'no startup message carries the pool key or record bytes')
end

do -- B. maximal pool plus a 28,672-byte sibling: READY, durable, nothing lost
    local db = Load(F.Serialize(NexusDB))
    local sibling = Sibling()
    local sm = Measure(sibling)
    check(sm.tables == 33 and sm.edges == 2913 and sm.bytes == 28672 and sm.depth == 2 and sm.maxEdge == 64,
        'independent charge of the sibling: 2,913 small edges, 28,672 bytes, no edge above 64 bytes')
    local row = db.chars[F.OWNER]
    rawset(row, SIBLING, sibling)
    local rowCharge = Measure(row)
    local keys, wantSibling, wantParts = {}, dump(sibling), Parts(db)
    for k in pairs(row) do keys[#keys + 1] = k end
    local s, H = Observe(function() return F.Boot(db) end, false)
    CheckPumps(s, 'reboot with the maximal pool and a 28,672-byte sibling')
    local live = NexusDB.chars[F.OWNER]
    check(Nexus.StartupStatus().state == 'ready' and Nexus.Store.StateWriteStatus().mode == 'durable',
        'the Store reached READY and the row is durable')
    local missing = 0
    for _, k in ipairs(keys) do if rawget(live, k) == nil then missing = missing + 1 end end
    check(missing == 0 and dump(rawget(live, SIBLING)) == wantSibling and dump(rawget(live, KEY)) == MAXRECORD
        and Parts(NexusDB) == wantParts, 'no field lost: every row key kept; sibling, pool and unrelated parts exact')
    print(string.format('MEASURE row aggregate: pool %d + sibling %d = %d charged bytes; whole row %d edges /'
        ..' %d bytes against the notional per-row 32,768 bytes (not checked by WithinBounds); aggregate'
        ..' graphBytes %d of SGB %d', POOLM.bytes, sm.bytes, POOLM.bytes + sm.bytes, rowCharge.edges,
        rowCharge.bytes, s.work.graphBytes, s.bounds.SGB))
    check(POOLM.bytes + sm.bytes == 42258 and rowCharge.bytes > 32768,
        'the row exceeds the notional 32,768 bytes and startup still completed: only the aggregate bounds are enforced')
    local Q = Nexus.FlexiblePlanStore.New({store=Nexus.Store})
    local r = Q.Read()
    check(r.mode == 'durable' and r.class == 'CURRENT' and r.bytes == MAXBYTES and r.saveable,
        'the maximal pool loads beside the sibling')
    local done = Spy(Nexus, H)
    local sv = Q.Save(Session(), r)
    local calls, acts, sent = done()
    check(sv.state == 'saved' and sv.bytes == BYTES and calls == 0 and acts == 0 and sent == 0,
        'a durable Save beside the sibling: no owner call, action or message')
    local H2 = F.Reload()
    local rb = Nexus.FlexiblePlanStore.New({store=Nexus.Store}).Read()
    check(rb.mode == 'durable' and rb.class == 'CURRENT' and rb.bytes == BYTES and NexusDB.settingsVersion == 2
        and dump(rawget(NexusDB.chars[F.OWNER], SIBLING)) == wantSibling,
        'supported v2: canonical bytes and the sibling survive another serialized reboot')
    check(Leaks(H) == 0 and Leaks(H2) == 0, 'no startup message carries the pool')
end

do -- C. known format 5: the carried record keeps its canonical bytes across a serialized reboot
    local H = F.Boot(F.Database({mutate=function(db) db.chars[F.NAME][KEY] = Record() end}))
    local done = Spy(Nexus, H)
    local r5 = Nexus.FlexiblePlanStore.New({store=Nexus.Store}).Read()
    local calls, acts, sent = done()
    local plainText, carried = F.Serialize(NexusDB.chars[F.NAME]), NexusDB.chars[F.OWNER] == nil
    check(r5.mode == 'durable' and r5.class == 'CURRENT' and r5.bytes == BYTES and r5.carried == carried
        and calls == 0 and acts == 0 and sent == 0, 'format 5 reads the owned record with no effects')
    local H2 = F.Reload()
    local r6 = Nexus.FlexiblePlanStore.New({store=Nexus.Store}).Read()
    check(r6.mode == 'durable' and r6.class == 'CURRENT' and r6.bytes == BYTES and NexusDB.settingsVersion == 5
        and F.Serialize(NexusDB.chars[F.NAME]) == plainText and dump(rawget(NexusDB.chars[F.NAME], KEY)) == dump(Record()),
        'known format 5: canonical bytes, plain-name row and marker survive the serialized reboot')
    print(string.format('STARTUP format-5 boots: actions=%d/%d messages=%d/%d (normal initialization)',
        #H.actions, #H2.actions, #H.sent, #H2.sent))
    check(Leaks(H) == 0 and Leaks(H2) == 0, 'no startup message carries the pool')
end

-- D. released 9049 and current peers. Each peer copies this process globals
-- when it starts, so the single-runtime world above must be gone first.
Nexus, NexusDB, WishlistRealizerDB, SlashCmdList, ProjectEbonhold, NexusOrbRuntime = nil, nil, nil, nil, nil, nil
local PS = dofile('tests/prototype/sync_pair_support.lua')
PS.Boot({'Alpha', 'Bravo'}, 5, nil, {released={true, false}})
local function Peer(i) return i == 1 and PS.A or PS.B end
local function Row(e) local key = e.Nexus.Store.CurrentOwnerKey(); return key, e.NexusDB.chars[key] end
local function EnsureRow(i)
    local e = Peer(i).e
    if not select(2, Row(e)) then e.Nexus.OrbRuntime.SetRecycle(true) end
    local key, row = Row(e)
    assert(type(row) == 'table', 'peer '..i..': a durable row for '..tostring(key))
    return row
end
-- A reload of one peer from its own saved data, round-tripped through literal
-- serialization first (the shared-table Rejoin alone would keep identities).
local function Reboot(i)
    local old = Peer(i)
    old.e.NexusDB = Load(F.Serialize(old.e.NexusDB))
    return PS.Rejoin(i)
end
local function Preference(i)
    local orb = Peer(i).e.Nexus.OrbRuntime
    return (pcall(function() orb.SetRecycle(false); return orb.SetRecycle(true) end))
end
local function Cycle(i, label, want, read)
    local re = Reboot(i)
    local _, r1 = Row(re.e)
    check(type(r1) == 'table' and dump(rawget(r1, KEY)) == want, label..': kept across the serialized load')
    if read then read(re.e, label..' after the load') end
    check(re.e.Nexus.Store.StateWriteStatus().mode == 'durable', label..': the write mode stays durable')
    check(Preference(i), label..': an existing Orb preference write works')
    local _, r2 = Row(re.e)
    check(dump(rawget(r2, KEY)) == want, label..': kept by the preference write')
    re.H.Fire('PLAYER_LOGOUT')
    local re2 = Reboot(i)
    local _, r3 = Row(re2.e)
    check(type(r3) == 'table' and dump(rawget(r3, KEY)) == want, label..': kept across logout and a second serialized reload')
    if read then read(re2.e, label..' after the second reload') end
    check(Leaks(re.H) == 0 and Leaks(re2.H) == 0, label..': no message carries the pool')
end

do -- D1. released 9049: the raw synthetic owned record through the peer environment
    local e = PS.A.e
    check(e.Nexus.FlexiblePlanStore == nil and type(e.Nexus.Store.StateWriteStatus) == 'function',
        'the released 9049 peer has no pool owner (older build)')
    local row = EnsureRow(1)
    rawset(row, KEY, MaxRecord())
    Cycle(1, 'released 9049', MAXRECORD)
end

do -- D2. current: the actual pool Save and Read
    local e = PS.B.e
    EnsureRow(2)
    local Q = e.Nexus.FlexiblePlanStore.New({store=e.Nexus.Store})
    local r0 = Q.Read()
    check(r0.mode == 'durable' and r0.class == 'ABSENT', 'current peer: durable ABSENT before the Save: '
        ..tostring(r0.mode)..'/'..tostring(r0.reason))
    local done = Spy(e.Nexus, PS.B.H)
    local sv = Q.Save(MaxSession(), r0)
    local calls, acts, sent = done()
    check(sv.state == 'saved' and sv.bytes == MAXBYTES and calls == 0 and acts == 0 and sent == 0,
        'current peer: the actual Save, no owner call, action or message')
    local _, row = Row(e)
    check(dump(rawget(row, KEY)) == MAXRECORD, 'current peer: the Save wrote the exact record')
    Cycle(2, 'current', MAXRECORD, function(pe, label)
        local rr = pe.Nexus.FlexiblePlanStore.New({store=pe.Nexus.Store}).Read()
        check(rr.mode == 'durable' and rr.class == 'CURRENT' and rr.bytes == MAXBYTES,
            label..': the actual Read returns the exact bytes')
    end)
end

do -- D3. a FUTURE v2 record with unknown fields is kept unchanged by both builds
    for i = 1, 2 do
        local label = i == 1 and 'released 9049 future v2' or 'current future v2'
        rawset(EnsureRow(i), KEY, Future())
        local read
        if i == 2 then
            read = function(pe, l)
                local Q = pe.Nexus.FlexiblePlanStore.New({store=pe.Nexus.Store})
                local r = Q.Read()
                local s = Q.Save(Session(), r)
                local _, raw = Row(pe)
                check(r.class == 'FUTURE' and not r.loadable and not r.saveable and s.state == 'refused'
                    and s.reason == 'SAVED_FUTURE' and dump(rawget(raw, KEY)) == FUTURE, l..': refused and kept exactly')
            end
        end
        Cycle(i, label, FUTURE, read)
    end
end

print('NOT CLAIMED: native client or SavedVariables, a per-row 32,768-byte cap, chooser UI,'
    ..' builds between 9049 and current, full CI/package, final reviews')
print('PASS flexible_plan_persistence_retention checks='..checks)
